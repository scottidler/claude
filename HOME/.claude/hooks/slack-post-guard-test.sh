#!/bin/bash
# slack-post-guard-test.sh: the matrix for slack-post-guard.sh.
#
# Wired into `.otto.yml`'s test task by glob (`*-test.sh`), so it needs no
# .otto.yml edit of its own. The lint task's FILES array is explicit and does.
#
# ISOLATION IS `HOME`. The guard reads its id cache and its send ledger from
# `$HOME/.cache/slack/`, so a fixture HOME gives the matrix a synthetic cache, a
# controllable ledger and a real filesystem to race on, without touching the
# live cache. The transcript comes from the payload, so it needs no seam at all.
#
# That same override is a residual hole in the guard and it is named rather than
# patched blind, exactly as the design names the Grep/Glob hole for SECRET: a
# `HOME=/tmp/x slack write ...` reads a cache an agent could have written. It
# denies for every target the fake cache cannot resolve (a missing cache is a
# deny), it cannot fake the transcript, and the prefix is glaring in the
# transcript and in `clyde permit log`. Closing it would cost the matrix every
# branch below, which is a worse trade than naming it.
#
# NO FIXTURE CARRIES AN UNQUOTED `#channel`, because bash reads that as a
# comment and the CLI never sees it. The guard denies that shape and there is a
# fixture for it; every other fixture uses the bare name or a quoted `#name`,
# which is what a working invocation looks like.
#
# Deny fixtures ride shapes.sh's wrap_shapes, 18 spellings, because a guard that
# only holds for the bare form is not a guard. Fixtures carrying a single quote
# cannot ride the quoted wrappers (shapes.sh:45) and are asserted directly.

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
HOOK="$HOOKS/slack-post-guard.sh"
. "$HOOKS/shapes.sh" || exit 1
pass=0
fail=0

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
NOW=$(date +%s)

FHOME="$T/home"
mkdir -p "$FHOME/.cache/slack"
cat > "$FHOME/.cache/slack/ids.json" <<JSON
{
  "schema": 2,
  "users_synced_at": $NOW,
  "usergroups_synced_at": $NOW,
  "channels_synced_at": $NOW,
  "channels": {
    "C0L0DJU56": "engineering",
    "C0KB8708Y": "general"
  },
  "users": {
    "D01G4Q7AWLV": "scott.idler",
    "D02020W2872": "bruce"
  },
  "handles": {
    "U111": "bruce",
    "U222": "russ.smith"
  },
  "profiles": {
    "U111": {"display_name": "bruce", "real_name": "Bruce Wayne"},
    "U222": {"display_name": "russ", "real_name": "Russ Smith"}
  },
  "subteams": {
    "S49923T52": {"handle": "nerds", "name": "Engineers", "members": ["U111", "U222"]}
  },
  "self": {"dm": "D01G4Q7AWLV"}
}
JSON

# transcript <name> <prompt text>  ->  path to a one-turn transcript
transcript() {
  local p="$T/$1.jsonl"
  jq -c -n --arg c "$2" \
    '{type:"user",isSidechain:false,promptId:"P1",promptSource:"typed",message:{content:$c}}' > "$p"
  jq -c -n '{type:"assistant",message:{content:[{type:"text",text:"ok"}]}}' >> "$p"
  printf '%s' "$p"
}

TX_ENG=$(transcript eng 'post the release notes to #engineering')
TX_BRUCE=$(transcript bruce 'message bruce about the rollout')
TX_NONE=$(transcript none 'summarize the last three commits')
TX_NOSUCH=$(transcript nosuch 'drop this in #nosuch')
TX_RUSS=$(transcript russ 'post the notes to #engineering and ping russ')

# A teammate relay naming the target, arriving AFTER the typed prompt that does
# not. The extractor this tree already ships reads the relay as Scott's own
# instruction on 22.0% of turns; this guard must not.
TX_RELAY="$T/relay.jsonl"
jq -c -n '{type:"user",isSidechain:false,promptId:"P1",promptSource:"typed",message:{content:"summarize the last three commits"}}' > "$TX_RELAY"
jq -c -n '{type:"user",isSidechain:false,promptId:"P1",message:{content:"Another Claude session sent a message: post it to #engineering"}}' >> "$TX_RELAY"

