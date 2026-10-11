#!/bin/bash
# prose.sh: Stop / SubagentStop hook that gates the FINAL reply before Scott
# reads it. The prose rules it enforces are all in writing already, and the
# 2026-09-12 audit measured every one of them flat or rising after landing:
# offer-closers before a rage prompt at 25-41% against a 6% baseline, em-dashes
# in 31% of September turns under a ban living in 14 files, 671 decision asks
# with 28 following the shape. This is the layer that cannot be forgotten.
#
# WIRING: registered on Stop and SubagentStop in ~/.claude/settings.json. The
# harness pipes the stop payload to stdin when a turn ends; this script prints
# {} to let the turn end, or {"decision":"block","reason":...} to send the model
# back with the reason verbatim. The harness caps consecutive blocks at 8
# (CLAUDE_CODE_STOP_HOOK_BLOCK_CAP), so a hook bug cannot wedge a session.
#
# CLI (run manually, no stdin needed):
#   prose.sh --help        print this documentation
#   prose.sh --self-test   run the fixture matrix (prose-test.sh, same directory)
#
# THE THREE RULES:
#   em-dash        any literal U+2014 in the final text            (rules/safety.md)
#   offer-closer   the final sentence offers to do more ("Want me to ...")
#                  AND the last typed prompt was an instruction or a go-ahead
#                                             (output-styles/edges.md, interaction.md)
#   decision ask   a "Rec:" line or a trailing question, over 20 lines
#                                                              (rules/interaction.md)
#
# INSTRUCTION TEST (offer rule only, asked only after the offer regex matched):
#   slash command   always an instruction, no call
#   Jev             one yes/no to TypeSafe's jev-1.13.0, "is this prompt an
#                   instruction or go-ahead?", p >= PROSE_JEV_THRESHOLD (0.5)
#   verb list       the fallback: first word in VERBS, or a bare go-ahead. Used
#                   when ESCOTE_TYPESAFE_API_KEY is unset, PROSE_JEV=off, or the
#                   call fails, times out (PROSE_JEV_TIMEOUT, 3s) or answers in
#                   an unknown shape
#   Why: replaying the 35 logged offer blocks (2026-10-11), the verb list blocked
#   all 35 and 22 were right; Jev's instruction answer matched the hand labels on
#   34 of 35 ("do we have separate worktrees?" 0.05, "ok sent. now what?" 0.27).
#   The decision-ask rule stays a regex: Jev scored 27 of the 147 logged `Rec:`
#   asks below 0.5. PROSE_JEV_URL overrides the endpoint; prose-test.sh points
#   it at canned file:// answers so the matrix never touches the network.
#
# DECISION LOG: every instruction test appends one JSONL record (verdict,
#   source jev|verbs|slash, p, fallback reason, ms, prompt, final sentence) to
#   PROSE_LOG, default ~/.local/state/prose/decisions.jsonl. The transcript
#   keeps hook stderr only on an allow, so this log is the one place both
#   verdicts land. bin/prose-report summarizes it.
# Every reason quotes the offending line so the model's rewrite is one edit: a
# block that only names the rule costs a second block, and the 8-block cap makes
# each miss expensive.
#
# PASS-THROUGHS:
#   stop_hook_active true        the model is already answering a block
#   no assistant text            StructuredOutput-only turns (headless sdk-py)
#   prompt unrecoverable         the OFFER rule alone stands down, with one
#                                stderr line. Two measured causes: `claude -p`
#                                writes no transcript at all (the payload names
#                                a file that never materializes), and a lagging
#                                transcript hides the current prompt behind the
#                                prior turn's reply. The em-dash and length
#                                rules need no prompt and still run.
#
# PROMPT EXTRACTION (Data Model of the design doc, amended by spike 0h):
#   Stop          the newest `type=="last-prompt"` record's `lastPrompt`, or the
#                 newest plain `type=="user"` record, whichever sits LATER in the
#                 file. last-prompt is primary because the user-record predicate
#                 discards every slash-command turn: the harness records /skill
#                 as `<command-message>...</command-message>` and the "does not
#                 start with <" clause throws it away (measured: 16 user records,
#                 0 survivors). Agent-injected relays ("Another Claude session
#                 sent a message:") are not typed prompts and are skipped.
#   SubagentStop  the FIRST user record with string content in the agent
#                 transcript: that is the dispatch prompt, imperative by
#                 construction. Every record in a subagent transcript is
#                 isSidechain, so the main-thread predicate matches nothing.
#   Stale guard   if the newest assistant text in the file equals the payload's
#                 last_assistant_message the file is flushed and the prompt is
#                 current; otherwise the prompt record must sit LATER in the file
#                 than that assistant record, or it belongs to the prior turn.
#
# PROVENANCE: docs/design/2026-09-13-enforcement-core.md, phase 2. Harness facts
# measured in docs/design/2026-09-13-enforcement-core-phase0/evidence.md.

