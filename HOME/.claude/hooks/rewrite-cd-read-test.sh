#!/bin/bash
# rewrite-cd-read-test.sh: fixture matrix for rewrite-cd-read.py.
#
# Each case feeds the hook a PreToolUse payload on stdin and asserts on the
# command it hands back in updatedInput. The `git -C <cwd>` strip is the reason
# this file exists: it replaced a hook that DENIED that form 249 times with zero
# cross-repo saves, and the strip has to compose with the older cd rewrite
# inside this one process, because two updatedInput hooks on one Bash call each
# receive the ORIGINAL input and only the last to complete keeps its edit.
set -u
export LC_ALL=C

# readlink -f: the test is also reachable through its ~/.claude/hooks symlink, and
# "$HOOKS/../../.." from THERE is /home, not the repo.
HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
HOOK="$HOOKS/rewrite-cd-read.py"
REPO="$(cd "$HOOKS/../../.." && pwd)"
# The strip does no filesystem access, so any absolute path would do; the repo
# root keeps the matrix off machine-specific paths.
CWD="$REPO"
OTHER=/tmp
# Never append to the live ~/.cache/claude/rewrite-cd-read.log from a test run.
export REWRITE_CD_READ_LOG="${TMPDIR:-/tmp}/rewrite-cd-read-test.$$.log"
: > "$REWRITE_CD_READ_LOG"
trap 'rm -f "$REWRITE_CD_READ_LOG"' EXIT

pass=0
fail=0

fire() { # fire <cwd> <command>
  jq -n --arg c "$2" --arg d "$1" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | "$HOOK"
}

check() { # check <got> <want> <label>
  if [ "$1" = "$2" ]; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$3"
  else
    fail=$((fail + 1))
    printf 'FAIL  [want %s got %s] %s\n' "$2" "$1" "$3"
  fi
}

run() { # run <expected rewritten command | UNCHANGED> <cwd> <command>
  local expect="$1" cwd="$2" cmd="$3" out got
  out=$(fire "$cwd" "$cmd")
  if [ "$expect" = UNCHANGED ]; then
    got=$(printf '%s' "$out" | jq -r 'if .hookSpecificOutput then .hookSpecificOutput.updatedInput.command else "UNCHANGED" end')
  else
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // "UNCHANGED"')
  fi
  check "$got" "$expect" "$(printf '%s' "$cmd" | tr '\n' '~')"
}

echo "=== the flag points at the cwd: strip it ==="
run 'git status' "$CWD" "git -C $CWD status"
# The old hook's lookbehind matched a literal `git -C ` with one space on each
# side, so both of the next two ALLOWED the very form it existed to catch.
run 'git status' "$CWD" 'git -C "$PWD" status'
run 'git status' "$CWD" "git -C '\$PWD' status"
run 'git status' "$CWD" 'git -C $PWD status'
# splice drops the whitespace ahead of a dropped token and passes every other
# byte through, so the doubled space between the flag and `status` survives.
run 'git  status' "$CWD" "git  -C  $CWD  status"
run 'git status' "$CWD" "git -C $CWD/ status"
run 'git status' "$CWD" 'git -C . status'
# The live AC5 command, as a fixture.
run 'git rev-parse --show-toplevel' "$CWD" "git -C $CWD rev-parse --show-toplevel"

echo "=== the flag points somewhere else: leave it ==="
run UNCHANGED "$CWD" "git -C $OTHER status"
run 'git status && git -C /tmp log' "$CWD" "git -C $CWD status && git -C $OTHER log"
run UNCHANGED "$CWD" "git -C ${CWD}x status"

echo "=== -C is overloaded: only git's global option position counts ==="
run UNCHANGED "$CWD" 'git commit -C HEAD~1'
run UNCHANGED "$CWD" "git commit -C $CWD"
run UNCHANGED "$CWD" 'git switch -C feature'
run UNCHANGED "$CWD" "git switch -C $CWD"

echo "=== the text is not a command: leave it ==="
run UNCHANGED "$CWD" "echo \"git -C $CWD status\""
run UNCHANGED "$CWD" "echo 'git -C $CWD status'"
run UNCHANGED "$CWD" "rg -n 'git -C' $REPO/.otto.yml"
# A heredoc makes the whole command unrewritable (`<<` is a redirect this hook
# refuses to reason about), so a body line that looks like a git statement is
# never touched.
run UNCHANGED "$CWD" "$(printf 'cat <<%sEOF%s\ngit -C %s status\nEOF\n' "'" "'" "$CWD")"
run UNCHANGED "$CWD" 'ls -la'
run UNCHANGED "$CWD" 'echo no git here'

echo "=== the cd rewrite still works on its own ==="
run "cat $REPO/.otto.yml" "$CWD" "cd $REPO && cat .otto.yml"

echo "=== both rewrites in one output ==="
run 'git status' "$CWD" "cd $CWD && git -C $CWD status"
run "git -C $OTHER log" "$CWD" "cd $CWD && git -C $OTHER log"

echo "=== a deny-patterned form is canonicalized INTO its pattern, not out ==="
# Bash(git tag -d *) only matches after the flag is gone, so the strip runs here
# even though the cd rewrite refuses to touch a stage like this.
run 'git tag -d v1' "$CWD" "git -C $CWD tag -d v1"

echo "=== the sibling tool_input fields survive the updatedInput replacement ==="
# Scar tissue: updatedInput REPLACES tool_input wholesale. Emitting only
# `command` once dropped dangerouslyDisableSandbox and ran a git push sandboxed.
out=$(jq -n --arg c "git -C $CWD status" --arg d "$CWD" \
  '{tool_name:"Bash",tool_input:{command:$c,dangerouslyDisableSandbox:true,timeout:120000},cwd:$d}' | "$HOOK")
check "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.dangerouslyDisableSandbox')" 'true' 'dangerouslyDisableSandbox survives'
check "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.timeout')" '120000' 'timeout survives'
check "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command')" 'git status' 'command still rewritten beside them'

echo "=== the decision shape per branch ==="
out=$(fire "$CWD" "git -C $CWD status")
check "$(printf '%s' "$out" | jq -r '.hookSpecificOutput | has("permissionDecision")')" 'false' 'a strip-only rewrite carries no permissionDecision'
check "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason | test("-C") ')" 'true' 'a strip-only rewrite names the flag in its reason'
out=$(fire "$CWD" "cd $CWD && git -C $CWD status")
check "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"')" 'allow' 'a strip riding a read-only cd rewrite keeps the allow'

echo "=== the strip is observable in the log ==="
# Spike 0b (2026-09-14): a rewrite's permissionDecisionReason never reaches the
# model, so the log is the only place a strip can be seen at all.
if rg -q '	STRIP-C	flag-pointed-at-cwd	' "$REWRITE_CD_READ_LOG"; then
  pass=$((pass + 1)); printf 'PASS  a strip-only rewrite logs STRIP-C\n'
else
  fail=$((fail + 1)); printf 'FAIL  no STRIP-C line in %s\n' "$REWRITE_CD_READ_LOG"
fi
if rg -q 'all-stages-read-only\+strip-c' "$REWRITE_CD_READ_LOG"; then
  pass=$((pass + 1)); printf 'PASS  a strip riding a cd rewrite logs +strip-c\n'
else
  fail=$((fail + 1)); printf 'FAIL  no +strip-c detail in %s\n' "$REWRITE_CD_READ_LOG"
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
