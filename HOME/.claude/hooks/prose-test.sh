#!/bin/bash
# prose-test.sh: regression matrix for prose.sh.
#
# Builds synthetic JSONL transcripts under $TMPDIR and feeds synthetic Stop /
# SubagentStop payloads through the hook, asserting the expected block/allow for
# every rule: em-dash, offer-closer (with the instruction and go-ahead prompt
# gate, the code-span strip and the final-sentence anchor), the Jev instruction
# test and its verb-list fallback (canned file:// answers, never the network),
# oversized decision ask, and every pass-through (stop_hook_active, empty text,
# missing transcript, lagging transcript, agent relay). Exits non-zero on any
# failure.
#
# Transcript shapes matter here and are the point of several cases:
#   flushed   ... user, assistant(text == payload)   -> prompt is current
#   partial   ... assistant, user                    -> prompt sits after the reply
#   lagging   ... user, assistant(text != payload)   -> prompt is the PRIOR turn's,
#                                                       offer rule must fail open
#
# Run directly, or via: prose.sh --self-test
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/prose.sh"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/prose-test.XXXXXX")

EMDASH=$'\u2014'

urec() { jq -nc --arg c "$1" '{type:"user",isSidechain:false,message:{content:$c},timestamp:"2026-09-13T20:00:00.000Z"}'; }
arec() { jq -nc --arg c "$1" '{type:"assistant",isSidechain:false,message:{content:[{type:"text",text:$c}]},timestamp:"2026-09-13T20:00:01.000Z"}'; }
lprec() { jq -nc --arg p "$1" '{type:"last-prompt",lastPrompt:$p,leafUuid:"u",sessionId:"s"}'; }
srec() { jq -nc --arg c "$1" '{type:"user",isSidechain:true,message:{content:$c},timestamp:"2026-09-13T20:00:00.000Z"}'; }

# partial flush: an earlier reply, then the prompt. The prompt sits after the
# newest assistant record, so it is current whatever the payload text is.
T_PARTIAL="$ROOT/partial.jsonl"
{ arec "an earlier reply"; urec "fix the test"; } > "$T_PARTIAL"

# fully flushed: prompt, then the very reply under test.
T_FLUSHED="$ROOT/flushed.jsonl"
{ urec "fix the test"; arec "Done. Want me to run it?"; } > "$T_FLUSHED"

# lagging: prompt, then the PRIOR turn's reply; the payload text is neither.
T_LAG="$ROOT/lag.jsonl"
{ urec "fix the test"; arec "the prior turn's reply, already delivered"; } > "$T_LAG"

# a question, not an imperative
T_QUESTION="$ROOT/question.jsonl"
{ arec "an earlier reply"; urec "why is the build red?"; } > "$T_QUESTION"

# a bare go-ahead
T_GOAHEAD="$ROOT/goahead.jsonl"
{ arec "an earlier reply"; urec "yes"; } > "$T_GOAHEAD"

# five-plus words carrying "go" inside another word's neighbourhood: not a
# go-ahead and not verb-initial, so the offer rule must stand down.
T_NEITHER="$ROOT/neither.jsonl"
{ arec "an earlier reply"; urec "tell me how the golang build ran"; } > "$T_NEITHER"

# slash command: recorded as <command-message> in the user record (which the
# main-thread predicate drops) and verbatim in the last-prompt record.
T_SLASH="$ROOT/slash.jsonl"
{ arec "an earlier reply"
  jq -nc '{type:"user",isSidechain:false,message:{content:"<command-message>babysit-prs</command-message>\n<command-name>/babysit-prs</command-name>"},timestamp:"2026-09-13T20:00:00.000Z"}'
  lprec "/babysit-prs the two open PRs"; } > "$T_SLASH"

# agent relay only: not a typed prompt, so no prompt is recoverable.
T_RELAY="$ROOT/relay.jsonl"
{ arec "an earlier reply"; lprec "Another Claude session sent a message: implement phase 2"; } > "$T_RELAY"

# subagent transcript: every record is sidechain; the dispatch prompt is first.
T_AGENT="$ROOT/agent.jsonl"
{ srec "implement phase 2 of the design doc"
  jq -nc '{type:"assistant",isSidechain:true,message:{content:[{type:"text",text:"working"}]},timestamp:"2026-09-13T20:00:01.000Z"}'; } > "$T_AGENT"

# no assistant text anywhere: the StructuredOutput-only headless shape.
T_NOTEXT="$ROOT/notext.jsonl"
{ urec "fix the test"; jq -nc '{type:"assistant",isSidechain:false,message:{content:[{type:"tool_use",name:"Bash",input:{}}]},timestamp:"2026-09-13T20:00:01.000Z"}'; } > "$T_NOTEXT"

T_MISSING="$ROOT/never-written.jsonl"   # claude -p: the path never materializes

