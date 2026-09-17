#!/bin/bash
# slack-post-guard.sh: a Slack post goes where Scott named, once, and not as a
# test. Registered on the three Slack MCP write tools AND on the Bash matcher,
# because both surfaces post: the raw `slack` binary and the MCP tools are the
# two live paths (the plugin's own write skills are off in skillOverrides).
#
# THREE RULES, and the first deny wins:
#
#   TARGET     a post to a non-exempt recipient needs EITHER that recipient
#              named in the last 3 typed turns, OR a recent typed turn that
#              asks for a Slack post at all. Failing both denies.
#   TEST-TEXT  a first line that IS a test marker (short, or opening with
#              test/verify) is denied to any non-exempt recipient. The
#              2026-07-10 class: five live posts and an MCP write test into a
#              coworker DM during a shakedown.
#   RESEND     the same body to the same target twice is denied. The 2026-06-09
#              class: one post asked, two sent.
#
# TARGET HAS TWO SUFFICIENT CONDITIONS BECAUSE ONE WAS NOT ENOUGH, AND THE
# EVIDENCE IS THE CORPUS. The first cut required the recipient to be named in
# the current turn. Replayed against 211 historical posts with their real typed
# prompts it denied 79 of them, 37%, including:
#
#   "message russ to point at valet.test.tatari.dev and enroll"   -> DENIED
#   "send a message to ryan. codeblock with the json change"      -> DENIED
#   "ok lets send the message to Nick"                            -> DENIED
#   "i didnt ask for a draft. I asked you to send it"             -> DENIED
#   `slack write --help`                                          -> DENIED
#
# Two root causes. The id cache CANNOT resolve a DM to a name: its `users` map
# holds 120 DM ids and the ones in real traffic are absent (D01TL0BDQ4T,
# D0AH0DP9RJ5, D0B8FU6DLKU), so the rule collapsed into "the prompt must carry
# the raw id", which this design measured as blocking 72% of legitimate posts.
# And a posting task runs across turns: the turn that names the target is
# followed by "do it", "yes", "WAY TOO WORDY", not by a restatement.
#
# With the window and the second condition: 9 real denies of 214, and every one
# of them is a post no recent turn asked for ("force push the branches", a
# shakedown burst, "loos like 4 .json files?"). The 2026-07-10 shakedown posts
# still deny, which is the recall this rule exists for.
#
# What that gives up: "the right ask to the wrong channel" now passes when the
# channel is not the one named. No incident in the corpus is that shape; every
# one is an unasked post, a duplicate, or a test post.
#
# THE EXEMPT PAIR is `#clipboard` (C0ANJQAJC7N) and Scott's own DM
# (D01G4Q7AWLV), hardcoded as literals rather than resolved. `#clipboard` is a
# private channel Scott is the only member of and does not appear in the
# cache's 823 channels at all, so no resolution could find it. Being literals
# is also what lets them stay allowed when the cache or the transcript is
# unreadable, which is the state every other target denies in.
#
# THE EXEMPTION IS A BOUND ON THE FULL RECIPIENT SET, NOT ON THE NAMED TARGET.
# One call reaches past its target three ways, all confirmed in the client:
# `--broadcast` crossposts the body (cli.rs:278-287), `dm_mentioned` DMs the
# permalink to everyone the body mentions with usergroups expanded
# (mcp/request.rs:102-112), and `follow_ups` threads additional bodies under
# the parent (mcp/request.rs:113-122). So a post whose primary target is
# `#clipboard` can still land in a coworker's DM, and TEST-TEXT runs over every
# follow-up body as well as the primary one.
#
# THE SCAN IS GATED, AND THAT IS A LATENCY REQUIREMENT RATHER THAN AN
# OPTIMIZATION. Phase 0 measured the ungated shape at 230 ms per Bash call
# against a 250 ms whole-chunk budget, and the gated shape at 27 ms. So the
# command predicate runs FIRST and `lib.sh` is not even sourced until a Slack
# post is in hand. A 200K tail instead of 4 MB would be cheaper still and is
# not available: a 200K tail reaches the turn's prompt record on 51.7% of tool
# calls, 4 MB on 99.9%.
#
# FAIL CLOSED ON WHAT IT CANNOT READ, NOT ON WHAT IT CANNOT RESOLVE. An
# unreadable `lib.sh`, an unreadable transcript, a command this script cannot
# parse: those deny, and the exempt pair still passes because it needs none of
# them. A recipient the CACHE cannot resolve does not deny, and that
# distinction is the fix: denying on "I do not know whose DM this is" is how
# the first cut blocked "message russ".
#
# RESEND'S STATE IS A DIRECTORY OF ENTRY FILES AND THE MUTUAL EXCLUSION IS THE
# FILESYSTEM'S. A PreToolUse process exits before the tool runs, so a lock it
# holds cannot span the send and two sessions still interleave. Instead the
# PreToolUse half creates `<ledger>/<target>-<body-hash>` with O_EXCL: the
# create IS the reservation, and a create that fails because the entry exists
# is a deny whatever state that entry is in. The PostToolUse half marks the
# entry sent. A FAILED call leaves the entry in place, because a failure does
# not mean nothing was sent (`post_chunks` can fail after the parent has
# landed) and a PostToolUseFailure payload carries an `error` string with no
# tool_response, so there is nothing per-recipient to read. The cost is that a
# genuinely failed send waits out the hour or needs one `rm`, and the deny text
# names the exact file.
#
# EXPIRY IS RECLAIMED UNDER ITS OWN O_EXCL LOCK, NOT BY A RENAME. See
# reclaim_entry below: the doc prescribed renaming a fresh temp entry OVER the
# expired path, which is atomic but is not a compare-and-swap, so two racers
# that both observe the same expired entry both rename and both proceed.
# Reclamation takes a separate O_EXCL lock and never moves the entry.
#
# Emits a PreToolUse "deny" decision (with a reason Claude sees), or '{}'.

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

