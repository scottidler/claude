#!/bin/bash
# PreToolUse guard (Bash and Read) - COMPANION to the env redaction shim.
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
#
# ARTIFACT VECTORS (added with the SECRET rule). The env-var vectors above are
# only half of where a value comes from. The other half is a file, or a command
# that prints one, and all four below are measured leaks rather than guesses:
#
#   aws secretsmanager get-secret-value   an xoxb- bot token printed twice,
#                                         06-23 and 06-25
#   systemctl [--user] show-environment   an Anthropic key, 110 chars, 07-30,
#                                         in a SUBAGENT, after this guard existed
#   a shell history file                  an xoxp- user token, 78 chars, 09-07
#   a credential file                     sk-ant-, 108 chars, 06-16, through the
#                                         Read tool, which is why this hook is
#                                         registered on Read as well
#
# `--query` IS NOT A SAFETY PREDICATE, which is the trap in the obvious version
# of the aws rule: `--query SecretString` selects the decrypted value and is
# exactly what the 06-23 leak printed. Only projections that cannot carry a
# value are allowed, and a missing or unrecognized `--query` denies.
#
# THE PATH RULE IS A SPLIT, NOT A BLANKET DENY, because the measured traffic
# against these paths is about 200 auth-debugging statements against 4 leaks. A
# blanket deny is 200 denials for 4 catches and the tree learns to route around
# it. But "the shapes that print the whole file" is not an algorithm either:
# `jq 'has("access_token")'` must allow and `jq .access_token` must deny, and
# NEITHER prints the whole file. So the split is stated as a rule, and the
# default on an unrecognized shape is deny.
#
# THE jq ALLOWLIST MATCHES THE WHOLE FILTER STRING. A substring or containment
# test does not work here, because `has` takes an arbitrary expression:
#
#   $ printf '%s\n' '{"example":"visible"}' | jq 'has(.example | debug)'
#   ["DEBUG:","visible"]
#   false
#
# The outer filter returns a boolean and the ARGUMENT prints the selected value
# to stderr, straight past a rule whose entire purpose is that the value never
# prints. So the grammar is exact: a literal double-quoted string argument, no
# embedded pipeline, no expression, nothing before or after.
#
# Residual holes, named rather than patched blind: `Grep` and `Glob` over a
# credential path are not covered (a Grep result can carry the matching line),
# and no instance of either appears in the corpus.

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
. "$HOOKS/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }

