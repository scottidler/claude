#!/usr/bin/env bash
set -euo pipefail

DOC_PATH="$1"
PROMPT="$2"
SCRIPT_DIR="$(dirname "$0")"

cat "$DOC_PATH" | gemini \
  -m gemini-3.1-pro-preview \
  --policy "$SCRIPT_DIR/persona.md" \
  --approval-mode plan \
  -p "$PROMPT" \
  -o text 2>&1