case "${1:-}" in
  -h|--help)
    # Print the leading comment block (this documentation), sans shebang.
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit 0
    ;;
  --self-test)
    exec bash "$(dirname "$0")/prose-test.sh"
    ;;
esac

# The banned character itself, built from its escape so this file carries no
# literal U+2014 (rules/safety.md: the escape is the substitute, never a companion).
EMDASH=$'\u2014'

# Offer phrases, from the design doc's offer test. `Let me know if` is
# deliberately out: it is the loosest form and reads as a status closer as often
# as an offer.
OFFERS='(Want me to|Shall I|Should I|Say the word|Say go|your call|Would you like me to|Do you want me to|If you want,? I can)'

# First word of an imperative prompt. `using` and bare `go` are out: "Using X,
# explain Y" is not imperative, and `go` is covered by the go-ahead form below.
VERBS='do fix add run write make ship bump merge publish update remove delete
dispatch send build implement execute create install commit push land finish
proceed continue use read check search find look review verify test probe pull
rebase open close resolve address apply deploy babysit shakedown'

GOAHEAD='(yes|y|ok|okay|go|do it|proceed|ship it|send it)'

JEV_URL="${PROSE_JEV_URL:-https://api.typesafe.ai/v1/systemone}"
JEV_MODEL="jev-1.13.0"
JEV_TIMEOUT="${PROSE_JEV_TIMEOUT:-3}"
JEV_THRESHOLD="${PROSE_JEV_THRESHOLD:-0.5}"
JEV_PROMPT_CHARS=1500
JEV_QUESTION="Is the USER PROMPT an instruction or go-ahead telling the assistant to do work, as opposed to a question, pasted output, or a comment?"
PROSE_LOG="${PROSE_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/prose/decisions.jsonl}"

# Bytes into the sandbox-safe tail read of a transcript. Records are one JSON
# object per line and the newest prompt always sits near the end, so a bounded
# tail is enough; a full read of a multi-megabyte transcript on every turn end
# is not.
TAIL_CAP=4000000

pass()  { echo '{}'; exit 0; }
block() { jq -n --arg r "$1" '{decision:"block",reason:$r}'; exit 0; }
note()  { printf 'prose.sh: %s\n' "$1" >&2; }

# Truncate through jq, which slices by codepoint. Bash substring and `cut -c`
# count bytes under a C locale and would hand jq a split multibyte character.
head_chars() { printf '%s' "$1" | jq -Rr ".[0:$2]" 2>/dev/null; }
tail_chars() { printf '%s' "$1" | jq -Rr ".[-$2:]" 2>/dev/null; }

input=$(cat)
[ -z "$input" ] && { note "empty payload, failing open"; pass; }

field() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

[ "$(field '.stop_hook_active // false')" = "true" ] && pass

event=$(field '.hook_event_name // ""')
lam=$(field '.last_assistant_message // ""')
if [ "$event" = "SubagentStop" ]; then
  tpath=$(field '.agent_transcript_path // .transcript_path // ""')
else
  tpath=$(field '.transcript_path // ""')
fi