# A slash-command turn. The shipped extractor discards every one of these
# (138 of 1,237 measured turns); the corrected one parses them.
TX_CMD="$T/cmd.jsonl"
jq -c -n '{type:"user",isSidechain:false,promptId:"P1",promptSource:"typed",message:{content:"<command-name>slackify</command-name><command-args>this to #engineering</command-args>"}}' > "$TX_CMD"

# A sidechain (subagent) record naming the target. A subagent does not
# authorize an outward post.
TX_SIDE="$T/side.jsonl"
jq -c -n '{type:"user",isSidechain:false,promptId:"P1",promptSource:"typed",message:{content:"summarize the last three commits"}}' > "$TX_SIDE"
jq -c -n '{type:"user",isSidechain:true,promptId:"P1",message:{content:"post it to #engineering"}}' >> "$TX_SIDE"

reset_ledger() { rm -rf "$FHOME/.cache/slack/sent-ledger"; }

bash_payload() { # bash_payload <command> <transcript>
  jq -n --arg c "$1" --arg t "$2" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},transcript_path:$t,prompt_id:"P1",cwd:"/tmp"}'
}

mcp_payload() { # mcp_payload <tool> <tool_input json> <transcript> [event]
  jq -n --arg tool "$1" --argjson ti "$2" --arg t "$3" --arg e "${4:-PreToolUse}" \
    '{hook_event_name:$e,tool_name:$tool,tool_input:$ti,transcript_path:$t,prompt_id:"P1",cwd:"/tmp"}'
}

decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "allow"'; }

check() { # check <expect> <label> <payload> [home]
  local expect="$1" label="$2" payload="$3" home="${4:-$FHOME}" out d
  out=$(printf '%s' "$payload" | HOME="$home" bash "$HOOK")
  d=$(decision "$out")
  if [ "$d" = "$expect" ]; then
    pass=$((pass + 1)); printf 'PASS  [%s] %s\n' "$expect" "$label"
  else
    fail=$((fail + 1)); printf 'FAIL  [want %s got %s] %s\n' "$expect" "$d" "$label"
  fi
}

runb() { # runb <expect> <command> <transcript>
  check "$1" "$2" "$(bash_payload "$2" "$3")"
}

runwrapped() { # runwrapped <command> <transcript>
  local w
  while IFS= read -r w; do
    reset_ledger
    check deny "$w" "$(bash_payload "$w" "$2")"
  done < <(wrap_shapes "$1")
}

ok() { # ok <condition-result> <label>
  if [ "$1" -eq 0 ]; then
    pass=$((pass + 1)); printf 'PASS  %s\n' "$2"
  else
    fail=$((fail + 1)); printf 'FAIL  %s\n' "$2"
  fi
}

echo "=== the gate: a non-Slack command never reads the transcript ==="
# Criterion: under 50 ms against a transcript over 4 MB. The ungated shape
# measured 230 ms on this class, against a 250 ms whole-chunk budget.
BIG="$T/big.jsonl"
jq -c -n '{type:"user",isSidechain:false,promptId:"P1",promptSource:"typed",message:{content:"post the release notes to #engineering"}}' > "$BIG"
# --rawfile, not --arg: a 200 KB argument is past ARG_MAX and jq never runs.
head -c 200000 /dev/zero | tr '\0' 'x' > "$T/filler.txt"
bigline=$(jq -c -n --rawfile f "$T/filler.txt" '{type:"assistant",message:{content:[{type:"text",text:$f}]}}')
for _ in $(seq 1 25); do printf '%s\n' "$bigline" >> "$BIG"; done
bigsize=$(stat -c %s "$BIG")
runb allow 'git status --porcelain' "$BIG"
start=$(date +%s%N)
printf '%s' "$(bash_payload 'git status --porcelain' "$BIG")" | HOME="$FHOME" bash "$HOOK" >/dev/null
elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
[ "$bigsize" -gt 4000000 ] && [ "$elapsed" -lt 50 ]
ok $? "[gate] $bigsize byte transcript, non-Slack call took ${elapsed} ms (want < 50)"
runb allow 'slackify --input notes.md' "$TX_NONE"
runb allow 'slack read engineering --since 1h' "$TX_NONE"
runb allow 'slack channels --query eng' "$TX_NONE"