case "${1:-}" in
  -h|--help)
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit 0
    ;;
  --self-test)
    exec bash "$HOOKS/slack-post-guard-test.sh"
    ;;
esac

EXEMPT_CLIPBOARD="C0ANJQAJC7N"
EXEMPT_DM="D01G4Q7AWLV"
IDS="$HOME/.cache/slack/ids.json"
LEDGER="$HOME/.cache/slack/sent-ledger"
ENTRY_TTL=3600
CACHE_TTL=86400
CACHE_SCHEMA=2
TAIL_CAP=4000000
# How many typed turns back a posting task stays live. DO NOT WIDEN THIS. The
# number is measured twice over, and past 5 the rule starts eating the
# incidents it exists to catch.
#
# Where the authorizing turn actually sits, over 181 historical posts:
#
#   distance 1:  53.6%      distance 3:  72.9% cumulative
#   distance 2:  71.3%      then a thin scattered tail to 11, and 22 posts
#                           with no posting ask anywhere in the session
#
# A sharp cliff after 2, so 3 has margin without reaching. And the window's
# effect on the real denies, replayed against the corpus:
#
#   window  3    7 real denies
#   window  5    7 real denies, identical set
#   window  8    3, and the 4 it gives up include "force push the branches"
#                and the /cli-shakedown turns, which ARE the incident classes
#   window 12    0. The rule is inert.
PROMPT_WINDOW=3
REFRESH_CMD="slack cache refresh"

allow() { echo '{}'; exit 0; }

deny() { # deny <reason>
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

input=$(cat)
[ -z "$input" ] && allow

# ONE jq spawn on the hot path, not three. Measured on this machine: jq costs
# ~23 ms per invocation, so reading event, tool and command separately spent
# 71 ms on a plain `git status` and blew the 50 ms gate criterion on its own,
# before any transcript was read. The command rides base64 because it can carry
# newlines and tabs, and it is decoded only once the gate has passed.
mapfile -t payload < <(printf '%s' "$input" | jq -r '
  (.hook_event_name // "PreToolUse"),
  (.tool_name // ""),
  ((.tool_input.command // "") | @base64)' 2>/dev/null)
event="${payload[0]:-PreToolUse}"
tool="${payload[1]:-}"

# THE CHEAP PREDICATE. Nothing above this line reads a file and nothing below
# it runs for a command that is not a Slack post. The substring test is
# deliberately over-inclusive (`slackify` passes it and is rejected by
# cmdword_is a few lines later); it exists to make the common case, every
# non-Slack Bash call in every session, cost one `case`.
surface=""
case "$tool" in
  mcp__slack__chat_post_message|mcp__slack__chat_schedule_message|mcp__slack__chat_update)
    surface="mcp" ;;
  Bash)
    command=$(printf '%s' "${payload[2]:-}" | base64 -d 2>/dev/null)
    case "$command" in
      *slack*) surface="bash" ;;
      *) allow ;;
    esac
    ;;
  *) allow ;;
esac

# Fail-closed sourcing, which is NOT the tree's fail-open line. `lib.sh:5`'s
# `|| { echo '{}'; exit 0; }` emits an allow before any rule evaluates, which is
# right for a linter and wrong for an authorization gate.
LIB_OK=1
. "$HOOKS/lib.sh" 2>/dev/null || LIB_OK=0
[ "$LIB_OK" -eq 0 ] && deny "slack-post-guard: lib.sh is unreadable, so the command cannot be parsed and a Slack post cannot be authorized. Fix $HOOKS/lib.sh."

# ---------------------------------------------------------------- parsing ---

# Every value-taking flag `slack write` has. A token matching one of these
# consumes the NEXT token, so that operand is never mistaken for the target.
WRITE_VALUE_FLAGS=" --thread --broadcast --at --follow-up --edit --file --markdown-to-mrkdwn --blocks-file "

is_write_value_flag() { case "$WRITE_VALUE_FLAGS" in *" $1 "*) return 0;; esac; return 1; }

# Sanitize a target or hash into a filename component. A target can carry `#`
# and a permalink can carry `/`, neither of which belongs in a path segment.
sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

