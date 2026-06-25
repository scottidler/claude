#!/bin/bash
# block-draft-pr.sh — PreToolUse guard: HARD-DENY creation of DRAFT pull requests.
#
# Scott's standing rule: never open draft PRs — open them ready for review.
# This makes it impossible for Claude to create a draft, on either vector:
#   - Bash:  `gh pr create ... --draft`  or  `... -d`
#   - MCP:   mcp__multi-account-github__create_pr with draft=true
#
# Scope is CREATION only. It intentionally does NOT block `gh pr ready --undo`
# (converting an existing PR back to draft) — only the opening of a new draft.
#
# Bash commands are split per statement (on && || ; | and newlines) so a stray
# `-d`/`--draft` in an unrelated sibling command is not a false positive, while a
# real `gh pr create --draft` anywhere in the line IS caught.
#
# Emits a PreToolUse "deny" decision (with a reason Claude sees), or passes through ({}).

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // ""')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

case "$tool" in
  mcp__multi-account-github__create_pr)
    draft=$(echo "$input" | jq -r '.tool_input.draft // false')
    if [ "$draft" = "true" ]; then
      deny "Blocked: draft PRs are disabled (Scott's standing rule). Call create_pr with draft:false — open it ready for review."
    fi
    ;;
  Bash)
    cmd=$(echo "$input" | jq -r '.tool_input.command // ""')
    [ -z "$cmd" ] && { echo '{}'; exit 0; }
    split=$(printf '%s' "$cmd" | sed -E 's/&&/\n/g; s/\|\|/\n/g; s/;/\n/g; s/\|/\n/g')
    # gh must be the COMMAND WORD of the statement (after optional leading
    # VAR=val env assignments and command/builtin/exec/sudo/env wrappers, and an
    # optional /path/ prefix) — so `echo "gh pr create --draft"`, `git commit -m
    # "...gh pr create..."`, grep args and `# comments` are NOT treated as a real
    # invocation. Only an actual `gh pr create` run is.
    cmdword_create='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*((command|builtin|exec|sudo|env)[[:space:]]+)*(/?[^[:space:]]*/)?gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'
    while IFS= read -r stmt; do
      [ -z "$stmt" ] && continue
      if printf '%s' "$stmt" | grep -Eq "$cmdword_create" \
         && printf '%s' "$stmt" | grep -Eq -- '(--draft([[:space:]=]|$)|(^|[[:space:]])-d([[:space:]=]|$))'; then
        deny "Blocked: draft PRs are disabled (Scott's standing rule). Re-run 'gh pr create' WITHOUT --draft/-d — open it ready for review."
      fi
    done <<< "$split"
    ;;
esac

echo '{}'
exit 0
