#!/bin/bash
# user-units-check.sh (SessionStart): names failed systemd USER services and
# their ExecMainStatus, so a unit that has been dead for days is seen at the
# start of a session. See docs/design/2026-10-05-user-unit-failure-visibility.md
# (dotfiles repo) Layer 2 and Phase 0 result (f).
#
# --type=service is mandatory: desk carries dozens of failed
# app-com.google.Chrome-*.scope units that are not actionable.
#
# Phase 0 (f): `systemctl --user` with no XDG_RUNTIME_DIR, or inside the Claude
# Bash sandbox, prints nothing to stdout and exits 1 with a stderr bus error.
# The exit code is also 1 for a merely degraded manager. So this keys off
# stdout only: empty stdout means "cannot ask" or "nothing failed", and the
# hook stays silent either way. stderr is discarded so a bus error is never
# mistaken for a failed unit.
#
# Never exits non-zero: a SessionStart hook failing must not break session
# start. Silent (no output, zero tokens) when healthy.

set -u

listing=$(systemctl --user list-units --type=service --state=failed --no-legend --plain 2>/dev/null)
[ -n "$listing" ] || exit 0

lines=()
while read -r unit _; do
  status=$(systemctl --user show "$unit" -p ExecMainStatus --value 2>/dev/null)
  lines+=("${unit} (ExecMainStatus=${status:-unknown})")
done <<< "$listing"

[ "${#lines[@]}" -gt 0 ] || exit 0

detail=$(printf '%s; ' "${lines[@]}")
msg="user-units-check: failed systemd user service(s): ${detail}inspect: systemctl --user status <unit>; journalctl --user -u <unit>"
jq -n --arg ctx "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' 2>/dev/null

exit 0