# has_mask <token>
#
# lib.sh's maskers replace masked bytes with \001 and preserve length, so a
# token carrying \001 came out of a comment or a heredoc body rather than out of
# the command line. An UNQUOTED `#channel` is the case that matters: bash reads
# it as a comment, so `slack write #engineering hi` runs `slack write` with no
# arguments at all. A target like that is a parse failure, and a parse failure
# in an authorization gate denies.
has_mask() { case "$1" in *$'\001'*) return 0 ;; esac; return 1; }

body_hash() { printf '%s' "$1" | sha256sum | cut -c1-32; }

# first_line_is_test <body>
#
# Purely textual on purpose. The audit's phrasing ("no live posts during a
# /cli-shakedown") is not implementable from a hook: nothing in the payload
# says a shakedown is running.
first_line_is_test() {
  local first
  first=$(printf '%s' "$1" | head -1)
  # A test MARKER, not prose that happens to mention a test. Matching the word
  # anywhere in the first line denied two real posts in the historical replay:
  # "marquee DID already ship its own MCP-auth path: live on test and prod, ..."
  # and "the host the cli defaults to (`valet.internal.tatari.dev`) just isnt
  # deployed yet, only the test one is." Both are ordinary English about test
  # environments in a 180-character sentence.
  #
  # The incident is `**MCP write test**`: a short line that IS the marker. So
  # the word counts when the whole first line is short enough to be a marker,
  # or when it opens the line.
  case "$first" in
    *[Tt][Ee][Ss][Tt]*|*[Vv][Ee][Rr][Ii][Ff][Yy]*) ;;
    *) return 1 ;;
  esac
  if [ "${#first}" -le 60 ] \
     && printf '%s' "$first" | grep -qiE '(^|[^[:alnum:]])(test|testing|verify|verifying)([^[:alnum:]]|$)'; then
    return 0
  fi
  printf '%s' "$first" \
    | grep -qiE '^[^[:alnum:]]*(test|testing|verify|verifying)([^[:alnum:]]|$)' && return 0
  return 1
}

# read_body_file <path> -> the text that will be sent
#
# A body read from a file is checked as the text that will be sent, not as the
# filename. An unreadable path is a parse failure, which denies.
read_body_file() {
  local p="$1"
  case "$p" in "~/"*) p="$HOME/${p#\~/}" ;; esac
  [ -r "$p" ] || return 1
  cat "$p"
}

# ---------------------------------------------------------------- the cache ---

cache_state() { # -> fresh|stale|schema|missing
  [ -r "$IDS" ] || { echo missing; return; }
  local schema users groups now
  schema=$(jq -r '.schema // 0' "$IDS" 2>/dev/null) || { echo missing; return; }
  [ "$schema" = "$CACHE_SCHEMA" ] || { echo schema; return; }
  users=$(jq -r '.users_synced_at // 0' "$IDS" 2>/dev/null)
  groups=$(jq -r '.usergroups_synced_at // 0' "$IDS" 2>/dev/null)
  now=$(date +%s)
  if [ $((now - users)) -gt "$CACHE_TTL" ] || [ $((now - groups)) -gt "$CACHE_TTL" ]; then
    echo stale
  else
    echo fresh
  fi
}