deny_now() { # deny_now <reason>
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

input=$(cat)

# One jq spawn, not two. Every Bash call in every session pays this hook, and a
# second jq to read `tool_name` would cost about 23 ms of that on its own. The
# command rides base64 because it can carry newlines and tabs.
mapfile -t payload < <(printf '%s' "$input" | jq -r '
  (.tool_name // ""),
  ((.tool_input.command // "") | @base64),
  (.tool_input.file_path // "")' 2>/dev/null)
tool="${payload[0]:-}"
read_path="${payload[2]:-}"

# The measured credential artifacts on this machine, as patterns rather than
# literals because 37 of the 77 statements touching the Slack token spell it
# `${XDG_CACHE_HOME:-$HOME/.cache}/slack/token.json` rather than with a `~`. The
# `.env` entry is wider than the design's `/run/user/*/*.env` plus
# `~/.config/*/*.env`: the 06-16 leak was a `.env` read through the Read tool,
# and the design's own evidence row calls that glob incomplete.
path_is_secret() { # path_is_secret <token>
  case "$1" in
    *token.json|*tokens.json) return 0 ;;
    *.env) return 0 ;;
    *.bash_history|*.zsh_history|*.histfile) return 0 ;;
  esac
  return 1
}

SECRET_PATH_HELP="These files hold credential VALUES: token.json / tokens.json, /run/user/*/*.env, ~/.config/*/*.env and the shell history files. To check one WITHOUT printing a value: stat or ls -l for mode and mtime, jq 'has(\"access_token\")' for presence, jq .expires_at for expiry, grep -c or grep -q for a match count."

# ------------------------------------------------------------- the Read tool ---
#
# The Read matcher is the half of this rule Bash cannot cover: the 06-16 leak
# never went through a shell. Phase 0 measured both unknowns live, a
# `"matcher": "Read"` block DOES fire and its deny DOES beat `Read(**)` sitting
# in `permissions.allow`, so this is a seam rather than an assumption.
if [ "$tool" = "Read" ]; then
  if [ -n "$read_path" ] && path_is_secret "$read_path"; then
    deny_now "Blocked (read-secret-file): $read_path holds credential values, and reading it puts them in the transcript. That is the 06-16 leak exactly: sk-ant-, 108 characters, through this tool. $SECRET_PATH_HELP"
  fi
  echo '{}'
  exit 0
fi

command=$(printf '%s' "${payload[1]:-}" | base64 -d 2>/dev/null)
[ -z "$command" ] && { echo '{}'; exit 0; }

# ---------------------------------------------------- the artifact vectors ---

# verb_of <statement> <verb>...  -> prints the matching verb, or nothing
#
# `cmdword_is` answers "is the command word X" and lib.sh has no mode that
# PRINTS the command word, so the verb is found by asking. Each ask is a
# subprocess, so the candidate is pre-filtered on the text first, and this runs
# only for a statement that already named a credential artifact.
verb_of() {
  local stmt="$1" v
  shift
  for v in "$@"; do
    case "$stmt" in *"$v"*) ;; *) continue ;; esac
    if printf '%s' "$stmt" | cmdword_is "$v" >/dev/null 2>&1; then
      printf '%s' "$v"
      return 0
    fi
  done
  return 1
}

# Readers that cannot project: there is no safe form of pointing one of these at
# a credential file, so they deny outright.
# `tee` is deliberately NOT here: its operand is a file it WRITES, never one
# it reads.
PRINTERS="cat strings head tail less more xxd base64 sed awk perl od hexdump cut tr nl paste sort uniq"
# Metadata readers: mode, size, mtime, existence, byte count. No value.
METADATA="stat ls test [ wc file du realpath readlink basename dirname"
# Mutators: they move or destroy the file without printing it.
MUTATORS="rm mv cp chmod chown touch ln mkdir install shred rkvr"
# Verbs whose arguments are TEXT or whose effect is not printing a file.
# `echo "no slack token.json"` names a credential file in prose and reads
# nothing; `source <file>` loads it into the environment, where the env-var half
# of this guard covers what happens next. 10 of 108 corpus denies were these.
NONREADERS="echo printf source eval export set unset true false : tee"
MATCHERS="grep rg egrep fgrep ag"
PROJECTORS="jq yq"

# jq/yq flags that consume one or two following tokens, so a flag's operand is
# never mistaken for the filter.
JQ_FLAGS2=" --arg --argjson --slurpfile --rawfile "
JQ_FLAGS1=" --indent -f --from-file "

# jq_filter_is_safe <filter>
#
# The WHOLE string is matched. The dotted keys are the non-secret ones the
# measured auth-debugging traffic actually reads.
jq_filter_is_safe() {
  case "$1" in
    keys|keys_unsorted|type|length|paths) return 0 ;;
    .expires_at|.created_at|.scope|.token_type|.account) return 0 ;;
  esac
  printf '%s' "$1" | grep -qE '^has\("[A-Za-z0-9_.@-]+"\)$' && return 0
  return 1
}