echo "=== the exempt pair needs no cache, no transcript, no confirmation ==="
reset_ledger
check allow 'clipboard with no cache and no transcript at all' \
  "$(bash_payload 'slack write clipboard here is the summary' /nonexistent)" "$T/nohome"
[ ! -e "$T/nohome" ]
ok $? "[gate] the exempt path created no cache directory"
check allow 'mcp post to #clipboard by id' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"C0ANJQAJC7N","text":"notes"}' /nonexistent)" "$T/nohome"
check allow 'mcp post to Scotts own DM' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"D01G4Q7AWLV","text":"notes"}' /nonexistent)" "$T/nohome"
runb allow "slack write '#clipboard' here is the summary" "$TX_NONE"

echo "=== the exemption bounds the FULL recipient set, not the named target ==="
# Round 1's sharpest finding: one call reaches past its target three ways.
runb deny 'slack write clipboard --broadcast engineering here is the summary' "$TX_NONE"
runb deny 'slack write clipboard --dm-mentioned ping @russ.smith about this' "$TX_NONE"
check deny 'mcp post to #clipboard with dm_mentioned reaching russ' \
  "$(mcp_payload mcp__slack__chat_post_message \
    '{"channel":"C0ANJQAJC7N","text":"ping @russ.smith about this","dm_mentioned":true}' "$TX_NONE")"
check deny 'mcp follow_ups body to #clipboard mentioning russ with dm_mentioned' \
  "$(mcp_payload mcp__slack__chat_post_message \
    '{"channel":"C0ANJQAJC7N","text":"notes","dm_mentioned":true,"follow_ups":["and @russ.smith owns it"]}' "$TX_NONE")"
# no_mentions switches resolution off, so nothing fans out.
runb allow 'slack write clipboard --no-mentions ping @russ.smith about this' "$TX_NONE"

echo "=== TARGET: the post goes where Scott named it ==="
runb allow 'slack write engineering here are the release notes' "$TX_ENG"
runb deny  'slack write engineering here are the release notes' "$TX_NONE"
reset_ledger
runb allow "slack write '#engineering' here are the release notes" "$TX_ENG"
reset_ledger
runb allow 'slack write "#engineering" here are the release notes' "$TX_ENG"
reset_ledger
check allow 'mcp post to C0L0DJU56 with the prompt naming #engineering' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"C0L0DJU56","text":"notes"}' "$TX_ENG")"
reset_ledger
check deny 'mcp post to C0L0DJU56 with the prompt naming nothing' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"C0L0DJU56","text":"notes"}' "$TX_NONE")"
reset_ledger
check allow 'mcp post to a DM the prompt names by first name' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"D02020W2872","text":"notes"}' "$TX_BRUCE")"
reset_ledger
check deny 'mcp post to a DM the prompt does not name' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"D02020W2872","text":"notes"}' "$TX_NONE")"
# A target the cache cannot resolve is still checked, against its own spelling.
reset_ledger
runb allow 'slack write nosuch here are the notes' "$TX_NOSUCH"
runb deny  'slack write nosuch here are the notes' "$TX_NONE"
# A mention recipient must be named in its own right.
reset_ledger
runb allow 'slack write engineering --dm-mentioned ping @russ.smith about the notes' "$TX_RUSS"
runb deny  'slack write engineering --dm-mentioned ping @russ.smith about the notes' "$TX_ENG"
# A usergroup expands past the named channel. With a posting task live this is
# allowed: no incident in the corpus is a fan-out, and denying it is the
# annoyance class. The residual is named in the doc.
reset_ledger
runb allow 'slack write engineering --dm-mentioned heads up @nerds' "$TX_ENG"

