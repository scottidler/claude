#!/bin/sh
# manifest-scope-guard.sh — PreToolUse: deny an unscoped `manifest` invocation.
#
# `manifest` has no `apply` subcommand -- the root command IS the apply, and
# scoping is done entirely via glob flags (-l/-p/-a/-d/-n/-P/-x/--uv-tool/-f/
# -c/-g/-G/-s). Running bare `manifest` (or `manifest .`) with none of those
# applies the ENTIRE manifest.yml unscoped -- exactly the "applied the
# dotfiles manifest unscoped, causing unintended system changes" failure Scott
# hit. Deny it; require an explicit scope flag, `age`/`secrets` subcommands,
# or --help/--version.

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
[ -z "$cmd" ] && { echo '{}'; exit 0; }

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

split=$(printf '%s' "$cmd" | sed -E 's/&&/\n/g; s/\|\|/\n/g; s/;/\n/g; s/\|/\n/g')
while IFS= read -r stmt; do
  [ -z "$stmt" ] && continue
  printf '%s' "$stmt" | grep -Eq '(^|[[:space:]])manifest([[:space:]]|$)' || continue
  printf '%s' "$stmt" | grep -Eq -- '(^|[[:space:]])(age|secrets|help|--help|-h|--version|-V)([[:space:]]|$)' && continue
  printf '%s' "$stmt" | grep -Eq -- '(-l|--link|-p|--ppa|-a|--apt|-d|--dnf|-n|--npm|-P|--pip3|-x|--pipx|--uv-tool|-f|--flatpak|-c|--cargo|-g|--github|-G|--git-crypt|-s|--script)([[:space:]=]|$)' && continue
  deny "Blocked: bare \`manifest\` with no scope flag applies the WHOLE manifest.yml unscoped. Target the specific entry, e.g. \`manifest -l some-dotfile\`."
done <<EOF
$split
EOF

echo '{}'
exit 0
