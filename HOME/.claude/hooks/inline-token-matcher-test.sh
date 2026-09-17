#!/bin/bash
# inline-token-matcher-test.sh: regression matrix for inline/matcher.py.
#
# Runs the unittest suite in inline/tests.py, which scores the pinned
# docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/inline-token/
# fixtures.json (2,004 records) at each record's own occurrence, and asserts
# the three Phase 5 success criteria: zero of the 1,421 known false
# positives match, at least 95% of the 583 survivors match, and the two
# named adversarial phrases produce zero matches. Also covers the inversion
# itself (`dSt`'s leading-neighbor rule, inverted) and the round-2
# boundary-before-slash finding directly.
#
# Hooked into `otto ci` by NAME alone: the `test` task in .otto.yml already
# globs `HOME/.claude/hooks/*-test.sh`, so this file needs no otto edit to
# run. `inline/tests.py` uses stdlib `unittest`, not pytest: this directory
# ships no pyproject.toml, matching the one prior Python hook's (
# rewrite-cd-read.py) dependency-free precedent. `uv run pytest` on the same
# file passes too, checked manually, but is not what CI invokes.
set -u

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

pass=0
fail=0

out="$(cd "$HOOKS" && python3 inline/tests.py -v 2>&1)"
rc=$?
echo "$out"

if [ "$rc" -eq 0 ]; then
  pass=$((pass + 1))
  printf 'PASS  inline/tests.py exits 0\n'
else
  fail=$((fail + 1))
  printf 'FAIL  inline/tests.py exited %s\n' "$rc"
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
