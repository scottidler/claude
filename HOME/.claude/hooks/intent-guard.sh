#!/bin/bash
# intent-guard.sh: PreToolUse(Bash) guard for outward and irreversible actions
# that are Scott's to take, not an agent's.
#
# One hook, several rules, because the alternative measured worse: six hooks
# each pay a process spawn on every Bash call, and the tree already spends
# ~510 ms per call across ten guards. Rules are independent; the first deny
# wins and nothing after it runs.
#
# EVERY RULE MATCHES ON `stmts` OUTPUT FROM A MASKED COPY, never on the raw
# command. Observed live 2026-09-15T19:41 during this chunk's own measurement:
# a naive `acli.*delete` pattern matched the regex TEXT inside a quoted
# heredoc in scan5.py. That is the false-positive class lib.sh exists to kill,
# and it is why the command-word test is `cmdword_is` rather than a prefix
# regex (chunk B's fix for `{ git reset --hard; }` and `\git tag -d v1`).
#
# The command-word test runs on a `mask_heredoc | mask_comment` copy ONLY.
# Quote-masking it makes the verb read as no verb at all: that is audit finding
# CW1, and it is the same defect that let `'echo' $GH_TOKEN` past
# secret-echo-guard.sh until Phase 1 of this chunk.
#
# RULES
#
#   GH-WRITE   `gh api` writing repo/org settings, and `gh repo edit`.
#   DELETE-OUT `acli` delete subcommands, which destroy Jira and Confluence
#              content no local archive can recover.
#
# GH-WRITE PARSES THE METHOD ITSELF and does not use `flag_value`. Two reasons,
# both measured, both in the design doc: `flag_value` cannot see the attached
# form (`-XDELETE` returns empty), and it returns its FIRST match while `gh`
# honours the LAST, so `-X GET -X DELETE` reads as GET and executes as DELETE.
# Teaching `flag_value` the attached form flips two shipped guards from allow to
# deny and opens a fresh bypass, and `lib-test.sh` passes 135/0 over the patched
# copy, so the matrix does not protect that change. `flag_value` is left alone.
#
# The local parse handles four spellings, last occurrence wins, compared
# case-insensitively: `-X V`, `-XV`, `-X=V`, `--method[= ]V`. An uppercase-only
# test misses `gh api -X get`, which gh accepts; a parse that does not strip the
# `=` reads `-X=DELETE` as the value `=DELETE` and allows.
#
# OPERAND CONSUMPTION is the subtle part. `gh` accepts a dash-leading header
# value and `args` reports the tokens flat, so a naive scan for anything shaped
# like `-X...` picks up the OPERAND of `-H` and resolves the wrong method:
#
#   printf 'gh api -XDELETE -H "-XGET: x" repos/o/r' | args
#     ->  gh | api | -XDELETE | -H | -XGET: x | repos/o/r
#
# So the walk skips the operand of every value-taking flag before deciding
# whether a token is a method flag at all. VALUE_FLAGS below is the complete
# `gh api --help` specification, short AND long alias for each. Round 3 of the
# panel hand-listed a subset and round 4 executed two live bypasses through the
# gaps (`--header`, the long alias of an `-H` it had just fixed, and `-p`):
#
#   gh api -XDELETE -p -XGET /rate_limit --verbose      -> DELETE /rate_limit
#   gh api -XDELETE --header "-XGET: x" /rate_limit -v  -> DELETE /rate_limit
#
# The list is a snapshot of one binary's surface, so a flag gh grows later is a
# hole by construction. The matrix carries one operand-skip fixture per flag so
# a missing alias fails a test rather than passing silently.
#
# Emits a PreToolUse "deny" decision (with a reason Claude sees), or '{}'.

case "${1:-}" in
  -h|--help)
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit 0
    ;;
  --self-test)
    exec bash "$(dirname "$0")/intent-guard-test.sh"
    ;;
esac

. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }

deny() { # deny <reason>
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$command" ] && { echo '{}'; exit 0; }

# Every value-taking flag `gh api` has, short and long. A token matching one of
# these consumes the NEXT token as its operand, so that operand can never be
# mistaken for a method flag.
VALUE_FLAGS=" --cache -F --field -H --header --hostname --input -q --jq -X --method -p --preview -f --raw-field -t --template "

# Body-field flags. Their presence with no explicit method makes the request a
# POST, because that is what `gh api` does on its own.
BODY_FLAGS=" -f --raw-field -F --field --input "

is_value_flag() { case "$VALUE_FLAGS" in *" $1 "*) return 0;; esac; return 1; }
is_body_flag()  { case "$BODY_FLAGS"  in *" $1 "*) return 0;; esac; return 1; }

