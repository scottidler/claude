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
# If it is missing, recover ONLY the two display variables below from the foot
# process. This reads /proc/<pid>/environ of the foot terminal, so we disclose it
# explicitly on stderr and restrict ourselves to a strict allowlist of variable
# names (WAYLAND_DISPLAY, XDG_RUNTIME_DIR). No other variables are read or used.
#
# Preferred fix: export these in your shell profile so this recovery never runs.
# To disable the recovery entirely, set SLACKIFY_NO_PROC_RECOVERY=1.
if [[ -z "${WAYLAND_DISPLAY:-}" ]] && [[ "${SLACKIFY_NO_PROC_RECOVERY:-}" != "1" ]] && command -v wl-copy &>/dev/null; then
    foot_pid=$(pgrep -x foot | head -1)
    if [[ -n "$foot_pid" ]]; then
        echo "INFO: WAYLAND_DISPLAY not set; recovering WAYLAND_DISPLAY and XDG_RUNTIME_DIR (only) from foot process PID $foot_pid. Set SLACKIFY_NO_PROC_RECOVERY=1 to disable." >&2
        wd=$(tr '\0' '\n' < "/proc/$foot_pid/environ" 2>/dev/null | grep '^WAYLAND_DISPLAY=' | cut -d= -f2-)
        if [[ -n "$wd" ]]; then
            export WAYLAND_DISPLAY="$wd"
        fi
        xdg_rt=$(tr '\0' '\n' < "/proc/$foot_pid/environ" 2>/dev/null | grep '^XDG_RUNTIME_DIR=' | cut -d= -f2-)
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
