#!/bin/bash
# manifest-scope-guard.sh: PreToolUse: deny an unscoped `manifest` invocation.
#
# `manifest` has no `apply` subcommand: the root command IS the apply, and
# scoping is done entirely via glob flags (-l/-p/-a/-d/-n/-P/-x/--uv-tool/-f/
# -c/-g/-G/-s). Running bare `manifest` (or `manifest .`) with none of those
# applies the ENTIRE manifest.yml unscoped, exactly the "applied the dotfiles
# manifest unscoped, causing unintended system changes" failure Scott hit. Deny
# it; require an explicit scope flag, `age`/`secrets` subcommands, or
# --help/--version.
#
# Parsing is the shared bare-word set from lib.sh: `stmts` splits (yielding
# subshell and `bash -c` bodies as statements of their own), then heredoc,
# single-quote, double-quote and comment masking, then `cmdword_is manifest`.
# This guard DOES mask double quotes, because a bare word inside "..." is data
# and never a command word; `secret-echo-guard.sh` is the one guard that must
# not mask them, since that is where the shell expands.
. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
[ -z "$cmd" ] && { echo '{}'; exit 0; }

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

while IFS= read -r -d '' stmt; do
  masked=$(printf '%s' "$stmt" | mask_heredoc | mask_squote | mask_dquote | mask_comment)
  # The command word is read WITHOUT the quote maskers: `"manifest" -l x` is the
  # manifest command, quoting and all, and a masked verb reads as no verb at all
  # (audit CW1). Nothing is lost by that, because what keeps
  # `echo "=== manifest entry ==="` out is the anchor and not the masking: the
  # command word there is echo. The quote-masked copy stays the input to the
  # scope-flag and exemption matches below, where a quoted flag is not a flag.
  printf '%s' "$stmt" | mask_heredoc | mask_comment | cmdword_is manifest || continue
  printf '%s' "$masked" | grep -Eq -- '(^|[[:space:]])(age|secrets|help|--help|-h|--version|-V)([[:space:]]|$)' && continue
  printf '%s' "$masked" | grep -Eq -- '(-l|--link|-p|--ppa|-a|--apt|-d|--dnf|-n|--npm|-P|--pip3|-x|--pipx|--uv-tool|-f|--flatpak|-c|--cargo|-g|--github|-G|--git-crypt|-s|--script)([[:space:]=]|$)' && continue
  deny "Blocked: bare \`manifest\` with no scope flag applies the WHOLE manifest.yml unscoped. Target the specific entry, e.g. \`manifest -l some-dotfile\`."
done < <(printf '%s' "$cmd" | stmts)

echo '{}'
exit 0
