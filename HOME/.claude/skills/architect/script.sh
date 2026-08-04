#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# WHY THIS SCRIPT LOOKS THE WAY IT DOES
# -----------------------------------------------------------------------------
# This is the gemini-backed sibling of /staff-engineer. Held at STRUCTURAL PARITY
# with that script: same scratch discipline, same wall-clock cap, same pidfile,
# same retry policy, same capped failure dump. Change one, change both.
#
# Three hardening layers, each earned by a measured failure:
#
#   1. SCRATCH (2026-08-04). Every scratch file lives under ${TMPDIR:-/tmp}, and
#      the script preflights that it is writable. It used to hardcode bare /tmp,
#      which the Claude Code Bash sandbox mounts READ-ONLY. Result: both panel
#      seats died in ~3s with `mktemp: Read-only file system (os error 30)` and
#      an 82-byte output. That was 37% of ALL panel dispatches over
#      2026-07-13..08-03 (55 of 149), by a wide margin the single biggest cause
#      of "the review panel doesn't respond". The sandbox FS allowlist covers
#      $TMPDIR and /tmp/review-panel, never bare /tmp.
#
#   2. WALL_CLOCK + `timeout` (2026-07-04). gemini can NEVER hang forever. On
#      overrun it is killed and the script exits 124. This cap is PER ATTEMPT.
#      A caller wrapping this in its own `timeout` MUST allow more than
#      MAX_ATTEMPTS * WALL_CLOCK, or the outer kill wins and destroys the
#      diagnostic. See TIMEOUT TIE below.
#
#   3. MAX_ATTEMPTS (2026-08-04). gemini-3.1-pro-preview aborts mid-review with
#      `Invalid stream: The model returned an empty response or malformed tool
#      call.` while still exiting status 0. It hit 9 of 149 dispatches, dying
#      anywhere from 1 to 1093 tool calls in, and EVERY observed instance
#      succeeded on a plain retry. The retry lives HERE, not in the caller, so a
#      bare /architect run and the review-panel both get it.
#
# TIMEOUT TIE (2026-08-03, marquee mcp-auth doc). review-panel wrapped this in
# `timeout 600` while WALL_CLOCK was also 10m == 600s. The outer kill won, the
# EXIT trap never ran, and the caller got a 110-byte banner-only file, rc=124, a
# stale pidfile, and zero diagnostic. Twice in a row. The inner cap must always
# win; an outer timeout is a backstop, never a peer.
#
# The gemini-specific piece: gemini has no `-o <file>` for the final message (its
# `-o` is a FORMAT: text|json|stream-json). So we run `-o stream-json`, which
# emits newline-delimited events INCREMENTALLY to a trace file. A kill therefore
# leaves a partial trace to diagnose (parity with codex's trace dump), and on
# success the final answer is reassembled from the assistant `content` deltas.
# =============================================================================

DOC_PATH="$1"
PROMPT_ARG="$2"
EXTRA_DIRS="${3:-}"
SCRIPT_DIR="$(dirname "$0")"

# --- Scratch discipline ------------------------------------------------------
# NEVER hardcode /tmp. Under the Claude Code Bash sandbox /tmp is a read-only
# mount and only $TMPDIR (plus /tmp/review-panel) are writable. Preflight it and
# fail with an actionable message instead of a cryptic mktemp error.
SCRATCH="${TMPDIR:-/tmp}"
if [ ! -d "$SCRATCH" ] || [ ! -w "$SCRATCH" ]; then
  echo "error: scratch dir '$SCRATCH' is not writable." >&2
  echo "       Under the Claude Code Bash sandbox bare /tmp is read-only." >&2
  echo "       Re-run with the sandbox disabled, or point TMPDIR at a writable dir." >&2
  exit 3
fi

