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

# norm_path <absolute path> -- lexical only: `.` and empty segments drop, `..`
# pops. Deliberately NOT realpath: the answer must depend on the path string and
# not on what happens to exist, and it must never dereference anything.
norm_path() {
  printf '%s' "$1" | awk -F/ '{
    n = 0
    for (i = 1; i <= NF; i++) {
      p = $i
      if (p == "" || p == ".") continue
      if (p == "..") { if (n > 0) n--; continue }
      st[++n] = p
    }
    out = ""
    for (i = 1; i <= n; i++) out = out "/" st[i]
    if (out == "") out = "/"
    printf "%s", out
  }'
}

# abs_path <path> <base> -- absolute, tilde expanded, lexically normalized.
# Empty when the path is relative and the base is unknown, which is the
# fail-closed case the LN rule denies on.
abs_path() {
  local p="$1" base="$2"
  case "$p" in
    "~")   p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
  esac
  case "$p" in
    /*) ;;
    *)  [ -n "$base" ] || return 1
        p="$base/$p" ;;
  esac
  norm_path "$p"
}

# ln_link_entry <target> <linkpath> <base> -- the entry the link will OCCUPY.
#
# The basename is never resolved. `realpath -m` FOLLOWS an existing link, so on
# any `ln -sf` reinstall of a live symlink the link and its target resolve to
# the same file and an equality test fires on the single most common legitimate
# shape in the corpus. Verified 2026-09-15: realpath -m ~/.claude/hooks/lib.sh
# and realpath -m of its target print identical paths. So: resolve the PARENT,
# append the basename untouched.
ln_link_entry() {
  local target="$1" linkpath="$2" base="$3" abs
  # abs_path is lexical (norm_path), so this resolves the link path WITHOUT
  # dereferencing its final component, which is the whole point of the rule.
  abs=$(abs_path "$linkpath" "$base") || return 1
  # A destination that is an existing directory takes the target's basename,
  # which is `ln`'s own behaviour and the reason -n/-T exist to suppress it.
  # Tested on the RESOLVED path: testing the operand as written asks about the
  # hook process's cwd, which is never the cwd the command would run in.
  if [ -d "$abs" ] && [ "$LN_NO_DEREF" -eq 0 ]; then
    abs="${abs%/}/$(basename -- "$target")"
  fi
  printf '%s' "$abs"
}

GH_DENY='repo/org settings are Scott'"'"'s to change (rules/git.md). Report the blocker; do not change the setting.'
ACLI_DENY='acli delete destroys Jira/Confluence content no local archive can recover. Ask Scott; do not delete it.'
LN_CYCLE_DENY='this ln -s would make the target an ancestor of its own link, which is the symlink loop that froze the workstation on 2026-07-03. Check the direction of the link.'
LN_CLAUDE_DENY='~/Claude is the Cowork/Syncthing space and is symlink-free by policy (CLAUDE.md). Copy the file there instead of linking it.'
LN_CWD_DENY='this ln -s has a relative link path and the guard cannot resolve the cwd it would run in, so it cannot tell a loop from a reinstall. Use an absolute link path.'
INGEST_DENY='bulk vault ingest is Scott'"'"'s call: 164 URLs went in unasked on 2026-06-20. Ask him, or re-run with BULK_INGEST_ORDERED_BY_SCOTT=<n> as a leading assignment. Denied for'
INGEST_DOOR_DENY='BULK_INGEST_ORDERED_BY_SCOTT must be a non-negative integer. It is a ceiling on ingest occurrences, not a boolean.'

# The cwd the statements run in. Accumulated across the command's `cd` chain
# starting from the payload, because lib.sh's cd_last/cd_at REPLACE rather than
# accumulate, so `cd ~/repos/scottidler/claude && cd HOME && ln -s ...` yields
# the relative `HOME` from them. 97 of the 100 measured absolute-pair corpus
# statements use relative paths, so this matters for nearly all of them.
#
# Accumulation stops at a structural paren, because a `cd` inside a subshell
# does not escape it and `stmts` cannot see that it was one:
#
#   printf '(cd /tmp); pwd' | stmts   ->   cd /tmp | pwd
#
# The test is on the MASKED command. On the raw string it fires on a paren in a
# comment or a quoted string, which is 5 of the 8 corpus `ln -s` commands that
# contain a paren against only 3 that contain a structural `$(`. lib.sh:68
# classifies a command-substitution body as class P, "which no masker may
# erase", so masking separates the two at no cost.
# The stop is POSITIONAL, at the paren, not global. Testing the whole command
# for a paren discards the cd chain because of a `$( )` anywhere at all,
# including a trailing echo that runs after the ln. The corpus replay caught
# exactly that: `cd /tmp/wt-385b && ln -s .../node_modules node_modules && ...
# echo "$(git rev-parse HEAD)"` lost its cd, fell back to the payload cwd, and
# the relative link path then resolved onto the target itself and denied.
#
# A fallback cwd is worse than no cwd here. When a `cd` has already moved and
# the guard cannot follow it, resolving against the payload produces a
# CONFIDENT wrong answer rather than a conservative one, so that case is
# treated as unknown and the fail-closed branch below handles it.
payload_cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
masked_all=$(printf '%s' "$command" | mask_heredoc | mask_comment | mask_squote | mask_dquote)
ln_prefix="${masked_all%%ln *}"
cwd_accumulates=1
case "$ln_prefix" in *"("*) cwd_accumulates=0 ;; esac
cur_cwd="$payload_cwd"
# A subshell opened before the ln means the cwd at the ln is not knowable from
# here at all, so it is unknown rather than "the payload's".
[ "$cwd_accumulates" -eq 0 ] && cur_cwd=""

ingest_ops=0
door_open=0

# INGEST reads heredoc BODIES, which no other rule here does, because the
# 164-URL incident never looped `sb borg ingest`: at 00:32:22 it wrote a script
# with a QUOTED heredoc and at 00:32:40 ran it. The run statement's command word
# is `$S/ingest.sh`, so no verb matcher sees it, and the quoted delimiter means
# `heredoc_expanded` never emits it either. Denying at CREATION is what stops
# the sequence, and creation is only visible in the body.
#
# The scan is bounded to a redirect target ending in `.sh`, and the bound is not
# fussy on purpose. This design document contains both `while IFS= read -r url`
# and `sb borg ingest` in its own prose, so writing it through a heredoc would
# deny under an unbounded command-scope scan. That is chunk C's self-reference
# class. The incident's target is `"$S/ingest.sh"` and is caught; this doc's
# target is a `.md` path and is not. A script written to an extensionless path
# and chmodded afterwards is a named residual hole, not a silent one.
# A single quote is written \047 throughout: embedding one in a single-quoted
# shell string mangles the awk program, which is how the first version of this
# extractor silently matched nothing and let the founding incident through.
ingest_heredocs=$(printf '%s' "$command" | awk '
  !capture {
    i = index($0, "<<")
    if (i > 0) {
      left = substr($0, 1, i - 1)
      if (left ~ /\.sh[\047"]?[[:space:]]*$/) {
        rest = substr($0, i + 2)
        sub(/^-/, "", rest)
        gsub(/[[:space:]]/, "", rest)
        gsub(/[\047"]/, "", rest)
        if (rest != "") { delim = rest; capture = 1 }
      }
    }
    next
  }
  $0 == delim { capture = 0; next }
  { print }
')

while IFS= read -r -d '' stmt; do
  verbscan=$(printf '%s' "$stmt" | mask_heredoc | mask_comment)

  if [ "$cwd_accumulates" -eq 1 ] && printf '%s' "$verbscan" | cmdword_is cd >/dev/null 2>&1; then
    cd_op=$(printf '%s' "$verbscan" | args | sed -n '2p')
    case "$cd_op" in
      ""|-*) : ;;
      *) cur_cwd=$(abs_path "$cd_op" "$cur_cwd") || cur_cwd="" ;;
    esac
  fi

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

  # INGEST's door and its read-only exclusion are the two PER-STATEMENT steps.
  # Everything else about the rule is command-scope, handled after the loop.
  if printf '%s' "$verbscan" | grep -qE '(^|[^-[:alnum:]])borg[[:space:]]+(ingest|reingest|reingest-failed)\b'; then
    stmt_ops=$(printf '%s' "$verbscan" | grep -oE 'borg[[:space:]]+(ingest|reingest-failed|reingest)' | wc -l)
    # Same target counting the command-scope clause uses, so the ceiling means
    # the same thing in both places: `=1` must not admit five URLs.
    stmt_urls=$(printf '%s' "$verbscan" | grep -oE 'https?://[^[:space:]"]+' | wc -l)
    [ "$stmt_urls" -gt "$stmt_ops" ] && stmt_ops="$stmt_urls"
    # Read-only operations are DROPPED from the operation list rather than
    # returning an allow for the command. Round 3 wrote this as "always allow"
    # and `sb borg log; sb borg ingest --file urls.txt` then never reached the
    # deny clauses at all.
    case "$verbscan" in
      *--dry-run*) case "$verbscan" in *reingest*) stmt_ops=0 ;; esac ;;
    esac
    if [ "$stmt_ops" -gt 0 ]; then
      ingest_ops=$((ingest_ops + stmt_ops))
      # The door, anchored as a LEADING assignment on this statement so it
      # cannot be smuggled in from a heredoc body or a comment.
      door=$(printf '%s' "$verbscan" | sed -n 's/^[[:space:]]*BULK_INGEST_ORDERED_BY_SCOTT=\([^[:space:];|&]*\).*/\1/p' | head -1)
      if [ -n "$door" ]; then
        case "$door" in
          ''|*[!0-9]*) deny "$INGEST_DOOR_DENY" ;;
        esac
        # <n> is a CEILING and it is compared. Round 3 called it a maximum and
        # then never compared it, so =0 allowed and =1 allowed five ingests.
        if [ "$stmt_ops" -le "$door" ]; then
          door_open=1
        else
          deny "BULK_INGEST_ORDERED_BY_SCOTT=$door permits $door ingest occurrences and this statement carries $stmt_ops. Raise the ceiling deliberately or split the command."
        fi
      fi
    fi
  fi

  if printf '%s' "$verbscan" | cmdword_is ln >/dev/null 2>&1; then
    LN_NO_DEREF=0
    ln_symbolic=0
    ln_tdir=""
    ln_srcs=()
    skip=0
    seen_ln=0
    while IFS= read -r tok; do
      if [ "$seen_ln" -eq 0 ]; then
        case "$tok" in ln|\\ln) seen_ln=1 ;; esac
        continue
      fi
      if [ "$skip" -eq 1 ]; then skip=0; ln_tdir="$tok"; continue; fi
      case "$tok" in
        --symbolic)          ln_symbolic=1 ;;
        --no-target-directory|--no-dereference) LN_NO_DEREF=1 ;;
        --target-directory=*) ln_tdir="${tok#*=}" ;;
        --target-directory) skip=1 ;;
        -t)                 skip=1 ;;
        -t?*)               ln_tdir="${tok#-t}" ;;
        --*)                : ;;
        -*)
          # Combined short flags: -sfn is -s -f -n. Each letter is its own flag.
          case "$tok" in *s*) ln_symbolic=1 ;; esac
          case "$tok" in *[nT]*) LN_NO_DEREF=1 ;; esac
          ;;
        "") : ;;
        *) ln_srcs+=("$tok") ;;
      esac
      # A redirect is not an operand. `args` drops the `>` and emits its two
      # halves as bare tokens, so `ln -s a b 2>/dev/null` would otherwise take
      # `/dev/null` as the link path. Stripped from the statement text above,
      # before args ever sees it.
    done < <(printf '%s' "$verbscan" | sed -E 's/[0-9]*>>?&?[^[:space:]]*//g' | args)

    if [ "$ln_symbolic" -eq 1 ] && [ "${#ln_srcs[@]}" -gt 0 ]; then
      # Operand shapes, all from the installed `ln --help`:
      #   -t DIR a b     every operand is a source, DIR is the destination
      #   a b            one source, one link path
      #   a              one source, link name is basename(a) in the cwd
      #   a b c dir      many sources into a directory destination
      ln_dest=""
      if [ -n "$ln_tdir" ]; then
        ln_dest="$ln_tdir"
      elif [ "${#ln_srcs[@]}" -ge 2 ]; then
        ln_dest="${ln_srcs[-1]}"
        unset 'ln_srcs[-1]'
      fi
      for src in "${ln_srcs[@]}"; do
        linkpath="${ln_dest:-$(basename -- "$src")}"
        # An operand still carrying a `$` after masking is an unexpanded
        # variable or a command substitution, so its value is not knowable
        # here and comparing the literal text yields a verdict about a path
        # that will never exist. Skipped as a PAIR, after the destination has
        # been chosen: dropping such tokens from the operand list instead
        # shifts which token becomes the link path, which turned
        # `ln -sf plain-token.age "$SP/.secrets/alias-token.age"` into a
        # self-link and denied it. Found by the corpus replay.
        case "$src$linkpath" in *'$'*) continue ;; esac
        entry=$(ln_link_entry "$src" "$linkpath" "$cur_cwd") || deny "$LN_CWD_DENY"
        case "$entry" in
          "$HOME"/Claude/*) deny "$LN_CLAUDE_DENY" ;;
        esac
        # A relative target resolves against the LINK's parent, not the cwd,
        # which is what the symlink itself will do when it is followed.
        tgt=$(abs_path "$src" "${entry%/*}") || continue
        [ -z "$tgt" ] && continue
        if [ "$tgt" = "$entry" ]; then deny "$LN_CYCLE_DENY"; fi
        # `/` is an ancestor of everything, and the glob below cannot say so:
        # with tgt=/ the pattern is `//*`, which matches nothing. `ln -s .. x`
        # from /tmp resolves its target to / and is exactly the 2026-07-03
        # shape, so this case is the rule, not an edge.
        if [ "$tgt" = "/" ]; then deny "$LN_CYCLE_DENY"; fi
        case "$entry" in
          "$tgt"/*) deny "$LN_CYCLE_DENY" ;;
        esac
      done
    fi
  fi
done < <(printf '%s' "$command" | stmts)

# INGEST's deny clauses are COMMAND scope, which is a deliberate exception to
# the per-statement contract every other rule follows. `stmts` splits the
# incident's own loop body so that the statement carrying the ingest holds no
# loop keyword, no second URL and no file redirect:
#
#   while IFS= read -r url; do out=$(sb borg ingest ... "$url"); done < urls.txt
#     ->  while IFS= read -r url | do | out=$() | rc=$? | done < urls.txt
#         sb borg ingest --tags x -- "$url" 2> | 1
#
# A per-statement predicate does not fire on the shape that actually happened.
# A heredoc body is not a statement, so the per-statement loop above never sees
# it and `ingest_ops` stays 0. That is precisely the incident's shape, where the
# ingest exists ONLY inside the body being written to a .sh file, so counting
# statements alone let the founding vector through.
heredoc_ops=$(printf '%s' "$ingest_heredocs" | grep -cE 'borg[[:space:]]+(ingest|reingest-failed|reingest)' || true)
ingest_ops=$((ingest_ops + heredoc_ops))

if [ "$ingest_ops" -gt 0 ] && [ "$door_open" -eq 0 ]; then
  scan="$masked_all$ingest_heredocs"
  # Word boundaries, not globs. `*"while "*` needs a trailing space and misses
  # `echo while; sb borg ingest -- https://one.url`, which the design doc names
  # explicitly as a deny. A glob cannot express "this token, not this substring",
  # and a substring test would fire on `platform` for `for`.
  if printf '%s' "$scan" | grep -qE '(^|[^[:alnum:]_])(while|for|select)([^[:alnum:]_]|$)'; then
    deny "$INGEST_DENY (a loop construct)"
  fi
  if printf '%s' "$scan" | grep -qE '(^|[^[:alnum:]_])xargs([^[:alnum:]_]|$)'; then
    deny "$INGEST_DENY (xargs)"
  fi
  # A redirect READING a file. `> out.log` writes and is not a bulk source.
  if printf '%s' "$scan" | grep -qE '<[[:space:]]*[^<[:space:]]'; then
    deny "$INGEST_DENY (a redirect reading a file)"
  fi
  # An ingest carrying five literal URLs is a bulk ingest of five things, so the
  # counted unit is TARGETS, not verb occurrences. The doc's rule text says
  # "occurrences"; counting only those makes `sb borg ingest -- u1 u2 u3 u4 u5`
  # trip no clause at all, which contradicts the doc's own Phase 4 criterion
  # that the 5-URL form denies without the door and passes with `=5`. It is also
  # what makes <n> mean what a reader expects it to mean.
  url_targets=$(printf '%s' "$scan" | grep -oE 'https?://[^[:space:]"]+' | wc -l)
  [ "$url_targets" -gt "$ingest_ops" ] && ingest_ops="$url_targets"
  [ "$ingest_ops" -ge 2 ] && deny "$INGEST_DENY ($ingest_ops ingest targets)"
  case "$scan" in
    *"ingest --file"*|*"ingest -f "*) deny "$INGEST_DENY (--file is the CLI's own bulk path)" ;;
    *"reingest --all"*)               deny "$INGEST_DENY (--all is the largest bulk action available)" ;;
  esac
  # The literal-URL clause applies to `ingest` ONLY. `reingest` and
  # `reingest-failed` take no URL operand, so applying it to them would deny
  # every `reingest-failed --dry-run`.
  if printf '%s' "$scan" | grep -qE 'borg[[:space:]]+ingest\b'; then
    operands=$(printf '%s' "$scan" \
      | sed -n 's/.*borg[[:space:]]\{1,\}ingest[[:space:]]\{1,\}\(.*\)/\1/p' | head -1)
    case "$operands" in
      *" -- "*) operands="${operands#*" -- "}" ;;
      *)        operands=$(printf '%s' "$operands" | tr ' ' '\n' | grep -v '^-' | head -1) ;;
    esac
    operands=$(printf '%s' "$operands" | awk '{print $1}')
    if [ -n "$operands" ]; then
      case "$operands" in
        http://*|https://*) : ;;
        *) deny "$INGEST_DENY (the URL operand is not a literal http(s) token, so the target is not in the command)" ;;
      esac
    fi
  fi
fi

echo '{}'
