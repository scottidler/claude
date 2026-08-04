#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# WHY THIS SCRIPT LOOKS THE WAY IT DOES
# -----------------------------------------------------------------------------
# This is the codex-backed sibling of /architect. Held at STRUCTURAL PARITY with
# that script: same scratch discipline, same wall-clock cap, same pidfile, same
# retry policy, same capped failure dump. Change one, change both.
#
# Three hardening layers, each earned by a measured failure:
#
#   1. SCRATCH (2026-08-04). Every scratch file lives under ${TMPDIR:-/tmp}, and
#      the script preflights that it is writable. It used to hardcode bare /tmp,
#      which the Claude Code Bash sandbox mounts READ-ONLY. Result: both panel
#      seats died in ~3s with `mktemp: Read-only file system (os error 30)` and
#      an 86-byte output. That was 37% of ALL panel dispatches over
#      2026-07-13..08-03, by a wide margin the single biggest cause of "the
#      review panel doesn't respond". codex itself trips the same mount at
#      startup ("could not create PATH aliases: Read-only file system"). The
#      sandbox FS allowlist covers $TMPDIR and /tmp/review-panel, never bare /tmp.
#
#   2. WALL_CLOCK + `timeout` (2026-06-19). When these review skills are
#      dispatched via subagents, a backend that grinds with its output buffered
#      to the end looks IDENTICAL to a healthy long-running job. The orchestrator
#      would keep claiming "still waiting on the staff engineer" while the codex
#      process had actually wedged, and nobody noticed until Scott had to ask.
#      codex at model_reasoning_effort=high on a large design doc is exactly that
#      kind of job, so it can NEVER hang forever: on overrun it is killed and the
#      script exits 124. This cap is PER ATTEMPT. A caller wrapping this in its
#      own `timeout` MUST allow more than MAX_ATTEMPTS * WALL_CLOCK. See TIMEOUT
#      TIE below.
#
#   3. MAX_ATTEMPTS (2026-08-04). Symmetric with /architect, which retries the
#      gemini `Invalid stream` abort. codex has its own transient shape (a bare
#      "Execution error" final message, 5xx from the backend). Retry here, not in
#      the caller, so a bare /staff-engineer run and the review-panel both get it.
#      Credits/quota are deliberately NOT retried: that is the review-panel's
#      Step 3.5 substitute-model path and retrying would only delay it.
#
# TIMEOUT TIE (2026-08-03, marquee mcp-auth doc). review-panel wrapped the
# sibling script in `timeout 600` while its WALL_CLOCK was also 10m == 600s. The
# outer kill won, the EXIT trap never ran, and the caller got a banner-only file,
# rc=124, a stale pidfile, and zero diagnostic. Twice in a row. The inner cap
# must always win; an outer timeout is a backstop, never a peer.
#
# (Note: codex already separated final-message from trace and surfaced non-zero
# exits; that part predates all of the above.)
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
# We write THIS script's pid ($$); timeout+codex are its children/process group.
# Removed on exit (any path) by the trap below, so its absence == process gone.
# Override the path with STAFF_ENGINEER_PIDFILE when running more than one.
PIDFILE="${STAFF_ENGINEER_PIDFILE:-$SCRATCH/staff-engineer.pid}"

# Hard wall-clock cap on ONE codex attempt. 10m is a hard ceiling, not an
# estimate. Per Scott's rule: anything over 10m means the review hung, not that
# it's slow, so we kill it rather than wait. Held identical to the architect cap
# on purpose; the value is a hang-killer, not a per-tool performance budget, so
# there is no reason for the two to differ. A timeout is TERMINAL and is never
# retried.
WALL_CLOCK="${STAFF_ENGINEER_WALL_CLOCK:-10m}"

# Attempts allowed when the backend fails TRANSIENTLY (see is_transient below).
# 2 means one retry. Worst-case wall clock is MAX_ATTEMPTS * WALL_CLOCK.
MAX_ATTEMPTS="${STAFF_ENGINEER_MAX_ATTEMPTS:-2}"

# How much of a failed trace to echo. A full codex trace has hit 41 KB and the
# sibling script's has hit 539 KB; dumping the whole thing blows out the calling
# agent's context window. The full trace is preserved on disk and its path is
# printed instead.
TRACE_TAIL_BYTES="${STAFF_ENGINEER_TRACE_TAIL_BYTES:-4000}"

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
# trace. On success we print only the final message; on failure we surface a
# capped tail and preserve the whole trace on disk.
LAST_MSG=$(mktemp "$SCRATCH/staff-engineer-last.XXXXXX")
TRACE=$(mktemp "$SCRATCH/staff-engineer-trace.XXXXXX")
trap 'rm -f "$LAST_MSG" "$TRACE" "$PIDFILE"' EXIT

