#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# WHY THIS SCRIPT LOOKS THE WAY IT DOES  (liveness + wall-clock hardening, 2026-06-19)
# -----------------------------------------------------------------------------
# This is the codex-backed sibling of /architect. It was hardened in lockstep
# with /architect after a recurring, infuriating failure: when these review
# skills are dispatched via subagents, a backend that grinds with its output
# buffered to the end looks IDENTICAL to a healthy long-running job. The
# orchestrator would keep claiming "still waiting on the staff engineer" while
# the codex process had actually wedged (or died) — and nobody noticed until
# Scott had to ask. Babysitting a dispatched skill means driving it to a real
# terminal state, not narrating optimism. codex at `model_reasoning_effort=high`
# on a large design doc is exactly the kind of long, output-buffered job that
# triggers this, so it gets the same two guarantees as the architect script:
#   1. WALL_CLOCK + `timeout` wrap (see below): codex can NEVER hang forever. On
#      overrun it is killed and the script exits 124 with a clear message — a
#      babysitter always gets a definitive success/failure within bounded time.
#   2. PIDFILE (see below): the script writes its pid so a babysitter can FOLLOW
#      the actual process — `kill -0 $(cat PIDFILE)` to confirm it is truly alive,
#      and treat a vanished pidfile as the "it died" signal. No status claim
#      without evidence behind it.
# (Note: codex already separated final-message from trace and surfaced non-zero
# exits — that part predates this change; the timeout + pidfile are what's new.)
# =============================================================================

DOC_PATH="$1"
PROMPT_ARG="$2"
EXTRA_DIRS="${3:-}"
SCRIPT_DIR="$(dirname "$0")"

# PID handle so a babysitter can follow this review's liveness directly:
#   kill -0 "$(cat "$PIDFILE")"  -> alive ;  pidfile gone / kill fails -> dead.
# We write THIS script's pid ($$); timeout+codex are its children/process group.
# Removed on exit (any path) by the trap below, so its absence == process gone.
# Override the path with STAFF_ENGINEER_PIDFILE when running more than one.
PIDFILE="${STAFF_ENGINEER_PIDFILE:-/tmp/staff-engineer.pid}"

# Hard wall-clock cap on the whole codex call. codex at high reasoning effort can
# grind for a long time with output buffered, presenting to a caller as a dead
# "still running" hang. `timeout` below guarantees a terminal state within
# WALL_CLOCK (exit 124 on overrun).
# 10m is a hard ceiling, not an estimate. Per Scott's rule: anything over 10m
# means the review hung, not that it's slow — so we kill it rather than wait. Held
# identical to the architect cap on purpose; the value is a hang-killer, not a
# per-tool performance budget, so there's no reason for the two to differ.
WALL_CLOCK="${STAFF_ENGINEER_WALL_CLOCK:-10m}"

# Prompt can be (a) a path to a file containing the prompt — preferred for long
# follow-up prompts to avoid shell-quoting issues — or (b) a literal string.
if [ -f "$PROMPT_ARG" ]; then
  PROMPT=$(cat "$PROMPT_ARG")
else
  PROMPT="$PROMPT_ARG"
fi

if [ -z "$PROMPT" ]; then
  echo "error: empty prompt" >&2
  exit 2
fi

# Inject the Staff Engineer persona by prepending it to the prompt. This is the
# reliable, scoped delivery mechanism: it keeps the persona out of any global
# codex config / AGENTS.md, so plain `codex` calls stay neutral.
PERSONA=$(cat "$SCRIPT_DIR/persona.md")

# Codex's read-only sandbox can read anywhere on disk, so there is no cross-repo
# jail to work around. When the caller passes reference dirs, just name them in
# the prompt so the reviewer knows where to look.
REFS=""
if [ -n "$EXTRA_DIRS" ]; then
  REFS="

Relevant reference paths you may read and verify against (read-only):
$(echo "$EXTRA_DIRS" | tr ',' '\n' | sed 's/^/  - /')"
fi

# Inject the owner's judgment standards alongside the persona. Codex CAN read
# the file itself, but embedding guarantees the standards are actually in
# context instead of hoping the reviewer goes and reads them.
TASTE_PATH="$HOME/repos/.claude/rules/taste.md"
TASTE=""
if [ -f "$TASTE_PATH" ]; then
  TASTE="

## Owner's Standards (judge against these, not generic best practice)

$(cat "$TASTE_PATH")"
fi

PROMPT="$PERSONA
$TASTE
$REFS

$PROMPT"

# Capture the clean final synthesis separately from the (verbose) execution
# trace. On success we print only the final message; on failure we surface the
# whole trace for diagnosis.
LAST_MSG=$(mktemp /tmp/staff-engineer-last.XXXXXX)
TRACE=$(mktemp /tmp/staff-engineer-trace.XXXXXX)
trap 'rm -f "$LAST_MSG" "$TRACE" "$PIDFILE"' EXIT

# The design doc is piped on stdin; codex appends it as a <stdin> block that the
# prompt refers to. -s read-only keeps the reviewer strictly non-mutating while
# still allowing rg/git/find/read for empirical verification.
echo "$$" > "$PIDFILE"
echo "staff-engineer: codex review running — pid $$ (follow: kill -0 \$(cat $PIDFILE))" >&2
# stdin redirection (not `cat |`) so `timeout` wraps codex directly and can kill
# it on overrun; codex reads the design doc from stdin exactly as before.
set +e
timeout --kill-after=30s "$WALL_CLOCK" \
  codex exec \
  -m gpt-5.5 \
  -c model_reasoning_effort="high" \
  -s read-only \
  --skip-git-repo-check \
  --color never \
  -o "$LAST_MSG" \
  "$PROMPT" <"$DOC_PATH" >"$TRACE" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -eq 124 ] || [ "$STATUS" -eq 137 ]; then
  echo "error: codex exceeded the ${WALL_CLOCK} wall-clock limit and was killed — no review was produced." >&2
  echo "       Over 10m means it hung, not that it's slow — retry rather than waiting longer." >&2
  echo "--- partial codex trace ---" >&2
  cat "$TRACE" >&2
  exit 124
elif [ "$STATUS" -eq 0 ] && [ -s "$LAST_MSG" ]; then
  cat "$LAST_MSG"
else
  echo "error: codex exec failed (status $STATUS) or produced no final message." >&2
  echo "--- full codex trace ---" >&2
  cat "$TRACE" >&2
  exit 1
fi
