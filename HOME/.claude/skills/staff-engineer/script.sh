#!/usr/bin/env bash
set -euo pipefail

DOC_PATH="$1"
PROMPT_ARG="$2"
EXTRA_DIRS="${3:-}"
SCRIPT_DIR="$(dirname "$0")"

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

PROMPT="$PERSONA
$REFS

$PROMPT"

# Capture the clean final synthesis separately from the (verbose) execution
# trace. On success we print only the final message; on failure we surface the
# whole trace for diagnosis.
LAST_MSG=$(mktemp /tmp/staff-engineer-last.XXXXXX)
TRACE=$(mktemp /tmp/staff-engineer-trace.XXXXXX)
trap 'rm -f "$LAST_MSG" "$TRACE"' EXIT

# The design doc is piped on stdin; codex appends it as a <stdin> block that the
# prompt refers to. -s read-only keeps the reviewer strictly non-mutating while
# still allowing rg/git/find/read for empirical verification.
set +e
cat "$DOC_PATH" | codex exec \
  -m gpt-5.5 \
  -c model_reasoning_effort="high" \
  -s read-only \
  --skip-git-repo-check \
  --color never \
  -o "$LAST_MSG" \
  "$PROMPT" >"$TRACE" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ] && [ -s "$LAST_MSG" ]; then
  cat "$LAST_MSG"
else
  echo "error: codex exec failed (status $STATUS) or produced no final message." >&2
  echo "--- full codex trace ---" >&2
  cat "$TRACE" >&2
  exit 1
fi
