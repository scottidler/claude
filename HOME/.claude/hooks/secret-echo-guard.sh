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
#       in front of (see env-redaction-shim.md, gap #4, the exact vector that
#       leaked ANTHROPIC_API_KEY / OPENAI_API_KEY on 2026-06-27).
#
# On a match this DENIES the Bash call and redirects back to Layer 1: use the
# redaction-shimmed `env` to inspect vars, and ${VAR:+present} (never ${VAR:-...})
# for presence-only checks.
#
# Parsing: `stmts` from lib.sh splits the command and yields every nested
# statement (subshell bodies and `bash -c` arguments), and each statement is
# masked with heredoc, comment, single-quote and escaped-`$` masking before the
# match. This guard deliberately does NOT mask DOUBLE quotes: bash expands $VAR
# inside "..." and not inside '...', so the double-quoted form is the exact
# vector this hook exists to catch while the single-quoted and backslash-escaped
# forms cannot leak anything. It is the one guard that deviates from the shared
# bare-word masker set, and the deviation is the shell's own semantics. For the
# same reason it takes a second input, `heredoc_expanded`: the bodies bash
# substitutes into before running anything, which the shared masker erases.
. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')
[ -z "$command" ] && { echo '{}'; exit 0; }

# One masked statement per line, so the matcher's [^\n;|&]* windows cannot
# straddle two statements and the safe-form anchors below mean "statement start".
scan=""
prints=""
printenvs=""
while IFS= read -r -d '' stmt; do
  masked=$(printf '%s' "$stmt" | mask_heredoc | mask_comment | mask_squote)
  scan="$scan$masked
"
  # Resolving the command word costs a subprocess per verb, so it runs only for
  # a statement that could possibly deny. This pattern is a deliberate SUPERSET
  # of the Python NAME regex below: every name that matcher fires on contains
  # one of these tokens, so skipping a statement without them cannot lose a
  # deny. Measured: ungated, the per-statement cmdword calls added 45 ms per
  # Bash call on a 3-statement command, against a 250 ms whole-chunk budget.
  case "$masked" in
    *[Ss][Ee][Cc][Rr][Ee][Tt]*|*[Tt][Oo][Kk][Ee][Nn]*|*[Pp][Aa][Ss][Ss][Ww][Dd]*|\
    *[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]*|*[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll]*|\
    *[Bb][Ee][Aa][Rr][Ee][Rr]*|*[Hh][Mm][Aa][Cc]*|*[Ss][Ii][Gg][Nn][Ii][Nn][Gg]*|\
    *[Pp][Rr][Ii][Vv][Aa][Tt][Ee]*|*[Aa][Pp][Ii][Kk][Ee][Yy]*|*_[Kk][Ee][Yy]*|*_[Pp][Aa][Tt]*) ;;
    *) continue ;;
  esac

  # The command-word test runs on a heredoc/comment-masked copy ONLY, never a
  # quote-masked one: mask_squote erases the verb itself, so an unanchored
  # `\becho\b` regex saw nothing in `'echo' $GH_TOKEN` and allowed it while
  # `"echo" $GH_TOKEN` denied. That was chunk B's open hole, and it is why the
  # verb test is cmdword_is here instead of a regex in the Python matcher.
  verbscan=$(printf '%s' "$stmt" | mask_heredoc | mask_comment)
  if printf '%s' "$verbscan" | cmdword_is echo >/dev/null 2>&1 \
  || printf '%s' "$verbscan" | cmdword_is printf >/dev/null 2>&1; then
    prints="$prints$masked
"
  fi
  if printf '%s' "$verbscan" | cmdword_is printenv >/dev/null 2>&1; then
    printenvs="$printenvs$masked
"
  fi
done < <(printf '%s' "$command" | stmts)

# The one place the h/H heredoc split is visible. A heredoc body whose delimiter
# is UNQUOTED is expanded by bash before the command ever runs, so
# `cat <<EOF` / `$GH_TOKEN` / `EOF` prints the secret to the transcript, which is
# this hook's whole subject. `cat <<'EOF'` prints the ten literal characters and
# stays inert. `mask_heredoc` erases both kinds (a heredoc body is never a
# command, which is the false-positive class the other guards need), so the
# expanded bodies arrive here as their own input instead (audit MF4).
heredocs=$(printf '%s' "$command" | heredoc_expanded)

