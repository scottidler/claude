#!/bin/bash
# panel-round-guard-test.sh: fixture matrix for panel-round-guard.sh.
#
# Each case feeds the hook an `Agent` PreToolUse payload on stdin and asserts on
# the decision. An ALLOW must also produce EMPTY stdout, which AC1 and AC2 both
# assert and which is the one place this guard's contract differs from its Bash
# siblings' `{}`.
#
# The matrix is stateful on purpose: the thing under test is a counter, so the
# cases run in ORDER inside each group and a group opens with a fresh, isolated
# counter directory. PANEL_ROUND_CACHE_DIR points every run at a mktemp dir
# under $ROOT, so nothing here can touch the user's real
# ~/.cache/review-panel/rounds/.
#
# No `shapes.sh` sweep, deliberately. Its 16 templates wrap a COMMAND WORD in
# shell (eval, bash -c, timeout, process substitution). This hook consumes
# tool_input.prompt: there is no command word and no shell, so all 16 shapes
# could pass while proving nothing about prompt parsing, marker placement or
# path extraction. The six mutations at the bottom are the prompt-appropriate
# replacement the design doc names.
set -u
export LC_ALL=C

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
HOOK="$HOOKS/panel-round-guard.sh"
pass=0
fail=0

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/panel-round-test.XXXXXX")
trap 'chmod -R u+w "$ROOT" 2>/dev/null' EXIT

# A fixture worktree that looks like a repo with design docs in it, so the
# relative-versus-absolute cases have something real to resolve against.
REPO="$ROOT/repo"
mkdir -p "$REPO/docs/design" "$REPO/notes"
printf '# Alpha\n\n**Status:** In Review\n' > "$REPO/docs/design/alpha.md"
printf '# Beta\n\n**Status:** In Review\n' > "$REPO/docs/design/beta.md"
printf '# Gamma\n\n**Status:** In Review\n' > "$REPO/docs/design/gamma.md"
printf '# Alpha review log\n\nRound 1 minutes.\n' > "$REPO/docs/design/alpha-review-log.md"
printf '# Alpha notes\n\nPhase 0.\n' > "$REPO/docs/design/alpha-implementation-notes.md"
printf '# Scratch\n\nNot a design doc.\n' > "$REPO/notes/scratch.md"

ALPHA="$REPO/docs/design/alpha.md"
BETA="$REPO/docs/design/beta.md"
GAMMA="$REPO/docs/design/gamma.md"

SUB="review-panel"

fresh_cache() { # fresh_cache
  CACHE=$(mktemp -d "$ROOT/cache.XXXXXX")
  export PANEL_ROUND_CACHE_DIR="$CACHE"
}

run() { # run <expect deny|allow> <label> <prompt> [<want substring in the reason>]
  local expect="$1" label="$2" prompt="$3" want="${4-}" out decision reason
  out=$(jq -n --arg s "$SUB" --arg p "$prompt" --arg d "$REPO" \
    '{tool_name:"Agent",tool_input:{subagent_type:$s,prompt:$p},cwd:$d}' \
    | bash "$HOOK" 2>/dev/null)
  if [ -z "$out" ]; then
    decision="allow"
    reason=""
  else
    decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "malformed"')
    reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  fi
  if [ "$decision" != "$expect" ]; then
    fail=$((fail + 1))
    printf 'FAIL  [want %s got %s] %s\n' "$expect" "$decision" "$label"
    return
  fi
  if [ -n "$want" ] && ! printf '%s' "$reason" | grep -qF -- "$want"; then
    fail=$((fail + 1))
    printf 'FAIL  [reason missing %s] %s\n' "$want" "$label"
    return
  fi
  pass=$((pass + 1))
  printf 'PASS  [%s] %s\n' "$expect" "$label"
}

check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
    printf 'PASS  [%s] %s\n' "$2" "$1"
  else
    fail=$((fail + 1))
    printf 'FAIL  [want %s got %s] %s\n' "$2" "$3" "$1"
  fi
}

echo "=== the cap holds: rounds 1-3 allow, round 4 denies (AC1) ==="
fresh_cache
run allow 'alpha round 1' "Design Review of $ALPHA"
run allow 'alpha round 2' "Design Review of $ALPHA, round 2"
run allow 'alpha round 3' "Design Review of $ALPHA, round 3"
run deny  'alpha round 4' "Design Review of $ALPHA, round 4" 'this is round 4'
run deny  'alpha round 4 names the cap' "Design Review of $ALPHA" 'the cap is 3'
run deny  'alpha round 4 names the remedy' "Design Review of $ALPHA" 'PANEL_ROUNDS_ORDERED_BY_SCOTT=<n>'
run deny  'alpha round 4 names the counter' "Design Review of $ALPHA" '(3 rounds recorded)'
run deny  'alpha round 4 names the doc' "Design Review of $ALPHA" "$ALPHA"

