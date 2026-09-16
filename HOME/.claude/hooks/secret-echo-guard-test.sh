#!/bin/bash
# secret-echo-guard-test.sh: fixture matrix for secret-echo-guard.sh.
#
# Each case feeds the hook a PreToolUse payload on stdin and asserts on whether
# a permissionDecision came back. Every fixture is inert text in THIS shell (the
# secret-shaped names are single-quoted or backslash-escaped), so running the
# matrix never expands anything.
#
# The deny cases are the leak vectors; the allow cases are the false positives
# the 2026-09-12 audit and staff review measured live, all three of which are
# forms the shell does not expand.
set -u
export LC_ALL=C

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
HOOK="$HOOKS/secret-echo-guard.sh"
. "$HOOKS/shapes.sh" || exit 1
pass=0
fail=0

run() { # run <expect deny|allow> <command>
  local expect="$1" cmd="$2" out decision
  out=$(jq -n --arg c "$cmd" --arg d "$PWD" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | bash "$HOOK")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  if [ "$decision" = "$expect" ]; then
    pass=$((pass + 1))
    printf 'PASS  [%s] %s\n' "$expect" "$cmd"
  else
    fail=$((fail + 1))
    printf 'FAIL  [want %s got %s] %s\n' "$expect" "$decision" "$cmd"
  fi
}

echo "=== the leak vectors deny ==="
run deny 'echo "$ANTHROPIC_API_KEY"'
run deny 'echo $OPENAI_API_KEY'
run deny 'echo ${GH_TOKEN:-x}'
run deny 'echo ${GH_TOKEN:?unset}'
run deny 'printf "%s\n" "$SLACK_BOT_TOKEN"'
run deny 'printenv AWS_SECRET_ACCESS_KEY'

echo "=== nested statements deny: the -c argument is a statement, not data ==="
run deny "bash -c 'echo \$SOME_TOKEN'"
run deny "sh -c 'echo \"\$GITHUB_PAT\"'"
run deny "zsh -c 'printenv GH_TOKEN'"
run deny 'echo "$(printenv GH_TOKEN)"'

echo "=== unexpanded forms allow: the shell leaks nothing here ==="
run allow "echo '\$SOME_TOKEN'"
run allow "printf '%s\n' '\\\$SOME_TOKEN'"
run allow "echo \\\$SOME_TOKEN"

echo "=== safe presence checks allow ==="
run allow 'echo "${GH_TOKEN:+present}"'
run allow 'echo "${GH_TOKEN+present}"'
run allow 'echo "${#GH_TOKEN}"'
run allow '[ -n "$GH_TOKEN" ] && echo present'
run allow '[ -z "$GH_TOKEN" ] && echo missing'
run allow 'if [ -n "$GH_TOKEN" ]; then echo present; fi'
run allow '[[ -n "$GH_TOKEN" ]] && echo present'

echo "=== the bracket test is only safe in command position ==="
run deny 'echo [ -n "$GH_TOKEN" ]'

echo "=== the _PAT anchor: five names ==="
run allow 'echo "$RIPGREP_CONFIG_PATH"'
run allow 'echo "$MY_PATTERN"'
run allow 'echo "$SOME_PATH"'
run deny 'echo "$GITHUB_PAT"'
run deny 'echo "$GITHUB_PAT_HOME"'

echo "=== prose that names a var is not an expansion ==="
run allow 'rg -n "GH_TOKEN" notes.md'
run allow 'echo hi # echo "$GH_TOKEN"'
run allow "$(printf "cat > notes.md <<%sEOF%s\nnever echo \"\$GH_TOKEN\" in a session\nEOF\n" "'" "'")"
run allow "$(printf 'cat > notes.md <<EOF\nnever echo it\nEOF\nrg -n never notes.md')"

echo "=== a combined short flag is still -c (audit MF3) ==="
# `bash -lc 'x'` runs x exactly as `bash -c 'x'` does, and the guard read only
# the exact token -c, so the body was neither yielded as a statement nor
# neutralized. Measured deny-to-allow against 8ee8f60.
run deny "bash -lc 'echo \$GH_TOKEN'"
run deny "sh -xc 'printenv GH_TOKEN'"
run deny "zsh -lec 'echo \$GITHUB_PAT'"

echo "=== a heredoc body bash EXPANDS is a leak; a quoted one is not (audit MF4) ==="
# The delimiter's quoting is the whole difference: <<EOF substitutes the value
# into the body before cat ever runs, <<'EOF' prints the ten characters.
run deny "$(printf 'cat <<EOF\n$GH_TOKEN\nEOF')"
run deny "$(printf 'cat > notes.md <<EOF\ntoken: ${GITHUB_TOKEN}\nEOF')"
run allow "$(printf "cat <<'EOF'\n\$GH_TOKEN\nEOF")"
run allow "$(printf 'cat <<EOF\nno secret named here\nEOF')"

echo "=== chunk B's hole: a single-quoted verb is still the verb ==="
# mask_squote erased the verb before an unanchored /\becho\b/ ever saw it, so
# 'echo' $GH_TOKEN allowed while "echo" $GH_TOKEN denied. The verb test is
# cmdword_is now, per statement. Asserted directly because shapes.sh:45 says a
# command carrying a single quote cannot ride the quoted wrapper shapes.
run deny "'echo' \$GH_TOKEN"
run deny "'printf' '%s' \$GH_TOKEN"
run deny "'printenv' GH_TOKEN"
run allow "echo '\$GH_TOKEN'"

