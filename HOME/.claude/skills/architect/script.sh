#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# WHY THIS SCRIPT LOOKS THE WAY IT DOES  (liveness + wall-clock hardening, 2026-06-19)
# -----------------------------------------------------------------------------
# Background: the Architect persona used to run on the `gemini` CLI for months
# with no trouble — gemini took `-m gemini-3.1-pro-preview` on the command line,
# ran at its default reasoning effort, and returned a full review in 2-3 min.
# Google is retiring gemini in favor of Antigravity (`agy`), so this skill was
# migrated to `agy`. The migration introduced GENUINE new failure modes that
# gemini structurally could not have:
#   - agy ignores `--model` in `-p` mode and reads its model ONLY from a global
#     settings.json (by exact display label) — wrong label => SILENT downgrade
#     to Flash. (Handled below by snapshot/force/restore of settings.json.)
#   - agy's `-p` buffers ALL output to the very end, and `--print-timeout` only
#     bounds IDLE time, NOT active reasoning. A model that is actively grinding
#     therefore produces ZERO output and never returns — which a caller reads as
#     "still running" indefinitely.
#
# The failure that motivated the hardening below: when this skill is dispatched
# via a subagent, that silent no-output hang looked to the orchestrator like a
# healthy long-running job. It would claim "still waiting on the architect" while
# the process underneath had wedged (or died) — and nobody noticed until Scott
# got angry and asked. That is unacceptable. The fixes, all WHY-commented at
# their site below:
#   1. WALL_CLOCK + `timeout` wrap (see below): agy can NEVER hang forever. On
#      overrun it is killed and the script exits 124 with a clear message, so a
#      babysitter always gets a definitive terminal state within a bounded time.
#   2. PIDFILE (see below): the script writes its pid so a babysitter can FOLLOW
#      the actual process — `kill -0 $(cat PIDFILE)` to confirm it is truly alive,
#      and treat a vanished pidfile as the "it died" signal. No more trusting a
#      "still running" status with no evidence behind it.
# =============================================================================

DOC_PATH="$1"
PROMPT_ARG="$2"
EXTRA_DIRS="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# PID handle so a babysitter can follow this review's liveness directly:
#   kill -0 "$(cat "$PIDFILE")"  -> alive ;  pidfile gone / kill fails -> dead.
# We write THIS script's pid ($$); timeout+agy are its children/process group,
# so if $$ is alive the review is alive. The file is removed on exit (any path)
# by the trap below, so its absence is itself the "process is gone" signal.
# Override the path with ARCHITECT_PIDFILE when running more than one at once.
PIDFILE="${ARCHITECT_PIDFILE:-/tmp/architect.pid}"

# The Architect runs on Antigravity's Pro reasoning model. agy selects its model
# ONLY from settings.json — the --model flag is silently ignored in `-p` print
# mode, and only the exact display *label* is accepted (the gemini-style id
# "gemini-3.1-pro" is silently downgraded to Flash). MODEL_LABEL must match a
# label from `agy models` verbatim.
#
# Use the (Low) reasoning variant, NOT (High). This mirrors the gemini path that
# worked for months: gemini ran `gemini-3.1-pro-preview` at its DEFAULT reasoning
# effort and returned a full review in 2-3 min. The (High) variant cranks the
# reasoning budget to the ceiling, and on a large prompt (persona + full inlined
# design doc + a completeness-mandated bullet-by-bullet audit) it grinds for
# 20+ min. agy's `-p` buffers all output to the end, and --print-timeout only
# bounds IDLE waiting — it does NOT interrupt an actively-reasoning model — so
# (High) presents as a dead 20-minute hang with zero output. (Low) is the Pro
# tier without that pathology; bump to (High) only for a deliberately small,
# focused prompt where you will wait.
MODEL_LABEL="Gemini 3.1 Pro (Low)"
SETTINGS="$HOME/.gemini/antigravity-cli/settings.json"
# Idle-wait bound for a single headless review (Go duration). NOTE: this caps
# how long agy waits with no activity, NOT total wall-clock — an actively
# working model runs past it. The real wall-clock safety belongs at the call
# site (wrap the script in `timeout`), never trust this alone.
PRINT_TIMEOUT="8m"
# Hard wall-clock cap on the entire agy call, enforced by `timeout` below. agy's
# `-p` buffers all output to the end and --print-timeout only bounds IDLE waiting,
# so an actively-reasoning model (esp. the High variant) can hang for 20+ min with
# zero output and no terminal state — which reads to a caller as "still running"
# forever. This cap guarantees the script ALWAYS reaches a definitive
# success/failure within WALL_CLOCK: on overrun, agy is killed and the script
# exits 124 with a clear message. Override via ARCHITECT_WALL_CLOCK if a large
# audit legitimately needs longer. A working Low-Pro review returns in 2-3 min.
# 10m is a hard ceiling, not an estimate: a legitimate Low-Pro review returns in
# 2-3 min, so 10m is pure hang-killer headroom. Scott's rule: anything over 10m
# means something is wrong, not slow — so we kill it rather than wait longer.
WALL_CLOCK="${ARCHITECT_WALL_CLOCK:-10m}"

