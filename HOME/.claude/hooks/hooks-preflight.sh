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
ROUTED_DIR="${HOOKS_PREFLIGHT_ROUTED:-$HOME/repos/.claude/routed}"
VOICE_STATE="${HOOKS_PREFLIGHT_VOICE_STATE:-$HOME/.local/state/voice-guard}"
# The SessionStart payload carries session_id on stdin. A test sets
# HOOKS_PREFLIGHT_SESSION_ID (empty means: no session id, skip the load check).
if [ "${HOOKS_PREFLIGHT_SESSION_ID+set}" = set ]; then
  SESSION_ID="$HOOKS_PREFLIGHT_SESSION_ID"
else
  SESSION_ID=$(cat 2>/dev/null | jq -r '.session_id // empty' 2>/dev/null)
fi

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

# rails owns the rule router (docs/design/2026-10-08-rule-routing.md). Since
# Phase 7 the routed rules live in ~/repos/.claude/routed, which nothing but
# rails loads: rails not running means they never load. Absent keys mean
# enabled (plugin.json defaults); only an explicit false warns.
# The engine reads options under the plugin id (`pluginConfigs["rails@skills-dir"]`,
# its debug log, CC 2.1.304); the bare name is read too, for older settings.
rails_down=$(jq -r '
  def opt(k): [.pluginConfigs["rails@skills-dir"].options[k], .pluginConfigs.rails.options[k]] | any(. == false);
  if .enabledPlugins["rails@skills-dir"] == false then "rails@skills-dir is disabled in enabledPlugins"
  elif opt("enabled") then "pluginConfigs rails options.enabled is false"
  elif (.env.CLAUDE_CODE_ENABLE_FUNCTION_HOOKS // "") != "1" then "env.CLAUDE_CODE_ENABLE_FUNCTION_HOOKS is not \"1\""
  else empty end' "$SETTINGS" 2>/dev/null)
routing_off=$(jq -r 'if [.pluginConfigs["rails@skills-dir"].options.rule_routing, .pluginConfigs.rails.options.rule_routing] | any(. == false) then "pluginConfigs rails options.rule_routing is false" else empty end' "$SETTINGS" 2>/dev/null)

# voice-guard (docs/design/2026-11-18-voice-mod.md, Phase 6): disabled the
# same way rails is, and a failed load. The mod writes heartbeat.<sessionId>
# at session.start; this reads last-session-id (the previous session this
# hook ran in), warns if that session has no heartbeat, and only THEN writes
# the current id: writing first would warn every session. No last-session-id
# (first run) is no warning. This sees a load failure at the NEXT session
# start, and a session that ended before session.start ran warns falsely.
voice_down=$(jq -r '
  def opt(k): [.pluginConfigs["voice-guard@skills-dir"].options[k], .pluginConfigs["voice-guard"].options[k]] | any(. == false);
  if .enabledPlugins["voice-guard@skills-dir"] == false then "voice-guard@skills-dir is disabled in enabledPlugins"
  elif opt("enabled") then "pluginConfigs voice-guard options.enabled is false"
  elif (.env.CLAUDE_CODE_ENABLE_FUNCTION_HOOKS // "") != "1" then "env.CLAUDE_CODE_ENABLE_FUNCTION_HOOKS is not \"1\""
  else empty end' "$SETTINGS" 2>/dev/null)

voice_unloaded=""
if [ -n "$SESSION_ID" ]; then
  last_id=""
  [ -r "$VOICE_STATE/last-session-id" ] && last_id=$(head -n 1 "$VOICE_STATE/last-session-id" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$last_id" ] && [ ! -e "$VOICE_STATE/heartbeat.$last_id" ]; then
    voice_unloaded="$last_id"
  fi
  mkdir -p "$VOICE_STATE" 2>/dev/null && printf '%s\n' "$SESSION_ID" > "$VOICE_STATE/last-session-id" 2>/dev/null
fi

if [ "${#missing[@]}" -gt 0 ]; then
  detail=$(printf '%s; ' "${missing[@]}")
  # The globs are spelled out rather than a bare `hooks/*`, which also emits a
  # link for every __pycache__/*.pyc (measured 2026-09-14, Phase 7).
  msg="hooks-preflight: unresolved hook(s): ${detail}fix: cd ~/repos/scottidler/claude && manifest -l HOME/.claude/hooks/*.sh HOME/.claude/hooks/*.py | bash"
fi

if [ -n "$rails_down" ]; then
  msg="${msg:+$msg
}hooks-preflight: rails will not run ($rails_down), so git, marquee, otto and voice rules never load: they live in ~/repos/.claude/routed, which only rails reads. fix: enable the rails plugin and set env.CLAUDE_CODE_ENABLE_FUNCTION_HOOKS to \"1\"; until then read the rule a task needs from that directory"
elif [ -n "$routing_off" ]; then
  msg="${msg:+$msg
}hooks-preflight: rule routing is off ($routing_off), so git, marquee, otto and voice rules are flushed whole into each loop at its first prompt or tool call instead of on trigger. fix: set pluginConfigs[\"rails@skills-dir\"].options.rule_routing true"
fi

if [ -n "$voice_down" ]; then
  msg="${msg:+$msg
}hooks-preflight: voice-guard will not run ($voice_down), so the em-dash and phrase checks the mod shadows or enforces are off. fix: enable the voice-guard plugin and set env.CLAUDE_CODE_ENABLE_FUNCTION_HOOKS to \"1\""
fi

if [ -n "$voice_unloaded" ]; then
  msg="${msg:+$msg
}hooks-preflight: voice-guard did not load last session (no heartbeat for session $voice_unloaded in $VOICE_STATE). fix: run claude plugin validate --strict ~/.claude/skills/voice-guard and read the plugin load errors in the debug log"
fi

if [ ! -d "$ROUTED_DIR" ]; then
  msg="${msg:+$msg
}hooks-preflight: $ROUTED_DIR does not resolve to a directory, so the rails rule router has no routed rules and points every loop at them instead. fix: cd ~/repos/scottidler/claude && manifest -l HOME/repos/.claude/routed | bash"
fi

if [ -n "${msg:-}" ]; then
  jq -n --arg ctx "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
fi

exit 0