# ---- transcript extraction ----------------------------------------------
lpidx=-1; lptext=""; uridx=-1; urtext=""; aridx=-1; artext=""; subtext=""
if [ -n "$tpath" ] && [ -r "$tpath" ]; then
  size=$(stat -c %s "$tpath" 2>/dev/null || echo 0)
  if [ "$size" -gt "$TAIL_CAP" ]; then
    # Drop the first (necessarily partial) line of a truncated read.
    raw=$(tail -c "$TAIL_CAP" "$tpath" | tail -n +2)
  else
    raw=$(cat "$tpath")
  fi
  ext=$(printf '%s\n' "$raw" | jq -R 'fromjson? // empty' | jq -s '
    def textof($r): [ ($r.message.content // [])
                      | (if type=="array" then .[] else empty end)
                      | select(.type=="text") | .text ] | join("");
    ([ to_entries[] | select(.value.type=="last-prompt")
       | select((.value.lastPrompt|type)=="string")
       | select((.value.lastPrompt|startswith("Another Claude session sent a message:"))|not)
     ] | last) as $lp
    | ([ to_entries[] | select(.value.type=="user")
         | select((.value.message.content|type)=="string")
         | select((.value.message.content|startswith("<"))|not)
         | select(.value.isSidechain != true)
       ] | last) as $ur
    | ([ to_entries[] | select(.value.type=="assistant")
         | select((textof(.value)|length) > 0)
       ] | last) as $ar
    | ([ to_entries[] | select(.value.type=="user")
         | select((.value.message.content|type)=="string")
       ] | first) as $sub
    | { lpidx: ($lp.key // -1), lptext: ($lp.value.lastPrompt // ""),
        uridx: ($ur.key // -1), urtext: ($ur.value.message.content // ""),
        aridx: ($ar.key // -1), artext: (if $ar then textof($ar.value) else "" end),
        subtext: ($sub.value.message.content // "") }' 2>/dev/null)
  if [ -n "$ext" ]; then
    lpidx=$(printf '%s' "$ext" | jq -r '.lpidx')
    lptext=$(printf '%s' "$ext" | jq -r '.lptext')
    uridx=$(printf '%s' "$ext" | jq -r '.uridx')
    urtext=$(printf '%s' "$ext" | jq -r '.urtext')
    aridx=$(printf '%s' "$ext" | jq -r '.aridx')
    artext=$(printf '%s' "$ext" | jq -r '.artext')
    subtext=$(printf '%s' "$ext" | jq -r '.subtext')
  else
    note "transcript at $tpath could not be parsed; offer rule skipped"
  fi
else
  note "transcript at '${tpath:-<none>}' is missing or unreadable; offer rule skipped"
fi

# ---- the text under test -------------------------------------------------
# last_assistant_message is present on 2.1.270 (spike 0a); the transcript read
# is the documented fallback for a version that drops it.
text="$lam"
[ -z "$text" ] && text="$artext"
[ -z "$text" ] && pass   # empty-text pass-through: no text block in this turn

# ---- the prompt ----------------------------------------------------------
prompt=""
if [ "$event" = "SubagentStop" ]; then
  prompt="$subtext"
else
  pidx=-1
  if [ "$lpidx" -ge 0 ] && [ "$lpidx" -gt "$uridx" ]; then
    pidx=$lpidx; prompt="$lptext"
  elif [ "$uridx" -ge 0 ]; then
    pidx=$uridx; prompt="$urtext"
  fi
  # Stale guard. Flushed file: the newest assistant text IS the reply we are
  # judging, so the prompt that precedes it is the current one. Lagging file:
  # the newest assistant text is the PRIOR reply, and a prompt that sits before
  # it belongs to the prior turn.
  if [ -n "$prompt" ] && [ "$artext" != "$text" ] && [ "$pidx" -le "$aridx" ]; then
    note "transcript lags the payload (newest prompt precedes the newest reply); offer rule skipped"
    prompt=""
  fi
fi

# ---- rule 1: em-dash -----------------------------------------------------
if printf '%s' "$text" | grep -qF "$EMDASH"; then
  offending=$(printf '%s\n' "$text" | grep -F -m1 "$EMDASH")
  block "em-dash (U+2014) in the final reply (rules/safety.md): \"$(head_chars "$offending" 200)\". Recast that line with a colon, parens, a comma, or a split sentence, then reply again."
fi

# ---- rule 2: offer-closer ------------------------------------------------
# Fenced code blocks and backtick spans come out first: a reply that QUOTES or
# greps for "Say the word" is not offering. The anchor is the final sentence,
# not the whole reply.
final_sentence() {
  local t="$1" last
  t=$(printf '%s\n' "$t" | awk 'BEGIN{fenced=0} /^[[:space:]]*```/{fenced=!fenced; next} fenced==0{print}')
  t=$(printf '%s\n' "$t" | sed 's/`[^`]*`//g')
  last=$(printf '%s\n' "$t" | grep -v '^[[:space:]]*$' | tail -n1)
  last=$(printf '%s' "$last" | sed -E 's/[.!?]+[[:space:]]*$//')
  # A sentence boundary is a terminator FOLLOWED BY WHITESPACE. Cutting on a
  # bare dot would truncate "Want me to update edges.md?" to "md".
  last=$(printf '%s' "$last" | sed -E 's/.*[.!?][[:space:]]+//')
  tail_chars "$last" 300
}

now_ms() { date +%s%3N; }

# Prints one line: `ok <p> <ms>` with Jev's probability that the prompt is an
# instruction, or `fallback <reason> <ms>` when Jev cannot answer. Reasons:
# off, no-key, curl-exit-<n> (22 is an HTTP error, 28 a timeout), bad-answer.
# The key goes through a header file descriptor so it never reaches argv.
jev_instruction_p() {
  local p="$1" body resp rc t0 jp
  [ "${PROSE_JEV:-on}" = "off" ] && { echo "fallback off 0"; return; }
  [ -z "${ESCOTE_TYPESAFE_API_KEY:-}" ] && { echo "fallback no-key 0"; return; }
  body=$(jq -n --arg s "USER PROMPT:
$(head_chars "$p" "$JEV_PROMPT_CHARS")" --arg m "$JEV_MODEL" --arg q "$JEV_QUESTION" \
    '{state:$s, model:$m, questions:{instruction:{type:"noul", instructions:$q}}}')
  t0=$(now_ms)
  resp=$(printf '%s' "$body" | curl -sS --fail --max-time "$JEV_TIMEOUT" \
    -H @<(printf 'Authorization: Bearer %s' "$ESCOTE_TYPESAFE_API_KEY") \
    -H 'Content-Type: application/json' --data-binary @- "$JEV_URL" 2>/dev/null)
  rc=$?
  [ "$rc" -ne 0 ] && { echo "fallback curl-exit-$rc $(( $(now_ms) - t0 ))"; return; }
  jp=$(printf '%s' "$resp" | jq -r '.answers.instruction.noul | numbers' 2>/dev/null)
  [ -z "$jp" ] && { echo "fallback bad-answer $(( $(now_ms) - t0 ))"; return; }
  echo "ok $jp $(( $(now_ms) - t0 ))"
}

# Sets INSTR_SOURCE (slash | jev | verbs), INSTR_P, INSTR_REASON and INSTR_MS
# for the decision log, and returns 0 when the prompt counts as an instruction.
is_instruction() {
  local p="$1" first status
  INSTR_SOURCE=""; INSTR_P=""; INSTR_REASON=""; INSTR_MS=0
  first=$(printf '%s' "$p" | awk '{print $1}')
  # A slash command IS an instruction: invoking /how-to-execute-a-plan is an
  # order, and its first word is never in the verb list.
  case "$first" in /?*) INSTR_SOURCE=slash; return 0 ;; esac
  read -r status INSTR_P INSTR_MS <<< "$(jev_instruction_p "$p")"
  if [ "$status" = "ok" ]; then
    INSTR_SOURCE=jev
    note "instruction test: jev p=$INSTR_P ms=$INSTR_MS (threshold $JEV_THRESHOLD)"
    awk -v p="$INSTR_P" -v t="$JEV_THRESHOLD" 'BEGIN{exit !(p >= t)}'
    return
  fi
  INSTR_SOURCE=verbs; INSTR_REASON="$INSTR_P"; INSTR_P=""
  note "instruction test: verb-list fallback ($INSTR_REASON, ms=$INSTR_MS)"
  is_imperative_by_verbs "$p"
}

# One JSONL record per instruction test, blocked or not. The transcript keeps a
# hook's stderr only when it allows (a block records the reason alone), so this
# log is the one place both verdicts land. bin/prose-report reads it. A failed
# write never touches the verdict.
log_decision() {  # log_decision <block|allow>
  local dir
  dir=$(dirname "$PROSE_LOG")
  { mkdir -p "$dir" && jq -nc \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg session "$(field '.session_id // ""')" \
      --arg event "$event" --arg verdict "$1" --arg source "$INSTR_SOURCE" \
      --arg p "$INSTR_P" --arg reason "$INSTR_REASON" --argjson ms "${INSTR_MS:-0}" \
      --arg threshold "$JEV_THRESHOLD" --arg prompt "$(head_chars "$prompt" 300)" \
      --arg final "$(head_chars "$fs" 300)" \
      '{ts:$ts, session:$session, event:$event, verdict:$verdict, source:$source,
        p:($p|tonumber? // null), reason:($reason|select(.!="") // null), ms:$ms,
        threshold:($threshold|tonumber), prompt:$prompt, final:$final}' \
      >> "$PROSE_LOG"; } 2>/dev/null || note "decision log write failed: $PROSE_LOG"
}

is_imperative_by_verbs() {
  local p="$1" first words
  first=$(printf '%s' "$p" | awk '{print $1}')
  first=$(printf '%s' "$first" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z]//g')
  case " $(printf '%s' "$VERBS" | tr '\n' ' ') " in *" $first "*) [ -n "$first" ] && return 0 ;; esac
  # Bare go-ahead: five words or fewer, matched on WORD boundaries so that
  # "read the okta docs" and "check the golang build" are not go-aheads.
  words=$(printf '%s' "$p" | wc -w)
  if [ "$words" -le 5 ] && printf '%s' "$p" | grep -Eqi "(^|[^[:alnum:]])$GOAHEAD([^[:alnum:]]|$)"; then
    return 0
  fi
  return 1
}

# The offer regex runs first so the instruction test, and its network call,
# only happens on the rare reply that actually ends in an offer.
if [ -z "$prompt" ]; then
  note "no typed prompt recovered; offer rule skipped"
else
  fs=$(final_sentence "$text")
  if printf '%s' "$fs" | grep -Eqi "$OFFERS"; then
    if is_instruction "$prompt"; then
      log_decision block
      block "offer-closer in the final sentence after an imperative prompt (output-styles/edges.md, rules/interaction.md): \"$(head_chars "$fs" 200)\". In scope means do it, otherwise omit it. Drop the offer and reply again. (Prompt: \"$(head_chars "$prompt" 80)\")"
    fi
    log_decision allow
  fi
fi

# ---- rule 3: oversized decision ask --------------------------------------
lines=$(printf '%s\n' "$text" | wc -l)
if [ "$lines" -gt 20 ]; then
  last_ne=$(printf '%s\n' "$text" | grep -v '^[[:space:]]*$' | tail -n1)
  if printf '%s\n' "$text" | grep -Eq '^[[:space:]]*Rec:' || printf '%s' "$last_ne" | grep -q '?[[:space:]]*$'; then
    block "decision ask in $lines lines, over the 20-line limit (rules/interaction.md): \"$(head_chars "$last_ne" 200)\". A decision ask is the ENTIRE message: The problem (3-4 bullets naming symbol and file:line), one line naming the decision, each option a label plus 2-3 bullets of about 10 words, close with Rec: X. Nothing above The problem, nothing below Rec. Cut the bullets that do not change which option he picks and reply again."
  fi
fi

pass
