#!/bin/bash
# intent-guard-test.sh: the matrix for intent-guard.sh.
#
# Wired into `.otto.yml`'s test task by glob (`*-test.sh`), so it needs no
# .otto.yml edit of its own. The lint task's FILES array is explicit and does.
#
# Every irreversible deny runs through shapes.sh's wrap_shapes, 18 spellings,
# because a guard that only holds for the bare form is not a guard. The
# exception is any fixture carrying a single quote: shapes.sh:45 states that a
# command with a single quote or a newline cannot ride the quoted wrapper
# shapes, so those are asserted directly.

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
HOOK="$HOOKS/intent-guard.sh"
. "$HOOKS/shapes.sh" || exit 1
pass=0
fail=0

run() { # run <expect deny|allow> <command>
  local expect="$1" cmd="$2" out decision
  out=$(jq -n --arg c "$cmd" --arg d "$PWD" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | bash "$HOOK")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  if [ "$decision" = "$expect" ]; then
    pass=$((pass + 1))
    printf 'PASS  [%s] %s\n' "$expect" "$cmd"
  else
    fail=$((fail + 1))
    printf 'FAIL  [want %s got %s] %s\n' "$expect" "$decision" "$cmd"
  fi
}

runwrapped() { # runwrapped <command>
  local w
  while IFS= read -r w; do run deny "$w"; done < <(wrap_shapes "$1")
}

echo "=== the two founding incidents deny, in every shape bash offers ==="
runwrapped 'gh api -X DELETE repos/tatari-tv/valet/branches/main/protection/enforce_admins'
runwrapped 'acli jira workitem delete --key SEC-2997 --yes'

echo "=== method parse: four spellings, last wins, case-insensitive ==="
run deny  'gh api -XDELETE repos/o/r/branches/main/protection'
run deny  'gh api --method=DELETE repos/o/r/rulesets/5'
run deny  'gh api -X delete repos/o/r/rulesets'
run deny  'gh api repos/o/r -X GET -X DELETE'
run deny  'gh api -X=DELETE repos/o/r'
run allow 'gh api --method GET repos/o/r -f x=1'
run deny  'gh api --field description=x repos/o/r'
run deny  'gh api /repos/o/r -X PATCH'
run deny  'gh api repos/{owner}/{repo} -X PATCH'

echo "=== round 4's two live bypasses, executed against the endpoint ==="
# gh api -XDELETE -p -XGET /rate_limit --verbose sent DELETE while a parse over
# round 3's hand-listed skip set resolved GET. Same for --header, the long alias
# of the -H that round 3 had just fixed in its short form only.
run deny 'gh api -XDELETE -p -XGET repos/o/r'
run deny 'gh api -XDELETE --preview -XGET repos/o/r'
run deny 'gh api -XDELETE --header -XGET repos/o/r'

echo "=== one operand-skip fixture per value-taking flag ==="
# Each: an explicit DELETE, then a flag whose OPERAND is shaped like a method
# flag. The operand must be consumed, so DELETE stands and the call denies. A
# flag missing from VALUE_FLAGS fails here instead of shipping as a bypass.
for f in --cache -F --field -H --header --hostname --input -q --jq -p --preview -f --raw-field -t --template; do
  run deny "gh api -XDELETE $f -XGET repos/o/r"
done

echo "=== guarded paths, and the ones that are not ==="
run deny  'gh api orgs/tatari-tv/rulesets -X POST'
run deny  'gh api repos/o/r -X PATCH'
run allow 'gh api repos/o/r/pulls/1 -X PATCH -f body=x'
run allow 'gh api repos/tatari-tv/philo/pulls/1 -X PATCH -f body=x'
run allow 'gh api repos/o/r'
run allow 'gh api /rate_limit'
run allow 'gh api -XDELETE -p -XGET /rate_limit'
run allow 'gh api repos/o/r/branches/main/protection'

echo "=== gh repo edit is the same settings surface through another door ==="
run deny  'gh repo edit tatari-tv/mcp-io-rs --visibility public'
run allow 'gh pr create --title x --head flat-slug'
run allow 'gh repo view tatari-tv/philo'

echo "=== DELETE-OUT, and the --help carve-out ==="
run deny  'acli confluence page delete --id 12345'
run allow 'acli jira workitem delete --help'
run allow 'acli jira workitem view --key SEC-2997'
# The permissions.deny entries this phase adds carry no --help carve-out and are
# evaluated independently of what a hook returns, so the COMBINED behaviour of
# `acli jira workitem delete --help` is whatever the permission layer decides.
# This asserts the hook's half only; the combined result is recorded in the
# design doc as a fixture rather than an assumption.

echo "=== the false-positive class lib.sh exists to kill ==="
# Observed live 2026-09-15T19:41: a naive acli.*delete pattern matched the
# regex TEXT inside a quoted heredoc in scan5.py.
run allow 'echo "gh api -XDELETE repos/o/r"'
run allow "$(printf "cat <<'EOF'\nacli jira workitem delete --key X\nEOF")"
run allow '# gh api -X DELETE repos/o/r/rulesets'

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