echo "=== TARGET: what does NOT count as Scott naming a target ==="
runb deny  'slack write engineering here are the notes' "$TX_RELAY"
runb deny  'slack write engineering here are the notes' "$TX_SIDE"
reset_ledger
runb allow 'slack write engineering here are the notes' "$TX_CMD"
runb deny  'slack write engineering here are the notes' /nonexistent

echo "=== TARGET: the cache states, and which of them deny ==="
EHOME="$T/emptyhome"; mkdir -p "$EHOME"
check deny 'a missing id cache denies a non-exempt target' \
  "$(bash_payload 'slack write engineering notes' "$TX_ENG")" "$EHOME"
SHOME="$T/schemahome"; mkdir -p "$SHOME/.cache/slack"
jq '.schema = 1' "$FHOME/.cache/slack/ids.json" > "$SHOME/.cache/slack/ids.json"
check deny 'a schema-old id cache denies a non-exempt target' \
  "$(bash_payload 'slack write engineering notes' "$TX_ENG")" "$SHOME"
STALE="$T/stalehome"; mkdir -p "$STALE/.cache/slack"
jq --argjson t $((NOW - 90000)) '.users_synced_at = $t | .usergroups_synced_at = $t' \
  "$FHOME/.cache/slack/ids.json" > "$STALE/.cache/slack/ids.json"
check deny 'a stale cache denies dm_mentioned, whose recipient set it cannot vouch for' \
  "$(bash_payload 'slack write engineering --dm-mentioned ping @russ.smith' "$TX_RUSS")" "$STALE"
check allow 'a stale cache still resolves a plain named target' \
  "$(bash_payload 'slack write engineering here are the notes' "$TX_ENG")" "$STALE"
check allow 'a stale cache does not touch the exempt pair' \
  "$(bash_payload 'slack write clipboard here are the notes' "$TX_NONE")" "$STALE"

echo "=== TEST-TEXT: the 2026-07-10 class ==="
reset_ledger
check deny 'an MCP write test as the first line, into a DM' \
  "$(mcp_payload mcp__slack__chat_post_message \
    '{"channel":"D02020W2872","text":"**MCP write test**\nignore this"}' "$TX_BRUCE")"
reset_ledger
check deny 'a follow-up body that opens with testing' \
  "$(mcp_payload mcp__slack__chat_post_message \
    '{"channel":"C0L0DJU56","text":"release notes","follow_ups":["testing the thread path"]}' "$TX_ENG")"
reset_ledger
check allow 'the same test text into #clipboard' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"C0ANJQAJC7N","text":"**MCP write test**"}' /nonexistent)"
reset_ledger
check allow 'the word test on the SECOND line is not a test post' \
  "$(mcp_payload mcp__slack__chat_post_message \
    '{"channel":"C0L0DJU56","text":"release notes\nthe test suite is green"}' "$TX_ENG")"
reset_ledger
runb deny 'slack write engineering verifying the release notes land here' "$TX_ENG"