stop_payload() {  # stop_payload <transcript> <text>
  jq -n --arg t "$1" --arg m "$2" \
    '{hook_event_name:"Stop",stop_hook_active:false,session_id:"t",transcript_path:$t,last_assistant_message:$m}'
}

# Instruction-test fixtures: canned Jev answers served from file:// URLs, so the
# Jev path is exercised offline.
T_VERBQ="$ROOT/verbq.jsonl"   # verb-initial question: the verb list's false block
{ arec "an earlier reply"; urec "do we have separate worktrees?"; } > "$T_VERBQ"
jev_answer() {  # jev_answer <name> <noul>: write a canned Jev response, print its URL
  jq -nc --argjson p "$2" '{model:"jev-1.13.0",answers:{instruction:{type:"noul",noul:$p}}}' > "$ROOT/$1.json"
  printf 'file://%s/%s.json' "$ROOT" "$1"
}
JEV_LOW=$(jev_answer low 0.05)
JEV_HIGH=$(jev_answer high 0.95)
JEV_MID=$(jev_answer mid 0.6)
printf '{"error":"rate limited"}' > "$ROOT/garbage.json"
JEV_GARBAGE="file://$ROOT/garbage.json"
JEV_DOWN="file://$ROOT/never-written.json"

# Settings for each hook run. Default: Jev off, so every case outside the
# instruction-test section runs the verb-list fallback exactly as before.
HOOK_ENV=(PROSE_JEV=off)
# Every run logs here, never to the real ~/.local/state/prose/decisions.jsonl.
LOG="$ROOT/decisions.jsonl"
log_lines() { [ -f "$LOG" ] && wc -l < "$LOG" || echo 0; }
# check_log <label> <jq predicate on the newest record>
check_log() {
  if [ -f "$LOG" ] && tail -n1 "$LOG" | jq -e "$2" >/dev/null 2>&1; then
    pass=$((pass+1)); printf 'PASS  [log] %s\n' "$1"
  else
    fail=$((fail+1)); printf 'FAIL  [log] %s\n      -> %s\n' "$1" "$(tail -n1 "$LOG" 2>/dev/null | head -c 200)"
  fi
}
jev_env() {  # jev_env <url> [VAR=val...]: Jev on against a canned answer
  HOOK_ENV=(PROSE_JEV=on ESCOTE_TYPESAFE_API_KEY=canned "PROSE_JEV_URL=$1" "${@:2}")
}

# ---------- runner ----------
pass=0; fail=0
run() {  # run <expect block|allow> <label> <payload-json>
  local expect="$1" label="$2" payload="$3" out decision
  out=$(printf '%s' "$payload" | env "PROSE_LOG=$LOG" "${HOOK_ENV[@]}" bash "$HOOK" 2>/dev/null)
  decision=$(printf '%s' "$out" | jq -r '.decision // "allow"' 2>/dev/null)
  if [ "$decision" = "$expect" ]; then
    pass=$((pass+1)); printf 'PASS  [%s] %s\n' "$expect" "$label"
  else
    fail=$((fail+1)); printf 'FAIL  [want %s got %s] %s\n      -> %s\n' \
      "$expect" "$decision" "$label" "$(printf '%s' "$out" | jq -r '.reason // .' 2>/dev/null | head -c 200)"
  fi
}

echo "=== em-dash (rules/safety.md) ==="
run block "literal U+2014 in the final text" \
  "$(stop_payload "$T_PARTIAL" "The fix landed${EMDASH}CI is green.")"
run allow "same sentence recast with a colon" \
  "$(stop_payload "$T_PARTIAL" "The fix landed: CI is green.")"
run block "U+2014 with no transcript at all (rule needs no prompt)" \
  "$(stop_payload "$T_MISSING" "The fix landed${EMDASH}CI is green.")"
run allow "the escape text \\u{2014} with no literal" \
  "$(stop_payload "$T_PARTIAL" 'Assert absence with the escape \u{2014} form.')"

echo "=== offer-closer (output-styles/edges.md) ==="
run block "offer after an imperative prompt" \
  "$(stop_payload "$T_PARTIAL" "Done. Want me to run it?")"
run allow "no offer after an imperative prompt" \
  "$(stop_payload "$T_PARTIAL" "Done. The test passes.")"
run block "offer after a fully flushed transcript" \
  "$(stop_payload "$T_FLUSHED" "Done. Want me to run it?")"
run allow "offer after a question, not an imperative" \
  "$(stop_payload "$T_QUESTION" "Done. Want me to run it?")"
run block "offer after a bare go-ahead" \
  "$(stop_payload "$T_GOAHEAD" "Pushed. Say the word and I will tag it.")"
run allow "offer after a prompt that is neither verb-initial nor a go-ahead" \
  "$(stop_payload "$T_NEITHER" "Done. Want me to run it?")"
