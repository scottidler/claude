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
# The 54 cases above the "parser fixes" section are the regression net for the
# lib.sh parser swap and their expectations have never moved. The two cases in
# that section are the only verdicts the swap changed, both of them parser bugs
# rather than gate policy. Everything from "tag force" down is the gate work
# that followed the swap: tag force and off-main tag creation, Gate C matched
# against the EXTRACTED branch name, path-scoped reverts, the statement's own
# worktree, the $TMPDIR / $HOME body-file spellings, and commit on a PR-gated
# main. Those 55 cases are the only expectations added after the swap ran green.
#
# Three runners, because three things vary. `run` checks out a branch in $REPO.
# `runcwd` feeds a payload whose `cwd` differs from the hook process's, which is
# where the guard reads branch and tree state. `runwith` sets one environment
# variable for the hook, which is what makes the body-file expansion observable
# rather than a coincidence of the machine this runs on.
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

# ---------- fixture 4: a dirty worktree and a clean one, judged via the payload ----------
# The destructive-op gates read the tree, and the matrix above never carried a
# dirty-tree case. These two also carry the payload-cwd cases: the hook process
# runs somewhere that is not a repo at all, so any verdict it reaches has to
# have come from the directory the payload named.
git init -q "$ROOT/repo-dirty"
D="$ROOT/repo-dirty"
cd "$D"
echo 'x' > tracked.txt
git add -A && git commit -qm init
echo 'y' >> tracked.txt      # modified but uncommitted: the tree is dirty
echo 'z' > untracked.txt

git init -q "$ROOT/repo-clean"
N="$ROOT/repo-clean"
cd "$N"
echo 'x' > tracked.txt
git add -A && git commit -qm init

# ---------- fixture 5: two mains that differ only by their origin URL ----------
# The commit-on-gated-main gate is scoped by the remote, not by the branch: a
# tatari-tv main is PR-gated so a commit there can never be pushed, while a
# personal main takes direct pushes. `git remote add` is enough; nothing here
# talks to a network.
git init -q -b main "$ROOT/repo-tatari"
W="$ROOT/repo-tatari"
cd "$W"
echo 'x' > f.txt
git add -A && git commit -qm init
git remote add origin git@github.com:tatari-tv/philo.git

git init -q -b main "$ROOT/repo-home"
V="$ROOT/repo-home"
cd "$V"
echo 'x' > f.txt
git add -A && git commit -qm init
git remote add origin git@github.com:scottidler/claude.git

# ---------- fixture 6: body files reached through $TMPDIR and $HOME ----------
# Gate D reads the RAW command text, so these two variables arrive unexpanded
# and the hook expands them itself, by literal string replacement against its
# own environment. The cases below hand the hook a TMPDIR and a HOME of their
# own, so the expansion is observable rather than a coincidence of the machine.
mkdir -p "$ROOT/tmpd" "$ROOT/fakehome"
printf 'Release: rides this PR (v0.1.1)\n\nreal work\n' > "$ROOT/tmpd/body.md"
printf 'Release: rides this PR (v0.1.1)\n\nreal work\n' > "$ROOT/fakehome/body.md"

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

runcwd() { # runcwd <expect deny|allow> <payload cwd> <hook process cwd> <command...>
  local expect="$1" pcwd="$2" hcwd="$3" cmd="$4" out decision
  out=$(cd "$hcwd" && jq -n --arg c "$cmd" --arg w "$pcwd" '{cwd:$w,tool_input:{command:$c}}' | bash "$HOOK")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  if [ "$decision" = "$expect" ]; then
    pass=$((pass+1)); printf 'PASS  [%s cwd=%s] %s\n' "$expect" "${pcwd##*/}" "$cmd"
  else
    fail=$((fail+1)); printf 'FAIL  [want %s got %s cwd=%s] %s\n      -> %s\n' "$expect" "$decision" "${pcwd##*/}" "$cmd" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' | head -c 160)"
  fi
}

