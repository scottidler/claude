#!/bin/sh
# ssh-agent-check.sh - SessionStart: warn early if commit signing will fail.
#
# git commit is configured for SSH commit signing (gpg.format=ssh), and inside the
# Bash sandbox ssh-agent is NOT a fallback: the sandbox denies socket(AF_UNIX)
# creation outright (EPERM before any connect), so $SSH_AUTH_SOCK is unreachable
# and ssh-keygen -Y sign must read the private key file itself. Measured
# 2026-09-13, docs/design/2026-09-13-enforcement-core-phase0/evidence.md section 0f.
#
# So the thing to check is file readability of the ACTIVE signing key, both halves.
# The private half is readable in-sandbox only if it is listed in
# sandbox.filesystem.allowRead in settings.json.

pub=$(git config --get user.signingkey 2>/dev/null)

if [ -n "$pub" ]; then
    # git accepts a ~-prefixed path here; the shell does not expand it for us.
    case "$pub" in
        "~/"*) pub="$HOME/${pub#\~/}" ;;
    esac
    priv="${pub%.pub}"

    if [ ! -r "$pub" ]; then
        echo "WARN: signing key $pub is not readable -- \`git commit\` will fail. Add it to sandbox.filesystem.allowRead in settings.json."
    elif [ ! -r "$priv" ]; then
        echo "WARN: signing key $pub is readable but its private half $priv is not -- \`git commit\` will fail with \"No private key found for public key\". Add $priv to sandbox.filesystem.allowRead in settings.json."
    fi
fi

# Unrelated to signing: an unloaded agent still breaks unsandboxed pushes.
ssh-add -l >/dev/null 2>&1 || echo "WARN: no ssh key loaded in ssh-agent -- unsandboxed \`git push\` will prompt or fail."

exit 0