run block "offer after a slash command (last-prompt record)" \
  "$(stop_payload "$T_SLASH" "Both PRs are green. Want me to merge them?")"
run allow "the offer phrase only inside a backtick span" \
  "$(stop_payload "$T_PARTIAL" 'Searched the tree for `Say the word` and found 43 hits.')"
run allow "the offer phrase only inside a fenced block" \
  "$(stop_payload "$T_PARTIAL" "$(printf 'Here is the grep:\n\n```\nWant me to run it?\n```\n\nFour hits total.')")"
run allow "the offer phrase is not the final sentence" \
  "$(stop_payload "$T_PARTIAL" "Want me to keep going was the old closer. It is gone from every reply now.")"
run block "offer whose sentence carries a dotted filename" \
  "$(stop_payload "$T_PARTIAL" "Rule moved. Want me to update edges.md?")"

echo "=== instruction test: Jev, with verb-list fallback ==="
run block "Jev off: verb-initial question still blocks (the false block Jev fixes)" \
  "$(stop_payload "$T_VERBQ" "Done. Want me to run it?")"
jev_env "$JEV_LOW"
run allow "Jev p=0.05 on a verb-initial question: not an instruction" \
  "$(stop_payload "$T_VERBQ" "Done. Want me to run it?")"
jev_env "$JEV_HIGH"
run block "Jev p=0.95 on a prompt the verb list misses" \
  "$(stop_payload "$T_NEITHER" "Done. Want me to run it?")"
jev_env "$JEV_LOW"
run block "slash command blocks without asking Jev (Jev says 0.05)" \
  "$(stop_payload "$T_SLASH" "Both PRs are green. Want me to merge them?")"
jev_env "$JEV_LOW"
run allow "Jev consulted only on an offer: no offer, no block" \
  "$(stop_payload "$T_PARTIAL" "Done. The test passes.")"
jev_env "$JEV_MID"
run block "Jev p=0.6 meets the default 0.5 threshold" \
  "$(stop_payload "$T_NEITHER" "Done. Want me to run it?")"
jev_env "$JEV_MID" PROSE_JEV_THRESHOLD=0.7
run allow "Jev p=0.6 under a raised 0.7 threshold" \
  "$(stop_payload "$T_NEITHER" "Done. Want me to run it?")"
jev_env "$JEV_DOWN"
run block "Jev unreachable: verb list decides (verb-initial blocks)" \
  "$(stop_payload "$T_VERBQ" "Done. Want me to run it?")"
jev_env "$JEV_GARBAGE"
run block "Jev answers an unknown shape: verb list decides" \
  "$(stop_payload "$T_VERBQ" "Done. Want me to run it?")"
run allow "Jev answers an unknown shape: verb list decides (non-verb prompt allows)" \
  "$(stop_payload "$T_NEITHER" "Done. Want me to run it?")"
HOOK_ENV=(PROSE_JEV=on ESCOTE_TYPESAFE_API_KEY= "PROSE_JEV_URL=$JEV_LOW")
run block "Jev on but no key: verb list decides, no call" \
  "$(stop_payload "$T_VERBQ" "Done. Want me to run it?")"
jev_env "$JEV_LOW" PROSE_JEV=off
run block "PROSE_JEV=off kill switch beats a key and a URL" \
  "$(stop_payload "$T_VERBQ" "Done. Want me to run it?")"
HOOK_ENV=(PROSE_JEV=off)

echo "=== decision log (one record per instruction test, either verdict) ==="
jev_env "$JEV_LOW"
run allow "log: Jev allow" "$(stop_payload "$T_VERBQ" "Done. Want me to run it?")"
check_log "allow recorded with source jev, p 0.05, no reason, the prompt and final sentence" \
  '.verdict=="allow" and .source=="jev" and .p==0.05 and .reason==null and .threshold==0.5
   and .prompt=="do we have separate worktrees?" and .final=="Want me to run it" and .event=="Stop"'
jev_env "$JEV_HIGH"
run block "log: Jev block" "$(stop_payload "$T_NEITHER" "Done. Want me to run it?")"
check_log "block recorded too (the transcript drops stderr on a block)" \
  '.verdict=="block" and .source=="jev" and .p==0.95'
jev_env "$JEV_DOWN"
run block "log: unreachable" "$(stop_payload "$T_VERBQ" "Done. Want me to run it?")"
check_log "unreachable names curl's exit code (37: file not found)" \
  '.source=="verbs" and .reason=="curl-exit-37" and .p==null'