echo "=== the posts Scott asked for, which the first cut denied ==="
# Every fixture here is a real turn from the 211-post replay that the
# target-name-only rule denied. They are the reason the rule has a second
# sufficient condition.
TX_RUSS_DM=$(transcript russdm 'message russ to point at valet.test.tatari.dev and enroll')
TX_RYAN=$(transcript ryan 'send a message to ryan. codeblock with the json change')
TX_NICK=$(transcript nick 'ok lets send the message to Nick and mention that we updated the doc too')
TX_MIKE=$(transcript mike 'drop the quick missive to Mike in that thread')
TX_POSTIT=$(transcript postit 'post it')
TX_SENDIT=$(transcript sendit 'i didnt ask for a draft. I asked you to send it')
# A DM id the cache cannot resolve, which is every DM id in the real traffic:
# the users map holds 120 and D01TL0BDQ4T, D0AH0DP9RJ5 and D0B8FU6DLKU are all
# absent from it.
reset_ledger
check allow 'message russ, to a DM id the cache cannot resolve' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"D01TL0BDQ4T","text":"hey russ, the host the cli defaults to just isnt deployed yet"}' "$TX_RUSS_DM")"
reset_ledger
check allow 'send a message to ryan' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"D0AH0DP9RJ5","text":"here is the json change"}' "$TX_RYAN")"
reset_ledger
check allow 'send the message to Nick' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"D0B8FU6DLKU","text":"we updated the doc too"}' "$TX_NICK")"
reset_ledger
check allow 'a missive to Mike in a channel the prompt does not name' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"C0AA8UBU5MX","text":"quick note on the spec"}' "$TX_MIKE")"
reset_ledger
check allow 'post it, where the target was named an earlier turn' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"C09PCEA4T8F","text":"the summary"}' "$TX_POSTIT")"
reset_ledger
check allow 'I asked you to send it' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"C0ACWPXHLPK","text":"the summary"}' "$TX_SENDIT")"
# His own DM, addressed by handle rather than by id.
reset_ledger
runb allow "slack write '@scott.idler' --at 2026-08-13T15:00:00Z Finish the thing" "$TX_NONE"
# --help posts nothing, and the no-target deny fired on it 20 times.
runb allow 'slack write --help' "$TX_NONE"
runb allow 'slack write --help 2>&1 | head -40' "$TX_NONE"

echo "=== the posts nobody asked for, which still deny ==="
TX_PUSH=$(transcript push 'force push the branches')
TX_SHAKE=$(transcript shake 'ok PR, /babysit, merge, finish bump, install, and test')
TX_FILES=$(transcript files 'loos like 4 .json files?')
reset_ledger
check deny 'force push the branches, and a post goes to a work channel' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"C0ACWPXHLPK","text":"the summary"}' "$TX_PUSH")"
reset_ledger
check deny 'a shakedown turn, which is the 2026-07-10 class' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"C0L0DJU56","text":"the summary"}' "$TX_SHAKE")"
reset_ledger
check deny 'loos like 4 .json files?' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"C089C6Y41ND","text":"the summary"}' "$TX_FILES")"

echo "=== TEST-TEXT is a marker line, not prose about a test environment ==="
# Both of these are real bodies the first cut denied, with a posting ask live.
reset_ledger
check allow 'prose mentioning test and prod in a long first line' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"C01FXF7P3ST","text":"marquee DID already ship its own MCP-auth path: live on test and prod, bypasses the broker and auth-svc entirely, and there is no work left"}' "$TX_SENDIT")"
reset_ledger
check allow 'prose mentioning the test host in a long first line' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"D01TL0BDQ4T","text":"hey russ, the host the cli defaults to (valet.internal.tatari.dev) just isnt deployed yet, only the test one is. two steps:"}' "$TX_RUSS_DM")"
reset_ledger
check deny 'the marker line itself' \
  "$(mcp_payload mcp__slack__chat_post_message '{"channel":"D02020W2872","text":"**MCP write test**\nignore this"}' "$TX_BRUCE")"

echo "=== RESEND: one post was asked for, so one post goes out ==="
reset_ledger
runb allow 'slack write engineering here are the release notes' "$TX_ENG"
runb deny  'slack write engineering here are the release notes' "$TX_ENG"
# The deny names the exact file to remove, because a genuinely failed send
# cannot otherwise be retried until the entry expires.
out=$(printf '%s' "$(bash_payload 'slack write engineering here are the release notes' "$TX_ENG")" \
  | HOME="$FHOME" bash "$HOOK")
reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
namedfile=$(printf '%s' "$reason" | grep -oE '/[^ ]*sent-ledger/[^ ]+' | sed 's/[.,]$//')
[ -n "$namedfile" ] && [ -e "$namedfile" ]
ok $? "[deny] the resend deny names an entry file that exists ($namedfile)"
# A failure leaves the entry in place: no PostToolUse ever arrives, and the
# retry still denies. `post_chunks` can fail after the parent has landed and a
# PostToolUseFailure payload carries no per-recipient detail, so the guard
# cannot learn that nothing was sent.
runb deny 'slack write engineering here are the release notes' "$TX_ENG"
# A confirmed send marks the entry, and the retry still denies.
printf '%s' "$(bash_payload 'slack write engineering here are the release notes' "$TX_ENG")" \
  | jq '.hook_event_name = "PostToolUse"' | HOME="$FHOME" bash "$HOOK" >/dev/null
