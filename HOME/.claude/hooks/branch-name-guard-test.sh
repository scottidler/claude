#!/bin/bash
# branch-name-guard-test.sh: fixture matrix for branch-name-guard.sh.
#
# Each case feeds the hook a PreToolUse payload on stdin and asserts on the
# decision, and the deny cases that carry a `want` string also assert the
# OFFERED slug is in the reason: the measured failure was the model not knowing
# what to type next, so a deny whose text names no legal name is not a pass.
#
# The deny set is every creation shape the guard covers (checkout -b/-B,
# switch -c/-C, branch <name>, branch -m, worktree add, gh pr create --head).
# The allow set is the three things a name guard must never touch: a legal flat
# slug (including `bump-0.2.1`, which only git-release-guard.sh's Gate C
# rejects, for a different reason, with its own text), a name that is READ
# rather than created (`branch -d`, `branch --list`, an existing `--head`), and
# the same words sitting anywhere but a git command's argument position.
set -u
export LC_ALL=C

HOOK="$(cd "$(dirname "$0")" && pwd)/branch-name-guard.sh"
pass=0
fail=0

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/branch-name-test.XXXXXX")
trap 'chmod -R u+w "$ROOT" 2>/dev/null' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# One repo carrying an ALREADY EXISTING slashed branch, which is what separates
# `gh pr create --head <new name>` from `--head <a branch with commits on it>`,
# and a second repo to be the target of a `cd`.
git init -q -b main "$ROOT/repo"
(cd "$ROOT/repo" && echo x > f && git add -A && git commit -qm init && git branch 'legacy/old-thing')
R="$ROOT/repo"
git init -q -b main "$ROOT/other"
(cd "$ROOT/other" && echo x > f && git add -A && git commit -qm init)
O="$ROOT/other"

run() { # run <expect deny|allow> <command> [<want substring in the reason>]
  local expect="$1" cmd="$2" want="${3-}" out decision reason
  out=$(cd "$ROOT" && jq -n --arg c "$cmd" --arg d "$R" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | bash "$HOOK")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  if [ "$decision" != "$expect" ]; then
    fail=$((fail + 1))
    printf 'FAIL  [want %s got %s] %s\n' "$expect" "$decision" "$cmd"
    return
  fi
  if [ -n "$want" ] && ! printf '%s' "$reason" | grep -Fq -- "$want"; then
    fail=$((fail + 1))
    printf 'FAIL  [%s, reason lacks "%s"] %s\n      -> %s\n' "$expect" "$want" "$cmd" "$reason"
    return
  fi
  pass=$((pass + 1))
  printf 'PASS  [%s] %s\n' "$expect" "$cmd"
}

SQ=\'

echo "=== branch creation denies on a slash, an underscore, or uppercase ==="
run deny 'git checkout -b fix/x' 'Use `fix-x`'
run deny 'git checkout -B Fix-X' 'Use `fix-x`'
run deny 'git switch -c Fix-X' 'Use `fix-x`'
run deny 'git switch -C fix_x' 'Use `fix-x`'
run deny 'git switch --create fix/x' 'Use `fix-x`'
run deny 'git branch fix_x' 'Use `fix-x`'
run deny 'git branch feature/JIRA-123' 'Use `feature-jira-123`'
run deny 'git checkout -b chore/bump-0.9.0' 'Use `chore-bump-0-9-0`'
run deny 'git checkout -b "feature/dark mode"' 'Use `feature-dark-mode`'

echo "=== a leading or trailing hyphen is not a slug either ==="
run deny 'git checkout -b fix-' 'Use `fix`'
run deny 'git checkout -b -fix' 'Use `fix`'

echo "=== a rename is judged on where it LANDS, never on where it came from ==="
run deny 'git branch -m fix/x' 'Use `fix-x`'
run deny 'git branch -m old-flat fix/x' 'Use `fix-x`'
run deny 'git branch -M Bad_Name' 'Use `bad-name`'
run allow 'git branch -m flat-slug'
run allow 'git branch -m fix/x flat-slug'

echo "=== worktree add, both flag orders ==="
run deny 'git worktree add ../w -b a/b' 'Use `a-b`'
run deny 'git worktree add -b a/b ../w' 'Use `a-b`'
run allow 'git worktree add ../w'
run allow 'git worktree add ../w -b flat-slug'

echo "=== gh pr create --head, only when the name is not an existing branch ==="
run deny "gh pr create --head fix/markdown-dark-mode --title ${SQ}fix(render): markdown dark mode${SQ}" 'Use `fix-markdown-dark-mode`'
run deny 'gh pr create --head scottidler:fix/x --title x' 'Use `fix-x`'
run allow 'gh pr create --head legacy/old-thing --title x'
run allow 'gh pr create --head flat-slug --title x'
run allow 'gh pr list --head fix/x'

echo "=== a legal flat slug always allows, whatever another guard thinks of it ==="
run allow 'git checkout -b fix-auth-bug'
# A legal name that only git-release-guard.sh's Gate C rejects, with its own
# text. This guard must not add a second, wrong reason to that command.
run allow 'git checkout -b bump-0.2.1'
run allow 'git checkout -b bumpkin-feature'
run allow 'git switch -c flat-slug'
run allow 'git branch flat-slug'

echo "=== reading a branch is not creating one ==="
run allow 'git branch -d bump-0.2.1'
run allow 'git branch -D fix/x'
run allow "git branch --list ${SQ}bump*${SQ}"
run allow 'git branch'
run allow 'git branch --show-current'
run allow 'git checkout main'
run allow 'git switch main'
run allow 'git checkout -- src/a.rs'

echo "=== the cmdword anchor: the same words outside git's argument position ==="
run allow 'echo "git checkout -b a/b"'
run allow "echo ${SQ}git checkout -b a/b${SQ}"
run allow 'grep -n "git checkout -b a/b" notes.md'
run allow 'branch-name-guard.sh --help'
run allow '# git checkout -b a/b'
run allow 'git commit -m "mention checkout -b a/b in the docs"'
run allow 'git tag -a v1 -m "switch -c Bad/Name"'
run allow "$(printf 'cat > notes.md <<EOF\ngit checkout -b a/b\nEOF\ngit checkout -b flat-slug')"

echo "=== nested statements and cd targets are judged too ==="
run deny "bash -c ${SQ}git checkout -b a/b${SQ}" 'Use `a-b`'
run deny "cd $O && git checkout -b a/b" 'Use `a-b`'
run deny 'echo hi && git switch -c Bad_Name' 'Use `bad-name`'
run allow "cd $O && git checkout -b flat-slug"

echo "=== an unknowable name passes through ==="
run allow 'git checkout -b "$(gen-name)"'
run allow 'git checkout -b `gen-name`'

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
