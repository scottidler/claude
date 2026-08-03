#!/bin/bash
# block-question-picker.sh -- PreToolUse guard: HARD-DENY the AskUserQuestion tool.
#
# Scott's standing rule: never ask him a question through the interactive picker
# widget. Its option descriptions wrap into dense unreadable blocks, and he has
# rejected it in the strongest terms (2026-07-28: "This bullshit is inscrutible").
#
# Questions go in the message text, in the shape documented in
# ~/repos/.claude/rules/interaction.md -- a `The problem` context block, one line
# naming the decision, then per-option label lines with 2-3 short bullets each,
# closing with `Rec: X`.
#
# A rules-file bullet was not enough: Claude violated it three times in the
# session that produced this hook, including once immediately after writing the
# rule. This makes the failure mechanically impossible instead of discouraged.
#
# Emits a PreToolUse "deny" decision (with a reason Claude sees), or passes through ({}).

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // ""')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

if [ "$tool" = "AskUserQuestion" ]; then
  deny "Blocked: the AskUserQuestion picker is disabled (Scott's standing rule -- he finds it inscrutable). Ask in your MESSAGE TEXT using the required shape: a 'The problem' block of 3-4 bullets naming the symbol and file.rs:line, then 'The decision: <question>', then each option as a label line ('A: short-label') followed by 2-3 bullets of ~10 words each, closing with 'Rec: X'. Trim to the bullets that change which option he picks. See ~/repos/.claude/rules/interaction.md."
fi

echo '{}'
exit 0