echo "=== a denied round does not increment: the deny is stable (AC1) ==="
run deny 'alpha stays at round 4' "Design Review of $ALPHA" 'this is round 4'

echo "=== the counter entry is three lines of plain text (Data Model) ==="
entry=$(ls "$CACHE" | head -1)
check 'one entry for one (doc, mode)' 1 "$(ls "$CACHE" | wc -l)"
check 'entry name is a sha256' 64 "${#entry}"
check 'entry carries path=' "path=$ALPHA" "$(sed -n '1p' "$CACHE/$entry")"
check 'entry carries mode=' 'mode=1' "$(sed -n '2p' "$CACHE/$entry")"
check 'entry carries rounds=' 'rounds=3' "$(sed -n '3p' "$CACHE/$entry")"

echo "=== two docs are counted independently (AC6) ==="
run allow 'beta round 1 while alpha is capped' "Design Review of $BETA"
run allow 'beta round 2' "Design Review of $BETA"
run allow 'beta round 3' "Design Review of $BETA"
run deny  'beta round 4' "Design Review of $BETA" 'this is round 4'
run deny  'alpha is still capped' "Design Review of $ALPHA" 'this is round 4'

echo "=== a different subagent_type is never touched (AC2) ==="
# Same prompt that denies above, five times, on a subagent this guard has no
# opinion about.
for other in Explore general-purpose phase-implementer architect ""; do
  SUB="$other"
  run allow "subagent_type='$other' allows" "Design Review of $ALPHA"
done
SUB="review-panel"

echo "=== an unparseable prompt allows and warns (fail open) ==="
fresh_cache
run allow 'no path: implementation audit' 'Run an **Implementation Audit** (post-implementation mode) cross-model review'
run allow 'no path: PR review' 'Review a code change (not a design doc) on the `tatari-tv/clyde` repo: PR #54'
run allow 'no path, repeated 5 times (1)' 'Run the panel IN PARALLEL as an IMPLEMENTATION REVIEW'
run allow 'no path, repeated 5 times (2)' 'Run the panel IN PARALLEL as an IMPLEMENTATION REVIEW'
run allow 'no path, repeated 5 times (3)' 'Run the panel IN PARALLEL as an IMPLEMENTATION REVIEW'
run allow 'empty prompt' ''
check 'no counter written for a docless dispatch' 0 "$(ls "$CACHE" | wc -l)"

stderr_of() { # stderr_of <prompt>
  jq -n --arg s "$SUB" --arg p "$1" --arg d "$REPO" \
    '{tool_name:"Agent",tool_input:{subagent_type:$s,prompt:$p},cwd:$d}' \
    | bash "$HOOK" 2>&1 1>/dev/null
}
warned=no
stderr_of 'Review a code change (not a design doc): PR #54' | grep -q 'no .md path found' && warned=yes
check 'the unparseable case says so on stderr' yes "$warned"

echo "=== a missing lib.sh passes the dispatch through (fail open) ==="
# The library is sourced with `|| exit 0` for one reason: a hook that denied
# every dispatch because its library moved would take the panel out on every
# machine at once. Run the guard from a directory with no lib.sh beside it.
NOLIB="$ROOT/nolib"
mkdir -p "$NOLIB"
cp "$HOOK" "$NOLIB/panel-round-guard.sh"
nolib_out=$(jq -n --arg d "$REPO" \
  '{tool_name:"Agent",tool_input:{subagent_type:"review-panel",prompt:"Design Review of docs/design/alpha.md"},cwd:$d}' \
  | bash "$NOLIB/panel-round-guard.sh" 2>/dev/null)
nolib_decision=allow
[ -n "$nolib_out" ] && nolib_decision=deny
check 'no lib.sh beside the hook still allows' allow "$nolib_decision"