marked=$(cat "$FHOME/.cache/slack/sent-ledger/"* 2>/dev/null | head -1)
case "$marked" in sent\ *) r=0 ;; *) r=1 ;; esac
ok $r "[ledger] PostToolUse marked the entry sent (read back: ${marked:-empty})"
runb deny  'slack write engineering here are the release notes' "$TX_ENG"
runb allow 'slack write engineering a different body entirely' "$TX_ENG"
reset_ledger
runb allow 'slack write nosuch here are the release notes' "$TX_NOSUCH"
runb allow 'slack write engineering here are the release notes' "$TX_ENG"

echo "=== RESEND: an edit is the opposite of a resend ==="
reset_ledger
check allow 'chat_update, first' \
  "$(mcp_payload mcp__slack__chat_update '{"channel":"C0L0DJU56","text":"corrected notes"}' "$TX_ENG")"
check allow 'chat_update, same body again' \
  "$(mcp_payload mcp__slack__chat_update '{"channel":"C0L0DJU56","text":"corrected notes"}' "$TX_ENG")"
reset_ledger
runb allow 'slack write engineering --edit 1719835300.000500 corrected notes' "$TX_ENG"
runb allow 'slack write engineering --edit 1719835300.000500 corrected notes' "$TX_ENG"

echo "=== RESEND: the exclusion is the filesystem's, and it spans processes ==="
# A PreToolUse process exits before the tool runs, so a lock it holds cannot
# cover the send. Racers, exactly one reservation.
concurrent() { # concurrent <n> <setup-fn> -> prints the allow count
  local n="$1" setup="$2" i
  reset_ledger
  mkdir -p "$FHOME/.cache/slack/sent-ledger"
  "$setup"
  rm -f "$T"/race.*
  for i in $(seq 1 "$n"); do
    ( printf '%s' "$(bash_payload 'slack write engineering the racing body' "$TX_ENG")" \
      | HOME="$FHOME" bash "$HOOK" > "$T/race.$i" ) &
  done
  wait
  grep -L 'permissionDecision' "$T"/race.* 2>/dev/null | wc -l
}

noop() { :; }
allows=$(concurrent 8 noop)
[ "$allows" = "1" ]
ok $? "[race] 8 concurrent fresh creates left exactly 1 allowed (got $allows)"

# The expired-entry path is its own race and its own criterion. The doc
# prescribed renaming a fresh temp entry OVER the expired path, which is atomic
# and is not a compare-and-swap: every racer's rename succeeds, so every racer
# proceeds. This asserts the replace path, not just the fresh-create path.
plant_expired() {
  local key
  key="$(printf '%s' 'engineering' | tr -c 'A-Za-z0-9._-' '_')-$(printf '%s' 'the racing body' | sha256sum | cut -c1-32)"
  printf 'reserved 0\n' > "$FHOME/.cache/slack/sent-ledger/$key"
  touch -d '2 hours ago' "$FHOME/.cache/slack/sent-ledger/$key"
}
allows=$(concurrent 8 plant_expired)
[ "$allows" = "1" ]
ok $? "[race] 8 concurrent reclaims of one EXPIRED entry left exactly 1 allowed (got $allows)"

reset_ledger
mkdir -p "$FHOME/.cache/slack/sent-ledger"
plant_expired
check allow 'a single reclaim of an expired entry proceeds' \
  "$(bash_payload 'slack write engineering the racing body' "$TX_ENG")"