# artifact_verdict <verbscan> -> prints a deny code, or nothing
artifact_verdict() {
  local stmt="$1" verb filter q i n k tok hit seen_verb pattern seen_pattern
  local -a toks optoks
  mapfile -t toks < <(printf '%s' "$stmt" | args)
  n=${#toks[@]}

  if printf '%s' "$stmt" | cmdword_is aws >/dev/null 2>&1; then
    case "$stmt" in
      *get-secret-value*)
        # The projection is parsed here rather than with `flag_value`, which
        # returns its FIRST match while the aws CLI honours the LAST: measured,
        # `--query ARN --query SecretString` reads as ARN and executes as
        # SecretString. Same defect class as `gh api -X GET -X DELETE`.
        # An absent or unrecognized projection denies, because the DEFAULT
        # output carries SecretString: "no --query" is the leak, not the safe
        # case.
        q=""
        for ((k = 0; k < n; k++)); do
          case "${toks[$k]}" in
            --query) q="${toks[$((k + 1))]}" ;;
            --query=*) q="${toks[$k]#*=}" ;;
          esac
        done
        case "$(printf '%s' "$q" | tr 'A-Z' 'a-z')" in
          arn|name|versionid|createddate) ;;
          *) printf '%s' "aws-secret-value"; return 0 ;;
        esac
        ;;
    esac
  fi

  if printf '%s' "$stmt" | cmdword_is systemctl >/dev/null 2>&1; then
    case "$stmt" in
      *show-environment*) printf '%s' "systemctl-environment"; return 0 ;;
    esac
  fi

  # A statement with no command word cannot read anything. Measured over the
  # 299-command corpus: a bare assignment (`C="$HOME/.cache/slack/token.json"`),
  # a `for` header and a `case` arm account for 21 of 108 denies on their own,
  # and not one of them runs a command at all.
  # The splitter leaves the keyword attached (`if true; then cat f; fi` yields
  # `then cat f`), so the keywords come off first. Bailing on a LEADING keyword
  # instead would have allowed the whole `if`/`for`/`while` half of the
  # wrapper sweep, which is where this was caught.
  local -a head=("${toks[@]}")
  while [ "${#head[@]}" -gt 0 ]; do
    case "${head[0]}" in
      if|then|else|elif|fi|do|done|while|until|case|esac|time|\!) head=("${head[@]:1}") ;;
      *) break ;;
    esac
  done
  case "${head[0]:-}" in
    [A-Za-z_]*=*) return 1 ;;
    for) return 1 ;;
  esac

  # Everything below needs a credential path as a READ OPERAND, which is why
  # redirect targets come out first: `printf ... > digest.env` and `: >
  # digest.env` WRITE the file, and a write is not this rule's subject. Same
  # `sed` the LN rule uses for the same reason.
  mapfile -t optoks < <(printf '%s' "$stmt" \
    | sed -E 's/[0-9]*>>?&?[^[:space:]]*//g' | args)
  hit=""
  for tok in "${optoks[@]}"; do
    if path_is_secret "$tok"; then hit="$tok"; break; fi
  done
  [ -z "$hit" ] && return 1

  verb_of "$stmt" $METADATA $MUTATORS $NONREADERS >/dev/null && return 1

  if verb=$(verb_of "$stmt" $PROJECTORS); then
    i=0
    filter=""
    seen_verb=0
    while [ "$i" -lt "$n" ]; do
      tok="${toks[$i]}"
      i=$((i + 1))
      if [ "$seen_verb" -eq 0 ]; then
        case "$tok" in "$verb"|"\\$verb"|*/"$verb") seen_verb=1 ;; esac
        continue
      fi
      if [ "${tok:0:1}" = "-" ]; then
        case "$JQ_FLAGS2" in *" $tok "*) i=$((i + 2)); continue ;; esac
        case "$JQ_FLAGS1" in *" $tok "*) i=$((i + 1)); continue ;; esac
        continue
      fi
      filter="$tok"
      break
    done
    jq_filter_is_safe "$filter" && return 1
    printf '%s' "projector-filter"
    return 0
  fi

  if verb=$(verb_of "$stmt" $MATCHERS); then
    # A match prints the matching LINE, which is the credential. A count and an
    # exit code carry nothing.
    case " ${optoks[*]} " in
      *" -c "*|*" -q "*|*" --count "*|*" --quiet "*) return 1 ;;
    esac
    # The FIRST non-flag operand is the PATTERN, not a file. 14 of 108 corpus
    # denies were `grep -rln "...tokens.json..." --include=*.md`, where the only
    # credential-shaped token was the search string and no credential file was
    # opened at all.
    seen_verb=0
    pattern=""
    for tok in "${optoks[@]}"; do
      if [ "$seen_verb" -eq 0 ]; then
        case "$tok" in "$verb"|"\\$verb"|*/"$verb") seen_verb=1 ;; esac
        continue
      fi
      [ "${tok:0:1}" = "-" ] && continue
      pattern="$tok"
      break
    done
    hit=""
    seen_pattern=0
    for tok in "${optoks[@]}"; do
      if [ "$seen_pattern" -eq 0 ] && [ "$tok" = "$pattern" ]; then seen_pattern=1; continue; fi
      [ "$seen_pattern" -eq 1 ] && path_is_secret "$tok" && { hit="$tok"; break; }
    done
    [ -z "$hit" ] && return 1
    printf '%s' "matcher-line"
    return 0
  fi

  verb_of "$stmt" $PRINTERS >/dev/null && { printf '%s' "print-secret-file"; return 0; }

  # An unrecognized verb against a credential path. Fail closed: the reason this
  # rule is a split rather than a blanket deny is that the SAFE shapes are
  # enumerable, and a shape not on the list has not been measured.
  printf '%s' "unknown-reader"
  return 0
}