echo "=== the door is a ceiling: =5 allows 4 and 5, denies 6 (AC3) ==="
fresh_cache
DOOR5=$'Design Review of '"$ALPHA"$', round 4\nPANEL_ROUNDS_ORDERED_BY_SCOTT=5'
DOOR5_6=$'Design Review of '"$ALPHA"$', round 6\nPANEL_ROUNDS_ORDERED_BY_SCOTT=5'
run allow 'door: round 1 plain' "Design Review of $ALPHA"
run allow 'door: round 2 plain' "Design Review of $ALPHA"
run allow 'door: round 3 plain' "Design Review of $ALPHA"
run deny  'door: round 4 plain denies' "Design Review of $ALPHA" 'the cap is 3'
run allow 'door: round 4 with the marker' "$DOOR5"
run allow 'door: round 5 with the marker' "$DOOR5"
run deny  'door: round 6 with the marker' "$DOOR5_6" 'this is round 6'
run deny  'door: the deny names the raised cap' "$DOOR5_6" 'the cap is 5'
run deny  'door: closing it again denies at 5 recorded' "Design Review of $ALPHA" 'the cap is 3'

echo "=== relative and absolute resolve to one counter (AC6) ==="
fresh_cache
run allow 'relative round 1' 'Design Review of docs/design/alpha.md'
run allow 'absolute round 2' "Design Review of $ALPHA"
run allow 'dot-relative round 3' 'Design Review of ./docs/design/alpha.md'
run deny  'dot-dot-relative round 4' 'Design Review of docs/../docs/design/alpha.md' 'this is round 4'
check 'all four spellings share one entry' 1 "$(ls "$CACHE" | wc -l)"

echo "=== flipping the doc to Status: Implemented starts a fresh count (AC6) ==="
fresh_cache
run allow 'gamma mode 1 round 1' "Design Review of $GAMMA"
run allow 'gamma mode 1 round 2' "Design Review of $GAMMA"
run allow 'gamma mode 1 round 3' "Design Review of $GAMMA"
run deny  'gamma mode 1 round 4' "Design Review of $GAMMA" 'this is round 4'
printf '# Gamma\n\n**Status:** Implemented\n' > "$GAMMA"
run allow 'gamma mode 2 round 1' "Implementation Audit of $GAMMA"
run allow 'gamma mode 2 round 2' "Implementation Audit of $GAMMA"
run allow 'gamma mode 2 round 3' "Implementation Audit of $GAMMA"
run deny  'gamma mode 2 round 4' "Implementation Audit of $GAMMA" 'this is round 4'
check 'the flip made a second entry, not one' 2 "$(ls "$CACHE" | wc -l)"
printf '# Gamma\n\n**Status:** In Review\n' > "$GAMMA"
run deny 'flipping back finds the mode 1 counter still at 3' "Design Review of $GAMMA" 'this is round 4'

echo "=== a Status line in PROSE is not the doc's status (mode is line-anchored) ==="
printf '# Delta\n\n**Status:** In Review\n\nThe test Step 1.2 uses is `Status: Implemented` in the doc.\n' \
  > "$REPO/docs/design/delta.md"
fresh_cache
run allow 'delta round 1' 'Design Review of docs/design/delta.md'
run allow 'delta round 2' 'Design Review of docs/design/delta.md'
run allow 'delta round 3' 'Design Review of docs/design/delta.md'
run deny  'delta round 4: prose did not mint a second mode' 'Design Review of docs/design/delta.md' 'this is round 4'
check 'delta has exactly one counter' 1 "$(ls "$CACHE" | wc -l)"

echo "=== mutation: the door marker indented is not a control line ==="
fresh_cache
INDENTED=$'Design Review of '"$ALPHA"$', round 4\n  PANEL_ROUNDS_ORDERED_BY_SCOTT=5'
run allow 'indented: round 1' "Design Review of $ALPHA"
run allow 'indented: round 2' "Design Review of $ALPHA"
run allow 'indented: round 3' "Design Review of $ALPHA"
run deny  'indented marker does NOT open the door' "$INDENTED" 'the cap is 3'

echo "=== mutation: the door marker quoted in prose is not a control line ==="
# This is the exact self-trigger the design doc warns about: the doc being
# reviewed carries the literal marker four times in its own text.
QUOTED="Design Review of $ALPHA, round 4. The doc says the door is \`PANEL_ROUNDS_ORDERED_BY_SCOTT=5\` and that quoting it must not open it."
run deny 'quoted marker does NOT open the door' "$QUOTED" 'the cap is 3'
INLINE="Design Review of $ALPHA round 4 PANEL_ROUNDS_ORDERED_BY_SCOTT=9 mid-sentence"
run deny 'a mid-sentence marker does NOT open the door' "$INLINE" 'the cap is 3'
TRAILING=$'Design Review of '"$ALPHA"$'\nPANEL_ROUNDS_ORDERED_BY_SCOTT=5 please'
run deny 'a marker with trailing text does NOT open the door' "$TRAILING" 'the cap is 3'
BADVAL=$'Design Review of '"$ALPHA"$'\nPANEL_ROUNDS_ORDERED_BY_SCOTT=<n>'
run deny 'the deny text pasted back does NOT open the door' "$BADVAL" 'the cap is 3'

