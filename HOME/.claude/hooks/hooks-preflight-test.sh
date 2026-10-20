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