echo "=== RESEND: an unusable ledger denies ==="
RHOME="$T/rohome"
mkdir -p "$RHOME/.cache/slack/sent-ledger"
cp "$FHOME/.cache/slack/ids.json" "$RHOME/.cache/slack/ids.json"
chmod 500 "$RHOME/.cache/slack/sent-ledger"
check deny 'a read-only send ledger denies rather than skipping the check' \
  "$(bash_payload 'slack write engineering here are the release notes' "$TX_ENG")" "$RHOME"
chmod 700 "$RHOME/.cache/slack/sent-ledger"

echo "=== parse: what posts, what does not, and what cannot be parsed ==="
reset_ledger
runb allow 'slack write --print engineering testing the renderer' "$TX_NONE"
runb allow 'slack write --preview engineering testing the renderer' "$TX_NONE"
runb deny  'slack write' "$TX_NONE"
# An unquoted `#channel` is a shell comment, so the CLI never sees a target.
runb deny  'slack write #engineering here are the release notes' "$TX_ENG"
runb deny  'slack write clipboard --broadcast #engineering here is the summary' "$TX_NONE"
runb deny  'slack write --file /nonexistent/body.md engineering' "$TX_ENG"
BODY="$T/body.md"; printf 'testing the upload path\nsecond line\n' > "$BODY"
runb deny  "slack write --markdown-to-mrkdwn $BODY engineering" "$TX_ENG"
printf 'here are the release notes\n' > "$BODY"
reset_ledger
runb allow "slack write --markdown-to-mrkdwn $BODY engineering" "$TX_ENG"
runb deny  "slack write --markdown-to-mrkdwn $BODY engineering" "$TX_ENG"
# `--thread` takes an operand, and that operand is not the target.
reset_ledger
runb allow 'slack write --thread 1719835300.000500 engineering here are the notes' "$TX_ENG"
reset_ledger
# A different channel than the one named, with a posting task live: allowed.
# "right ask, wrong channel" is not an incident class in the corpus, and the
# rule that denied it also denied "message russ".
runb allow 'slack write --thread 1719835300.000500 general here are the notes' "$TX_ENG"
# repost carries its body in Slack, so the destination is what gets checked.
reset_ledger
runb allow 'slack repost general:1719835300.000500 engineering' "$TX_ENG"
reset_ledger
runb allow 'slack repost engineering:1719835300.000500 general' "$TX_ENG"

echo "=== every deny holds in all 18 spellings bash offers ==="
runwrapped 'slack write engineering here are the release notes' "$TX_NONE"
runwrapped 'slack write clipboard --broadcast engineering here is the summary' "$TX_NONE"

echo "=== round-6: the slash-command wrapper tag, and compound posting statements ==="
# M3: a slash-command turn arrives as <command-message>name</command-message>,
# and `posting_intent` matched the literal word `message` inside the TAG, so any
# slash-command turn in the window authorized a post to any resolvable target.
# 58 of 400 sampled transcripts carry it, and /cli-shakedown is one of the
# incident classes this rule exists to catch. The fixture at :95 used
# <command-name> only, which is why the matrix never saw it.
TX_CMDMSG=$(transcript cmdmsg '<command-message>cli-shakedown</command-message><command-name>cli-shakedown</command-name>')
TX_CMDARGS=$(transcript cmdargs '<command-name>slackify</command-name><command-args>send this to #engineering</command-args>')
reset_ledger
runb deny  'slack write engineering r6a' "$TX_CMDMSG"
reset_ledger
runb allow 'slack write clipboard r6b' "$TX_CMDMSG"
# Inner text is the user's own words and still counts.
reset_ledger
runb allow 'slack write engineering r6c' "$TX_CMDARGS"

# M4: the statement loop broke after the first posting statement, so everything
# below judged statement one and an exempt first target authorized the second
# post. Mutation proof that no fixture covered this: replacing the `break` with
# a no-op left the suite at 123/0.
reset_ledger
runb deny 'slack write scott.idler r6d; slack write engineering r6e' "$TX_ENG"
reset_ledger
runb deny 'slack write scott.idler r6f && slack write general r6g' "$TX_ENG"
reset_ledger
runb allow 'slack write engineering r6h' "$TX_ENG"

echo
printf 'pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
