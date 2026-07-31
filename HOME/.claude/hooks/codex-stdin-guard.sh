#!/bin/bash
# Deny `codex exec` (and `gemini -p`) when stdin is left OPEN.
#
# Why this exists: `codex exec` deliberately reads stdin and appends it to the prompt as a
# `<stdin>` block. That is a feature -- the staff-engineer skill relies on it
# (`codex exec "$PROMPT" <"$DOC_PATH"`). But from a non-TTY caller like Claude Code's Bash tool,
# stdin is neither a file nor closed, so codex prints "Reading additional input from stdin..."
# and blocks until the tool timeout. The call looks hung for no visible reason.
#
# The `general:codex` skill's own command patterns all omit any stdin handling, and that skill
# lives in a plugin cache that a plugin update overwrites, so the guard belongs here instead.
#
# Legal forms, all of which resolve stdin:
#   codex exec "..." < /dev/null          # no extra context wanted
#   codex exec "..." < some-file          # file appended as the <stdin> block (the intended use)
#   cat file | codex exec "..."           # same, via a pipe
#   printf '%s' "$x" | codex exec "..."
#
# Deliberately NOT matched: `codex login`, `codex resume`, `codex mcp`, `codex --help`,
# `codex sandbox`, and the wrapper scripts (which already redirect). Only the `exec` subcommand
# and gemini's non-interactive `-p`/`--prompt` form read stdin this way.

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

# Nothing to do unless this is a non-interactive codex/gemini invocation.
needs_stdin=""
if printf '%s' "$command" | grep -qE '(^|[;&|]|\s)codex\s+(exec|e)\b'; then
    needs_stdin="codex exec"
elif printf '%s' "$command" | grep -qE '(^|[;&|]|\s)gemini\s+.*(-p|--prompt)\b'; then
    needs_stdin="gemini -p"
fi
[ -z "$needs_stdin" ] && exit 0

# Already resolved? A `<` redirect (including `< /dev/null` and heredoc/herestring forms) or an
# upstream pipe into it both count.
if printf '%s' "$command" | grep -qE '<'; then
    exit 0
fi
if printf '%s' "$command" | grep -qE '\|\s*(timeout\s+[^|]*)?(env\s+[^|]*)?(codex|gemini)\b'; then
    exit 0
fi

jq -n --arg tool "$needs_stdin" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "\($tool) with stdin left OPEN will hang until the tool timeout: it reads stdin and appends it to the prompt. Add `< /dev/null` for no extra context, or `< <file>` to pass the file as the <stdin> block. For a design-doc review use the staff-engineer / architect scripts instead of calling the CLI directly."
    }
}'
exit 0
