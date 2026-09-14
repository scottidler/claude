#!/bin/bash
# manifest-scope-guard-test.sh: fixture matrix for manifest-scope-guard.sh.
#
# Each case feeds the hook a PreToolUse payload on stdin and asserts on whether
# a permissionDecision came back. The allow cases are the false-positive classes
# the 2026-09-12 audit measured; the deny cases are the unscoped applies the
# guard exists to stop.
set -u
export LC_ALL=C

HOOK="$(cd "$(dirname "$0")" && pwd)/manifest-scope-guard.sh"
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

echo "=== unscoped applies deny ==="
run deny 'manifest'
run deny 'manifest .'
run deny 'cd /home/saidler/repos/scottidler/dotfiles && manifest'
run deny 'bash -c "manifest apply"'
run deny "bash -c 'manifest apply'"
run deny 'sudo manifest'

echo "=== scoped and exempt invocations allow ==="
run allow 'manifest -l x'
run allow 'manifest --link HOME/.claude/hooks/lib.sh'
run allow 'manifest -l HOME/.claude/hooks/* | bash'
run allow 'manifest age decrypt /home/saidler/repos/scottidler/keep/.secrets/x.age'
run allow 'manifest --help'
run allow 'manifest -V'

echo "=== audit false positives: the word is not a command word ==="
# Bit live twice in the design session: a bare word inside a double-quoted
# string is an argument to echo, not a command.
run allow 'echo "=== manifest entry ==="'
run allow "echo '=== manifest entry ==='"
run allow 'rg -n "tasks" /home/saidler/repos/scottidler/dotfiles/manifest.yml'
run allow "rg -n 'tasks' /home/saidler/repos/scottidler/dotfiles/manifest.yml"
run allow 'manifest-scope-guard.sh --help'
run allow 'git commit -m "run manifest for the new entry"'
run allow '# manifest'
run allow "$(printf 'cat > notes.md <<%sEOF%s\nrun manifest to apply\nmanifest\nEOF\n' "'" "'")"
run allow "$(printf 'cat > notes.md <<EOF\nrun manifest to apply\nEOF\nrg -n x notes.md')"

echo "=== a nested statement is still a command word ==="
run deny "$(printf 'cat > notes.md <<EOF\nprose\nEOF\nmanifest')"
run allow "$(printf 'cat > notes.md <<EOF\nprose\nEOF\nmanifest -l x')"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