# resolve_names <spelling> -> one acceptable name per line, id first
#
# Answers "what would Scott have typed to mean this recipient". A channel is
# its id, its `#name` and its bare name; a DM is its id, the person's handle,
# display name, real name and first name. The spelling itself is always
# acceptable, which is what lets an unresolvable `#foo` still pass when the
# prompt says `#foo`.
resolve_names() {
  local spell="$1"
  printf '%s\n' "$spell"
  [ -r "$IDS" ] || return 0
  jq -r --arg s "$spell" '
    def bare: if startswith("#") then .[1:] else . end;
    ($s | bare) as $b
    | ( .channels // {} ) as $ch
    | ( .dms // {} ) as $dm
    | ( .handles // {} ) as $hd
    | ( .profiles // {} ) as $pr
    | ( .subteams // {} ) as $st
    # channel: by id, or by name back to its id
    | ( [ $ch | to_entries[] | select(.key == $s or .value == $b) ] ) as $chits
    # dm: by dm id, which the dms map takes straight to a user id
    | ( [ $dm | to_entries[] | select(.key == $s) ] ) as $dmits
    # user: by user id or handle, which dm_mentioned recipients arrive as
    | ( [ $hd | to_entries[] | select(.key == $s or .value == $b) ] ) as $uits
    | ( [ $st | to_entries[] | select(.key == $s or .value.handle == $b) ] ) as $sits
    | [ ( $chits[] | .key, .value, ("#" + .value) ),
        ( $dmits[] | .key, .value, ( $hd[.value] // empty ) ),
        ( $uits[]  | .key, .value ),
        ( $sits[]  | .key, .value.handle, .value.name )
      ] as $ids
    | ( [ $ids[], ( $dmits[] | .value ), ( $uits[] | .value ) ] ) as $keys
    | ( [ $keys[] | select(startswith("U")) ] ) as $uids
    | ( [ $ids[],
          ( $uids[] as $u | $pr[$u] // empty | .display_name, .real_name ) ]
        | map(select(. != null and . != "")) | unique )[]
  ' "$IDS" 2>/dev/null
  # First names, derived rather than stored: `scott.idler` -> `scott`, and
  # `Philip Inghelbrecht` -> `Philip`. Three characters minimum, so a two-letter
  # fragment cannot authorize a post by appearing somewhere in the prompt.
  jq -r --arg s "$spell" '
    def bare: if startswith("#") then .[1:] else . end;
    ($s | bare) as $b
    | ( .dms // {} ) as $dm
    | ( .handles // {} ) as $hd
    | ( .profiles // {} ) as $pr
    | ( [ $dm | to_entries[] | select(.key == $s) | .value ] ) as $dmuids
    | [ ( $dmuids[] | $hd[.] // empty ),
        ( $hd | to_entries[] | select(.key == $s or .value == $b) | .value ) ] as $handles
    | ( [ $handles[] as $h | $hd | to_entries[] | select(.value == $h) | .key ]
        + $dmuids ) as $uids
    | [ ( $handles[] | split(".")[0] ),
        ( $uids[] as $u | $pr[$u] // empty | (.real_name // "") | split(" ")[0] ),
        ( $uids[] as $u | $pr[$u] // empty | (.display_name // "") | split(".")[0] ) ]
    | map(select(. != null and (. | length) >= 3)) | unique | .[]
  ' "$IDS" 2>/dev/null
}

# Scott's own DM and #clipboard, in every spelling the corpus uses. The ids are
# literals so the pair needs no cache and no prompt; the handles are here
# because `slack write '@scott.idler' --at ... ` is how he actually addresses
# his own DM, and the guard denied it.
is_exempt_spelling() {
  case "$1" in
    "$EXEMPT_CLIPBOARD"|"$EXEMPT_DM") return 0 ;;
    clipboard|\#clipboard) return 0 ;;
    scott.idler|@scott.idler|scott|@scott|escote|@escote) return 0 ;;
  esac
  return 1
}

# is_dm_spelling <spelling> -> 0 when this recipient is a person, not a channel
#
# Variant B's discriminator. A `D…` or `U…` id is a DM by construction; a bare
# spelling is a DM when it resolves to a handle and NOT to a channel, which is
# how a `dm_mentioned` fan-out recipient arrives. An unresolvable spelling is
# treated as not-a-DM, so the weak condition still covers it.
is_dm_spelling() {
  local s="$1" b="${s#@}"
  case "$s" in
    \#*) return 1 ;;
    D[A-Z0-9][A-Z0-9][A-Z0-9]*) return 0 ;;
    U[A-Z0-9][A-Z0-9][A-Z0-9]*) return 0 ;;
  esac
  [ -r "$IDS" ] || return 1
  jq -e --arg s "$s" --arg b "$b" '
    ( .channels // {} ) as $ch
    | ( .handles // {} ) as $hd
    | if ( [ $ch | to_entries[] | select(.key == $s or .value == $b) ] | length ) > 0
      then false
      else ( [ $hd | to_entries[] | select(.key == $s or .value == $b) ] | length ) > 0
      end
  ' "$IDS" >/dev/null 2>&1
}

# ------------------------------------------------------------ the prompt ---

# typed_prompt -> the last PROMPT_WINDOW typed human turns, newest last
#
# A WINDOW, not the current turn, and that is the whole difference between a
# guard that catches the unasked post and one that blocks the asked one.
# Measured over 211 historical posts: reading only the current turn denied 37%
# of them, because a posting task runs across turns. "message russ to point at
# valet.test.tatari.dev and enroll" establishes it, and the turns that follow
# are "do it", "yes", "WAY TOO WORDY", "did you fucking fix your mess?", not a
# restatement of the target. Nineteen of the denies were exactly that shape.
#
# Criterion 8 measured two defects in the extractor this tree already ships
# (prose.sh:131-153) over 1,237 turns: it reads a teammate relay as Scott's own
# instruction on 22.0% of turns, and it discards every slash-command turn. Both
# are fixed here rather than inherited. The corrected extractor scored 0 relay
# and 0 wrapper false authorizations with a 0.57% miss rate.
typed_prompt() {
  local tp="$1" pid="$2"
  [ -r "$tp" ] || return 1
  # No `tail -n +2`. A 4 MB tail can start mid-record, and the prototype
  # dropped the first line to cope; that also drops a whole record from any
  # transcript SMALLER than the cap, which is most of them. `fromjson? // empty`
  # already discards the partial line and keeps every intact one.
  tail -c "$TAIL_CAP" "$tp" | jq -R 'fromjson? // empty' 2>/dev/null \
    | jq -s -r --arg pid "$pid" --arg w "$PROMPT_WINDOW" '
      def relay: startswith("Another Claude session sent a message:");
      def cmdwrap: test("^<command-(message|name|args)");
      def wrap: startswith("<");
      [ .[]
        | select(.type == "user")
        | select(.isSidechain != true)
        | select((.message.content | type) == "string")
        | {c: .message.content, p: (.promptId // "")}
        | select((.c | relay) | not)
        | select((.c | cmdwrap) or ((.c | wrap) | not))
      ] as $u
      | [ $u[] | select($pid != "" and .p == $pid) ] as $exact
      | ( [ $u[-($w | tonumber):][]?.c ] ) as $window
      | ( if ($exact | length) > 0 then [$exact[].c] else [] end ) as $now
      | ( $window + $now | unique_by(.) ) as $all
      | if ($all | length) > 0 then ($all | join("\n")) else "" end
    ' 2>/dev/null
}

# posting_intent <text> -> 0 when a recent typed turn asks for a Slack post
#
# The second sufficient condition for TARGET, and the one that makes the rule
# match its intent. The incidents are an unasked post, a duplicate post and a
# test post: none of them is "the right ask to the wrong channel". So a post
# that a live posting task covers is allowed even when the target is not named
# in so many words, and what the guard still denies is a post no recent turn
# asked for at all ("force push the branches", "yes, clear the stale requests
# and rebase onto main", "loos like 4 .json files?").
#
# The word set is taken from the 211 historical posts, not invented.
posting_intent() {
  # Strip XML-ish markup before matching. A slash-command turn arrives wrapped in
  # `<command-message>name</command-message>`, and the literal word `message`
  # inside that TAG matched the word set, so ANY slash-command turn in the window
  # authorized a post to any resolvable target. 58 of 400 sampled transcripts
  # carry the tag, and /cli-shakedown is one of the incident classes this rule
  # exists to catch. Only the delimiters go: inner text is the user's own words
  # and still counts, so `<command-args>send this to russ</command-args>` matches.
  printf '%s' "$1" | sed 's/<[^>]*>/ /g' | grep -qiE '(^|[^[:alnum:]])(post|posts|posted|posting|send|sends|sent|sending|share|shares|shared|sharing|announce|announced|announcement|message|messages|messaged|msg|dm|dms|slack|slackify|reply|replies|replied|ping|pings|notify|tell|thread|crosspost|cross-post|missive|clipboard|mrkdwn)([^[:alnum:]]|$)'
}

# prompt_names <prompt> <name>...  -> 0 when any name appears as a word
prompt_names() {
  local prompt="$1" n
  shift
  for n in "$@"; do
    [ -z "$n" ] && continue
    printf '%s' "$prompt" | grep -qiF -- "$n" || continue
    # Word-boundary confirm, so `#eng` does not authorize `#engineering` and a
    # name embedded in a longer token does not count.
    printf '%s' "$prompt" \
      | grep -qiE "(^|[^[:alnum:]_.-])$(printf '%s' "$n" | sed -e 's/[][\.*^$(){}?+|/\\-]/\\&/g')([^[:alnum:]_-]|$)" \
      && return 0
  done
  return 1
}

# ------------------------------------------------------------- the ledger ---

# reserve_entry <path> -> 0 when the reservation is ours
#
# The O_EXCL create IS the reservation. bash's noclobber redirect is O_EXCL, so
# two processes racing on the same path leave exactly one winner, and the
# exclusion spans processes because the create does.
reserve_entry() {
  local path="$1"
  ( set -o noclobber; : > "$path" ) 2>/dev/null
}

# reclaim_entry <path> -> 0 when the expired entry is now ours
#
# The doc prescribes "a single atomic rename of a freshly created temp entry
# over the old path". That rename is atomic and it is NOT a compare-and-swap:
# `mv temp path` succeeds whether or not `path` still holds the entry we
# observed, so two racers that both read the same expired mtime both rename and
# both proceed, which loses the exclusion the O_EXCL create exists to provide.
# Its own acceptance criterion ("two concurrent reclaims of the same expired
# entry leave exactly one allowed") cannot pass in that shape.
#
# Renaming the expired entry AWAY instead, to a name only this process knows,
# looks like the compare-and-swap it needs, and it was the first fix here. It
# still failed 1 round in 30 under 8 racers: whenever the taken file turns out
# to be someone else's fresh reservation it has to be put back, and for the
# length of that restore the path is EMPTY, so a third process's plain O_EXCL
# create succeeds and a second post goes out. Any scheme that removes a live
# entry even briefly has that window.
#
# So the exclusion is a separate O_EXCL lock and the entry is never moved. Only
# one process can be reclaiming a given pair, it re-reads the expiry while
# holding the lock, and a racer that arrives during the reclaim either wins the
# fresh create (and this process then denies) or sees the new entry and denies.
reclaim_entry() {
  # Two statements, not one. bash 5.3.9 does not make an earlier assignment in a
  # `local` visible to a later one in the SAME statement: `local p="$1"
  # c="$p.x"` yields `c=".x"`. That shipped here as `mv <entry> .claim.20.30341`
  # in the cwd, so every reclaim failed and an expired entry could never be
  # retaken.
  local path="$1"
  local lock="$path.reclaim"
  local r
  # A stale lock would wedge reclamation for this pair forever, so one older
  # than a minute is swept and this call denies; the next one reclaims. Two
  # processes sweeping the same stale lock both deny, which is safe. Removing
  # the ENTRY by hand, which is what the deny text asks for, bypasses the lock
  # entirely: the fresh O_EXCL create never consults it.
  if [ -e "$lock" ] && [ -n "$(find "$lock" -mmin +1 2>/dev/null)" ]; then
    rm -f "$lock" 2>/dev/null
    return 1
  fi
  ( set -o noclobber; : > "$lock" ) 2>/dev/null || return 1
  if entry_expired "$path"; then
    rm -f "$path" 2>/dev/null
    reserve_entry "$path"
    r=$?
  else
    r=1
  fi
  rm -f "$lock" 2>/dev/null
  return "$r"
}

entry_expired() { # entry_expired <path>
  local mtime now
  mtime=$(stat -c %Y "$1" 2>/dev/null) || return 1
  now=$(date +%s)
  [ $((now - mtime)) -gt "$ENTRY_TTL" ]
}

# ------------------------------------------------------------- extraction ---

target=""
body=""
posts=1          # 0 when the invocation posts nothing
is_edit=0        # chat_update / `--edit`: the opposite of a resend
dm_mentioned=0
mentions_off=0
broadcasts=()
follow_ups=()

if [ "$surface" = "mcp" ]; then
  [ "$tool" = "mcp__slack__chat_update" ] && is_edit=1
  target=$(printf '%s' "$input" | jq -r '.tool_input.channel // ""' 2>/dev/null)
  body=$(printf '%s' "$input" | jq -r '.tool_input.text // ""' 2>/dev/null)
  [ "$(printf '%s' "$input" | jq -r '.tool_input.dm_mentioned // false')" = "true" ] && dm_mentioned=1
  [ "$(printf '%s' "$input" | jq -r '.tool_input.raw // false')" = "true" ] && mentions_off=1
  [ "$(printf '%s' "$input" | jq -r '.tool_input.no_mentions // false')" = "true" ] && mentions_off=1
  while IFS= read -r f; do [ -n "$f" ] && follow_ups+=("$f"); done < <(
    printf '%s' "$input" | jq -r '(.tool_input.follow_ups // [])[]' 2>/dev/null)
  [ -z "$target" ] && deny "slack-post-guard: the post carries no channel, so its recipient cannot be established. Fail-closed."
else
  # The command word test runs on a mask_heredoc | mask_comment copy ONLY.
  # Quote-masking it makes the verb read as no verb at all, which is audit
  # finding CW1 and the defect that let `'echo' $GH_TOKEN` past
  # secret-echo-guard.sh until Phase 1 of this chunk.
  stmt_found=0
  post_stmts=0
  while IFS= read -r -d '' stmt; do
    verbscan=$(printf '%s' "$stmt" | mask_heredoc | mask_comment)
    printf '%s' "$verbscan" | cmdword_is slack >/dev/null 2>&1 || continue
    # Redirects come off first. `slack write --help 2>&1 | head -40` handed the
    # parser a `2` and it read that as the target, then denied because no prompt
    # names a channel called 2. Same sed the LN rule uses.
    mapfile -t toks < <(printf '%s' "$verbscan" \
      | sed -E 's/[0-9]*>>?&?[^[:space:]]*//g' | args)
    i=0; n=${#toks[@]}; seen_slack=0; subcmd=""
    while [ "$i" -lt "$n" ]; do
      tok="${toks[$i]}"; i=$((i + 1))
      if [ "$seen_slack" -eq 0 ]; then
        case "$tok" in slack|\\slack|*/slack) seen_slack=1 ;; esac
        continue
      fi
      case "$tok" in
        -*) continue ;;
        *) subcmd="$tok"; break ;;
      esac
    done
    case "$subcmd" in
      write|repost) ;;
      *) continue ;;
    esac
    stmt_found=1
    post_stmts=$((post_stmts + 1))
    if [ "$subcmd" = "repost" ]; then
      # `slack repost <source> <destination>`: the body is the source message,
      # which lives in Slack rather than on the command line. The target is the
      # destination, which is the second operand.
      ops=()
      while [ "$i" -lt "$n" ]; do
        tok="${toks[$i]}"; i=$((i + 1))
        case "$tok" in -*) continue ;; *) ops+=("$tok") ;; esac
      done
      [ "${#ops[@]}" -ge 2 ] || deny "slack-post-guard: \`slack repost\` was parsed with fewer than two operands, so its destination cannot be established. Fail-closed."
      target="${ops[1]}"
      body="repost:${ops[0]}"
      break
    fi
    # `slack write [flags] <target> [more flags] <content...>`. The flags do NOT
    # all precede the target: `content` is a `trailing_var_arg` positional, so
    # clap keeps parsing flags right up until the first content token and then
    # swallows everything, flags included ("Put flags before the content, not
    # after", cli.rs:246-250). A parser that stops accepting flags at the target
    # reads `--broadcast`, `--dm-mentioned` and `--edit` as body words, which is
    # three rules silently disarmed by argument order.
    content=()
    file_body=""
    preview=0
    content_started=0
    while [ "$i" -lt "$n" ]; do
      tok="${toks[$i]}"; i=$((i + 1))
      if [ "$content_started" -eq 1 ]; then
        content+=("$tok")
        continue
      fi
      case "$tok" in
        --broadcast) broadcasts+=("${toks[$i]}"); i=$((i + 1)) ;;
        --broadcast=*) broadcasts+=("${tok#*=}") ;;
        --follow-up) follow_ups+=("${toks[$i]}"); i=$((i + 1)) ;;
        --follow-up=*) follow_ups+=("${tok#*=}") ;;
        --file|--markdown-to-mrkdwn|--blocks-file)
          file_body="${toks[$i]}"; i=$((i + 1)) ;;
        --file=*|--markdown-to-mrkdwn=*|--blocks-file=*)
          file_body="${tok#*=}" ;;
        --edit) is_edit=1; i=$((i + 1)) ;;
        --edit=*) is_edit=1 ;;
        --print|--help|-h) posts=0 ;;
        --preview) preview=1 ;;
        --dm-mentioned) dm_mentioned=1 ;;
        --raw|--no-mentions) mentions_off=1 ;;
        -*) is_write_value_flag "$tok" && i=$((i + 1)) ;;
        *)
          if [ -z "$target" ]; then
            target="$tok"
          else
            content_started=1
            content+=("$tok")
          fi
          ;;
      esac
    done
    # `--preview` posts to the caller's own self-DM as a render sandbox, which
    # is the exempt DM whatever the target said.
    [ "$preview" -eq 1 ] && target="$EXEMPT_DM"
    if [ -n "$file_body" ]; then
      body=$(read_body_file "$file_body") || deny "slack-post-guard: the body file $file_body is unreadable, so the text that would be sent cannot be checked. Fail-closed."
    else
      body="${content[*]}"
    fi
  done < <(printf '%s' "$command" | stmts)
  [ "$stmt_found" -eq 1 ] || allow
  # The loop used to `break` after the first posting statement, so everything
  # below judged statement one and the rest of the command was never seen:
  # `slack write scott.idler aaa; slack write engineering bbb` allowed, because
  # the exempt first target authorized the second post. Everything downstream
  # (the recipient set, TARGET, TEST-TEXT, the RESEND ledger entry) is built
  # from ONE statement's variables, so the honest fix is to refuse the shape
  # rather than silently authorize on the first one. Two posts in one command
  # is also the 2026-06-09 duplicate class. Splitting the command is the remedy
  # and the deny says so.
  if [ "$post_stmts" -gt 1 ]; then
    deny "slack-post-guard: this command carries $post_stmts Slack posting statements and the guard authorizes one at a time, so the later ones would ride on the first one's target. Split them into separate commands."
  fi
  # An invocation that posts nothing is nobody's business, and this has to come
  # BEFORE the target check: `slack write --help` has no target by construction,
  # and the no-target deny fired on it 20 times in the historical replay.
  [ "$posts" -eq 0 ] && allow
  has_mask "$target" && target=""
  [ -n "$target" ] || deny "slack-post-guard: a \`slack write\` was parsed with no target, so its recipient cannot be established. An unquoted \`#channel\` is the usual cause: bash reads it as a comment, so the CLI never sees it. Quote it, or use the bare channel name."
  for b in "${broadcasts[@]}"; do
    has_mask "$b" && deny "slack-post-guard: a \`--broadcast\` target was consumed by a shell comment, so the recipient set cannot be established. Quote it, or use the bare channel name."
  done
