#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# WHY THIS SCRIPT LOOKS THE WAY IT DOES  (liveness + wall-clock hardening, 2026-07-04)
# -----------------------------------------------------------------------------
# This is the gemini-backed sibling of /staff-engineer, brought to parity with
# that script's hardening after a recurring, infuriating failure: dispatched via
# a subagent, gemini in headless mode would grind past the caller's cap and get
# killed, and with `-o text` (which buffers the whole answer and flushes only at
# the end) the killed run produced ZERO bytes — indistinguishable from "still
# working". The panel then silently returned half a review. Two guarantees, held
# identical to the staff-engineer script:
#   1. WALL_CLOCK + `timeout` wrap: gemini can NEVER hang forever. On overrun it
#      is killed and the script exits 124 with a clear message.
#   2. PIDFILE: the script writes its pid so a babysitter can FOLLOW the actual
#      process — `kill -0 $(cat PIDFILE)` to confirm liveness; a vanished pidfile
#      means it died.
# The gemini-specific piece: gemini has no `-o <file>` for the final message (its
# `-o` is a FORMAT: text|json|stream-json). So we run `-o stream-json`, which
# emits newline-delimited events INCREMENTALLY to a trace file — a kill therefore
# leaves a partial trace to diagnose (parity with codex's trace dump), and on
# success the final answer is reassembled from the assistant `content` deltas.
# =============================================================================

DOC_PATH="$1"
PROMPT_ARG="$2"
EXTRA_DIRS="${3:-}"
SCRIPT_DIR="$(dirname "$0")"

# PID handle so a babysitter can follow this review's liveness directly:
#   kill -0 "$(cat "$PIDFILE")"  -> alive ;  pidfile gone / kill fails -> dead.
# We write THIS script's pid ($$); timeout+gemini are its children/process group.
# Removed on exit (any path) by the trap below. Override with ARCHITECT_PIDFILE
# when running more than one.
PIDFILE="${ARCHITECT_PIDFILE:-/tmp/architect.pid}"

# Hard wall-clock cap on the whole gemini call. Held identical to the
# staff-engineer cap on purpose; the value is a hang-killer, not a per-tool
# performance budget. Per Scott's rule: over 10m means it hung, not that it's
# slow — so we kill it rather than wait (exit 124 on overrun).
WALL_CLOCK="${ARCHITECT_WALL_CLOCK:-10m}"

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

# Inject the Architect persona by prepending it to the prompt. This is the only
# reliable delivery mechanism: gemini's --policy flag loads *.toml policy-engine
# files only and silently ignores a markdown file, and we deliberately do NOT
# rely on the global ~/.gemini/GEMINI.md so plain `gemini` calls stay neutral.
# Prepending also guarantees the prompt starts with non-dash text.
PERSONA=$(cat "$SCRIPT_DIR/persona.md")

# Inject the owner's judgment standards the same way. The sandbox only sees the
# repo dirs (--include-directories), so taste.md must ride in the prompt or the
# reviewer never sees it and falls back to generic best practice.
TASTE_PATH="$HOME/repos/.claude/rules/taste.md"
TASTE=""
if [ -f "$TASTE_PATH" ]; then
  TASTE="

## Owner's Standards (judge against these, not generic best practice)

$(cat "$TASTE_PATH")"
fi

PROMPT="$PERSONA
$TASTE

$PROMPT"

INCLUDE_ARGS=()
if [ -n "$EXTRA_DIRS" ]; then
  INCLUDE_ARGS=(--include-directories "$EXTRA_DIRS")
fi

# Stream events to a trace file so a timeout kill leaves a partial to diagnose
# (gemini has no separate final-message file; the answer is reassembled from the
# trace on success). Cleaned up on every exit path alongside the pidfile.
TRACE=$(mktemp /tmp/architect-trace.XXXXXX)
trap 'rm -f "$TRACE" "$PIDFILE"' EXIT

echo "$$" > "$PIDFILE"
echo "architect: gemini review running — pid $$ (follow: kill -0 \$(cat $PIDFILE))" >&2

# --skip-trust: this is a headless, automated reviewer. Without it gemini refuses
# to run in an untrusted CWD and, worse, silently OVERRIDES `--approval-mode plan`
# back to `default` (which then can't headlessly approve, so it hangs/fails).
# gemini's own docs recommend --skip-trust for headless environments; it only
# trusts the workspace for this session, and plan mode + the persona still enforce
# read-only.
# stdin redirection (not `cat |`) so `timeout` wraps gemini directly and can kill
# it on overrun; gemini reads the design doc from stdin and appends --prompt.
set +e
timeout --kill-after=30s "$WALL_CLOCK" \
  gemini \
  -m gemini-3.1-pro-preview \
  --approval-mode plan \
  --skip-trust \
  "${INCLUDE_ARGS[@]}" \
  --prompt="$PROMPT" \
  -o stream-json <"$DOC_PATH" >"$TRACE" 2>&1
STATUS=$?
set -e

# Reassemble the final answer from the assistant message deltas, and read the
# terminal result event's status (last one wins). `-R | fromjson?` is load-bearing:
# gemini interleaves raw non-JSON lines into the stream (denied out-of-sandbox
# tool reads print `Error executing tool ...`, `YOLO mode ...` banners, etc.), and
# a bare `jq` aborts the WHOLE parse on the first such line — which silently
# emptied FINAL and made a fully-successful review look like "no final message".
# Reading each line as raw text and parsing with `fromjson?` skips the noise.
FINAL=$(jq -Rrj 'fromjson? | select(.type=="message" and .role=="assistant") | .content' "$TRACE" 2>/dev/null || true)
RESULT_STATUS=$(jq -Rr 'fromjson? | select(.type=="result") | .status' "$TRACE" 2>/dev/null | tail -1 || true)

if [ "$STATUS" -eq 124 ] || [ "$STATUS" -eq 137 ]; then
  echo "error: gemini exceeded the ${WALL_CLOCK} wall-clock limit and was killed — no complete review." >&2
  echo "       Over 10m means it hung, not that it's slow — retry rather than waiting longer." >&2
  echo "--- partial gemini trace ---" >&2
  cat "$TRACE" >&2
  exit 124
elif [ "$STATUS" -eq 0 ] && [ -n "$FINAL" ]; then
  printf '%s\n' "$FINAL"
else
  echo "error: gemini failed (status $STATUS, result=${RESULT_STATUS:-none}) or produced no final message." >&2
  echo "--- full gemini trace ---" >&2
  cat "$TRACE" >&2
  exit 1
fi
