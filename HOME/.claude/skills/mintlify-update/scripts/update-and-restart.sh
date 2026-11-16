#!/usr/bin/env bash
# Update Mintlify Desktop; quit it first if running and relaunch it afterward.
set -euo pipefail

updater="$HOME/.local/bin/mintlify-update"
launcher="$HOME/.local/bin/mintlify-desktop"
pattern='mintlify-desktop/app-[0-9.]+/squashfs-root/mintlify-desktop'

main_pids() {
  pgrep -f "$pattern" | while read -r pid; do
    tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q -- '--type=' || echo "$pid"
  done
}

was_running=0
pids=$(main_pids)
if [[ -n $pids ]]; then
  was_running=1
  echo "Mintlify is running; quitting (SIGTERM)."
  kill -TERM $pids
  for _ in $(seq 30); do
    pgrep -f "$pattern" >/dev/null || break
    sleep 0.5
  done
  if pgrep -f "$pattern" >/dev/null; then
    echo "Mintlify did not quit within 15s; not force-killing." >&2
    exit 1
  fi
fi

rc=0
"$updater" || rc=$?

if (( was_running )); then
  echo "Relaunching Mintlify."
  setsid nohup "$launcher" --no-sandbox >/dev/null 2>&1 &
  sleep 3
  pgrep -af "$pattern" | grep -v -- '--type=' | head -1 || echo "Relaunch not detected." >&2
else
  echo "Mintlify was not running; not launching."
fi
exit "$rc"