# PID handle so a babysitter can follow this review's liveness directly:
#   kill -0 "$(cat "$PIDFILE")"  -> alive ;  pidfile gone / kill fails -> dead.
# We write THIS script's pid ($$); timeout+gemini are its children/process group.
# Removed on exit (any path) by the trap below. Override with ARCHITECT_PIDFILE
# when running more than one.
PIDFILE="${ARCHITECT_PIDFILE:-$SCRATCH/architect.pid}"

# Hard wall-clock cap on ONE gemini attempt. Held identical to the staff-engineer
# cap on purpose; the value is a hang-killer, not a per-tool performance budget.
# Per Scott's rule: over 10m means it hung, not that it's slow, so we kill it
# rather than wait (exit 124 on overrun). A timeout is TERMINAL and is never
# retried: two 10m hangs back to back is the observed shape, and burning another
# 10m proves nothing.
WALL_CLOCK="${ARCHITECT_WALL_CLOCK:-10m}"

# Attempts allowed when the backend fails TRANSIENTLY (see is_transient below).
# 2 means one retry. Worst-case wall clock is MAX_ATTEMPTS * WALL_CLOCK.
MAX_ATTEMPTS="${ARCHITECT_MAX_ATTEMPTS:-2}"

# How much of a failed trace to echo. The whole thing has hit 539 KB (a runaway
# 1093-tool-call run), which blows out the calling agent's context window. The
# full trace is preserved on disk and its path is printed instead.
TRACE_TAIL_BYTES="${ARCHITECT_TRACE_TAIL_BYTES:-4000}"

# Prompt can be (a) a path to a file containing the prompt, preferred for long
# follow-up prompts to avoid shell-quoting issues, or (b) a literal string.
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
# trace on success). Cleaned up on every exit path alongside the pidfile, except
# on terminal failure where preserve_trace() copies it out first.
TRACE=$(mktemp "$SCRATCH/architect-trace.XXXXXX")
trap 'rm -f "$TRACE" "$PIDFILE"' EXIT

echo "$$" > "$PIDFILE"
echo "architect: gemini review running -- pid $$ (follow: kill -0 \$(cat $PIDFILE))" >&2

# A transient backend failure is one a plain retry fixes. Deliberately EXCLUDES
# credits/quota/auth: those are the review-panel's Step 3.5 substitute-model
# path, and retrying here would only delay that fallback.
#
# Only the `{"type":"error"}` event messages are inspected, never the raw trace.
# The trace echoes the ENTIRE design doc back as the user message, so grepping it
# wholesale would match a doc that merely discusses quotas, 503s, or
# PERMISSION_DENIED and misclassify a real failure.
error_messages() {
  jq -Rr 'fromjson? | select(.type=="error") | .message' "$TRACE" 2>/dev/null || true
}

is_transient() {
  local msgs
  msgs=$(error_messages)
  [ -n "$msgs" ] || return 1
  if printf '%s' "$msgs" | rg -q -i 'credit|quota|billing|RESOURCE_EXHAUSTED|UNAUTHENTICATED|PERMISSION_DENIED|api key'; then
    return 1
  fi
  printf '%s' "$msgs" | rg -q -i 'invalid stream|empty response|malformed tool call|INTERNAL|UNAVAILABLE|\b5[0-9]{2}\b|timed? ?out|network'
}

preserve_trace() {
  local kept="$SCRATCH/architect-trace-failed-$$.jsonl"
  if cp "$TRACE" "$kept" 2>/dev/null; then
    echo "--- full gemini trace preserved: $kept ($(wc -c < "$kept") bytes) ---" >&2
    echo "--- last ${TRACE_TAIL_BYTES} bytes ---" >&2
    /usr/bin/tail -c "$TRACE_TAIL_BYTES" "$kept" >&2
  else
    echo "--- last ${TRACE_TAIL_BYTES} bytes of gemini trace ---" >&2
    /usr/bin/tail -c "$TRACE_TAIL_BYTES" "$TRACE" >&2
  fi
}

