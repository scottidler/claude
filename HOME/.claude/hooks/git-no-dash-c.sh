#!/bin/bash
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

path=$(echo "$command" | grep -oP '(?<=git -C )\S+' | head -1)

if [ -n "$path" ]; then
    real_path=$(realpath "$path" 2>/dev/null)
    real_cwd=$(realpath "$PWD" 2>/dev/null)

    if [ "$real_path" = "$real_cwd" ]; then
        jq -n --arg path "$path" '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: "git -C used with CWD — drop \"-C \($path)\" and run git directly"
            }
        }'
        exit 0
    fi
fi