echo "=== mutation: the door marker as its own control line DOES open it ==="
OWNLINE=$'Design Review of '"$ALPHA"$', round 4\nPANEL_ROUNDS_ORDERED_BY_SCOTT=5\nScott ordered two more.'
run allow 'own-line marker opens the door' "$OWNLINE"
CRLF=$'Design Review of '"$ALPHA"$', round 5\r\nPANEL_ROUNDS_ORDERED_BY_SCOTT=5\r\nScott ordered two more.'
run allow 'a CRLF prompt still opens the door' "$CRLF"
run deny 'and the raised ceiling still holds at 6' "$OWNLINE" 'the cap is 5'

echo "=== regression: a FENCED marker at column 1 does NOT open the door ==="
# Audit round 1, 2026-09-14. The group above only ever quoted the marker with
# inline backticks or indentation, both of which the ^ anchor already rejected,
# so CI could not see the one form that mattered: column 1 INSIDE a fenced code
# block. The design doc this guard enforces carries exactly that at :165, so a
# round-4 prompt quoting the doc's own door section raised the cap from 3 to 5.
# The document was opening its own door. These cases are the reason the hook
# masks fences before matching; break the awk mask and they fail.
fresh_cache
FENCED=$'Design Review of '"$ALPHA"$', round 4. Prior findings referenced the door section:\n\n```\nreview-panel this doc, round 4\nPANEL_ROUNDS_ORDERED_BY_SCOTT=5\n```\n'
run allow 'fenced: round 1' "Design Review of $ALPHA"
run allow 'fenced: round 2' "Design Review of $ALPHA"
run allow 'fenced: round 3' "Design Review of $ALPHA"
run deny  'a FENCED marker does NOT open the door' "$FENCED" 'the cap is 3'
TILDE=$'Design Review of '"$ALPHA"$'\n~~~\nPANEL_ROUNDS_ORDERED_BY_SCOTT=9\n~~~\n'
run deny  'a tilde-fenced marker does NOT open the door' "$TILDE" 'the cap is 3'
INDENTED_FENCE=$'Design Review of '"$ALPHA"$'\n  ```\nPANEL_ROUNDS_ORDERED_BY_SCOTT=9\n  ```\n'
run deny  'an indented fence still masks its marker' "$INDENTED_FENCE" 'the cap is 3'
AFTER_FENCE=$'Design Review of '"$ALPHA"$'\n```\nsome quoted block\n```\nPANEL_ROUNDS_ORDERED_BY_SCOTT=5\n'
run allow 'a real control line AFTER a closed fence still opens the door' "$AFTER_FENCE"

echo "=== regression: mode is read from the METADATA BLOCK, not the whole file ==="
# Same audit finding. The prose case above put `Status: Implemented` inside
# backticks; a FENCED one at column 1 slipped through the whole-file grep and
# keyed an In Review doc as Mode 2. The real damage is the inverse: the key then
# does not change when the status genuinely flips, so the first implementation
# audit inherits the exhausted design counter and is denied at dispatch.
printf '# Epsilon\n\n**Status:** In Review\n\n## Body\n\n```\nStatus: Implemented\n```\n' \
  > "$REPO/docs/design/epsilon.md"
fresh_cache
run allow 'epsilon round 1' "Design Review of $REPO/docs/design/epsilon.md"
check 'a fenced Status below the metadata block stays mode 1' 'mode=1' \
  "$(sed -n '2p' "$CACHE/$(ls "$CACHE" | head -1)")"
# And the genuine flip still reads as mode 2, including the follow-up-owed form
# that must NOT be broken by anchoring the match at end of line.
printf '# Zeta\n\n**Status:** Implemented\n\n## Body\n' > "$REPO/docs/design/zeta.md"
fresh_cache
run allow 'zeta round 1' "Design Review of $REPO/docs/design/zeta.md"
check 'a genuine Implemented status reads mode 2' 'mode=2' \
  "$(sed -n '2p' "$CACHE/$(ls "$CACHE" | head -1)")"
