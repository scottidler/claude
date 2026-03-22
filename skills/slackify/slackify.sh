#!/usr/bin/env bash
# slackify.sh - convert markdown on stdin to rich text HTML and copy to clipboard
# Slack reads text/html from clipboard and renders it as formatted rich text.
# Usage: echo "## Hello **world**" | slackify.sh
# Requires: pandoc, wl-copy (Wayland) or xclip (X11)

set -euo pipefail

if ! command -v pandoc &>/dev/null; then
    echo "ERROR: pandoc is required. Install with: sudo apt install pandoc" >&2
    exit 1
fi

# foot terminal runs on Wayland but child processes may not inherit WAYLAND_DISPLAY.
# Recover it from the foot process if missing.
if [[ -z "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy &>/dev/null; then
    foot_pid=$(pgrep -x foot | head -1)
    if [[ -n "$foot_pid" ]]; then
        wd=$(cat "/proc/$foot_pid/environ" 2>/dev/null | tr '\0' '\n' | grep '^WAYLAND_DISPLAY=' | cut -d= -f2-)
        if [[ -n "$wd" ]]; then
            export WAYLAND_DISPLAY="$wd"
        fi
        xdg_rt=$(cat "/proc/$foot_pid/environ" 2>/dev/null | tr '\0' '\n' | grep '^XDG_RUNTIME_DIR=' | cut -d= -f2-)
        if [[ -n "$xdg_rt" ]]; then
            export XDG_RUNTIME_DIR="$xdg_rt"
        fi
    fi
fi

input=$(cat)
html=$(printf '%s' "$input" | pandoc -f markdown -t html)

if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy &>/dev/null; then
    printf '%s' "$html" | wl-copy -t text/html
elif command -v xclip &>/dev/null; then
    printf '%s' "$html" | xclip -selection clipboard -t text/html
elif command -v pbcopy &>/dev/null; then
    printf '%s' "$html" | LANG=en_US.UTF-8 pbcopy
else
    echo "ERROR: No clipboard tool found." >&2
    exit 1
fi

echo "Copied rich text to clipboard - ready to paste in Slack."