fi

[ "$posts" -eq 0 ] && allow

# ------------------------------------------------------- the recipient set ---

# Every recipient, one per line, as the spelling the command used. `--preview`
# has already rewritten the target to Scott's own DM, which is where the client
# sends it.
recipients=("$target")
for b in "${broadcasts[@]}"; do recipients+=("$b"); done

# dm_mentioned reaches everyone the body mentions, so the mentions are
# recipients in their own right. `raw` and `no_mentions` switch mention
# resolution off entirely, so nothing fans out.
mention_spellings=()
if [ "$dm_mentioned" -eq 1 ] && [ "$mentions_off" -eq 0 ]; then
  while IFS= read -r m; do
    [ -n "$m" ] && mention_spellings+=("$m")
  done < <(printf '%s\n' "$body" "${follow_ups[@]}" \
    | grep -oE '<@U[A-Z0-9]+>|<!subteam\^S[A-Z0-9]+>|(^|[^[:alnum:]_])@[A-Za-z0-9._-]+' 2>/dev/null \
    | sed -E 's/^[^<@]*//; s/^<@//; s/^<!subteam\^//; s/>$//; s/^@//')
  for m in "${mention_spellings[@]}"; do recipients+=("$m"); done
fi

nonexempt=()
for r in "${recipients[@]}"; do
  is_exempt_spelling "$r" || nonexempt+=("$r")
