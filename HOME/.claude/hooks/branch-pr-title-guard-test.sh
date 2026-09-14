#!/bin/bash
# branch-pr-title-guard-test.sh: fixture matrix for branch-pr-title-guard.sh.
#
# The deny cases are the 43 denials the 2026-09-12 audit measured, by SHAPE,
# because the shape is what decides which of the three texts a model gets:
#   - slash branches (24 of the 43) and dot branches: unmatchable by any title,
#     so the text offers `git branch -m <slug>`
#   - on main/master: no branch to match, so the text offers `git checkout -b`
#   - plain mismatch: the branch is the source of truth, so the TITLE moves
#   - wrong repo (3 of the 43): the guard read `git branch --show-current` from
#     the hook process's own directory, so a `cd`-into-another-worktree command
#     was judged against the session's branch. Those cases assert on the
#     EFFECTIVE worktree: a payload `cwd`, a `cd`, and a `git -C`
# Every deny case asserts on its reason text, not just the decision: the whole
# defect was a denial demanding something no title could satisfy.
set -u
export LC_ALL=C

HOOK="$(cd "$(dirname "$0")" && pwd)/branch-pr-title-guard.sh"
pass=0
fail=0

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/branch-title-test.XXXXXX")
trap 'chmod -R u+w "$ROOT" 2>/dev/null' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# One repo carrying every branch shape the audit measured, with a github-style
# origin URL so the `--repo` cases can ask whether the named repo IS this
# worktree, and a second repo to be the target of a `cd` / `git -C`.
git init -q -b main "$ROOT/repo"
R="$ROOT/repo"
(
  cd "$R"
  echo x > f
  git add -A && git commit -qm init
  git remote add origin git@github.com:scottidler/fixture.git
  git branch add-viewport-support
  git branch fix/markdown-dark-mode
  git branch chore/retire-general-plugin
  git branch v0.2.x
)
git init -q -b other-branch "$ROOT/other"
O="$ROOT/other"
(cd "$O" && echo x > f && git add -A && git commit -qm init)

# Three runners, because three things vary: which branch the payload's worktree
# is on, which worktree the payload names, and the MCP vector.
assert() { # assert <expect> <label> <out> <want substring>
  local expect="$1" label="$2" out="$3" want="$4" decision reason
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  if [ "$decision" != "$expect" ]; then
    fail=$((fail + 1))
    printf 'FAIL  [want %s got %s] %s\n      -> %s\n' "$expect" "$decision" "$label" "$reason"
    return
  fi
  if [ -n "$want" ] && ! printf '%s' "$reason" | grep -Fq -- "$want"; then
    fail=$((fail + 1))
    printf 'FAIL  [%s, reason lacks "%s"] %s\n      -> %s\n' "$expect" "$want" "$label" "$reason"
    return
  fi
  pass=$((pass + 1))
  printf 'PASS  [%s] %s\n' "$expect" "$label"
}

run() { # run <expect> <branch checked out in $R> <command> [<want>]
  local expect="$1" br="$2" cmd="$3" want="${4-}" out
  git -C "$R" checkout -q "$br"
  out=$(cd "$ROOT" && jq -n --arg c "$cmd" --arg d "$R" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | bash "$HOOK")
  assert "$expect" "@$br $cmd" "$out" "$want"
}

runcwd() { # runcwd <expect> <payload cwd> <command> [<want>]
  local expect="$1" pcwd="$2" cmd="$3" want="${4-}" out
  out=$(cd "$ROOT" && jq -n --arg c "$cmd" --arg d "$pcwd" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | bash "$HOOK")
  assert "$expect" "cwd=${pcwd##*/} $cmd" "$out" "$want"
}

runmcp() { # runmcp <expect> <title> <head> [<want>]
  local expect="$1" title="$2" head="$3" want="${4-}" out
  out=$(cd "$ROOT" && jq -n --arg t "$title" --arg h "$head" \
    '{tool_name:"mcp__multi-account-github__create_pr",tool_input:{title:$t,head:$h}}' | bash "$HOOK")
  assert "$expect" "MCP head=$head title=$title" "$out" "$want"
}

SQ=\'
MM='git branch -m'
NB='git checkout -b'
MISMATCH='PR title must match the branch name'

echo "=== slash branches: 24 of the 43, unmatchable by any title ==="
run deny 'fix/markdown-dark-mode' \
  "gh pr create --title ${SQ}fix(render): markdown dark mode${SQ}" "$MM"
run deny 'fix/markdown-dark-mode' \
  "gh pr create --title ${SQ}fix(render): markdown dark mode${SQ}" 'git branch -m fix-markdown-dark-mode'
run deny main \
  "gh pr create --head fix/markdown-dark-mode --title ${SQ}fix(render): markdown dark mode${SQ}" "$MM"
run deny 'chore/retire-general-plugin' \
  "gh pr create --title ${SQ}chore(marketplace): retire general plugin${SQ}" "$MM"
run deny main \
  "gh pr create --head chore/retire-general-plugin --title ${SQ}chore(x): retire general plugin${SQ}" "$MM"
