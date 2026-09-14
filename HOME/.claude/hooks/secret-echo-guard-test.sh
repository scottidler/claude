#!/bin/bash
# secret-echo-guard-test.sh: fixture matrix for secret-echo-guard.sh.
#
# Each case feeds the hook a PreToolUse payload on stdin and asserts on whether
# a permissionDecision came back. Every fixture is inert text in THIS shell (the
# secret-shaped names are single-quoted or backslash-escaped), so running the
# matrix never expands anything.
#
# The deny cases are the leak vectors; the allow cases are the false positives
# the 2026-09-12 audit and staff review measured live, all three of which are
# forms the shell does not expand.
set -u
export LC_ALL=C

HOOK="$(cd "$(dirname "$0")" && pwd)/secret-echo-guard.sh"
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

echo "=== the leak vectors deny ==="
run deny 'echo "$ANTHROPIC_API_KEY"'
run deny 'echo $OPENAI_API_KEY'
run deny 'echo ${GH_TOKEN:-x}'
run deny 'echo ${GH_TOKEN:?unset}'
run deny 'printf "%s\n" "$SLACK_BOT_TOKEN"'
run deny 'printenv AWS_SECRET_ACCESS_KEY'

echo "=== nested statements deny: the -c argument is a statement, not data ==="
run deny "bash -c 'echo \$SOME_TOKEN'"
run deny "sh -c 'echo \"\$GITHUB_PAT\"'"
run deny "zsh -c 'printenv GH_TOKEN'"
run deny 'echo "$(printenv GH_TOKEN)"'

echo "=== unexpanded forms allow: the shell leaks nothing here ==="
run allow "echo '\$SOME_TOKEN'"
run allow "printf '%s\n' '\\\$SOME_TOKEN'"
run allow "echo \\\$SOME_TOKEN"

echo "=== safe presence checks allow ==="
run allow 'echo "${GH_TOKEN:+present}"'
run allow 'echo "${GH_TOKEN+present}"'
run allow 'echo "${#GH_TOKEN}"'
run allow '[ -n "$GH_TOKEN" ] && echo present'
run allow '[ -z "$GH_TOKEN" ] && echo missing'
run allow 'if [ -n "$GH_TOKEN" ]; then echo present; fi'
run allow '[[ -n "$GH_TOKEN" ]] && echo present'

echo "=== the bracket test is only safe in command position ==="
run deny 'echo [ -n "$GH_TOKEN" ]'

echo "=== the _PAT anchor: five names ==="
run allow 'echo "$RIPGREP_CONFIG_PATH"'
run allow 'echo "$MY_PATTERN"'
run allow 'echo "$SOME_PATH"'
run deny 'echo "$GITHUB_PAT"'
run deny 'echo "$GITHUB_PAT_HOME"'

echo "=== prose that names a var is not an expansion ==="
run allow 'rg -n "GH_TOKEN" notes.md'
run allow 'echo hi # echo "$GH_TOKEN"'
run allow "$(printf "cat > notes.md <<%sEOF%s\nnever echo \"\$GH_TOKEN\" in a session\nEOF\n" "'" "'")"
run allow "$(printf 'cat > notes.md <<EOF\nnever echo it\nEOF\nrg -n never notes.md')"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
