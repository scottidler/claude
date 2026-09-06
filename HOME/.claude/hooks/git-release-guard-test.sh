#!/bin/bash
# git-release-guard-test.sh -- regression matrix for git-release-guard.sh.
#
# Builds throwaway fixture repos (origin + clone, feature/bump-only/dep-bump/
# lockfile-only branches; a tagged Rust repo, a never-tagged versioned Python
# repo -- the okta-auth-py shape -- and a version-less-manifest repo) and feeds
# synthetic PreToolUse JSON through the hook, asserting the expected allow/deny
# for every gate: branch-name (C), zero-ahead bump (A), bump-only push/PR
# content (B), release-intent on gh pr create (D, tagged AND never-tagged),
# the BUMP_ORDERED_BY_SCOTT=1 door, and all pre-existing checks (tag deletion,
# --tags push, force-push, dirty-tree bump, false-positive guards). Exits
# non-zero on any failure.
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

# ---------- fixture 2: versioned but NEVER tagged (okta-auth-py shape) ----------
# Gate D must apply here too -- requiring a v* tag exempted exactly this repo
# shape and let okta-auth-py #5/#6 merge bumpless (2026-07-13).
git init -q --bare "$ROOT/origin-py.git"
git -C "$ROOT/origin-py.git" symbolic-ref HEAD refs/heads/main
git clone -q "$ROOT/origin-py.git" "$ROOT/repo-py" 2>/dev/null
P="$ROOT/repo-py"
cd "$P"
cat > pyproject.toml <<'EOF'
[project]
name = "fixture-py"
version = "0.3.0"
EOF
mkdir src && echo 'x = 1' > src/lib.py
git add -A && git commit -qm init && git push -q origin main
git remote set-head origin main
# NO tag, deliberately.

git checkout -qb py-feat
echo 'y = 2' >> src/lib.py
git commit -qam 'feat: real work'

git checkout -qb py-feat-bumped
sed -i 's/^version = "0.3.0"/version = "0.4.0"/' pyproject.toml
git commit -qam 'Bump version to v0.4.0'
git checkout -q main

# ---------- fixture 3: manifest with NO version line (tool-config-only) ----------
git init -q --bare "$ROOT/origin-cfg.git"
git -C "$ROOT/origin-cfg.git" symbolic-ref HEAD refs/heads/main
git clone -q "$ROOT/origin-cfg.git" "$ROOT/repo-cfg" 2>/dev/null
C="$ROOT/repo-cfg"
cd "$C"
cat > pyproject.toml <<'EOF'
[tool.ruff]
line-length = 120
EOF
echo 'x = 1' > lib.py
git add -A && git commit -qm init && git push -q origin main
git remote set-head origin main
git checkout -qb cfg-feat
echo 'y = 2' >> lib.py
git commit -qam 'feat: real work'
git checkout -q main

cd "$R"

# ---------- runner ----------
pass=0; fail=0
REPO="$R"
run() { # run <expect deny|allow> <branch-to-checkout> <command...>  (in $REPO)
  local expect="$1" br="$2" cmd="$3" out decision
  git -C "$REPO" checkout -q "$br"
  out=$(cd "$REPO" && jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$HOOK")
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

# --body-file: the path is read from the RAW command text, so every quoting and
# expansion form has to land. All four "allow" cases below denied before
# 2026-09-06 (otto-rs/otto #6, #7): the file test failed silently and the body
# was never read.
printf 'Release: rides this PR (v0.1.1)\n\nreal work\n' > "$ROOT/body.md"
printf 'Release: rides this PR (v0.1.1)\n\nreal work\n' > "$ROOT/body with space.md"
run allow feat-real "gh pr create --title 'feat: real' --body-file $ROOT/body.md"
run allow feat-real "gh pr create --title 'feat: real' --body-file '$ROOT/body.md'"
run allow feat-real "gh pr create --title 'feat: real' --body-file \"$ROOT/body.md\""
run allow feat-real "gh pr create --title 'feat: real' --body-file=$ROOT/body.md"
run allow feat-real "gh pr create --title 'feat: real' --body-file \"$ROOT/body with space.md\""
# Named but unverifiable: still a deny. These three denied before the fix too,
# so they do not discriminate old from new -- the harness matches the DECISION,
# not the reason, and the change here is that the reason is now accurate
# ("cannot be read") instead of the misleading "no release-intent line". They
# are pinned so a later rewrite cannot quietly let an unreadable body through.
run deny  feat-real 'gh pr create --title "feat: real" --body-file $BODY/b.md'
run deny  feat-real 'gh pr create --title "feat: real" --body-file -'
run deny  feat-real 'gh pr create --title "feat: real" --body-file /nonexistent/body.md'

echo "=== Gate D: applies to versioned-but-NEVER-tagged repos (okta-auth-py #5/#6) ==="
REPO="$P"
run deny  py-feat        'gh pr create --title "feat: real" --body "no intent line here"'
run allow py-feat        'gh pr create --title "feat: real" --body "Release: none - port only, version policy-gated"'
run deny  py-feat        'gh pr create --title "feat: real" --body "Release: rides this PR (v0.4.0)"'   # claims rides, no version change
run allow py-feat-bumped 'gh pr create --title "feat: real" --body "Release: rides this PR (v0.4.0)"'

echo "=== Gate D: version-less manifest (tool-config-only) stays ungated ==="
REPO="$C"
run allow cfg-feat 'gh pr create --title "feat: real" --body "no intent line here"'
REPO="$R"

echo "=== heredoc bodies are not statements (otto-rs/otto b428680, 2026-09-01) ==="
# A commit message whose wrapped line STARTS with "bump" is prose, not a command.
run allow feat-real "git add -A && git commit -q -F - <<'MSG'
docs: handoff

... Adding an optional field does NOT
bump it. Every key here is additive.
MSG"
# The inverse: a real bump AFTER the terminator must still be caught.
run deny feat-real "git commit -q -F - <<'MSG'
docs: x
bump this line is prose
MSG
bump -m"
# Gate D still sees a Release: line delivered by heredoc ($cmd is not stripped).
run allow feat-real "gh pr create --title 'feat: real' --body \"\$(cat <<'B'
real work here
Release: rides this PR (v0.1.1)
B
)\""

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