printf '# Eta\n\n**Status:** Implemented with a follow-up owed\n\n## Body\n' > "$REPO/docs/design/eta.md"
fresh_cache
run allow 'eta round 1' "Design Review of $REPO/docs/design/eta.md"
check 'Implemented-with-follow-up still reads mode 2' 'mode=2' \
  "$(sed -n '2p' "$CACHE/$(ls "$CACHE" | head -1)")"

echo "=== regression: a RELATIVE cache override never writes into the cwd ==="
# The round-1 audit's probing ran with PANEL_ROUND_CACHE_DIR set to a relative
# path, which resolved against its cwd and left a bare `bin/<sha256>` counter
# file in this repo's tracked bin/ directory (found 2026-09-15). A guard that
# scatters state into whatever repo is under review is the bug; a relative
# override is refused and falls back to the default.
REL_WORK="$ROOT/relwork"
mkdir -p "$REL_WORK"
rel_payload=$(jq -n --arg s "$SUB" --arg p "Design Review of $ALPHA" --arg d "$REL_WORK" \
  '{tool_name:"Agent",tool_input:{subagent_type:$s,prompt:$p},cwd:$d}')
# HOME is redirected into $ROOT for this one case: the refusal falls back to
# $HOME/.cache/review-panel/rounds by design, and a test must never write to the
# user's real counter. Caught while adding this case, which did exactly that.
REL_HOME="$ROOT/relhome"
mkdir -p "$REL_HOME"
rel_out=$( cd "$REL_WORK" \
  && printf '%s' "$rel_payload" \
  | HOME="$REL_HOME" PANEL_ROUND_CACHE_DIR=relbin bash "$HOOK" 2>&1 >/dev/null )
check 'the refusal fell back under the redirected HOME' 1 \
  "$(find "$REL_HOME" -type f | wc -l)"
case "$rel_out" in
  *"must be an absolute path"*) pass=$((pass + 1)); echo "PASS  [warn] relative cache override is refused" ;;
  *) fail=$((fail + 1)); echo "FAIL  [warn] relative cache override was not refused: $rel_out" ;;
esac
check 'a relative override wrote nothing under the cwd' 0 "$(find "$REL_WORK" -type f | wc -l)"

echo "=== mutation: two .md paths in one prompt key on the design doc ==="
fresh_cache
run allow 'two paths, round 1' "Design Review of $ALPHA. Cross-check against $BETA."
run allow 'alpha round 2 proves the first path won' "Design Review of $ALPHA"
run allow 'alpha round 3' "Design Review of $ALPHA"
run deny  'alpha round 4' "Design Review of $ALPHA" 'this is round 4'
run allow 'beta is untouched at round 1' "Design Review of $BETA"

echo "=== mutation: a design/ path beats a non-design one wherever it sits ==="
fresh_cache
run allow 'scratch first, beta second' "Read notes/scratch.md then review docs/design/beta.md"
run allow 'beta round 2 proves design/ won' "Design Review of $BETA"
run allow 'beta round 3' "Design Review of $BETA"
run deny  'beta round 4' "Design Review of $BETA" 'this is round 4'

echo "=== mutation: an .md that is not the doc under review is dropped ==="
fresh_cache
COMPANIONS="Round 2 of the panel on $ALPHA. Prior minutes: $REPO/docs/design/alpha-review-log.md and $REPO/docs/design/alpha-implementation-notes.md."
run allow 'companions named alongside the doc, round 1' "$COMPANIONS"
run allow 'alpha round 2 proves the companions were dropped' "Design Review of $ALPHA"
run allow 'alpha round 3' "Design Review of $ALPHA"
run deny  'alpha round 4' "Design Review of $ALPHA" 'this is round 4'
check 'one entry, not three' 1 "$(ls "$CACHE" | wc -l)"

echo "=== mutation: a companion alone is the only candidate, so it is the key ==="
fresh_cache
run allow 'review log alone, round 1' "Review $REPO/docs/design/alpha-review-log.md"
check 'the lone companion did get a counter' 1 "$(ls "$CACHE" | wc -l)"
run allow 'alpha itself is still at round 1' "Design Review of $ALPHA"
check 'and it keyed separately' 2 "$(ls "$CACHE" | wc -l)"

echo "=== a path with a line suffix still resolves (foo.md:281-288) ==="
fresh_cache
run allow 'line-suffixed path, round 1' "Design Review of $ALPHA:281-288"
run allow 'alpha round 2 proves the suffix was stripped' "Design Review of $ALPHA"
run allow 'alpha round 3' "Design Review of $ALPHA"
run deny  'alpha round 4' "Design Review of $ALPHA" 'this is round 4'

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
