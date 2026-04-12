#!/usr/bin/env bash
# Auto-allow any Bash command that ends with --help
cmd=$(jq -r '.tool_input.command // ""')
if [[ "$cmd" =~ --help[[:space:]]*$ ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Command ends with --help"}}'
else
  echo '{}'
fi