echo "$$" > "$PIDFILE"
echo "staff-engineer: codex review running -- pid $$ (follow: kill -0 \$(cat $PIDFILE))" >&2

# A transient backend failure is one a plain retry fixes. Deliberately EXCLUDES
# credits/quota/auth: those are the review-panel's Step 3.5 substitute-model
# path, and retrying here would only delay that fallback.
#
# Only the TAIL of the trace plus the final message are inspected, never the
# whole trace. codex echoes the ENTIRE design doc back into the trace, so
# grepping it wholesale would match a doc that merely discusses quotas, 503s, or
# rate limits and misclassify a real failure. Errors land at the end.
error_tail() {
  { /usr/bin/tail -c 2000 "$TRACE" 2>/dev/null; printf '\n'; cat "$LAST_MSG" 2>/dev/null; } || true
}

is_transient() {
  local t
  t=$(error_tail)
  if printf '%s' "$t" | rg -q -i 'out of credits|insufficient (credits|balance)|quota|billing|rate limit|unauthorized|not authenticated|invalid api key'; then
    return 1
  fi
  printf '%s' "$t" | rg -q -i '^Execution error|stream (disconnected|error)|unexpected EOF|connection (reset|closed|refused)|Internal Server Error|Service Unavailable|Bad Gateway|Gateway Time-?out'
}

preserve_trace() {
  local kept="$SCRATCH/staff-engineer-trace-failed-$$.log"
  if cp "$TRACE" "$kept" 2>/dev/null; then
    echo "--- full codex trace preserved: $kept ($(wc -c < "$kept") bytes) ---" >&2
    echo "--- last ${TRACE_TAIL_BYTES} bytes ---" >&2
    /usr/bin/tail -c "$TRACE_TAIL_BYTES" "$kept" >&2
  else
    echo "--- last ${TRACE_TAIL_BYTES} bytes of codex trace ---" >&2
    /usr/bin/tail -c "$TRACE_TAIL_BYTES" "$TRACE" >&2
  fi
}

# The design doc is piped on stdin; codex appends it as a <stdin> block that the
# prompt refers to. -s read-only keeps the reviewer strictly non-mutating while
# still allowing rg/git/find/read for empirical verification.
# stdin redirection (not `cat |`) so `timeout` wraps codex directly and can kill
# it on overrun; codex reads the design doc from stdin exactly as before.
# NOTE: this function must NOT touch errexit. An earlier draft did `set +e ...
# set -e; return $rc` internally, which re-armed errexit before returning, so a
# non-zero return aborted the script at the call site and NOTHING after it ran.
# The caller got a banner-only file and no diagnostic: precisely the failure this
# script exists to prevent. The CALLER owns errexit around this call.
run_attempt() {
  timeout --kill-after=30s "$WALL_CLOCK" \
    codex exec \
    -m gpt-5.5 \
    -c model_reasoning_effort="high" \
    -s read-only \
    --skip-git-repo-check \
    --color never \
    -o "$LAST_MSG" \
    "$PROMPT" <"$DOC_PATH" >"$TRACE" 2>&1
}

STATUS=0
attempt=1
while :; do
  : >"$TRACE"
  : >"$LAST_MSG"
  set +e
  run_attempt
  STATUS=$?
  set -e

  # Stop on success, on a timeout (terminal by policy), when attempts are
  # exhausted, or when a retry cannot help.
  if { [ "$STATUS" -eq 0 ] && [ -s "$LAST_MSG" ]; } \
     || [ "$STATUS" -eq 124 ] || [ "$STATUS" -eq 137 ] \
     || [ "$attempt" -ge "$MAX_ATTEMPTS" ] \
     || ! is_transient; then
    break
  fi

  echo "staff-engineer: attempt $attempt failed transiently (status $STATUS); retrying." >&2
  attempt=$((attempt + 1))
done

if [ "$STATUS" -eq 124 ] || [ "$STATUS" -eq 137 ]; then
  echo "error: codex exceeded the ${WALL_CLOCK} wall-clock limit and was killed. No review was produced." >&2
  echo "       Over 10m means it hung, not that it's slow. Retry rather than waiting longer." >&2
  preserve_trace
  exit 124
elif [ "$STATUS" -eq 0 ] && [ -s "$LAST_MSG" ]; then
  if [ "$attempt" -gt 1 ]; then
    echo "staff-engineer: succeeded on attempt $attempt of $MAX_ATTEMPTS." >&2
  fi
  cat "$LAST_MSG"
else
  echo "error: codex exec failed (status $STATUS) after $attempt attempt(s), or produced no final message." >&2
  preserve_trace
  exit 1
fi