done

# The two exempt ids need no cache, no transcript and no confirmation. Scott,
# 2026-09-11: "change that to NOT do that when the fucking target is my own DM
# or #clipboard". A duplicate into a single-member private channel harms
# nobody, so the ledger does not run either.
[ "${#nonexempt[@]}" -eq 0 ] && allow

# The client's recipient set is authoritative and the guard never grants an
# exemption on a set it cannot vouch for: `fanout_recipients` refreshes a stale
# cache from the API before expanding (write.rs:785-787), so a cache past the
# client's own 24h TTL authorizes a smaller set than the client then sends to.
cstate=$(cache_state)
if [ "$dm_mentioned" -eq 1 ] && [ "$mentions_off" -eq 0 ] && [ "$cstate" != "fresh" ]; then
  deny "slack-post-guard: \`dm_mentioned\` fans the post out to everyone the body mentions, and the id cache is $cstate, so the recipient set cannot be established. Run \`$REFRESH_CMD\`, or drop dm_mentioned."
fi
if [ "$cstate" = "missing" ] || [ "$cstate" = "schema" ]; then
  deny "slack-post-guard: the id cache $IDS is $cstate, so a recipient cannot be resolved to a name Scott would have typed. Run \`$REFRESH_CMD\`. Posts to #clipboard and to your own DM are unaffected."
