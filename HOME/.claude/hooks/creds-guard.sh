#!/bin/bash
# creds-guard.sh: Stop / SubagentStop hook that blocks a final reply claiming
# the model cannot get AWS, kubectl or ArgoCD credentials, or handing Scott a
# login command, and sends the model back with the recipe it already has.
#
# WHY: 2026-11-23, tatari-tv/renovate. The model said both credentials had
# expired, told Scott to run `aws login`, and later said no ArgoCD server was
# known. Hindsight work bank and clyde session 17f77394 held the recipe all
# along: aws-vault device-code flow started in the background, link forwarded to
# Scott. Scott: "make a claude mod/hook that intercepts you every fucking time
# you say you dont know how to get creds for aws, k8s and/or argocd".
#
# WIRING: registered on Stop and SubagentStop in ~/.claude/settings.json. The
# harness pipes the stop payload to stdin; this script prints {} to let the turn
# end, or {"decision":"block","reason":...} to send the model back.
#
# FIRES when the final text has BOTH
#   subject   aws, aws-vault, kubectl, k8s, kubernetes, eks, argocd, sso
#   give-up   "can't/unable/don't know" near credentials or login, credentials
#             or a token or a session "expired/invalid/missing", NoCredentials,
#             or a hand-off to Scott: `aws login`, `aws sso login`,
#             `argocd login`, "you log in", "you need to log in"
# STANDS DOWN when the text carries the correct recipe, because forwarding the
# device-code link is exactly the right behavior: `user_code`, `--device-code`,
# or `tatari.awsapps.com/start`. Also stands down when the text names
# creds-guard (a reply about this hook), and when stop_hook_active is true
# (the model is already answering a block; the harness caps blocks at 8).
#
# CLI: creds-guard.sh --help | --self-test (creds-guard-test.sh, same directory)

case "${1:-}" in
  -h|--help)
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit 0
    ;;
  --self-test)
    exec bash "$(cd "$(dirname "$0")" && pwd)/creds-guard-test.sh"
    ;;
esac

payload=$(cat)
active=$(jq -r '.stop_hook_active // false' <<<"$payload" 2>/dev/null)
[ "$active" = "true" ] && { echo '{}'; exit 0; }

text=$(jq -r '.last_assistant_message // empty' <<<"$payload" 2>/dev/null)
[ -z "$text" ] && { echo '{}'; exit 0; }

# Every keyword is word-bounded: bare substrings matched eks in "weeks", sso in
# "lesson", auth in "author", session in "obsession", use in "because".
SUBJECT='\b(aws|kubectl|k8s|kubernetes|eks|argocd|sso)\b'
CREDWORD='(credentials?|creds|log ?in|auth|authenticat\w*|authori[sz]\w*|tokens?)\b'
GIVEUP="(\bNoCredentials\b|\bUnable to locate credentials"
GIVEUP="$GIVEUP|\b(can'?t|cannot|couldn'?t|unable to|do(n'?t| not) know|not able to|no way to)\b[^.]{0,80}\b$CREDWORD"
GIVEUP="$GIVEUP|\b(credentials?|creds|tokens?|sessions?|login|log in)\b[^.]{0,40}\b(expired|invalid|missing|not (found|available))\b"
GIVEUP="$GIVEUP|(\b(run|type|use)\b|!|\`)[ \`!]*\b(aws (sso )?login|argocd login)\b"
GIVEUP="$GIVEUP|\byou (need to |have to |must )?log ?in\b|\blog ?in (to|with|via) (aws|argocd|sso|the cluster)\b)"
RECIPE='(user_code|device.code|tatari\.awsapps\.com/start)'
# A reply that names this hook is discussing it, not giving up on credentials.
SELF='\bcreds-guard\b'

if grep -qiE "$RECIPE" <<<"$text"; then echo '{}'; exit 0; fi
if grep -qiE "$SELF" <<<"$text"; then echo '{}'; exit 0; fi
if grep -qiE "$SUBJECT" <<<"$text" && grep -qiE "$GIVEUP" <<<"$text"; then
  quoted=$(grep -iE "$GIVEUP" <<<"$text" | head -1 | cut -c1-200)
  reason="You do know how to get these credentials; the recipe is in memory (hindsight work bank, clyde session 17f77394). Offending line: \"$quoted\". Do this now, then continue the task:
- AWS: start the login yourself, never hand Scott a login command. Run, with run_in_background, a bare command that starts with aws-vault (no pipes, &&, \$(...), timeout prefix): aws-vault exec --device-code --stdout -d 12h prod -- true, output redirected to a file in the scratchpad. Poll that file for user_code, then give Scott the https://tatari.awsapps.com/start/#/device?user_code=XXXX-XXXX link. It works from any machine and lasts 12 hours.
- kubectl: prefix every call, aws-vault exec -d 12h prod -- kubectl --context <ctx> ... Context apps is dead (NXDOMAIN) and apps-1 is not in the kubeconfig: find it with eks list-clusters and build a scratch kubeconfig. Use describe secret, never get secret -o json.
- ArgoCD: prefer kubectl --context ops -n argocd-infra get application <app> through aws-vault (apps-1-renovate lives there, manual sync). The argocd CLI login is argocd login --sso, browser plus terminal, and needs the server address: recall it from hindsight or clyde before saying it is unknown.
- Before saying you do not know any of this, run mcp__hindsight-work__recall and mcp__clyde__sessions_search."
  jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
  exit 0
fi
echo '{}'
