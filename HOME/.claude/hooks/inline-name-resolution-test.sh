#!/bin/bash
# inline-name-resolution-test.sh: regression matrix for inline/resolve.py.
#
# Runs the unittest suite in inline/resolve_tests.py, which covers the four
# Phase 6 rules (enumerate live skills, drop `skillOverrides: "off"`, drop
# bare aliases for plugin skills, enforce the generic-word deny list)
# against both injected fixtures and the real live `settings.json` and
# skills tree (read-only; nothing here writes to either).
#
# Hooked into `otto ci` by NAME alone, same as inline-token-matcher-test.sh:
# the `test` task already globs `HOME/.claude/hooks/*-test.sh`, so this file
# needs no otto edit to run.
set -u

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

pass=0
fail=0

out="$(cd "$HOOKS" && python3 inline/resolve_tests.py -v 2>&1)"
rc=$?
echo "$out"

if [ "$rc" -eq 0 ]; then
  pass=$((pass + 1))
  printf 'PASS  inline/resolve_tests.py exits 0\n'
else
  fail=$((fail + 1))
  printf 'FAIL  inline/resolve_tests.py exited %s\n' "$rc"
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
