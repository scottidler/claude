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

# Inject the Architect persona by prepending it to the prompt. This is the only
# reliable delivery mechanism: gemini's --policy flag loads *.toml policy-engine
# files only and silently ignores a markdown file, and we deliberately do NOT
# rely on the global ~/.gemini/GEMINI.md so plain `gemini` calls stay neutral.
# Prepending also guarantees the prompt starts with non-dash text.
PERSONA=$(cat "$SCRIPT_DIR/persona.md")
PROMPT="$PERSONA

$PROMPT"

INCLUDE_ARGS=()
if [ -n "$EXTRA_DIRS" ]; then
  INCLUDE_ARGS=(--include-directories "$EXTRA_DIRS")
fi

cat "$DOC_PATH" | gemini \
  -m gemini-3.1-pro-preview \
  --approval-mode plan \
  "${INCLUDE_ARGS[@]}" \
  --prompt="$PROMPT" \
  -o text 2>&1