runwith() { # runwith <expect> <branch> <VAR=value> <command...>  (in $REPO)
  local expect="$1" br="$2" kv="$3" cmd="$4" out decision
  git -C "$REPO" checkout -q "$br"
  out=$(cd "$REPO" && jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | env "$kv" bash "$HOOK")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  if [ "$decision" = "$expect" ]; then
    pass=$((pass+1)); printf 'PASS  [%s @%s %s] %s\n' "$expect" "$br" "${kv%%=*}" "$cmd"
  else
    fail=$((fail+1)); printf 'FAIL  [want %s got %s @%s %s] %s\n      -> %s\n' "$expect" "$decision" "$br" "${kv%%=*}" "$cmd" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' | head -c 160)"
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

echo "=== parser fixes: the only two verdicts the lib.sh swap moves ==="
# PARSER FIX 1 (problem 2a). `<<EOF` inside double quotes is DATA, not a heredoc
# opener. The old strip_heredocs was not quote-aware, so it opened a heredoc on
# that token and swallowed every following line as a body: the `git reset --hard`
# on line 2 was never handed to a gate at all, and a bypass this shape ALLOWED on
# a dirty tree. lib.sh classes the token as double-quoted content, so line 2 is a
# statement of its own and the dirty-tree gate sees it.
runcwd deny "$D" "$D" 'echo "<<EOF"
git reset --hard'
# PARSER FIX 2. A subshell is a NESTED statement, not text belonging to the outer
# one. The outer statement's $( ) span is neutralized, so `git push` no longer
# reads the inner `--tags` as its own flag, and the nested statement's verb is
# `describe`, not `push`. This denied on main before the swap: the measured false
# positive on the one command that reads the latest tag name.
run allow main 'git push origin "$(git describe --tags --abbrev=0)"'

echo "=== branch and tree state come from the payload's cwd ==="
# The hook process runs in $ROOT, which is not a repo, so neither verdict can
# have come from its own directory.
runcwd deny  "$D" "$ROOT" 'git reset --hard'
runcwd allow "$N" "$ROOT" 'git reset --hard'

echo "=== tag force: never move a tag, whatever the spelling ==="
run deny  main 'git tag -f -a v1 -m moved'
run deny  main 'git tag -fa v1 -m moved'          # the combined form a model types
run deny  main 'git tag -af v1 -m moved'
run deny  main 'git tag --force -a v1 -m moved'
run deny  main 'git tag -d v0.1.0'                # deletion, still walled
run allow main "git tag -l 'v*'"                  # listing is not creation
run allow main 'git tag'                          # bare listing
# mask_optarg: a flag named inside a -m value is prose, not an option. -F is a
# message FILE flag and carries no lowercase f for the cluster match to find.
run allow main 'git tag -a v1 -m "added --force"'
# cmdword_is git: the statement's command word is echo, so no gate applies.
run allow main 'echo "git tag -f v1"'
# ...but a subshell IS a statement, and the deny comes from the nested one.
run deny  main 'echo "$(git push origin --tags)"'

echo "=== tag creation is cut on main only ==="
run allow main      'git tag -a v9.9.9 -m probe'
run deny  feat-real 'git tag -a v9.9.9 -m probe'
run deny  feat-real 'git tag -s v9.9.9 -m probe'
run deny  feat-real 'git tag v9.9.9'
# The -d lives in a MESSAGE, so this is a creation off main and not a deletion.
run deny  feat-real 'git tag -a v1 -m "fix the -d flag"'
# Read-only forms carrying an operand are not creations.
run allow feat-real 'git tag --contains HEAD'
run allow feat-real "git tag -l 'v*'"

echo "=== path-scoped reverts are allowed; tree-wide ones are not ==="
runcwd allow "$D" "$D" 'git checkout -- tracked.txt'
runcwd allow "$D" "$D" 'git checkout -- tracked.txt untracked.txt'
runcwd deny  "$D" "$D" 'git checkout -- .'
runcwd deny  "$D" "$D" 'git checkout -- ./'
runcwd deny  "$D" "$D" 'git checkout -- :/'
runcwd deny  "$D" "$D" 'git checkout -- "src/*.rs"'
runcwd deny  "$D" "$D" 'git checkout -- $SOMEDIR'
runcwd deny  "$D" "$D" 'git checkout -- "$(pwd)"'
runcwd deny  "$D" "$D" 'git checkout --'
runcwd allow "$D" "$D" 'git restore src/'
runcwd deny  "$D" "$D" 'git restore --staged src/'
runcwd deny  "$D" "$D" 'git restore --source=HEAD~1 src/'
runcwd deny  "$D" "$D" 'git reset --hard'
runcwd allow "$N" "$N" 'git checkout -- .'        # clean tree: nothing to lose

echo "=== the tree judged is the STATEMENT's, not the last cd in the chain ==="
# cd_at, not cd_target. With cd_target this resolves to the clean directory and
# ALLOWS a revert that discards the work in the dirty one.
runcwd deny  "$D" "$D" "git checkout -- . && cd $N"
runcwd deny  "$D" "$D" "git reset --hard && cd $N"
# ...and the mirror: the cd comes FIRST, so the statement runs in the dirty tree.
runcwd deny  "$N" "$N" "cd $D && git reset --hard"

echo "=== git clean -f is judged against the statement's own worktree ==="
runcwd deny  "$D" "$ROOT" 'git clean -fd'         # untracked files present
runcwd allow "$N" "$ROOT" 'git clean -fd'         # none present
runcwd deny  "$N" "$N"    "cd $D && git clean -fd"
runcwd allow "$D" "$D"    "cd $N && git clean -fd"

echo "=== Gate C matches the EXTRACTED branch name ==="
run deny  main 'git checkout -b chore/bump-0.9.0'
run deny  main 'git switch -c feature/release-1.2.3'
run allow main 'git checkout -b bumpkin-feature'
run allow main 'git checkout -b fix-auth-bug'
# The name is extracted, so a statement that merely MENTIONS one is not a create.
run allow main "git commit -m 'mention bump-1.0.0'"
run allow main "git commit -m 'git checkout -b bump-1.0.0'"

echo "=== mask_optarg: prose in a message value is not an operation ==="
# Measured in Phase 3: this DENIED before the parser swap and allows after,
# because `restore --staged` sits in a -m value. Pinned here, in the phase whose
# matrix names the mask_optarg cases.
runcwd allow "$D" "$D" 'git commit -m "explain git restore --staged in the docs"'

echo "=== --body-file expands \$TMPDIR / \$HOME, by string replacement ==="
runwith allow feat-real "TMPDIR=$ROOT/tmpd" 'gh pr create --title "feat: real" --body-file "$TMPDIR/body.md"'
runwith allow feat-real "TMPDIR=$ROOT/tmpd" 'gh pr create --title "feat: real" --body-file "${TMPDIR}/body.md"'
runwith allow feat-real "TMPDIR=$ROOT/tmpd" 'gh pr create --title "feat: real" --body-file=$TMPDIR/body.md'
runwith allow feat-real "HOME=$ROOT/fakehome" 'gh pr create --title "feat: real" --body-file "$HOME/body.md"'
runwith allow feat-real "HOME=$ROOT/fakehome" 'gh pr create --title "feat: real" --body-file "${HOME}/body.md"'
# An expandable spelling pointing at a file that is not there is still a deny:
# the expansion widens what can be VERIFIED, it never waves a body through.
runwith deny  feat-real "TMPDIR=$ROOT/tmpd" 'gh pr create --title "feat: real" --body-file "$TMPDIR/missing.md"'
# A variable this hook does not know stays unexpanded and still refuses loudly.
runwith deny  feat-real "TMPDIR=$ROOT/tmpd" 'gh pr create --title "feat: real" --body-file "$XDG_CACHE_HOME/body.md"'

echo "=== commit on a PR-gated main is scoped by the remote ==="
REPO="$W"
run deny  main 'git commit -m "fix: something"'
run deny  main 'git add -A && git commit -m "fix: something"'
REPO="$V"
run allow main 'git commit -m "fix: something"'
REPO="$R"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