reason=$(GUARD_CMD="$scan" GUARD_HEREDOC="$heredocs" GUARD_PRINTS="$prints" GUARD_PRINTENV="$printenvs" python3 <<'PY'
import os, re, sys

cmd = os.environ.get("GUARD_CMD", "")
heredoc = os.environ.get("GUARD_HEREDOC", "")
prints = os.environ.get("GUARD_PRINTS", "")
printenvs = os.environ.get("GUARD_PRINTENV", "")

# Distinctive secret-name components. Underscore-anchored _KEY/_PAT avoid PATH,
# "monkey", "compatible", etc. TOKEN/SECRET/PASSWORD/CREDENTIAL are distinctive
# on their own. _PAT carries a negative lookahead because the NAME tail below
# would otherwise let it swallow the H of RIPGREP_CONFIG_PATH and the TERN of
# _PATTERN; GITHUB_PAT and GITHUB_PAT_HOME still match, since neither is
# followed by a letter.
TOKENS = r"(?:SECRET|TOKEN|PASSWORD|PASSWD|CREDENTIAL|BEARER|HMAC|SIGNING|PRIVATE|APIKEY|_KEY|_PAT(?![A-Za-z]))"
NAME = rf"[A-Za-z0-9_]*{TOKENS}[A-Za-z0-9_]*"

# 1) Leaky parameter expansion of a secret var: ${NAME:-x} ${NAME-x}
#    ${NAME:=x} ${NAME=x} ${NAME:?} ${NAME?} all emit the VALUE when set.
#    The safe ${NAME:+x} / ${NAME+x} form is excluded ([-=?] only, not +).
if re.search(rf"\$\{{{NAME}:?[-=?]", cmd, re.IGNORECASE):
    print("leaky-substitution")
    sys.exit(0)

# Remove the SAFE forms before the print check, so a correct presence-check
# idiom is never flagged: ${NAME:+...}, ${#NAME} (a length, never the value),
# and a [ -n "$NAME" ] / [ -z "$NAME" ] test. The test form is anchored to the
# start of a statement so that `echo [ -n "$NAME" ]`, which WOULD print the
# value, is not stripped into an allow.
stripped = re.sub(rf"\$\{{{NAME}:?\+[^}}]*\}}", "", prints, flags=re.IGNORECASE)
stripped = re.sub(rf"\$\{{#{NAME}\}}", "", stripped, flags=re.IGNORECASE)
stripped = re.sub(
    rf"(?m)^[ \t]*(?:if|elif|while|until)?[ \t]*\[\[?[ \t]+-[nz][ \t]+\"?\$\{{?{NAME}\}}?\"?[ \t]+\]\]?",
    "",
    stripped,
    flags=re.IGNORECASE,
)

# 2) Printing a secret var directly. The VERB is no longer matched here: the
#    shell above already selected the statements whose command word is echo,
#    printf or printenv, using lib.sh's structural cmdword walk. All that is
#    left is the payload, and it is matched on the squote-masked copy so
#    `echo '$GH_TOKEN'` stays an allow.
if re.search(rf"\$\{{?{NAME}", stripped, re.IGNORECASE):
    print("print-secret")
    sys.exit(0)
if re.search(NAME, printenvs, re.IGNORECASE):
    print("printenv-secret")
    sys.exit(0)

# 3) A secret var referenced in a heredoc body bash EXPANDS. No command check:
#    the substitution has already happened by the time any command sees the
#    body, so `cat` prints it, `tee` prints and writes it, and a redirect
#    writes it to a file. Every one of those is a place the value must not go.
if re.search(rf"\$\{{?{NAME}", heredoc, re.IGNORECASE):
    print("heredoc-secret")
    sys.exit(0)
PY
)

if [ -n "$reason" ]; then
    jq -n --arg reason "$reason" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: ("Blocked (\($reason)): this command would expand a secret-named env var into session output, which lands in the transcript and logs. Never echo/printf/printenv a secret, and never use ${VAR:-...} for a presence check (it prints the value when set). To INSPECT env vars, use the redaction-shimmed `env` (e.g. `env | grep -i NAME` or `env --redact`): it masks secret values inside an LLM session. To check PRESENCE only, use ${VAR:+present} (the :+ form never emits the value).")
        }
    }'
    exit 0
fi

echo '{}'
exit 0