if ! command -v agy >/dev/null 2>&1; then
  echo "error: agy (Antigravity CLI) not found — install from https://antigravity.dev" >&2
  exit 127
fi

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
if [ ! -f "$DOC_PATH" ]; then
  echo "error: design doc not found: $DOC_PATH" >&2
  exit 2
fi

# Assemble the full prompt: persona, then the inlined design doc, then the task.
# Unlike gemini, agy's `-p` print mode does NOT read the doc from stdin, so the
# doc content is inlined here to guarantee the Architect actually sees it. The
# persona leads so the prompt never starts with a dash. The codebase itself is
# reachable via the cwd workspace plus the --add-dir entries below, so the
# Architect can still grep/read files to verify claims against the inlined doc.
PERSONA=$(cat "$SCRIPT_DIR/persona.md")
DOC_CONTENT=$(cat "$DOC_PATH")
FULL_PROMPT="$PERSONA

--- DESIGN DOCUMENT ($DOC_PATH) ---
$DOC_CONTENT

--- TASK ---
$PROMPT"

# agy takes workspace dirs as a repeatable --add-dir flag, not a comma list.
# EXTRA_DIRS arrives comma-joined (assembled by the skill); split it back out.
ADD_DIR_ARGS=()
if [ -n "$EXTRA_DIRS" ]; then
  IFS=',' read -ra _dirs <<< "$EXTRA_DIRS"
  for d in "${_dirs[@]}"; do
    [ -n "$d" ] && ADD_DIR_ARGS+=(--add-dir "$d")
  done
fi

# Scope the model to THIS call only: snapshot settings.json, force the Pro label,
# and restore the original on exit (normal, error, or interrupt). This avoids
# permanently changing the user's global agy model. Note: concurrent agy runs
# that also write settings.json are not supported — run the Architect serially.
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
BACKUP="$(mktemp "${SETTINGS}.architect-bak.XXXXXX")"
cp "$SETTINGS" "$BACKUP"
restore_settings() { cp "$BACKUP" "$SETTINGS" 2>/dev/null && rm -f "$BACKUP"; rm -f "$PIDFILE"; }
trap restore_settings EXIT INT TERM

python3 - "$SETTINGS" "$MODEL_LABEL" <<'PY'
import json, os, sys
path, model = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path)) if os.path.getsize(path) else {}
except Exception:
    data = {}
data["model"] = model
json.dump(data, open(path, "w"))
PY

# CRITICAL: --print-timeout and every --add-dir flag MUST precede -p, and the
# prompt MUST be the token immediately after -p. agy's `-p` consumes the next
# single token as the prompt; if a flag follows -p, that flag string becomes the
# "prompt" and the real prompt is dropped. Do NOT pass --dangerously-skip-
# permissions: headless agy already auto-grants read tools (so the Architect can
# verify against code), while write/shell tools stay gated — preserving the
# read-only guarantee that gemini's `--approval-mode plan` used to enforce.
# Wrap in `timeout` so a hung/runaway agy can never wedge the caller. SIGTERM at
# WALL_CLOCK, SIGKILL 30s later if it ignores TERM. `set +e` so we can inspect the
# exit code and emit a clear, parseable failure instead of dying silently under
# `set -e`. The EXIT trap still fires afterward to restore settings.json.
echo "$$" > "$PIDFILE"
echo "architect: agy review running — pid $$ (follow: kill -0 \$(cat $PIDFILE))" >&2
set +e
timeout --kill-after=30s "$WALL_CLOCK" \
  agy ${ADD_DIR_ARGS[@]+"${ADD_DIR_ARGS[@]}"} --print-timeout "$PRINT_TIMEOUT" -p "$FULL_PROMPT" 2>&1
rc=$?
set -e
if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
  echo "error: agy exceeded the ${WALL_CLOCK} wall-clock limit and was killed — no review was produced." >&2
  echo "       The model likely hung (see the (High)-variant pathology documented above)." >&2
  echo "       Over 10m means it hung, not that it's slow — retry rather than waiting longer." >&2
  exit 124
fi
exit "$rc"
