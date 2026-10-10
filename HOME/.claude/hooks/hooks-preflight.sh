#!/bin/bash
# hooks-preflight.sh (SessionStart): warns when settings.json registers a
# hook whose file is missing or a bare PATH name that resolves to nothing,
# and when ~/.claude/hooks/lib.sh is not readable (every sourcing guard goes
# inert without it). See docs/design/2026-09-13-guard-precision.md Phase 7.
#
# Spike 0a (2026-09-14): both plain stdout and additionalContext reach the
# model in an interactive session, as separate attachments; neither fires
# under `claude -p`. This emits additionalContext, the documented channel;
# bin/hooks-resolve covers the headless case by blocking the merge instead.
#
# Never exits non-zero: a SessionStart hook failing must not break session
# start. Silent (no output) when everything resolves.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="${HOOKS_PREFLIGHT_SETTINGS:-$HOME/.claude/settings.json}"
LIB_SH="${HOOKS_PREFLIGHT_LIB:-$HOME/.claude/hooks/lib.sh}"

# shellcheck source=hooks-resolve-lib.sh
. "$SCRIPT_DIR/hooks-resolve-lib.sh" 2>/dev/null || exit 0

[ -r "$SETTINGS" ] || exit 0

missing=()

while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  hook_resolve_target "$cmd"
  if ! hook_target_exists "$HOOK_TARGET" "$HOOK_KIND"; then
    missing+=("$cmd")
  fi
done < <(jq -r '.hooks[][].hooks[]? | select(.type=="command") | .command' "$SETTINGS" 2>/dev/null)

if [ ! -r "$LIB_SH" ]; then
  missing+=("~/.claude/hooks/lib.sh (not readable)")
fi

# rails owns the rule router (docs/design/2026-10-08-rule-routing.md). Absent
# keys mean enabled (plugin.json defaults); only an explicit false warns.
rails_off=$(jq -r '
  if .enabledPlugins["rails@skills-dir"] == false then "rails@skills-dir is disabled in enabledPlugins"
  elif .pluginConfigs.rails.options.enabled == false then "pluginConfigs.rails.options.enabled is false"
  elif .pluginConfigs.rails.options.rule_routing == false then "pluginConfigs.rails.options.rule_routing is false"
  else empty end' "$SETTINGS" 2>/dev/null)

if [ "${#missing[@]}" -gt 0 ]; then
  detail=$(printf '%s; ' "${missing[@]}")
  # The globs are spelled out rather than a bare `hooks/*`, which also emits a
  # link for every __pycache__/*.pyc (measured 2026-09-14, Phase 7).
  msg="hooks-preflight: unresolved hook(s): ${detail}fix: cd ~/repos/scottidler/claude && manifest -l HOME/.claude/hooks/*.sh HOME/.claude/hooks/*.py | bash"
fi

if [ -n "$rails_off" ]; then
  msg="${msg:+$msg
}hooks-preflight: rule routing is off ($rails_off), so git, marquee, otto and voice rules load in bulk instead of on trigger. fix: enable the rails plugin and set pluginConfigs.rails.options.rule_routing true"
fi

if [ -n "${msg:-}" ]; then
  jq -n --arg ctx "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
fi

exit 0
