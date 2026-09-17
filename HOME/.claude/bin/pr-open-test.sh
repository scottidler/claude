#!/bin/bash
# pr-open-test.sh: the regression net for `pr-open`, and the mechanical form of
# Phase 9's success criteria.
#
# The criteria are "run it against the LIVE hooks", meaning: take the command
# pr-open prints, wrap it in a PreToolUse payload, feed it to the hook on stdin
# and read the JSON. Never open a PR to find out. That is exactly what this
# does, in both directions:
#
#   - version delta on the branch + `--release rides`  -> git-release-guard.sh
#     and branch-pr-title-guard.sh both return `{}` (allow).
#   - no version delta + a body claiming `rides`       -> Gate D denies, and the
#     denial text is asserted rather than assumed.
#
# Fixtures are throwaway repos under $TMPDIR (bare origin + clone), built the
# same way git-release-guard-test.sh builds its own, because both gates read
# real git state: the branch, the remote default branch, and the version-line
# diff vs that base.
#
# Run directly: bash HOME/.claude/bin/pr-open-test.sh
set -u

BIN="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PROPEN="$BIN/pr-open"
RELEASE="$BIN/release"
HOOKS="$(cd "$BIN/../hooks" && pwd)"
RELEASE_GUARD="$HOOKS/git-release-guard.sh"
TITLE_GUARD="$HOOKS/branch-pr-title-guard.sh"

for f in "$PROPEN" "$RELEASE" "$RELEASE_GUARD" "$TITLE_GUARD"; do
  [ -r "$f" ] || { echo "MISSING: $f"; exit 1; }
done

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/pr-open-test.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT   # regenerable: this whole tree is built above

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
want() { # want <label> <expected substring> <actual>
  case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "expected to contain: $2"$'\n     got: '"$3" ;; esac
}
wantnot() {
  case "$3" in *"$2"*) bad "$1" "should NOT contain: $2"$'\n     got: '"$3" ;; *) ok "$1" ;; esac
}

# A PreToolUse Bash payload whose cwd is the fixture repo, fed to a hook.
hook() { # hook <hook path> <cwd> <command>
  jq -n --arg c "$3" --arg d "$2" \
    '{tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' | "$1"
}

# ---------- fixture: bare origin + clone, a Rust-shaped release-managed repo ----
git init -q --bare "$ROOT/origin.git"
git -C "$ROOT/origin.git" symbolic-ref HEAD refs/heads/main
git clone -q "$ROOT/origin.git" "$ROOT/repo" 2>/dev/null
R="$ROOT/repo"
cd "$R" || exit 1
cat > Cargo.toml <<'EOF'
[package]
name = "fixture"
version = "0.1.0"
EOF
mkdir src && echo 'fn main(){}' > src/main.rs
git add -A && git commit -qm "chore: init" && git push -q origin main
git remote set-head origin main

# Branch WITH a version delta: real work, then the bump that rides it.
git checkout -q -b pr-open-fixture
echo 'fn extra(){}' >> src/main.rs
git commit -qam "feat(fixture): pr open fixture"
sed -i 's/version = "0.1.0"/version = "0.1.1"/' Cargo.toml
git commit -qam "bump version 0.1.0 -> 0.1.1"

# Branch WITHOUT a version delta: work only.
git checkout -q main
git checkout -q -b pr-open-nobump
echo 'fn other(){}' >> src/main.rs
git commit -qam "fix(fixture): pr open nobump"

echo "=== pr-open: the emitted command ==="
git checkout -q pr-open-fixture
CMD=$(cd "$R" && "$PROPEN" --type feat --scope fixture --release rides 2>/dev/null)
RC=$?
[ "$RC" = 0 ] || bad "pr-open exits 0 on a delta branch" "exit $RC"
want "title is derived from the branch" '--title "feat(fixture): pr open fixture"' "$CMD"
want "head is the branch"               '--head pr-open-fixture'                   "$CMD"
want "base is the origin default"       '--base main'                              "$CMD"
want "persona is explicit"              'GH_PERSONA='                              "$CMD"
wantnot "no --fill"                     '--fill'                                   "$CMD"
wantnot "no unexpanded TMPDIR"          '$TMPDIR'                                  "$CMD"
wantnot "no stdin body"                 '--body-file -'                            "$CMD"

