#!/bin/bash
# terraform-apply-guard.sh: PreToolUse guard: the agent plans, Scott applies.
#
# Denies every Terraform / OpenTofu / Terragrunt invocation that mutates real
# infrastructure or its state: apply, destroy, import, taint, untaint,
# force-unlock, refresh, `state rm|mv|push|replace-provider`,
# `workspace delete`, the terragrunt `apply-all` / `destroy-all` spellings, and
# `-auto-approve` anywhere. `plan` (including `-destroy`, `-out`, `-lock=false`),
# `init`, `validate`, `fmt`, `show`, `output`, `state list|show|pull` pass.
#
# Why a hook and not a deny rule: a `Bash(terraform apply:*)` rule matches the
# invocation the model usually produces and is "not a security boundary" (Claude
# Code permissions docs). `terraform -chdir=x apply`, `/usr/bin/tofu apply` and
# `aws-vault exec p -- terraform apply` all slip past it. A rule also cannot
# carve out `terraform apply -help`, which must work. A hook's deny holds even
# under bypassPermissions, so the hook is the only layer and settings.json
# carries no terraform deny rules.
#
# Parsing is lib.sh's. `stmts` splits the command (a `bash -c` / `$( )` body
# arrives as a statement of its own, heredoc bodies arrive masked), then `args`
# gives one token per line with quotes already dropped. The tool word is found
# ANYWHERE in the statement, not only in command position, so a wrapper that
# lib.sh does not know (`aws-vault exec p --`, `op run --`) is stepped over.
# A quoted string stays ONE token, so `echo "terraform apply"` and
# `git commit -m "fix terraform apply"` are not false positives.
#
# Fails CLOSED on a mutating verb after a tool word: a false deny costs one
# human-run command, a false allow costs a production apply. Not covered, by
# design: `make apply`, `otto apply` and other wrappers that call terraform
# inside a script, and `ssh host 'terraform apply'` (the remote command is one
# quoted token). Plan-only credentials are the layer that covers those.
#
# Emits a PreToolUse "deny" decision (with a reason Claude sees), or passes through ({}).
. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
[ "$tool" = "Bash" ] || { echo '{}'; exit 0; }
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
[ -z "$cmd" ] && { echo '{}'; exit 0; }

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

is_tool() { # is_tool <token>: basename is terraform, tofu or terragrunt
  case "${1##*/}" in terraform | tofu | terragrunt) return 0 ;; esac
  return 1
}

# Echoes the mutating verb found after the tool word, or nothing. A help
# request is read-only: `-help` / `--help` / `-h` makes the tool print usage and
# exit before it parses anything else, and `terraform help apply` prints the same
# page, so neither is a mutation. `help` counts only as the first non-flag word
# after the tool, so `terraform apply help` (a plan file named help) is still
# a deny.
mutating_verb() {
  local seen=0 prev="" first="" tok
  local -a after=()
  while IFS= read -r tok; do
    if [ "$seen" = 0 ]; then
      is_tool "$tok" && seen=1
      continue
    fi
    after+=("$tok")
  done
  for tok in "${after[@]}"; do
    case "$tok" in -help | --help | -h) return 1 ;; esac
    case "$tok" in -*) ;; *) [ -z "$first" ] && first="$tok" ;; esac
  done
  [ "$first" = help ] && return 1
  for tok in "${after[@]}"; do
    case "$tok" in
      apply | destroy | import | taint | untaint | force-unlock | refresh | apply-all | destroy-all | -auto-approve | --auto-approve)
        printf '%s' "$tok"
        return 0
        ;;
    esac
    case "$prev:$tok" in
      state:rm | state:mv | state:push | state:replace-provider | workspace:delete)
        printf '%s %s' "$prev" "$tok"
        return 0
        ;;
    esac
    prev="$tok"
  done
  return 1
}

while IFS= read -r -d '' stmt; do
  masked=$(printf '%s' "$stmt" | mask_comment)
  verb=$(printf '%s' "$masked" | args | mutating_verb) || continue
  deny "Blocked: '$verb' on terraform/tofu/terragrunt mutates real infrastructure or state. The standing rule is that the agent plans and Scott applies. Run 'terraform plan -out=tfplan' (read-only), read the full plan, and hand it to Scott: he applies from his own terminal. Do not rephrase the command to get around this guard."
done < <(printf '%s' "$cmd" | stmts)

echo '{}'
exit 0