# One masked statement per line, so the matcher's [^\n;|&]* windows cannot
# straddle two statements and the safe-form anchors below mean "statement start".
scan=""
prints=""
printenvs=""
while IFS= read -r -d '' stmt; do
  masked=$(printf '%s' "$stmt" | mask_heredoc | mask_comment | mask_squote)
  scan="$scan$masked
"
  verbscan=""

  # The artifact pre-filter: the same shape, and for the same reason, as the
  # secret-name superset below. A `case` costs nothing, and a statement naming
  # none of these artifacts cannot deny on any of the four vectors.
  # Gated on `verbscan`, NOT `$masked`. `$masked` has mask_squote applied, so a
  # single-quoted credential path is erased before the pre-filter sees it and the
  # whole artifact branch is skipped: `cat '<path>/token.json'` allowed while the
  # bare and double-quoted forms denied. The branch below already reads verbscan.
  verbscan=$(printf '%s' "$stmt" | mask_heredoc | mask_comment)
  case "$verbscan" in
    *get-secret-value*|*show-environment*|*.env*|*token.json*|*tokens.json*|*_history*)
      artifact=$(artifact_verdict "$verbscan")
      case "$artifact" in
        aws-secret-value)
          deny_now "Blocked (aws-secret-value): get-secret-value prints the decrypted secret, and --query SecretString SELECTS that value rather than hiding it (it is what leaked an xoxb- bot token on 06-23 and 06-25). Project something that cannot carry a value: --query ARN, Name, VersionId or CreatedDate." ;;
        systemctl-environment)
          deny_now "Blocked (systemctl-environment): show-environment prints every variable in the manager environment WITH its value, which leaked a 110-character Anthropic key on 07-30. For one variable's presence use \${VAR:+present}; to inspect the set use the redaction-shimmed \`env\`." ;;
        print-secret-file|unknown-reader)
          deny_now "Blocked (read-secret-file): this reads a file holding credential values into the transcript. $SECRET_PATH_HELP" ;;
        projector-filter)
          deny_now "Blocked (projector-filter): against these files only a filter that cannot emit a value is allowed, and this one is not on the list. The whole filter must be one of: has(\"key\"), keys, keys_unsorted, type, length, paths, .expires_at, .created_at, .scope, .token_type, .account. has() takes an EXPRESSION, so has(.access_token | debug) prints the value to stderr; the argument has to be a literal string." ;;
        matcher-line)
          deny_now "Blocked (matcher-line): a grep or rg match prints the matching LINE, which is the credential itself. Use -c for a count or -q for an exit code. $SECRET_PATH_HELP" ;;
      esac
      ;;
  esac

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
  [ -z "$verbscan" ] && verbscan=$(printf '%s' "$stmt" | mask_heredoc | mask_comment)
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
