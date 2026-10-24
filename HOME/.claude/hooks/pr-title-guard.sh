#!/bin/bash
# pr-title-guard.sh: PreToolUse guard: a PR title never opens with a
# conventional-commit `type:` / `type(scope):` prefix.
#
# Scott's standing rule (2026-10-24, replacing the 2026-07-23 branch-match rule):
# never this title format again, ticket or no ticket. The old rule demanded
# `slug(title minus type(scope)) == branch`, which manufactured
# `feat(cli): add okta cli` every time: a restated branch slug behind a prefix.
# A title is written for a reviewer, in plain words, sentence case:
#   - with a Jira key: `SRE-4401: Add an Okta admin CLI and MCP server`
#   - without one:     `Add an Okta admin CLI and MCP server`
# Ticket-key-as-scope (`feat(SRE-3658): ...`) is the same format and is denied.
#
# The prefix is a LOWERCASE first word, an optional `(...)` scope, an optional
# `!`, then a colon and whitespace (or end). An uppercase ticket key
# (`SRE-4401:`) does not match, and neither does `https://...`.
#
# Vectors:
#   - Bash:  gh pr create --title "..." | gh pr edit --title "..."
#   - MCP:   mcp__multi-account-github__create_pr {title}
#
# Parsing is lib.sh's. `stmts` splits the command (heredoc bodies and
# command-substitution spans arrive neutralized, and a `$( )`, backtick or
# `bash -c` body arrives as a record of its own), then mask_comment, then
# `cmdword_is gh`, so a `gh pr create` inside an echo, a grep pattern or a
# commit message is not a false positive. The title comes from
# `flag_value --title -t`, which returns RAW text: a title this hook cannot
# expand (`--title "$(gen-title)"`, `--title "$T"`) is unknowable and passes.
#
# Fails OPEN on a missing or unknowable title: it denies only a title it can
# read that carries the prefix.
#
# Emits a PreToolUse "deny" decision (with a reason Claude sees), or passes through ({}).
. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')

# The \x01 a masker leaves behind: a title carrying one came out of a command
# substitution, so its value is unknowable.
MASKCH=$(printf '\001')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

has_type_prefix() {
  printf '%s' "$1" | grep -Eq '^[[:space:]]*[a-z][a-z0-9_-]*(\([^)]*\))?!?:([[:space:]]|$)'
}

check() {
  local title="$1"
  [ -z "$title" ] && return 0
  case "$title" in *'$'* | *'`'* | *"$MASKCH"*) return 0 ;; esac
  has_type_prefix "$title" || return 0
  deny "Blocked: PR title '$title' opens with a conventional-commit 'type(scope):' prefix, which Scott never wants on a PR title, ticket or no ticket. Write the outcome for a reviewer in plain words, sentence case, under ~70 chars: 'KEY: Summary' when there is a confirmed Jira key (e.g. 'SRE-4401: Add an Okta admin CLI'), else just 'Summary'. Never restate the branch slug."
}

case "$tool" in
  mcp__multi-account-github__create_pr)
    check "$(printf '%s' "$input" | jq -r '.tool_input.title // ""')"
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
    [ -z "$cmd" ] && { echo '{}'; exit 0; }
    while IFS= read -r -d '' stmt; do
      masked=$(printf '%s' "$stmt" | mask_comment)
      printf '%s' "$masked" | cmdword_is gh || continue
      # Matched on the UNQUOTED copy: `"gh" "pr" create` is the same invocation
      # gh receives, spelled to dodge a matcher (audit CW1).
      printf '%s' "$masked" | unquote | grep -Eq '(^|[[:space:]])pr[[:space:]]+(create|edit)([[:space:]]|$)' || continue
      check "$(printf '%s' "$stmt" | flag_value --title -t)"
    done < <(printf '%s' "$cmd" | stmts)
    ;;
esac

echo '{}'
exit 0
