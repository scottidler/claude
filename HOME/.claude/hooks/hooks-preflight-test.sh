#!/bin/bash
# hooks-preflight-test.sh: fixture matrix for hooks-preflight.sh and
# bin/hooks-resolve, which share hooks-resolve-lib.sh's command parsing.
#
# Each fixture is a settings.json naming one or two SessionStart hooks.
# The missing-hook fixtures cover the shape a first-token check would
# silently pass: `bash '<path>' session`, whose first token is "bash".
set -u

# readlink -f: the test is also reachable through its ~/.claude/hooks symlink, and
# "$HOOKS_DIR/../../.." from THERE is /home, not the repo.
HOOKS_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ROOT="$(cd "$HOOKS_DIR/../../.." && pwd)"
PREFLIGHT="$HOOKS_DIR/hooks-preflight.sh"
RESOLVE="$ROOT/bin/hooks-resolve"

SCRATCH="${TMPDIR:-/tmp}/hooks-preflight-test.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

pass=0
fail=0

# The voice-guard load check reads and writes ~/.local/state/voice-guard: point it at
# the scratch dir, and give every run no session id (skip the check, no stdin read)
# unless a case sets one.
export HOOKS_PREFLIGHT_VOICE_STATE="$SCRATCH/voice-state"
export HOOKS_PREFLIGHT_SESSION_ID=""

