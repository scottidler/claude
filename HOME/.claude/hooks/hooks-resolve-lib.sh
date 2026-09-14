#!/bin/bash
# hooks-resolve-lib.sh: shared command-string parsing for hooks-preflight.sh
# and bin/hooks-resolve. Sourced, never run.
#
# A settings.json hook command comes in three live shapes: a tilde path
# (~/.claude/hooks/foo.sh), a bare PATH name (clyde permit log), or a runner
# plus a quoted path (bash '/home/saidler/.claude/hooks/foo.sh' session). The
# runner shape is the one a first-token check silently passes, since its
# first token is "bash", not the hook file.
#
# Tokenizing goes through `xargs -n1`, which strips the shell's own quoting
# (single quotes here) without an eval, so a crafted command string cannot
# run anything: these are two config-parsing steps, not a shell.

# hook_resolve_target <command>
# Sets HOOK_KIND to "path" or "bare" and HOOK_TARGET to the token that names
# the file (tilde or absolute, quotes already stripped) or the bare PATH name.
hook_resolve_target() {
  local cmd="$1" tok first
  local tokens=()
  while IFS= read -r tok; do
    tokens+=("$tok")
  done < <(printf '%s' "$cmd" | xargs -n1 printf '%s\n' 2>/dev/null)

  first="${tokens[0]:-}"

  if [[ "$first" == */* ]]; then
    HOOK_KIND=path
    HOOK_TARGET="$first"
    return
  fi

  if [[ "$first" == "bash" || "$first" == "sh" ]]; then
    for tok in "${tokens[@]:1}"; do
      if [[ "$tok" == */* ]]; then
        HOOK_KIND=path
        HOOK_TARGET="$tok"
        return
      fi
    done
  fi

  HOOK_KIND=bare
  HOOK_TARGET="$first"
}

# hook_target_exists <target> <kind> [repo_root]
# Checks the target found by hook_resolve_target. A bare target is always a
# PATH lookup (`command -v`). A path target is tilde-expanded and checked
# live against $HOME when repo_root is omitted (hooks-preflight.sh's case:
# the actual session), or remapped from ~/.claude/hooks/<x> (and its literal
# $HOME spelling) onto <repo_root>/HOME/.claude/hooks/<x> when repo_root is
# given (bin/hooks-resolve's case: CI, where nothing is symlinked into the
# runner's home). Sets HOOK_RESOLVED to the path or name actually checked.
# Returns 0 when found (and, for a path, executable).
hook_target_exists() {
  local target="$1" kind="$2" root="${3:-}" resolved

  if [[ "$kind" == "bare" ]]; then
    HOOK_RESOLVED="$target"
    command -v "$target" >/dev/null 2>&1
    return $?
  fi

  if [[ -n "$root" ]]; then
    case "$target" in
      "$HOME"/.claude/hooks/*) resolved="$root/HOME/.claude/hooks/${target#"$HOME"/.claude/hooks/}" ;;
      "~/.claude/hooks/"*)     resolved="$root/HOME/.claude/hooks/${target#"~/.claude/hooks/"}" ;;
      *)                       resolved="$target" ;;
    esac
  else
    case "$target" in
      "~/"*) resolved="$HOME/${target#\~/}" ;;
      *)     resolved="$target" ;;
    esac
  fi

  HOOK_RESOLVED="$resolved"
  [[ -x "$resolved" ]]
}
