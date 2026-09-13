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
#                  AND the last typed prompt was imperative or a bare go-ahead
#                                             (output-styles/edges.md, interaction.md)
#   decision ask   a "Rec:" line or a trailing question, over 20 lines
#                                                              (rules/interaction.md)
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

is_imperative() {
  local p="$1" first words
  first=$(printf '%s' "$p" | awk '{print $1}')
  # A slash command IS an imperative: invoking /how-to-execute-a-plan is an
  # order, and its first word is never in the verb list.
  case "$first" in /?*) return 0 ;; esac
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

if [ -z "$prompt" ]; then
  note "no typed prompt recovered; offer rule skipped"
elif is_imperative "$prompt"; then
  fs=$(final_sentence "$text")
  if printf '%s' "$fs" | grep -Eqi "$OFFERS"; then
    block "offer-closer in the final sentence after an imperative prompt (output-styles/edges.md, rules/interaction.md): \"$(head_chars "$fs" 200)\". In scope means do it, otherwise omit it. Drop the offer and reply again. (Prompt: \"$(head_chars "$prompt" 80)\")"
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