run deny main 'gh pr create --head scottidler:fix/markdown-dark-mode --title x' "$MM"
run deny 'fix/markdown-dark-mode' \
  "gh pr create --title ${SQ}fix(render): markdown dark mode${SQ} --body-file body.md" "$MM"

echo "=== dot branches: same collapse, same fix ==="
run deny 'v0.2.x' "gh pr create --title ${SQ}chore(release): v0 2 x${SQ}" "$MM"
run deny main "gh pr create --head v0.2.x --title ${SQ}chore(release): the release${SQ}" "$MM"

echo "=== on main/master there is no branch to match ==="
run deny main "gh pr create --title ${SQ}feat(ui): add viewport support${SQ}" \
  'git checkout -b add-viewport-support'
run deny main "gh pr create -t ${SQ}feat(ui): add viewport support${SQ}" "$NB"
run deny main 'gh pr create --head main --title "feat(x): a thing"' "$NB"
run deny main 'gh pr create --head master --title "feat(x): a thing"' "$NB"

echo "=== plain mismatch: the branch is the source of truth, the TITLE moves ==="
run deny add-viewport-support \
  "gh pr create --title ${SQ}feat(ui): something else entirely${SQ}" "$MISMATCH"
run deny add-viewport-support \
  "gh pr create --title ${SQ}feat(ui): something else entirely${SQ}" 'Do NOT rename the branch'
run deny add-viewport-support \
  'gh pr create --head add-viewport-support --title "feat(ui): other thing"' "$MISMATCH"
run deny add-viewport-support \
  "bash -c ${SQ}gh pr create --title \"feat(ui): other thing\"${SQ}" "$MISMATCH"

echo "=== the wrong-repo denials: the branch is read in the EFFECTIVE worktree ==="
# 3 of the 43. Each of these was judged against the session's branch before.
runcwd allow "$O" "cd $R && gh pr create --title ${SQ}feat(ui): add viewport support${SQ}"
runcwd deny "$R" "cd $O && gh pr create --title ${SQ}feat(ui): add viewport support${SQ}" "$MISMATCH"
runcwd allow "$O" "git -C $R status && gh pr create --title ${SQ}feat(ui): add viewport support${SQ}"
runcwd deny "$O" "gh pr create --title ${SQ}feat(ui): add viewport support${SQ}" "$MISMATCH"
runcwd allow "$O" "gh pr create --title ${SQ}chore(x): other branch${SQ}"

echo "=== --repo names the repository, and it was never read before ==="
run allow add-viewport-support \
  "gh pr create --repo tatari-tv/philo --title ${SQ}feat(x): whatever${SQ}"
run allow add-viewport-support \
  "gh pr create -R tatari-tv/philo --title ${SQ}feat(x): whatever${SQ}"
run deny add-viewport-support \
  "gh pr create --repo scottidler/fixture --title ${SQ}feat(x): whatever${SQ}" "$MISMATCH"
run allow add-viewport-support \
  "gh pr create --repo scottidler/fixture --title ${SQ}feat(ui): add viewport support${SQ}"

echo "=== a matching title allows ==="
run allow add-viewport-support "gh pr create --title ${SQ}feat(ui): add viewport support${SQ}"
run allow add-viewport-support "gh pr create --title ${SQ}feat(ui)!: add viewport support${SQ}"
run allow add-viewport-support "gh pr create --title ${SQ}chore: add viewport support${SQ}"
run allow add-viewport-support \
  "gh pr create --head add-viewport-support --title ${SQ}feat(ui): add viewport support${SQ}"
run allow add-viewport-support \
  "gh pr create --head scottidler:add-viewport-support --title ${SQ}feat(ui): add viewport support${SQ}"
run allow add-viewport-support 'gh pr create --title=add-viewport-support'

echo "=== missing or unknowable data passes through, never denies ==="
run allow add-viewport-support 'gh pr create --head add-viewport-support'
run allow add-viewport-support 'gh pr create --title "$(gen-title)"'
run allow add-viewport-support 'gh pr create --title "$TITLE"'
run allow add-viewport-support 'gh pr create --title `gen-title`'
run allow add-viewport-support 'gh pr create --title "!!!"'
run allow add-viewport-support 'gh pr list'
run allow add-viewport-support 'gh pr create --fill'

echo "=== the cmdword anchor: a gh pr create that is not a command ==="
run allow add-viewport-support 'echo "gh pr create --title x"'
run allow add-viewport-support "grep -n ${SQ}gh pr create --title x${SQ} notes.md"
run allow add-viewport-support 'git commit -m "gh pr create --title bogus"'
run allow add-viewport-support "$(printf 'cat > notes.md <<EOF\ngh pr create --title bogus\nEOF\ngit status')"
run allow add-viewport-support 'gh-pr-helper create --title bogus'

echo "=== the MCP vector carries the same three texts ==="
runmcp allow 'feat(ui): add viewport support' add-viewport-support
runmcp allow 'feat(ui): add viewport support' 'scottidler:add-viewport-support'
runmcp deny 'fix(render): markdown dark mode' 'fix/markdown-dark-mode' "$MM"
runmcp deny 'feat(x): a thing' main "$NB"
runmcp deny 'feat(ui): something else' add-viewport-support "$MISMATCH"
runmcp allow 'feat(ui): add viewport support' ''

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
