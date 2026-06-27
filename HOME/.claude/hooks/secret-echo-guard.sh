#!/bin/bash
# PreToolUse / Bash guard - COMPANION to the env redaction shim.
#
# Two-layer defense against leaking secret env vars into an LLM session
# transcript (which also lands in logs):
#
#   Layer 1 (binary)   ~/bin/env  ->  scottidler/helpful/bin/env.py
#       Redacts secret VALUES when `env` / `env --redact` is run inside an LLM
#       session. Installed via dotfiles/manifest.yml; ~/bin precedes /usr/bin on
#       PATH so a bare `env` resolves to it. Docs:
#       scottidler/helpful/docs/env-redaction-shim.md
#
#   Layer 2 (this hook) catches the vector Layer 1 STRUCTURALLY cannot: direct
#       shell expansion - echo "$SECRET", printf "$SECRET", and ${VAR:-default}
#       presence checks. That expansion happens in the shell builtin BEFORE any
#       binary on PATH runs, so there is no executable for the PATH shim to sit
#       in front of (see env-redaction-shim.md, gap #4 - the exact vector that
#       leaked ANTHROPIC_API_KEY / OPENAI_API_KEY on 2026-06-27).
#
# On a match this DENIES the Bash call and redirects back to Layer 1: use the
# redaction-shimmed `env` to inspect vars, and ${VAR:+present} (never ${VAR:-...})
# for presence-only checks.
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

reason=$(GUARD_CMD="$command" python3 <<'PY'
import os, re, sys

cmd = os.environ.get("GUARD_CMD", "")

# Distinctive secret-name components. Underscore-anchored _KEY/_PAT avoid PATH,
# "monkey", "compatible", etc. TOKEN/SECRET/PASSWORD/CREDENTIAL are distinctive
# on their own.
TOKENS = r"(?:SECRET|TOKEN|PASSWORD|PASSWD|CREDENTIAL|BEARER|HMAC|SIGNING|PRIVATE|APIKEY|_KEY|_PAT)"
NAME = rf"[A-Za-z0-9_]*{TOKENS}[A-Za-z0-9_]*"

# 1) Leaky parameter expansion of a secret var: ${NAME:-x} ${NAME-x}
#    ${NAME:=x} ${NAME=x} ${NAME:?} ${NAME?} all emit the VALUE when set.
#    The safe ${NAME:+x} / ${NAME+x} form is excluded ([-=?] only, not +).
if re.search(rf"\$\{{{NAME}:?[-=?]", cmd, re.IGNORECASE):
    print("leaky-substitution")
    sys.exit(0)

# Remove the SAFE alternate form ${NAME:+...} / ${NAME+...} before the print
# check, so the correct presence-check idiom is never flagged.
stripped = re.sub(rf"\$\{{{NAME}:?\+[^}}]*\}}", "", cmd, flags=re.IGNORECASE)

# 2) Printing a secret var directly: echo/printf with $NAME or ${NAME},
#    or printenv naming a secret var.
if re.search(rf"\b(?:echo|printf)\b[^\n;|&]*\$\{{?{NAME}", stripped, re.IGNORECASE):
    print("print-secret")
    sys.exit(0)
if re.search(rf"\bprintenv\b[^\n;|&]*{NAME}", stripped, re.IGNORECASE):
    print("printenv-secret")
    sys.exit(0)
PY
)

if [ -n "$reason" ]; then
    jq -n --arg reason "$reason" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: ("Blocked (\($reason)): this command would expand a secret-named env var into session output, which lands in the transcript and logs. Never echo/printf/printenv a secret, and never use ${VAR:-...} for a presence check (it prints the value when set). To INSPECT env vars, use the redaction-shimmed `env` (e.g. `env | grep -i NAME` or `env --redact`) — it masks secret values inside an LLM session. To check PRESENCE only, use ${VAR:+present} (the :+ form never emits the value).")
        }
    }'
    exit 0
fi