BODY=$(printf '%s' "$CMD" | sed -nE 's/.*--body-file ([^ ]+).*/\1/p')
case "$BODY" in /*) ok "body-file path is absolute" ;; *) bad "body-file path is absolute" "got: $BODY" ;; esac
[ -r "$BODY" ] && ok "body file exists and is readable" || bad "body file exists and is readable" "$BODY"
want "body carries the rides line" 'Release: rides this PR (v0.1.1)' "$(cat "$BODY" 2>/dev/null)"

echo "=== live hooks: ALLOW direction (version delta + rides) ==="
OUT=$(hook "$RELEASE_GUARD" "$R" "$CMD")
[ "$OUT" = "{}" ] && ok "git-release-guard.sh allows (empty decision)" \
                  || bad "git-release-guard.sh allows (empty decision)" "got: $OUT"
OUT=$(hook "$TITLE_GUARD" "$R" "$CMD")
[ "$OUT" = "{}" ] && ok "branch-pr-title-guard.sh allows (empty decision)" \
                  || bad "branch-pr-title-guard.sh allows (empty decision)" "got: $OUT"

echo "=== live hooks: DENY direction (no version delta + a rides claim) ==="
git checkout -q pr-open-nobump
# pr-open refuses to emit this at all, which is the first half of the criterion.
ERR=$(cd "$R" && "$PROPEN" --type fix --scope fixture --release rides 2>&1 >/dev/null)
RC=$?
[ "$RC" != 0 ] && ok "pr-open refuses --release rides with no version delta" \
               || bad "pr-open refuses --release rides with no version delta" "exit 0, output: $ERR"
want "and it says why" "no version line changes" "$ERR"

# The second half: the command SHAPE, carrying a rides claim, put in front of
# Gate D. Built from pr-open's own output (a `none` run, whose body file is then
# made to carry the rides claim) so the shape under test is never hand-copied.
CMD2=$(cd "$R" && "$PROPEN" --type fix --scope fixture --release none --reason "test fixture" 2>/dev/null)
BODY2=$(printf '%s' "$CMD2" | sed -nE 's/.*--body-file ([^ ]+).*/\1/p')
printf 'work\n\nRelease: rides this PR (v0.1.1)\n' > "$BODY2"
OUT=$(hook "$RELEASE_GUARD" "$R" "$CMD2")
DEC=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""')
[ "$DEC" = "deny" ] && ok "Gate D denies the unbacked rides claim" \
                    || bad "Gate D denies the unbacked rides claim" "got: $OUT"
want "deny names the missing version delta" "no version line changes" \
     "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"

echo "=== pr-open: the refusals ==="
git checkout -q pr-open-fixture
ERR=$(cd "$R" && "$PROPEN" --scope fixture --release rides 2>&1 >/dev/null); \
  want "--type is required" "--type is required" "$ERR"
ERR=$(cd "$R" && "$PROPEN" --type feat 2>&1 >/dev/null); \
  want "--release is required" "--release is required" "$ERR"
ERR=$(cd "$R" && "$PROPEN" --type feat --release none 2>&1 >/dev/null); \
  want "--release none requires a reason" "requires --reason" "$ERR"
git checkout -q main
ERR=$(cd "$R" && "$PROPEN" --type feat --release none --reason x 2>&1 >/dev/null); \
  want "refuses on main" "no feature branch" "$ERR"
git checkout -q -b feature/slashed 2>/dev/null
ERR=$(cd "$R" && "$PROPEN" --type feat --release none --reason x 2>&1 >/dev/null); \
  want "refuses a branch no title can match" "can never match any title" "$ERR"

echo "=== pr-open: persona comes from the remote's org, not the cwd ==="
git checkout -q pr-open-fixture
git remote set-url origin git@github.com:tatari-tv/fixture.git
CMD3=$(cd "$R" && "$PROPEN" --type feat --scope fixture --release rides 2>/dev/null)
want "tatari-tv remote yields the work persona" "GH_PERSONA=work" "$CMD3"
git remote set-url origin git@github.com:scottidler/fixture.git
CMD4=$(cd "$R" && "$PROPEN" --type feat --scope fixture --release rides 2>/dev/null)
want "a personal remote yields the home persona" "GH_PERSONA=home" "$CMD4"

echo "=== release: the PR-creation hand-back ==="
grep -q 'gh pr create --fill' "$RELEASE" \
  && bad "release no longer runs 'gh pr create --fill'" "the --fill call is still there" \
  || ok "release no longer runs 'gh pr create --fill'"
grep -q 'PR creation required' "$RELEASE" \
  && ok "release emits the 'PR creation required' result" \
  || bad "release emits the 'PR creation required' result" "string absent"
# An INVOCATION of pr-open puts it in command position: at the start of a
# statement, or inside a `$( )` or backtick substitution. The literal command
# text `release` prints lives inside a string assignment, which is none of
# those, so this separates "prints it" from "runs it".
CALLS=$(grep -nE '(\$\(|`|^[[:space:]]*|;[[:space:]]*)pr-open[[:space:]]' "$RELEASE" | grep -vE ':[[:space:]]*#')
[ -z "$CALLS" ] && ok "release does not CALL pr-open (it prints the command)" \
                || bad "release does not CALL pr-open" "$CALLS"
# Same idea for gh: command position only, so the many mentions inside quoted
# guidance text are not mistaken for calls.
BAREGH=$(grep -nE '(\$\(|^[[:space:]]*|;[[:space:]]*)gh[[:space:]]+(pr|api|repo)[[:space:]]' "$RELEASE")
[ -z "$BAREGH" ] && ok "every gh call in release sets GH_PERSONA" \
                 || bad "every gh call in release sets GH_PERSONA" "$BAREGH"

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ] || exit 1