fi

# ---------------------------------------------------------------- TARGET ---

prompt_id=$(printf '%s' "$input" | jq -r '.prompt_id // ""' 2>/dev/null)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)
prompt=$(typed_prompt "$transcript" "$prompt_id") || prompt=""
if [ -z "$prompt" ]; then
  deny "slack-post-guard: the turn's typed prompt could not be read from the transcript, so there is no record of Scott naming a target. Fail-closed. Posts to #clipboard and to your own DM are unaffected."
fi

# Two sufficient conditions, and only failing BOTH denies.
#
#   1. the recipient is named in the window (the doc's rule)
#   2. a recent typed turn asks for a Slack post at all
#
# Condition 2 exists because condition 1 alone cannot be satisfied for a DM:
# the cache's `users` map holds 120 DM ids and the ones in real traffic are
# absent from it (D01TL0BDQ4T, D0AH0DP9RJ5, D0B8FU6DLKU all ABSENT), so a DM
# target resolves to nothing but its literal id and the rule collapses into
# "the prompt must contain the raw id", which this doc measured as blocking
# 72% of legitimate posts. It denied "message russ to point at
# valet.test.tatari.dev and enroll" for exactly that reason.
for r in "${nonexempt[@]}"; do
  mapfile -t names < <(resolve_names "$r")
  prompt_names "$prompt" "${names[@]}" && continue
  if is_dm_spelling "$r"; then
    deny "slack-post-guard: nothing in the last $PROMPT_WINDOW typed turns names \`$r\`. A DM goes to the person Scott named. Ask him, or post to #clipboard."
  fi
  posting_intent "$prompt" && continue
  deny "slack-post-guard: no typed turn in the last $PROMPT_WINDOW asked for a Slack post, and nothing in them names \`$r\`. A post goes where Scott asked for it. Ask him, or post to #clipboard."
