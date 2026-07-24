#!/bin/bash
# branch-pr-title-guard.sh — PreToolUse guard: a PR's title MUST match its branch.
#
# Scott's standing rule (2026-07-23): the branch name is the source of truth for
# the PR title. Take the PR title, strip a leading conventional-commit
# `type(scope)!:` prefix, slugify the remainder (lowercase, non-alphanumeric runs
# -> '-', trim), and it MUST equal the head branch name. This makes it impossible
# to open a PR whose title and branch describe different things, on either vector:
#   - Bash:  gh pr create --title "..." [--head <branch>]
#   - MCP:   mcp__multi-account-github__create_pr {title, head}
#
# Fix on a block: rewrite the TITLE to match the branch (branch is source of
# truth), e.g. branch `add-viewport-support` -> title `feat(x): add viewport support`.
#
# Fails OPEN (passes through) whenever it cannot determine BOTH the title and the
# branch — it never blocks on ambiguity, only on a proven mismatch. Bash commands
# are split per statement so a stray `gh pr create` inside an unrelated sibling
# command (echo, grep, a commit message) is not a false positive.
#
# Emits a PreToolUse "deny" decision (with a reason Claude sees), or passes through ({}).

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // ""')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Strip leading conventional-commit `type(scope)!:` prefix, lowercase, collapse
# non-alphanumeric runs to '-', trim leading/trailing '-'.
title_slug() {
  printf '%s' "$1" \
    | sed -E 's/^[[:space:]]*[A-Za-z]+(\([^)]*\))?!?:[[:space:]]*//' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# deny on a proven mismatch; return (allow) on match or on missing data.
check() {
  local title="$1" branch="$2" slug
  [ -z "$title" ] && return 0
  [ -z "$branch" ] && return 0
  slug=$(title_slug "$title")
  [ -z "$slug" ] && return 0
  if [ "$slug" != "$branch" ]; then
    deny "Blocked: PR title must match the branch name (Scott's rule; branch is the source of truth). Branch is '$branch', but the title slugifies to '$slug'. Rewrite the TITLE so that stripping its 'type(scope):' prefix and slugifying the rest equals '$branch' — e.g. 'type(scope): $(printf '%s' "$branch" | tr '-' ' ')'. Do NOT rename the branch."
  fi
  return 0
}

# Pull a flag value out of a statement: handles `--flag x`, `--flag=x`,
# `-f x`, single/double quoted, or bare. $1=stmt $2=long(--title) $3=short(-t)
flag_value() {
  printf '%s' "$1" \
    | grep -oE -- "($2|(^|[[:space:]])$3)([[:space:]]+|=)(\"[^\"]*\"|'[^']*'|[^[:space:]]+)" \
    | head -1 \
    | sed -E "s/^([[:space:]]*)($2|$3)([[:space:]]+|=)//; s/^\"//; s/\"$//; s/^'//; s/'$//"
}

case "$tool" in
  mcp__multi-account-github__create_pr)
    title=$(echo "$input" | jq -r '.tool_input.title // ""')
    branch=$(echo "$input" | jq -r '.tool_input.head // ""')
    branch="${branch##*:}"   # strip any owner: prefix
    check "$title" "$branch"
    ;;
  Bash)
    cmd=$(echo "$input" | jq -r '.tool_input.command // ""')
    [ -z "$cmd" ] && { echo '{}'; exit 0; }
    split=$(printf '%s' "$cmd" | sed -E 's/&&/\n/g; s/\|\|/\n/g; s/;/\n/g; s/\|/\n/g')
    cmdword_create='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*((command|builtin|exec|sudo|env)[[:space:]]+)*(/?[^[:space:]]*/)?gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'
    while IFS= read -r stmt; do
      [ -z "$stmt" ] && continue
      printf '%s' "$stmt" | grep -Eq "$cmdword_create" || continue
      title=$(flag_value "$stmt" '--title' '-t')
      branch=$(flag_value "$stmt" '--head' '-H')
      branch="${branch##*:}"
      [ -z "$branch" ] && branch=$(git branch --show-current 2>/dev/null)
      check "$title" "$branch"
    done <<< "$split"
    ;;
esac

echo '{}'
exit 0