runread() { # runread <expect deny|allow> <path>
  local expect="$1" path="$2" out decision
  out=$(jq -n --arg p "$path" \
    '{tool_name:"Read",tool_input:{file_path:$p}}' | bash "$HOOK")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  if [ "$decision" = "$expect" ]; then
    pass=$((pass + 1))
    printf 'PASS  [%s] Read %s\n' "$expect" "$path"
  else
    fail=$((fail + 1))
    printf 'FAIL  [want %s got %s] Read %s\n' "$expect" "$decision" "$path"
  fi
}

echo "=== aws secretsmanager: --query is not a safety predicate ==="
# The draft's fixture baked the leak in: --query SecretString SELECTS the
# decrypted value and is exactly what printed an xoxb- token on 06-23 and 06-25.
run deny  'aws secretsmanager get-secret-value --secret-id prod/slack'
run deny  'aws secretsmanager get-secret-value --secret-id prod/slack --query SecretString'
run deny  'aws secretsmanager get-secret-value --secret-id x --query SecretBinary --output text'
run allow 'aws secretsmanager get-secret-value --secret-id prod/slack --query ARN'
run allow 'aws secretsmanager get-secret-value --secret-id x --query Name --output text'
run allow 'aws secretsmanager get-secret-value --secret-id x --query=VersionId'
run deny  'aws secretsmanager get-secret-value --secret-id x --query CreatedDate --query SecretString'
run deny  'aws secretsmanager get-secret-value --secret-id x --query Tags'
run allow 'aws secretsmanager list-secrets'
run allow 'aws secretsmanager describe-secret --secret-id prod/slack'

echo "=== systemctl show-environment prints every value it has ==="
run deny  'systemctl --user show-environment'
run deny  'systemctl show-environment'
run allow 'systemctl --user status borg.service'
run allow 'systemctl --user restart cortex.service'

echo "=== readers that cannot project deny against a credential path ==="
run deny 'cat /run/user/1000/borg.env'
run deny 'cat ~/.cache/slack/token.json'
run deny 'cat "${XDG_CACHE_HOME:-$HOME/.cache}/slack/token.json"'
run deny 'head -5 ~/.zsh_history'
run deny 'tail -20 ~/.bash_history'
run deny 'strings ~/.config/marquee/tokens.json'
run deny 'xxd ~/.cache/okta/tokens.json'
run deny 'base64 ~/.config/eratosthenes/digest.env'
run deny "sed -n '1,5p' ~/.cache/okta/tokens.json"
run deny 'python3 -m json.tool ~/.cache/slack/token.json'

echo "=== jq: the WHOLE filter is matched, and has() takes an expression ==="
# The measured traffic against these paths is ~200 auth-debugging statements
# against 4 leaks, so the safe shapes have to keep working.
run allow 'jq .expires_at ~/.cache/slack/token.json'
run allow 'jq -r .expires_at ~/.cache/okta/tokens.json'
run allow "jq 'has(\"access_token\")' ~/.cache/slack/token.json"
run allow 'jq keys ~/.cache/slack/token.json'
run allow 'jq length ~/.config/marquee/tokens.json'
run allow "jq --arg k x 'has(\"refresh_token\")' ~/.cache/slack/token.json"
run deny  'jq .access_token ~/.cache/slack/token.json'
run deny  'jq . ~/.cache/slack/token.json'
run deny  "jq -r '.[]' ~/.cache/slack/token.json"
run deny  'jq to_entries ~/.cache/okta/tokens.json'
# Round 4's reproduction: the outer filter returns a boolean and the ARGUMENT
# prints the selected value to stderr.
run deny  "jq 'has(.access_token | debug)' ~/.cache/slack/token.json"
run deny  "jq 'has(\"access_token\") | debug' ~/.cache/slack/token.json"

echo "=== grep prints the matching LINE; a count and an exit code do not ==="
run deny  'grep access_token ~/.cache/slack/token.json'
run deny  'rg xoxp ~/.zsh_history'
run allow 'grep -c access_token ~/.cache/slack/token.json'
run allow 'grep -q access_token ~/.cache/slack/token.json'
run allow 'rg -q xoxp ~/.zsh_history'

echo "=== metadata and mutation carry no value ==="
run allow 'stat -c %a ~/.cache/slack/token.json'
run allow 'ls -l ~/.config/marquee/tokens.json'
run allow 'test -f ~/.cache/okta/tokens.json'
run allow 'wc -c ~/.cache/slack/token.json'
run allow 'rm -f ~/.cache/okta/tokens.json'
run allow 'chmod 600 ~/.cache/slack/token.json'

echo "=== a path that is not a credential artifact is not this rule's business ==="
run allow 'cat ~/notes.md'
run allow 'cat ~/repos/scottidler/claude/README.md'
run allow 'jq . ~/repos/scottidler/claude/HOME/.claude/settings.json'
run allow 'grep -n hook ~/repos/scottidler/claude/.otto.yml'

echo "=== the Read tool: the 06-16 leak never went through a shell ==="
runread deny  "$HOME/.config/fabric/.env"
runread deny  '/run/user/1000/borg.env'
runread deny  "$HOME/.cache/slack/token.json"
runread deny  "$HOME/.cache/okta/tokens.json"
runread deny  "$HOME/.zsh_history"
runread allow "$HOME/repos/scottidler/claude/README.md"
runread allow "$HOME/repos/scottidler/claude/HOME/.claude/settings.json"

echo "=== every leak holds in every shape bash offers ==="
runwrapped() { # runwrapped <command>
  local w
  while IFS= read -r w; do run deny "$w"; done < <(wrap_shapes "$1")
}
runwrapped 'echo $GH_TOKEN'
runwrapped 'printenv AWS_SECRET_ACCESS_KEY'
runwrapped 'cat /run/user/1000/borg.env'
runwrapped 'systemctl --user show-environment'
runwrapped 'aws secretsmanager get-secret-value --secret-id prod/slack'

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