ok()  { printf 'PASS  %s\n' "$*"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s\n' "$*"; fail=$((fail + 1)); }

settings_with() { # settings_with <file> <command...>
  local file="$1"; shift
  local hooks_json
  hooks_json=$(printf '%s\n' "$@" | jq -R '{type:"command", command:.}' | jq -s '.')
  jq -n --argjson hooks "$hooks_json" \
    '{hooks:{SessionStart:[{matcher:"*",hooks:$hooks}]}}' > "$file"
}

# ---- fixture: a tilde path that does not exist ------------------------------
missing_sh="$SCRATCH/missing.json"
settings_with "$missing_sh" '~/.claude/hooks/does-not-exist.sh'

out=$("$RESOLVE" --settings "$missing_sh" --root "$ROOT" 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then ok "hooks-resolve: missing tilde path exits non-zero"; else bad "hooks-resolve: missing tilde path exited 0: $out"; fi

ctx=$(HOOKS_PREFLIGHT_SETTINGS="$missing_sh" bash "$PREFLIGHT")
if printf '%s' "$ctx" | rg -q 'does-not-exist\.sh'; then
  ok "hooks-preflight: names the missing tilde path"
else
  bad "hooks-preflight: did not name the missing tilde path: $ctx"
fi

# ---- fixture: the bash '<path>' <arg> shape, path missing -------------------
# This is the shape a first-token check ("bash" resolves, done) silently
# passes. It must be caught by resolving to the first ARGUMENT that looks
# like a path instead.
bash_shape="$SCRATCH/bash-shape.json"
settings_with "$bash_shape" "bash '$SCRATCH/does-not-exist-either.sh' session"

out=$("$RESOLVE" --settings "$bash_shape" --root "$ROOT" 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then
  ok "hooks-resolve: bash '<missing path>' session exits non-zero"
else
  bad "hooks-resolve: bash '<missing path>' session exited 0 (first-token check would pass this): $out"
fi

# ---- fixture: a bare PATH name that does not exist --------------------------
bare_missing="$SCRATCH/bare-missing.json"
settings_with "$bare_missing" 'this-binary-does-not-exist-anywhere'

ctx=$(HOOKS_PREFLIGHT_SETTINGS="$bare_missing" bash "$PREFLIGHT")
if printf '%s' "$ctx" | rg -q 'this-binary-does-not-exist-anywhere'; then
  ok "hooks-preflight: names the missing bare PATH name"
else
  bad "hooks-preflight: did not name the missing bare command: $ctx"
fi

# bin/hooks-resolve treats a missing bare name as a warning, not a failure.
out=$("$RESOLVE" --settings "$bare_missing" --root "$ROOT" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | rg -q 'WARN.*this-binary-does-not-exist-anywhere'; then
  ok "hooks-resolve: missing bare PATH name is a warning, exits 0"
else
  bad "hooks-resolve: missing bare PATH name rc=$rc: $out"
fi

# ---- fixture: only hooks that exist -----------------------------------------
# Named against a hook that is live-symlinked today (secret-echo-guard.sh),
# not one this same PR adds, so the fixture is valid before the post-merge
# link step runs. The lib.sh readability check is overridden to the repo's
# own copy for the same reason: it is unaffected by whether THIS host has
# linked ~/.claude/hooks/lib.sh yet.
good="$SCRATCH/good.json"
settings_with "$good" '~/.claude/hooks/secret-echo-guard.sh' 'echo'
# rails runs only with function hooks on (rule routing, Phase 7).
jq '. + {env:{CLAUDE_CODE_ENABLE_FUNCTION_HOOKS:"1"}}' "$good" > "$good.tmp" && mv "$good.tmp" "$good"
# The routed rules dir check reads this checkout's copy, not this host's link.
export HOOKS_PREFLIGHT_ROUTED="$ROOT/HOME/repos/.claude/routed"

out=$("$RESOLVE" --settings "$good" --root "$ROOT" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then ok "hooks-resolve: all-present fixture exits 0"; else bad "hooks-resolve: all-present fixture rc=$rc: $out"; fi

ctx=$(HOOKS_PREFLIGHT_SETTINGS="$good" HOOKS_PREFLIGHT_LIB="$HOOKS_DIR/lib.sh" bash "$PREFLIGHT")
if [ -z "$ctx" ]; then
  ok "hooks-preflight: all-present fixture prints nothing"
else
  bad "hooks-preflight: all-present fixture printed: $ctx"
fi

# ---- fixtures: rails not running, so routed rules never load ---------------
for case in \
  'enabled is false|{"pluginConfigs":{"rails":{"options":{"enabled":false}}}}' \
  'enabled is false|{"pluginConfigs":{"rails@skills-dir":{"options":{"enabled":false}}}}' \
  'disabled in enabledPlugins|{"enabledPlugins":{"rails@skills-dir":false}}' \
  'CLAUDE_CODE_ENABLE_FUNCTION_HOOKS is not|{"env":{}}'; do
  want="${case%%|*}"; extra="${case#*|}"
  off="$SCRATCH/rails-off.json"
  jq --argjson x "$extra" '. + $x' "$good" > "$off"
  ctx=$(HOOKS_PREFLIGHT_SETTINGS="$off" HOOKS_PREFLIGHT_LIB="$HOOKS_DIR/lib.sh" bash "$PREFLIGHT")
  if printf '%s' "$ctx" | rg -q "rails will not run \\([^)]*$want.*rules never load"; then
    ok "hooks-preflight: warns routed rules never load ($want)"
  else
    bad "hooks-preflight: no never-load warning for $want: $ctx"
  fi
done

# ---- fixture: rule_routing false, so routed rules are flushed --------------
off="$SCRATCH/routing-off.json"
jq '. + {pluginConfigs:{rails:{options:{rule_routing:false}}}}' "$good" > "$off"
ctx=$(HOOKS_PREFLIGHT_SETTINGS="$off" HOOKS_PREFLIGHT_LIB="$HOOKS_DIR/lib.sh" bash "$PREFLIGHT")
if printf '%s' "$ctx" | rg -q 'rule routing is off \(pluginConfigs.rails.options.rule_routing is false\).*flushed whole'; then
  ok "hooks-preflight: warns routed rules are flushed when rule_routing is false"
else
  bad "hooks-preflight: no flush warning for rule_routing false: $ctx"
fi
off="$SCRATCH/routing-off-id.json"
jq '. + {pluginConfigs:{"rails@skills-dir":{options:{rule_routing:false}}}}' "$good" > "$off"
ctx=$(HOOKS_PREFLIGHT_SETTINGS="$off" HOOKS_PREFLIGHT_LIB="$HOOKS_DIR/lib.sh" bash "$PREFLIGHT")
if printf '%s' "$ctx" | rg -q 'rule routing is off.*flushed whole'; then
  ok "hooks-preflight: reads rule_routing under the plugin id too"
else
  bad "hooks-preflight: missed rule_routing under rails@skills-dir: $ctx"
fi

# ---- fixtures: voice-guard disabled ------------------------------------------
for case in \
  'voice-guard@skills-dir is disabled in enabledPlugins|{"enabledPlugins":{"voice-guard@skills-dir":false}}' \
  'options.enabled is false|{"pluginConfigs":{"voice-guard":{"options":{"enabled":false}}}}' \
  'options.enabled is false|{"pluginConfigs":{"voice-guard@skills-dir":{"options":{"enabled":false}}}}' \
  'CLAUDE_CODE_ENABLE_FUNCTION_HOOKS is not|{"env":{}}'; do
  want="${case%%|*}"; extra="${case#*|}"
  off="$SCRATCH/voice-off.json"
  jq --argjson x "$extra" '. + $x' "$good" > "$off"
  ctx=$(HOOKS_PREFLIGHT_SETTINGS="$off" HOOKS_PREFLIGHT_LIB="$HOOKS_DIR/lib.sh" bash "$PREFLIGHT")
  if printf '%s' "$ctx" | rg -q "voice-guard will not run \\([^)]*$want"; then
    ok "hooks-preflight: names voice-guard when disabled ($want)"
  else
    bad "hooks-preflight: no voice-guard disabled warning for $want: $ctx"
  fi
done

# ---- fixtures: voice-guard load check (heartbeat.<session id>) ----------------
# Read last-session-id, compare to heartbeat.<that id>, THEN write the current id.
run_voice() { # run_voice <current session id>
  HOOKS_PREFLIGHT_SETTINGS="$good" HOOKS_PREFLIGHT_LIB="$HOOKS_DIR/lib.sh" HOOKS_PREFLIGHT_SESSION_ID="$1" HOOKS_PREFLIGHT_SOURCE="${2:-startup}" bash "$PREFLIGHT"
}

rm -rf "$HOOKS_PREFLIGHT_VOICE_STATE"; mkdir -p "$HOOKS_PREFLIGHT_VOICE_STATE"
ctx=$(run_voice sess-new)
if [ -z "$ctx" ] && [ "$(cat "$HOOKS_PREFLIGHT_VOICE_STATE/last-session-id")" = "sess-new" ]; then
  ok "hooks-preflight: first run (no last-session-id) is silent and records the id"
else
  bad "hooks-preflight: first run warned or did not record the id: $ctx"
fi

rm -rf "$HOOKS_PREFLIGHT_VOICE_STATE"; mkdir -p "$HOOKS_PREFLIGHT_VOICE_STATE"
printf 'sess-old\n' > "$HOOKS_PREFLIGHT_VOICE_STATE/last-session-id"
: > "$HOOKS_PREFLIGHT_VOICE_STATE/heartbeat.sess-old"
ctx=$(run_voice sess-new)
if [ -z "$ctx" ] && [ "$(cat "$HOOKS_PREFLIGHT_VOICE_STATE/last-session-id")" = "sess-new" ]; then
  ok "hooks-preflight: a matching heartbeat is silent"
else
  bad "hooks-preflight: a matching heartbeat warned: $ctx"
fi

rm -f "$HOOKS_PREFLIGHT_VOICE_STATE/heartbeat.sess-old"
printf 'sess-old\n' > "$HOOKS_PREFLIGHT_VOICE_STATE/last-session-id"
ctx=$(run_voice sess-new)
if printf '%s' "$ctx" | rg -q 'voice-guard did not load last session.*sess-old' \
   && [ "$(cat "$HOOKS_PREFLIGHT_VOICE_STATE/last-session-id")" = "sess-new" ]; then
  ok "hooks-preflight: a missing heartbeat for the recorded id names voice-guard, then records the new id"
else
  bad "hooks-preflight: missing heartbeat not named, or id not recorded: $ctx"
fi

# The id was written after the compare: the next run, still without a heartbeat for
# sess-new, warns about sess-new (not about sess-old again).
ctx=$(run_voice sess-newer)
if printf '%s' "$ctx" | rg -q 'no heartbeat for session sess-new in' && ! printf '%s' "$ctx" | rg -q 'sess-old'; then
  ok "hooks-preflight: the recorded id advances each run"
else
  bad "hooks-preflight: recorded id did not advance: $ctx"
fi

# /clear: the engine raises no session.start for it, so its id never gets a heartbeat.
# startup X, /clear to Y, startup Z: Z must not warn about Y.
rm -rf "$HOOKS_PREFLIGHT_VOICE_STATE"; mkdir -p "$HOOKS_PREFLIGHT_VOICE_STATE"
ctx=$(run_voice sess-x startup)
: > "$HOOKS_PREFLIGHT_VOICE_STATE/heartbeat.sess-x"
ctx_clear=$(run_voice sess-y clear)
ctx_z=$(run_voice sess-z startup)
if [ -z "$ctx_clear" ] && [ -z "$ctx_z" ] && [ "$(cat "$HOOKS_PREFLIGHT_VOICE_STATE/last-session-id")" = "sess-z" ]; then
  ok "hooks-preflight: startup X, /clear to Y, startup Z does not warn about Y"
else
  bad "hooks-preflight: /clear sequence warned or mis-recorded: clear=[$ctx_clear] z=[$ctx_z]"
fi

# source "clear" leaves last-session-id untouched.
printf 'sess-x\n' > "$HOOKS_PREFLIGHT_VOICE_STATE/last-session-id"
run_voice sess-y clear >/dev/null
if [ "$(cat "$HOOKS_PREFLIGHT_VOICE_STATE/last-session-id")" = "sess-x" ]; then
  ok "hooks-preflight: source clear does not record the id"
else
  bad "hooks-preflight: source clear overwrote last-session-id"
fi

# ---- fixture: the routed rules dir does not resolve --------------------------
ctx=$(HOOKS_PREFLIGHT_SETTINGS="$good" HOOKS_PREFLIGHT_LIB="$HOOKS_DIR/lib.sh" HOOKS_PREFLIGHT_ROUTED="$SCRATCH/no-such-routed" bash "$PREFLIGHT")
if printf '%s' "$ctx" | rg -q "no-such-routed does not resolve to a directory"; then
  ok "hooks-preflight: warns when the routed rules dir does not resolve"
else
  bad "hooks-preflight: no routed-dir warning: $ctx"
fi

# ---- bin/hooks-resolve with no arguments, against the repo as-is -----------
out=$("$RESOLVE" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  ok "hooks-resolve: no arguments, repo as-is, exits 0"
else
  bad "hooks-resolve: no arguments, repo as-is, rc=$rc: $out"
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
