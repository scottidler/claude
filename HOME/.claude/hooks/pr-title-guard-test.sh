#!/bin/bash
# pr-title-guard-test.sh: fixture matrix for pr-title-guard.sh.
#
# Deny: every `type:` / `type(scope):` shape, including the ticket-key-as-scope
# variant, on `gh pr create`, `gh pr edit` and the MCP vector. Every deny case
# asserts on its reason text, not just the decision.
# Allow: plain sentence-case titles, `KEY: Summary` titles, and anything the
# hook cannot read (no title, a substituted title, a gh call that is not a
# command).
set -u
export LC_ALL=C

HOOK="$(cd "$(dirname "$0")" && pwd)/pr-title-guard.sh"
pass=0
fail=0

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

run() { # run <expect> <command> [<want>]
  local expect="$1" cmd="$2" want="${3-}" out
  out=$(jq -n --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c},cwd:"/tmp"}' | bash "$HOOK")
  assert "$expect" "$cmd" "$out" "$want"
}

runmcp() { # runmcp <expect> <title> [<want>]
  local expect="$1" title="$2" want="${3-}" out
  out=$(jq -n --arg t "$title" \
    '{tool_name:"mcp__multi-account-github__create_pr",tool_input:{title:$t,head:"x"}}' | bash "$HOOK")
  assert "$expect" "MCP title=$title" "$out" "$want"
}

SQ=\'
WHY="type(scope):"

echo "=== type(scope): titles deny, ticket or no ticket ==="
run deny "gh pr create --title ${SQ}feat(cli): add okta cli${SQ}" "$WHY"
run deny "gh pr create --title ${SQ}fix(db): stop dead job sessions from holding row locks${SQ}" "$WHY"
run deny "gh pr create --title ${SQ}chore(marketplace): pin squad to v0.1.2${SQ}" "$WHY"
run deny "gh pr create --title ${SQ}feat(SRE-3658): remove adtechtax CloudFront${SQ}" "$WHY"
run deny "gh pr create --title ${SQ}feat(warm-pull-through): add action${SQ}" "$WHY"
run deny "gh pr create --title ${SQ}feat(bayesian_amazon_lift): inject DAG${SQ}" "$WHY"
run deny "gh pr create --title ${SQ}feat(ui)!: drop the old flag${SQ}" "$WHY"
run deny "gh pr create --title ${SQ}chore: add viewport support${SQ}" "$WHY"
run deny "gh pr create --title ${SQ}docs: fix the readme${SQ}" "$WHY"
run deny 'gh pr create -t "test(python): warm pull through"' "$WHY"
run deny 'gh pr create --title="fix(x): a b"' "$WHY"
run deny "gh pr create --body-file b.md --title ${SQ}refactor(core): split client${SQ} --base main" "$WHY"
run deny "cd /tmp && gh pr create --title ${SQ}feat(x): y${SQ}" "$WHY"
run deny "bash -c ${SQ}gh pr create --title \"feat(ui): other thing\"${SQ}" "$WHY"
run deny "GH_PERSONA=work gh pr create --title ${SQ}feat(x): y${SQ}" "$WHY"

echo "=== gh pr edit carries the same rule ==="
run deny "gh pr edit 1 --title ${SQ}feat(cli): add okta cli${SQ}" "$WHY"
run deny "gh pr edit https://github.com/o/r/pull/1 -t ${SQ}fix: thing${SQ}" "$WHY"
run allow "gh pr edit 1 --title ${SQ}SRE-4401: Add an Okta admin CLI${SQ}"
run allow 'gh pr edit 1 --add-label bug'

echo "=== the deny text names both acceptable shapes ==="
run deny "gh pr create --title ${SQ}feat(x): y${SQ}" "KEY: Summary"
run deny "gh pr create --title ${SQ}feat(x): y${SQ}" "ticket or no ticket"

echo "=== plain and ticket-keyed titles allow ==="
run allow "gh pr create --title ${SQ}SRE-4401: Add an Okta admin CLI and MCP server${SQ}"
run allow "gh pr create --title ${SQ}Add an Okta admin CLI and MCP server${SQ}"
run allow "gh pr create --title ${SQ}BAOP-1475: Fix price rounding${SQ}"
run allow "gh pr create --title ${SQ}Stop dead job sessions from holding row locks${SQ}"
run allow "gh pr create --title ${SQ}Note: this one starts with a capital word${SQ}"
run allow "gh pr create --title ${SQ}https://example.com is down${SQ}"
run allow "gh pr create --title ${SQ}Bump rmcp to 3.6 (fix: tools/list)${SQ}"

echo "=== missing or unknowable titles pass through ==="
run allow 'gh pr create --head add-viewport-support'
run allow 'gh pr create --title "$(gen-title)"'
run allow 'gh pr create --title "$TITLE"'
run allow 'gh pr create --title `gen-title`'
run allow 'gh pr create --fill'
run allow 'gh pr list'
run allow 'gh pr view 1 --json title'

echo "=== the cmdword anchor: a gh pr create that is not a command ==="
run allow 'echo "gh pr create --title feat(x): y"'
run allow "grep -n ${SQ}gh pr create --title feat(x): y${SQ} notes.md"
run allow 'git commit -m "gh pr create --title feat(x): y"'
run allow "$(printf 'cat > notes.md <<EOF\ngh pr create --title "feat(x): y"\nEOF\ngit status')"
run allow 'gh-pr-helper create --title "feat(x): y"'

echo "=== the MCP vector ==="
runmcp deny 'feat(ui): add viewport support' "$WHY"
runmcp deny 'fix: markdown dark mode' "$WHY"
runmcp allow 'SRE-4401: Add an Okta admin CLI'
runmcp allow 'Add viewport support'
runmcp allow ''

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
