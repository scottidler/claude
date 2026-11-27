#!/bin/bash
# creds-guard-test.sh: regression matrix for creds-guard.sh.
# Feeds synthetic Stop payloads and asserts block or allow. Exits non-zero on
# any failure. Run directly, or via: creds-guard.sh --self-test
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/creds-guard.sh"
pass=0
fail=0

# expect <block|allow> <label> <final text> [stop_hook_active]
expect() {
  local want="$1" label="$2" text="$3" active="${4:-false}" out got
  out=$(jq -nc --arg t "$text" --argjson a "$active" '{last_assistant_message:$t,stop_hook_active:$a}' | bash "$HOOK")
  got=allow
  [[ "$out" == *'"decision":"block"'* ]] && got=block
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL [$label]: want $want, got $got"
  fi
}

# The three real give-ups from 2026-11-23 must block.
expect block "tell Scott to run aws login" 'Run `aws login`, and then I can check the kubectl context.'
expect block "both expired" 'I cannot confirm the sync: the argocd refresh token is invalid and kubectl returned NoCredentials from aws.'
expect block "two credentials expired" 'Two credentials expired: the ArgoCD CLI login and the AWS session. Fix: argocd login.'
expect block "no server address" 'I do not know the ArgoCD server address, so I cannot log in.'
expect block "NoCredentials alone" 'kubectl --context apps failed: aws: NoCredentials.'
expect block "you log in" 'Please log in to AWS so I can run kubectl.'
expect block "sso login handoff" 'Type ! aws sso login --profile prod and tell me when done.'

# The correct recipe must pass: forwarding the device-code link.
expect allow "device-code link" 'AWS login started. Approve https://tatari.awsapps.com/start/#/device?user_code=ABCD-EFGH, then I run kubectl.'
expect allow "recipe command named" 'Starting aws-vault exec --device-code --stdout -d 12h prod -- true in the background.'

# 2026-11-23 false positive: a status line that reports a SUCCESSFUL login.
expect allow "login worked, device-code prose" 'Anchor: ArgoCD app apps-1-renovate, context ops. AWS login worked through the device-code flow.'
expect allow "bare AWS login mention" 'The AWS login lasts 12 hours and kubectl runs under it.'

# Unrelated text must pass.
expect allow "no subject" 'The tests passed, 12 of 12.'
expect allow "subject, no give-up" 'The aws-vault session lasts 12 hours and kubectl runs under it.'
expect allow "give-up, no subject" 'I cannot find the token in the config file; it expired in the parser.'

# Substring false positives: each blocks against the unbounded matcher.
expect allow "eks inside weeks" 'The token expired about two weeks ago.'
expect allow "sso inside lesson" 'The lesson: billing is cheap but the creds file was missing.'
expect allow "auth inside author, eks inside weeks" 'I cannot reach the author of that commit; he left weeks ago.'
expect allow "session inside obsession, eks inside weeks" 'The obsession with caching went missing for weeks.'
expect allow "use inside because" 'Billing jumped because aws login events doubled.'

# A reply that quotes this hook's own header is about the hook, not a give-up.
expect allow "quotes hook header" "$(bash "$HOOK" --help | sed -n '1,3p')"

# Word boundaries must not cost the true positives.
expect block "aws-vault still a subject" 'aws-vault said the session expired, so I cannot continue.'
expect block "plural credentials" 'I cannot get the credentials for the eks cluster.'

# Pass-throughs.
expect allow "stop_hook_active" 'Run `aws login`.' true
expect allow "empty text" ''

echo "creds-guard-test: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