# --skip-trust: this is a headless, automated reviewer. Without it gemini refuses
# to run in an untrusted CWD and, worse, silently OVERRIDES `--approval-mode plan`
# back to `default` (which then can't headlessly approve, so it hangs/fails).
# gemini's own docs recommend --skip-trust for headless environments; it only
# trusts the workspace for this session, and plan mode + the persona still enforce
# read-only.
# stdin redirection (not `cat |`) so `timeout` wraps gemini directly and can kill
# it on overrun; gemini reads the design doc from stdin and appends --prompt.
# NOTE: this function must NOT touch errexit. An earlier draft did `set +e ...
# set -e; return $rc` internally, which re-armed errexit before returning, so a
# non-zero return aborted the script at the call site and NOTHING after it ran.
# The caller got a banner-only file and no diagnostic: precisely the failure this
# script exists to prevent. The CALLER owns errexit around this call.
run_attempt() {
  timeout --kill-after=30s "$WALL_CLOCK" \
    gemini \
    -m gemini-3.1-pro-preview \
    --approval-mode plan \
    --skip-trust \
    "${INCLUDE_ARGS[@]}" \
    --prompt="$PROMPT" \
    -o stream-json <"$DOC_PATH" >"$TRACE" 2>&1
}

FINAL=""
STATUS=0
RESULT_STATUS=""
attempt=1
while :; do
  : >"$TRACE"
  set +e
  run_attempt
  STATUS=$?
  set -e

  # Reassemble the final answer from the assistant message deltas, and read the
  # terminal result event's status (last one wins). `-R | fromjson?` is
  # load-bearing: gemini interleaves raw non-JSON lines into the stream (denied
  # out-of-sandbox tool reads print `Error executing tool ...`, `YOLO mode ...`
  # banners, etc.), and a bare `jq` aborts the WHOLE parse on the first such
  # line, which silently emptied FINAL and made a fully-successful review look
  # like "no final message". Reading each line raw and parsing with `fromjson?`
  # skips the noise.
  FINAL=$(jq -Rrj 'fromjson? | select(.type=="message" and .role=="assistant") | .content' "$TRACE" 2>/dev/null || true)
  RESULT_STATUS=$(jq -Rr 'fromjson? | select(.type=="result") | .status' "$TRACE" 2>/dev/null | /usr/bin/tail -1 || true)

  # Stop on success, on a timeout (terminal by policy), when attempts are
  # exhausted, or when a retry cannot help.
  if { [ "$STATUS" -eq 0 ] && [ -n "$FINAL" ]; } \
     || [ "$STATUS" -eq 124 ] || [ "$STATUS" -eq 137 ] \
     || [ "$attempt" -ge "$MAX_ATTEMPTS" ] \
     || ! is_transient; then
    break
  fi

  echo "architect: attempt $attempt failed transiently (status $STATUS, result=${RESULT_STATUS:-none}); retrying." >&2
  rg -o -i -m1 'Invalid stream[^"]{0,90}' "$TRACE" 2>/dev/null | sed 's/^/       signature: /' >&2 || true
  attempt=$((attempt + 1))
done

if [ "$STATUS" -eq 124 ] || [ "$STATUS" -eq 137 ]; then
  echo "error: gemini exceeded the ${WALL_CLOCK} wall-clock limit and was killed. No complete review." >&2
  echo "       Over 10m means it hung, not that it's slow. Retry rather than waiting longer." >&2
  preserve_trace
  exit 124
elif [ "$STATUS" -eq 0 ] && [ -n "$FINAL" ]; then
  if [ "$attempt" -gt 1 ]; then
    echo "architect: succeeded on attempt $attempt of $MAX_ATTEMPTS." >&2
  fi
  printf '%s\n' "$FINAL"
else
  echo "error: gemini failed (status $STATUS, result=${RESULT_STATUS:-none}) after $attempt attempt(s), or produced no final message." >&2
  preserve_trace
  exit 1
fi