done

# -------------------------------------------------------------- TEST-TEXT ---

for b in "$body" "${follow_ups[@]}"; do
  if first_line_is_test "$b"; then
    deny "slack-post-guard: the first line of a body reads as a test, and the recipients are not just #clipboard and your own DM. Send the test to #clipboard instead: 2026-07-10 put five live posts and an MCP write test into a coworker's DM."
  fi
done

# ----------------------------------------------------------------- RESEND ---

# Editing an existing message is the opposite of a resend, and it cannot fan
# out: ChatUpdateRequest carries no dm_mentioned and no follow_ups.
[ "$is_edit" -eq 1 ] && allow

entry_key="$(sanitize "$target")-$(body_hash "$body")"
entry="$LEDGER/$entry_key"

mkdir -p "$LEDGER" 2>/dev/null
[ -d "$LEDGER" ] && [ -w "$LEDGER" ] || deny "slack-post-guard: the send ledger $LEDGER is not writable, so a duplicate post cannot be ruled out. Fail-closed."

if [ "$event" = "PostToolUse" ]; then
  # The send is confirmed. Marking it refreshes the mtime, so the hour runs
  # from the send rather than from the reservation.
  [ -e "$entry" ] && printf 'sent %s\n' "$(date +%s)" > "$entry" 2>/dev/null
  allow
fi

if reserve_entry "$entry"; then
  printf 'reserved %s\n' "$(date +%s)" > "$entry" 2>/dev/null
  allow
fi

if entry_expired "$entry" && reclaim_entry "$entry"; then
  printf 'reserved %s\n' "$(date +%s)" > "$entry" 2>/dev/null
  allow
fi

deny "slack-post-guard: this exact body has already been sent to \`$target\` in the last hour, or a send of it is in flight. One post was asked for, so one post goes out. If the send genuinely failed and you mean to retry it, remove $entry."
