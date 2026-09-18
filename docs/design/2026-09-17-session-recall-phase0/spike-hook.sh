#!/usr/bin/env bash
# THROWAWAY Phase 0 spike hook. Lives only in a scratch project.
# Logs the raw UserPromptSubmit payload, then emits the candidate
# additionalContext string when the prompt trips the session-recall predicate.
set -uo pipefail

LOG="${SPIKE_LOG:-$HOME/.cache/session-recall-phase0.log}"
mkdir -p "$(dirname "$LOG")"

PAYLOAD=$(cat)
printf '%s\n' "$PAYLOAD" >> "$LOG"

PROMPT=$(printf '%s' "$PAYLOAD" | jq -r '.prompt // ""')

# Bails, in the doc's order.
case "$PROMPT" in
  '<'*) exit 0 ;;
  'Another Claude session sent a message:'*) exit 0 ;;
  *'```'*) exit 0 ;;
  'You are '*|'Summarize this Claude Code'*|'Review this change for security'*|'Analyze the following'*) exit 0 ;;
esac
if printf '%s' "$PROMPT" | grep -qi 'clyde'; then
  exit 0
fi

UUID_RE='(?<![/\w\-"'"'"'])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![/\w\-"'"'"'])'
PHRASE_RE='(previous|last|prior|earlier)\s+(session|conversation|chat)|the session where|that (doc|design|spec) we (wrote|made|did)'

QUOTED=$(printf '%s' "$PROMPT" | grep -oiP "$UUID_RE" | head -1)
ARM=id
if [ -z "$QUOTED" ]; then
  QUOTED=$(printf '%s' "$PROMPT" | grep -oiP "$PHRASE_RE" | head -1)
  ARM=phrase
fi
[ -z "$QUOTED" ] && exit 0

CONTEXT="session-recall hook: this prompt names a prior session, quoted verbatim from it: ${QUOTED}.

Decide from the prompt's own wording:
- asking about that session's content (what was decided, what was built, where a file went) -> resolve it with clyde's MCP session tools (mcp__clyde__sessions_search, mcp__clyde__session_grep, mcp__clyde__session_read; run ToolSearch with select: on those names first if they are not already loaded) before answering, and cite path:line.
- naming it in passing (a statistic, an aside, a session you are already reading) -> resolve nothing. This line is context, not an order."

printf '%s\n' "FIRED arm=$ARM quoted=$QUOTED" >> "$LOG.fires"

jq -n --arg ctx "$CONTEXT" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
