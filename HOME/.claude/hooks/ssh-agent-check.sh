#!/bin/sh
# ssh-agent-check.sh — SessionStart: warn early if commit signing will fail.
#
# git commit is configured for SSH commit signing (gpg.format=ssh). If no key
# is loaded in ssh-agent, the first `git commit` fails mid-task with a cryptic
# "Couldn't load public key ... No such file or directory" — and the sandbox
# denies reading ~/.ssh outright, so the failure looks like a missing-file bug
# rather than "no key loaded" or "sandboxed". Surface it once, up front.

ssh-add -l >/dev/null 2>&1 || echo "WARN: no ssh key loaded in ssh-agent -- \`git commit\` will fail until a key is loaded (also remember: the sandbox denies reading ~/.ssh, so commits need the sandbox disabled)."
exit 0
