#!/bin/bash
# git-release-guard-test.sh -- regression matrix for git-release-guard.sh.
#
# Builds a throwaway fixture repo (origin + clone, feature/bump-only/dep-bump/
# lockfile-only branches, v* tag so Gate D applies) and feeds synthetic
# PreToolUse JSON through the hook, asserting the expected allow/deny for every
# gate: branch-name (C), zero-ahead bump (A), bump-only push/PR content (B),
# release-intent on gh pr create (D), the BUMP_ORDERED_BY_SCOTT=1 door, and all
# pre-existing checks (tag deletion, --tags push, force-push, dirty-tree bump,
# false-positive guards). Exits non-zero on any failure.
#
# Run directly, or via: git-release-guard.sh --self-test
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/git-release-guard.sh"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/guard-test.XXXXXX")
trap 'chmod -R u+w "$ROOT" 2>/dev/null' EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# ---------- fixture: origin + clone ----------
git init -q --bare "$ROOT/origin.git"
git -C "$ROOT/origin.git" symbolic-ref HEAD refs/heads/main
git clone -q "$ROOT/origin.git" "$ROOT/repo" 2>/dev/null
R="$ROOT/repo"
cd "$R"
cat > Cargo.toml <<'EOF'
[package]
name = "fixture"
version = "0.1.0"

[dependencies]
mcp-io = { git = "https://example.com/mcp-io", tag = "v0.1.1" }
EOF
echo 'lock v1' > Cargo.lock
mkdir src && echo 'fn main(){}' > src/main.rs
git add -A && git commit -qm init && git push -q origin main
git remote set-head origin main
git tag -a v0.1.0 -m v0.1.0   # release-managed repo: Gate D applies

# feature branch WITH real work + a version bump (legit gated flow)
git checkout -qb feat-real
echo '// real change' >> src/main.rs
git commit -qam 'feat: real work'
sed -i 's/^version = "0.1.0"/version = "0.1.1"/' Cargo.toml
echo 'lock v2' > Cargo.lock
git commit -qam 'Bump version to v0.1.1'

# bump-only branch (the crime): only version + lock changed
git checkout -q main
git checkout -qb sneaky-bump
sed -i 's/^version = "0.1.0"/version = "0.2.1"/' Cargo.toml
echo 'lock v3' > Cargo.lock
git commit -qam 'Bump version to v0.2.1'

# dep-bump branch (PR #15 shape): Cargo.toml dep line + lock, NO version line
git checkout -q main
git checkout -qb dep-bump
sed -i 's/tag = "v0.1.1"/tag = "v0.1.2"/' Cargo.toml
echo 'lock v4' > Cargo.lock
git commit -qam 'chore(deps): bump mcp-io to v0.1.2'

# lockfile-only branch (cargo update shape)
git checkout -q main
git checkout -qb lock-only
echo 'lock v5' > Cargo.lock
git commit -qam 'chore: cargo update'

# zero-ahead branch (fresh off main, nothing committed)
git checkout -q main
git checkout -qb fresh-branch

git checkout -q main

# ---------- runner ----------
pass=0; fail=0
run() { # run <expect deny|allow> <branch-to-checkout> <command...>
  local expect="$1" br="$2" cmd="$3" out decision
  git -C "$R" checkout -q "$br"
  out=$(cd "$R" && jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$HOOK")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  if [ "$decision" = "$expect" ]; then
    pass=$((pass+1)); printf 'PASS  [%s @%s] %s\n' "$expect" "$br" "$cmd"
  else
    fail=$((fail+1)); printf 'FAIL  [want %s got %s @%s] %s\n      -> %s\n' "$expect" "$decision" "$br" "$cmd" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' | head -c 160)"
  fi
}

echo "=== Gate C: branch-name creation ==="
run deny  main 'git checkout -b bump-0.2.1'
run deny  main 'git checkout -b release-0.1.1'
run deny  main 'git switch -c bump-9.9.9'
run deny  main 'git branch bump-0.2.1 a09cc40'
run allow main 'git checkout -b fix-auth-bug'
run allow main 'git branch -d bump-0.2.1'
run allow main "git branch --list 'bump*'"
run allow main 'git checkout -b bumpkin-feature'

echo "=== Gate A: bump --no-tag needs real work ahead ==="
run allow feat-real   'bump --no-tag'
run deny  fresh-branch 'bump --no-tag'
run deny  sneaky-bump 'bump'                 # pre-existing: tag-creating bump on branch
run allow main        'bump --gates'
run deny  feat-real   'bump -m'              # pre-existing: tag-creating on branch

echo "=== Gate B: push/PR of bump-only content ==="
run deny  sneaky-bump 'git push -u origin sneaky-bump 2>&1 | /usr/bin/tail -2'
run deny  sneaky-bump 'git push origin sneaky-bump'
run deny  sneaky-bump 'git push'                                   # no refspec -> HEAD
run deny  main        'git push origin sneaky-bump'                # from main, explicit ref
run deny  sneaky-bump 'GH_PERSONA=work gh pr create --repo tatari-tv/slack-cli --base main --head sneaky-bump --title "chore(release): bump version to v0.2.1"'
run deny  sneaky-bump 'gh pr create --title x --body y'
run allow feat-real   'git push -u origin feat-real'               # bump rides real work
run allow dep-bump    'git push -u origin dep-bump'                # PR #15 shape
run allow lock-only   'git push -u origin lock-only'
run allow main        'git push origin main'
run allow sneaky-bump 'git push origin --delete sneaky-bump'       # deletion pushes no content

echo "=== Gate D: release intent required on gh pr create ==="
run allow feat-real 'gh pr create --title "feat: real" --body "stuff
Release: rides this PR (v0.1.1)"'
run allow dep-bump  'gh pr create --title "chore(deps): bump" --body "Release: none - dep bump only, no release cut"'
run deny  feat-real 'gh pr create --title "feat: real" --body "no intent line here"'
run deny  dep-bump  'gh pr create --title "chore(deps): bump" --body "Release: rides this PR (v9.9.9)"'  # claims rides, no version change

echo "=== Scott override: BUMP_ORDERED_BY_SCOTT=1 opens the door ==="
run allow main         'BUMP_ORDERED_BY_SCOTT=1 git checkout -b bump-0.1.3'
run allow fresh-branch 'BUMP_ORDERED_BY_SCOTT=1 bump --no-tag'
run allow sneaky-bump  'BUMP_ORDERED_BY_SCOTT=1 git push -u origin sneaky-bump'
run deny  fresh-branch 'bump --no-tag'                             # without the marker, still walled

echo "=== pre-existing checks still intact ==="
run deny  main 'git push --tags'
run deny  main 'git tag -d v0.1.0'
run deny  main 'git push origin --force main'
run allow main 'git push origin v0.2.1'
run allow main 'git status'
run allow main 'git commit -m "bump the widget count"'   # substring false-positive guard

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