# gh_api_verdict <statement>  ->  prints "<method> <explicit> <path>"
#
# method   effective HTTP method, uppercased, empty when none resolved
# explicit 1 when a -X/--method flag was present, else 0
# path     the first operand that is not a flag and not a flag's operand
gh_api_verdict() {
  local stmt="$1" tok method="" explicit=0 body=0 path="" seen_api=0 skip=0 gh_seen=0
  local -a toks=()
  mapfile -t toks < <(printf '%s' "$stmt" | args)
  local i=0 n=${#toks[@]}
  while [ "$i" -lt "$n" ]; do
    tok="${toks[$i]}"
    i=$((i + 1))
    # Nothing before `gh api` is an argument to it. Wrapper shapes put real
    # tokens ahead of the command word (`timeout 5 gh api ...`, `nohup gh ...`,
    # `for i in 1; do gh ...`), and walking from token 0 assigned the PATH from
    # the wrapper: `timeout` is not a guarded path, so 7 of the 18 wrap_shapes
    # spellings allowed the founding incident. cmdword_is has already confirmed
    # the command word is gh; this finds where its arguments actually begin.
    if [ "$seen_api" -eq 0 ]; then
      case "$tok" in
        gh|\\gh) gh_seen=1 ;;
        api)     [ "$gh_seen" -eq 1 ] && seen_api=1 ;;
      esac
      continue
    fi
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "$tok" in
      -X|--method)
        # separated form: the next token is the value, and it is consumed here
        # rather than skipped, which is why -X is in VALUE_FLAGS too.
        if [ "$i" -lt "$n" ]; then method="${toks[$i]}"; i=$((i + 1)); fi
        explicit=1
        continue
        ;;
      -X=*|--method=*) method="${tok#*=}"; explicit=1; continue ;;
      -X?*)            method="${tok#-X}"; explicit=1; continue ;;
      --method?*)      method="${tok#--method}"; method="${method#=}"; explicit=1; continue ;;
      -f|-F|--field|--raw-field|--input) body=1; skip=1; continue ;;
      -f?*|-F?*)       body=1; continue ;;
      -*)
        if is_value_flag "$tok"; then skip=1; fi
        if is_body_flag "$tok"; then body=1; fi
        continue
        ;;
      *)
        [ -z "$path" ] && path="$tok"
        continue
        ;;
    esac
  done
  [ "$seen_api" -eq 1 ] || return 1
  method=$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')
  if [ -z "$method" ] && [ "$body" -eq 1 ]; then method="POST"; fi
  printf '%s %s %s' "$method" "$explicit" "$path"
}

# is_guarded_path <path> -- repo and org settings surfaces, leading slash optional
is_guarded_path() {
  local p="${1#/}"
  case "$p" in
    repos/*/branches/*/protection|repos/*/branches/*/protection/*) return 0 ;;
    repos/*/rulesets|repos/*/rulesets/*)                           return 0 ;;
    orgs/*/rulesets|orgs/*/rulesets/*)                             return 0 ;;
  esac
  # a bare repos/<owner>/<repo> with nothing after it IS the settings surface
  case "$p" in
    repos/*/*/*) return 1 ;;
    repos/*/*)   return 0 ;;
  esac
  return 1
}

is_write_method() {
  case "$1" in PATCH|PUT|POST|DELETE) return 0 ;; esac
  return 1
}

GH_DENY='repo/org settings are Scott'"'"'s to change (rules/git.md). Report the blocker; do not change the setting.'
ACLI_DENY='acli delete destroys Jira/Confluence content no local archive can recover. Ask Scott; do not delete it.'

while IFS= read -r -d '' stmt; do
  verbscan=$(printf '%s' "$stmt" | mask_heredoc | mask_comment)

  if printf '%s' "$verbscan" | cmdword_is gh >/dev/null 2>&1; then
    # `gh repo edit` changes the same settings surface through a different door.
    # Adjacent tokens, matched as one run. Separate `*" repo "*" edit "*` globs
    # do NOT work: the first consumes the space the second needs, so a token
    # pair that IS adjacent fails to match.
    case " $(printf '%s' "$verbscan" | args | tr '\n' ' ') " in
      *" repo edit "*) deny "$GH_DENY" ;;
    esac
    if verdict=$(gh_api_verdict "$verbscan"); then
      method="${verdict%% *}"
      rest="${verdict#* }"
      explicit="${rest%% *}"
      path="${rest#* }"
      if [ -n "$path" ] && is_guarded_path "$path"; then
        # An EXPLICIT --method GET with body fields is a read, not a write.
        if [ "$explicit" -eq 1 ] && [ "$method" = "GET" ]; then
          :
        elif is_write_method "$method"; then
          deny "$GH_DENY"
        fi
      fi
    fi
  fi

  if printf '%s' "$verbscan" | cmdword_is acli >/dev/null 2>&1; then
    toks=" $(printf '%s' "$verbscan" | args | tr '\n' ' ') "
    case "$toks" in
      *" --help "*|*" -h "*) : ;;
      *" jira workitem delete "*|*" confluence page delete "*)
        deny "$ACLI_DENY" ;;
    esac
  fi
done < <(printf '%s' "$command" | stmts)

echo '{}'