jev_env "$JEV_GARBAGE"
run block "log: bad answer" "$(stop_payload "$T_VERBQ" "Done. Want me to run it?")"
check_log "unknown answer shape is bad-answer" '.source=="verbs" and .reason=="bad-answer"'
HOOK_ENV=(PROSE_JEV=on ESCOTE_TYPESAFE_API_KEY= "PROSE_JEV_URL=$JEV_LOW")
run block "log: no key" "$(stop_payload "$T_VERBQ" "Done. Want me to run it?")"
check_log "missing key is no-key" '.source=="verbs" and .reason=="no-key" and .ms==0'
HOOK_ENV=(PROSE_JEV=off)
run block "log: kill switch" "$(stop_payload "$T_VERBQ" "Done. Want me to run it?")"
check_log "kill switch is off" '.source=="verbs" and .reason=="off"'
jev_env "$JEV_LOW"
run block "log: slash" "$(stop_payload "$T_SLASH" "Both PRs are green. Want me to merge them?")"
check_log "slash command is source slash, no p" '.source=="slash" and .p==null and .verdict=="block"'
before=$(log_lines)
run allow "log: no offer" "$(stop_payload "$T_PARTIAL" "Done. The test passes.")"
if [ "$(log_lines)" -eq "$before" ]; then
  pass=$((pass+1)); echo "PASS  [log] no offer, no instruction test, no record"
else
  fail=$((fail+1)); echo "FAIL  [log] a reply with no offer wrote a record"
fi
jev_env "$JEV_LOW" "PROSE_LOG=/proc/prose-test/decisions.jsonl"
run allow "unwritable log never changes the verdict" "$(stop_payload "$T_VERBQ" "Done. Want me to run it?")"
jev_env "$JEV_HIGH" "PROSE_LOG=/proc/prose-test/decisions.jsonl"
run block "unwritable log never changes a block either" "$(stop_payload "$T_NEITHER" "Done. Want me to run it?")"
HOOK_ENV=(PROSE_JEV=off)

echo "=== decision ask over 40 lines (rules/interaction.md) ==="
LONG_REC=$(printf 'The problem\n%s\nRec: A\n' "$(for i in $(seq 1 42); do echo "- bullet $i"; done)")
SHORT_REC=$(printf 'The problem\n- one\n- two\n\nA: do it\nB: do not\n\nRec: A\n')
LONG_Q=$(printf '%s\nWhich one do you want?\n' "$(for i in $(seq 1 42); do echo "- bullet $i"; done)")
LONG_PLAIN=$(printf '%s\nAll 42 checks are green.\n' "$(for i in $(seq 1 42); do echo "- bullet $i"; done)")
run block "Rec: line in 45 lines" "$(stop_payload "$T_PARTIAL" "$LONG_REC")"
run allow "Rec: line in 8 lines"  "$(stop_payload "$T_PARTIAL" "$SHORT_REC")"
run block "trailing question in 44 lines" "$(stop_payload "$T_PARTIAL" "$LONG_Q")"
run allow "44 lines, no Rec: and no trailing question" "$(stop_payload "$T_PARTIAL" "$LONG_PLAIN")"

echo "=== pass-throughs ==="
run allow "stop_hook_active true, offending text" \
  "$(jq -n --arg t "$T_PARTIAL" --arg m "Done. Want me to run it?" \
     '{hook_event_name:"Stop",stop_hook_active:true,session_id:"t",transcript_path:$t,last_assistant_message:$m}')"
run allow "empty last_assistant_message and no assistant text in the transcript" \
  "$(jq -n --arg t "$T_NOTEXT" '{hook_event_name:"Stop",stop_hook_active:false,session_id:"t",transcript_path:$t}')"
run allow "lagging transcript: prompt precedes the prior reply, payload differs" \
  "$(stop_payload "$T_LAG" "Done. Want me to run it?")"
run allow "missing transcript (claude -p writes none)" \
  "$(stop_payload "$T_MISSING" "Done. Want me to run it?")"
run allow "agent relay is not a typed prompt" \
  "$(stop_payload "$T_RELAY" "Done. Want me to run it?")"
run allow "malformed payload" 'not json at all'

echo "=== SubagentStop ==="
run block "offer after the dispatch prompt" \
  "$(jq -n --arg t "$T_AGENT" --arg m "Phase 2 is committed. Want me to start phase 3?" \
     '{hook_event_name:"SubagentStop",stop_hook_active:false,session_id:"t",transcript_path:"/nonexistent.jsonl",agent_transcript_path:$t,agent_id:"a",agent_type:"general-purpose",last_assistant_message:$m}')"
run allow "no offer after the dispatch prompt" \
  "$(jq -n --arg t "$T_AGENT" --arg m "Phase 2 is committed: 3 files, tests green." \
     '{hook_event_name:"SubagentStop",stop_hook_active:false,session_id:"t",transcript_path:"/nonexistent.jsonl",agent_transcript_path:$t,agent_id:"a",agent_type:"general-purpose",last_assistant_message:$m}')"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
