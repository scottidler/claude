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
#   GH-WRITE    `gh api` writing repo/org settings, and `gh repo edit`.
#   DELETE-OUT  `acli` delete subcommands, which destroy Jira and Confluence
#               content no local archive can recover.
#   LN          `ln -s` shapes that make the target an ancestor of its own link
#               (the 2026-07-03 workstation freeze), and any link into ~/Claude.
#   INGEST      bulk `sb borg ingest`, command scope, with a counted door.
#   PUBLIC-REPO `git commit` / `git push` publishing a sensitive path or a blob
#               over 1 MB to a public remote.
#   SLEEP       foreground waiting past 25s, which is the harness's own
#               threshold, in the three shapes its statement-0 check misses.
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

deny() { # deny <reason>
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Fail CLOSED, not open. This hook carries PUBLIC-REPO, which the design contract
# names as a fail-closed rule, so an unreadable lib.sh cannot be allowed to turn
# the whole hook into a no-op. `slack-post-guard.sh:182` already did this
# correctly; this line shipped the tree's older fail-open form.
LIB_OK=1
. "$(dirname "$0")/lib.sh" 2>/dev/null || LIB_OK=0

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$command" ] && { echo '{}'; exit 0; }
# SLEEP's unconditional allow, matching the native predicate exactly
# (`&& !n.run_in_background`), so the guard never contradicts the harness. Read
# here rather than in the rule because the payload is only parsed once.
run_bg=0
case "$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)" in
  true|1) run_bg=1 ;;
esac
[ "$LIB_OK" -eq 0 ] && deny "intent-guard: lib.sh is unreadable, so the command cannot be parsed and PUBLIC-REPO cannot be evaluated. Fix $(dirname "$0")/lib.sh."

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
        # An attached long form carries its operand in the same token:
        # `--field=name=x` is the body flag `--field`, and `gh` accepts it.
        # Matching the whole token against the exact-token tables set NEITHER
        # body nor skip, so `gh api <path> --raw-field=name=x` read as a bare
        # GET and allowed. Split on the first `=` before testing.
        flag="${tok%%=*}"
        if is_value_flag "$flag"; then [ "$flag" = "$tok" ] && skip=1; fi
        if is_body_flag "$flag"; then body=1; fi
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
# The statements that remain IN SCOPE for INGEST's command-level clauses, each
# quote-masked. Replaces the old command-wide `door_open` flag and the
# command-wide `masked_all` scan, which between them carried three defects:
#   - one `=1` statement opened the door for EVERY later ingest in the command
#   - the clauses read the whole command quote-masked, so an `eval "..."` /
#     `bash -c "..."` payload was erased and the wrapper allowed
#   - the op COUNT read the unquoted copy while the clauses read the masked one,
#     so `echo "sb borg ingest <url>"` counted targets no clause could see and
#     denied prose (this fired on three of the audit's own commands)
# `stmts` already emits an eval / `bash -c` payload as its own statement, so
# accumulating per-statement gets the executable text and only the executable
# text. Spec: "Count <= n allows the STATEMENT and nothing below runs ... the
# command's verdict is any-deny-wins over the statements that remain in scope."
ingest_scope=""
git_add_args=""
# SLEEP's gate. The span scan below reads a copy whose quotes are NOT masked, so
# it alone would fire on a quoted loop that is data. `stmts` + `cmdword_is` is
# the discrimination: a sleep has to be in EXECUTABLE position somewhere in the
# command before any span arithmetic runs. It is accumulated in the walk that is
# already happening rather than in a second one, and behind a substring test, so
# a Bash call with no `sleep` in it pays nothing.
sleep_seen=0

SENSITIVE_RE='(^|/)(personal|excluded|voice|secret|secrets)/|\.env$|\.age$'
BLOB_MAX=1048576
PUBLIC_DENY='this would publish a sensitive path (or a blob over 1 MB) to a PUBLIC remote. 119 of 136 personal repos are public, including this one. Move it to scottidler/keep, or confirm with Scott.'

# repo_root <cwd> -- empty when the cwd is not a git work tree
repo_root() {
  [ -n "$1" ] || return 1
  git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

# in_scope <repo root> -- ~/repos/scottidler/* only. No repo outside it has an
# origin remote Scott owns, third-party clones are not pushable, and tatari-tv
# is a different threat model.
in_scope() {
  case "$1" in "$HOME"/repos/scottidler/*) return 0 ;; esac
  return 1
}

# repo_visibility <repo root> -- public|private, cached a week under ~/.cache.
# UNKNOWN, MISSING OR UNREADABLE READS AS PUBLIC, so the guard is on rather than
# off when it has no answer. A `gh` call on every commit is not acceptable
# against the existing hook latency.
repo_visibility() {
  local root="$1" dir="$HOME/.cache/intent-guard/visibility" key entry vis epoch now
  key=$(printf '%s' "$root" | sha256sum | awk '{print $1}')
  entry="$dir/$key"
  now=$(date +%s)
  if [ -r "$entry" ]; then
    vis=$(sed -n 's/^visibility=//p' "$entry" | head -1)
    epoch=$(sed -n 's/^epoch=//p' "$entry" | head -1)
    case "$epoch" in ''|*[!0-9]*) epoch=0 ;; esac
    if [ $((now - epoch)) -lt 604800 ] && [ -n "$vis" ]; then
      printf '%s' "$vis"; return 0
    fi
  fi
  vis=$(cd "$root" && gh repo view --json visibility -q .visibility 2>/dev/null | tr '[:upper:]' '[:lower:]')
  case "$vis" in
    public|private|internal) ;;
    *) printf 'public'; return 0 ;;
  esac
  if mkdir -p "$dir" 2>/dev/null; then
    printf 'visibility=%s\nepoch=%s\n' "$vis" "$now" > "$entry" 2>/dev/null
  fi
  printf '%s' "$vis"
}

# revalidate_private <repo root> -- a cached `private` that has since gone
# public is the case unknown-reads-as-public does nothing for: a stale entry
# stays private for the rest of its week. So a cached private is rechecked with
# gh BEFORE a sensitive path is allowed, and only then. This is the
# deny-candidate path, never the hot path. If the recheck cannot run, deny.
revalidate_private() {
  local root="$1" vis
  vis=$(cd "$root" && gh repo view --json visibility -q .visibility 2>/dev/null | tr '[:upper:]' '[:lower:]')
  case "$vis" in
    private|internal) return 1 ;;
    public)           return 0 ;;
    *)                return 0 ;;
  esac
}

# expand_operand <repo root> <operand> -- ask GIT what a directory operand
# covers, never the filesystem. A glob walks ignored files and would deny on a
# gitignored .env that git is never going to stage.
expand_operand() {
  git -C "$1" ls-files -co --exclude-standard -- "$2" 2>/dev/null
}

paths_are_sensitive() { # stdin: one path per line
  grep -qE "$SENSITIVE_RE"
}

# SLEEP. One threshold, T1, in milliseconds so 0.5 is arithmetic and not a
# rounding argument. 25s is where the harness's own check fires (`var Dpn=25`
# with `if(g<Dpn)return null`), so the two guards agree at the boundary and the
# deny can speak with one number. There is deliberately NO per-iteration cap:
# Monitor's description mandates "30s+ for remote APIs (rate limits)" and its
# own `gh pr checks` example sleeps 30, so a per-iteration threshold at 25 would
# deny the pattern the harness recommends. One quantity is priced: total
# foreground wait.
SLEEP_T1_MS=25000
# Verbatim from the native deny, so the two read as one voice rather than two
# competing instructions.
SLEEP_ADVICE='To wait for a condition, use Monitor with an until-loop (e.g. `until <check>; do sleep 2; done`). To wait for a command you started, use run_in_background: true. Do not chain shorter sleeps to work around this block.'

# dur_ms <operand> -- a literal sleep operand in milliseconds, non-zero exit
# when the operand is not a literal (`sleep "$T"`). A non-literal contributes
# nothing: bounding it is the variable-verb limit chunk B handed on, and the
# phase's domain is the three measured bypass classes, not that one.
#
# All three spellings coreutils accepts, because `strtod` does: `0.5`, `.5` and
# `15.`. The first build spelled the fraction one way, `^[0-9]+([.][0-9]+)?`,
# and the fixtures spelled it the same way, so `for i in $(seq 1 60); do sleep
# .5; done` -- 30 seconds of wall clock -- contributed ZERO and allowed
# (audit M2, 2026-09-20). A duration parser that rejects a duration the shell
# accepts is a bypass, not a limit.
dur_ms() {
  LC_ALL=C awk -v v="$1" 'BEGIN {
    if (v !~ /^([0-9]+([.][0-9]*)?|[.][0-9]+)[smhd]?$/) exit 1
    c = substr(v, length(v), 1)
    u = 1
    if (c == "s") u = 1
    else if (c == "m") u = 60
    else if (c == "h") u = 3600
    else if (c == "d") u = 86400
    if (c ~ /[smhd]/) v = substr(v, 1, length(v) - 1)
    printf "%d", v * u * 1000 + 0.5
  }'
}

# sleep_ms <text> -- the foreground sleep in <text>, summed over every statement
# whose COMMAND WORD is sleep. `cmdword_is` is what keeps `echo "sleep 30"` and
# `# sleep 30` out of the total; a substring scan is the false-positive class
# lib.sh exists to kill.
sleep_ms() {
  local text="$1" total=0 st tok ms
  while IFS= read -r -d '' st; do
    case "$st" in *sleep*) ;; *) continue ;; esac
    printf '%s' "$st" | cmdword_is sleep >/dev/null 2>&1 || continue
    while IFS= read -r tok; do
      ms=$(dur_ms "$tok") || continue
      total=$((total + ms))
    done < <(printf '%s' "$st" | args | awk 'seen { print; next } /^\\?([^\/]*\/)*sleep$/ { seen = 1 }')
  done < <(printf '%s' "$text" | stmts)
  printf '%s' "$total"
}

# sleep_prep <redir|data> -- stdin: command text, stdout: the same text prepared
# for the span scan below. Two passes over one quote scanner, both SLEEP-local:
# no other rule here needs either, and both would be wrong for rules that price
# a verb rather than a duration.
#
#   redir  drops redirection operators and their operands. `sleep_ms` sums
#          every token after the `sleep` command word, and `args` hands back a
#          redirection's operand as a bare token, so `echo A; sleep 0.1 2>30`
#          was priced at 0.1 + 2 + 30 = 32.1s and denied a command that waits a
#          tenth of a second (audit M1, 2026-09-20). A `<` or `>` counts as a
#          redirection only where the shell reads one: not before `(`, which is
#          process substitution, and not glued to a word character, which is
#          what leaves `for ((i=0; i<30; i++))` intact.
#
#   data   masks the content of quoted words the shell will NOT run, and leaves
#          the ones it will. Exposed: a `bash`/`sh`/`zsh` `-c` payload, every
#          `eval` argument, and any quoted word with no whitespace in it, which
#          cannot carry loop structure and is how `"for" i in 1 2 3` and
#          `sleep "24"` keep working. Masked: everything else, so a loop that is
#          an argument to `echo`, or a positional argument sitting past the `-c`
#          payload, is text and not code. `bash -n` is a parse with no
#          execution, so its payload is masked too.
#
# The payload is re-scanned one level down, which is what makes
# `bash -c "echo '<loop>'"` a printed string rather than a loop: the outer
# payload is code, the string inside it is not.
sleep_prep() {
  LC_ALL=C awk -v mode="$1" '
  function scanq(b, e,   i, c, st) {
    st = ""
    i = b
    while (i <= e) {
      c = substr(s, i, 1)
      if (st == "") {
        if (c == "\\") { cl[i] = "e"; i += 2; if (i - 1 <= e) cl[i - 1] = "e"; continue }
        if (c == "\047") { cl[i] = "q"; st = "S"; i++; continue }
        if (c == "\"") { cl[i] = "q"; st = "D"; i++; continue }
        cl[i] = "."; i++; continue
      }
      if (st == "S") {
        if (c == "\047") { cl[i] = "q"; st = ""; i++; continue }
        cl[i] = "S"; i++; continue
      }
      if (c == "\\") { cl[i] = "D"; i += 2; if (i - 1 <= e) cl[i - 1] = "D"; continue }
      if (c == "\"") { cl[i] = "q"; st = ""; i++; continue }
      cl[i] = "D"; i++
    }
  }
  function bare(i) { return (cl[i] == ".") }
  function ws(c) { return (c == " " || c == "\t" || c == "\n") }
  function isbnd(i,   c, p, x) {
    if (!bare(i)) return 0
    c = substr(s, i, 1)
    if (c == ";" || c == "\n" || c == "&" || c == "|") return 1
    if (c == "(") { p = (i > 1) ? substr(s, i - 1, 1) : " "; return (p == "$" || p == "<" || p == ">") ? 0 : 1 }
    if (c == ")") return 1
    if (c != "{" && c != "}") return 0
    p = (i > 1) ? substr(s, i - 1, 1) : " "
    x = (i < length(s)) ? substr(s, i + 1, 1) : " "
    return (ws(p) || index(";|&", p) > 0) && (ws(x) || index(";|&", x) > 0)
  }
  function tokword(b, e,   i, out) {
    out = ""
    for (i = b; i <= e; i++) if (cl[i] != "q") out = out substr(s, i, 1)
    return out
  }
  function verbword(w) { sub(/^\\/, "", w); sub(/^.*\//, "", w); return w }
  # The same walk lib.sh runs, over the token map this pass builds: env
  # assignments, reserved words and wrappers are stepped over, because
  # `timeout 5 bash -c <loop>` is a shell invocation and a prefix regex
  # says it is a `timeout`.
  function cmdword_index(tb, te, nt,   k, w, o) {
    k = 1
    while (k <= nt) {
      w = verbword(tokword(tb[k], te[k]))
      if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { k++; continue }
      if (w == "for" || w == "select") {
        k++
        if (k <= nt) k++
        if (k <= nt && tokword(tb[k], te[k]) == "in") k++
        continue
      }
      if (index(RESERVED, " " w " ") > 0) { k++; continue }
      if (index(WRAPPERS, " " w " ") > 0) {
        k++
        while (k <= nt) { o = tokword(tb[k], te[k]); if (substr(o, 1, 1) != "-" || o == "-") break; k++ }
        if (w == "timeout" && k <= nt && tokword(tb[k], te[k]) ~ /^[0-9]+([.][0-9]+)?[smhd]?$/) k++
        continue
      }
      return k
    }
    return 0
  }
  # Whitespace is the test, and it is the whole test: a quoted word with none
  # cannot spell `do ... done`, and masking it would erase `"for"`, the shape
  # wrap_shapes builds by quoting the verb, and `sleep "24"`, the chaining
  # bypass this rule exists to price.
  function maskspans(b, e,   i, j, body) {
    i = b
    while (i <= e) {
      if (cl[i] != "S" && cl[i] != "D") { i++; continue }
      j = i
      body = ""
      while (j <= e && (cl[j] == "S" || cl[j] == "D")) { body = body substr(s, j, 1); j++ }
      if (body ~ /[ \t\n]/) for (; i < j; i++) mk[i] = 1
      i = j
    }
  }
  function expose(b, e, depth,   fc, lc) {
    if (depth >= 4) return
    if (e <= b + 1 || cl[b] != "q" || cl[e] != "q") return
    fc = substr(s, b, 1); lc = substr(s, e, 1)
    if (fc != lc) return
    scanq(b + 1, e - 1)
    process(b + 1, e - 1, depth + 1)
  }
  function dostmt(b, e, depth,   i, c, nt, tb, te, k, w, ci, verb, syn, pidx) {
    nt = 0
    i = b
    while (i <= e) {
      c = substr(s, i, 1)
      if (bare(i) && ws(c)) { i++; continue }
      nt++
      tb[nt] = i
      while (i <= e) { c = substr(s, i, 1); if (bare(i) && ws(c)) break; i++ }
      te[nt] = i - 1
    }
    if (nt == 0) return
    ci = cmdword_index(tb, te, nt)
    if (ci == 0) ci = 1
    verb = verbword(tokword(tb[ci], te[ci]))
    syn = 0; pidx = 0
    if (verb == "eval") {
      for (k = ci + 1; k <= nt; k++) expose(tb[k], te[k], depth)
      return
    }
    if (verb == "bash" || verb == "sh" || verb == "zsh") {
      for (k = ci + 1; k <= nt; k++) {
        w = tokword(tb[k], te[k])
        if (w !~ /^-/ || w == "--" || w == "-") break
        if (w !~ /^--/) {
          if (w ~ /n/) syn = 1
          if (w ~ /c$/) { pidx = k + 1; break }
        }
      }
    }
    for (k = 1; k <= nt; k++) {
      if (k == pidx && !syn) { expose(tb[k], te[k], depth); continue }
      maskspans(tb[k], te[k])
    }
  }
  function process(b, e, depth,   i, sb) {
    sb = b
    for (i = b; i <= e; i++) if (isbnd(i)) { dostmt(sb, i - 1, depth); sb = i + 1 }
    dostmt(sb, e, depth)
  }
  function striprd(b, e,   i, j, k, m, c, p) {
    i = b
    while (i <= e) {
      c = substr(s, i, 1)
      if (!bare(i) || (c != "<" && c != ">")) { i++; continue }
      if (substr(s, i + 1, 1) == "(") { i++; continue }
      j = i
      while (j > b && bare(j - 1) && substr(s, j - 1, 1) ~ /^[0-9]$/) j--
      if (c == ">" && j > b && bare(j - 1) && substr(s, j - 1, 1) == "&") j--
      p = (j > b) ? substr(s, j - 1, 1) : " "
      if (!(j == b || (bare(j - 1) && (ws(p) || index(";|&(){}", p) > 0)))) { i++; continue }
      k = i
      while (k <= e && bare(k) && index("<>&|", substr(s, k, 1)) > 0) k++
      while (k <= e && bare(k) && (substr(s, k, 1) == " " || substr(s, k, 1) == "\t")) k++
      while (k <= e && !(bare(k) && (ws(substr(s, k, 1)) || index(";|&()", substr(s, k, 1)) > 0))) k++
      for (m = j; m < k; m++) dl[m] = 1
      i = k
    }
  }
  BEGIN {
    MK = sprintf("%c", 1)
    RESERVED = " if then else elif fi while until do done case esac in function time ! [[ ]] { } "
    WRAPPERS = " timeout nohup command env stdbuf nice ionice sudo xargs "
  }
  { buf = buf $0 "\n" }
  END {
    s = buf
    n = length(s)
    scanq(1, n)
    if (mode == "data") process(1, n, 0); else striprd(1, n)
    out = ""
    for (i = 1; i <= n; i++) {
      if (mode == "data") out = out ((i in mk) ? MK : substr(s, i, 1))
      else if (!(i in dl)) out = out substr(s, i, 1)
    }
    printf "%s", out
  }'
}

# loop_spans -- stdin: the command, heredoc- and comment-masked. stdout: one
# TAB-separated record per region, `kind<TAB>multiplier<TAB>shape<TAB>text`:
#
#   FLAT     1  -        everything outside every loop, run once
#   MULT     n  -        a loop body whose iteration count resolved to n
#   OPEN     0  <bound>  a loop whose iteration count is not computable
#   UNBOUND  0  <loop>   `while true` / `while :` with no `break` in the body
#
# A RULE-LOCAL SPAN SCAN, not a `stmts` walk, and that is the whole reason this
# rule needed new code. Probed 2026-09-20: `for i in $(seq 1 30); do sleep 60;
# done` flattens to `for i in $()` | `do sleep 60` | `done` | `seq 1 30`, so the
# bound is re-emitted DETACHED from the loop it bounds and no statement carries
# both. The span keeps them together; `stmts` and `cmdword_is` then run inside
# the span text, which is where the quote and heredoc discipline comes back.
#
# QUOTES ARE ALREADY DECIDED before this function runs: `sleep_prep data` has
# masked every quoted word that is DATA and left every quoted word that is CODE
# exposed, so the keyword scan below can read the raw text. The first build
# skipped that step and scanned quotes wholesale, which is what the wrapper
# sweep needs for `eval "for i in 1 2 3; do sleep 30; done"` and what made
# `sleep 1; echo 'for i in 1 2 3; do sleep 30; done'` deny at 91s for a
# one-second wait (audit M1, 2026-09-20). The `sleep_seen` gate at the call
# site is still the outer bound -- `echo "..."` alone never opens it -- but a
# gate that opens on any `sleep` or any shell verb is not by itself a quote
# discipline.
#
# Reachability is not computable from here and is not attempted: `while true; do
# true && break; sleep 1; done` and the `|| break` form that never terminates
# are the same token stream, so the `break` carve-out is syntactic presence in
# the body. That is one narrow place this rule fails OPEN, taken because denying
# the class would deny Monitor's own `gh pr checks` example.
#
# A `for`/`while`/`until` that never reaches its `done` is not a loop: the frame
# dissolves into its enclosing context rather than denying, so `echo for; sleep
# 10` is priced as the 10s it is.
loop_spans() {
  LC_ALL=C awk '
  function kw(t,   w) {
    w = t
    sub(/^[$<>(!{\\\047"`]+/, "", w)
    sub(/[)};{\047"`]+$/, "", w)
    return w
  }
  function seqcount(s,   a, m, i, f, inc, l) {
    sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
    m = split(s, a, /[ \t]+/)
    for (i = 1; i <= m; i++) if (a[i] !~ /^-?[0-9]+$/) return -1
    if (m == 1) { l = a[1] + 0; return (l >= 1 ? l : 0) }
    if (m == 2) { f = a[1] + 0; l = a[2] + 0; return (l >= f ? l - f + 1 : 0) }
    if (m == 3) {
      f = a[1] + 0; inc = a[2] + 0; l = a[3] + 0
      if (inc == 0) return -1
      if (inc > 0) return (l >= f ? int((l - f) / inc) + 1 : 0)
      return (l <= f ? int((f - l) / (-inc)) + 1 : 0)
    }
    return -1
  }
  function wordcount(w,   a, lo, hi, st, span) {
    if (w ~ /^\{-?[0-9]+\.\.-?[0-9]+\}$/) {
      gsub(/[{}]/, "", w); split(w, a, /\.\./)
      lo = a[1] + 0; hi = a[2] + 0
      return (hi >= lo ? hi - lo + 1 : lo - hi + 1)
    }
    if (w ~ /^\{-?[0-9]+\.\.-?[0-9]+\.\.-?[0-9]+\}$/) {
      gsub(/[{}]/, "", w); split(w, a, /\.\./)
      lo = a[1] + 0; hi = a[2] + 0; st = a[3] + 0
      if (st == 0) return -1
      if (st < 0) st = -st
      span = (hi >= lo ? hi - lo : lo - hi)
      return int(span / st) + 1
    }
    if (w ~ /[*?$`]/ || w ~ /[][{}]/) return -1
    return 1
  }
  # The three computable bound forms and nothing else: a literal list, a brace
  # range, and `seq` with literal arguments. `seq` is the measured dominant
  # form (483 of 800 loop+sleep calls), and it is arithmetic, not an opaque
  # bound. Everything else returns -1 and the loop fails closed.
  function listcount(s,   m, a, i, tot, c) {
    if (s ~ /^\$\([ \t]*seq[ \t][^)]*\)$/) {
      m = s; sub(/^\$\([ \t]*seq[ \t]*/, "", m); sub(/\)$/, "", m)
      return seqcount(m)
    }
    if (s ~ /^`[ \t]*seq[ \t][^`]*`$/) {
      m = s; sub(/^`[ \t]*seq[ \t]*/, "", m); sub(/`$/, "", m)
      return seqcount(m)
    }
    if (s ~ /[$`]/) return -1
    tot = 0
    m = split(s, a, /[ \t]+/)
    for (i = 1; i <= m; i++) {
      if (a[i] == "") continue
      c = wordcount(a[i])
      if (c < 0) return -1
      tot += c
    }
    return tot
  }
  function setbound(d,   h, c) {
    h = hdr[d]
    gsub(/ ; /, " ", h)
    sub(/^[ \t]+/, "", h); sub(/[ \t;]+$/, "", h)
    if (lk[d] != "for") {
      # `until` is `while` with the test INVERTED, so the unbounded constant is
      # inverted too: `while true` never terminates, `until true` runs zero
      # iterations. Reading both off one `true` denied `until true; do sleep
      # 30; done` as a loop that never terminates, when it is the one shape in
      # the class that never even enters the body (audit M1, 2026-09-20).
      if (lk[d] == "until") {
        if (h == "false") { fk[d] = "U"; shp[d] = "until false"; return }
        fk[d] = "T"
        return
      }
      if (h == "true" || h == ":") { fk[d] = "U"; shp[d] = lk[d] " " h; return }
      fk[d] = "T"
      return
    }
    if (h ~ /^\(\(/) { fk[d] = "O"; shp[d] = "a C-style for ((...))"; return }
    if (h !~ /^[^ \t]+[ \t]+in([ \t]|$)/) {
      fk[d] = "O"; shp[d] = "a for loop with no `in` list, which iterates over \"$@\""
      return
    }
    sub(/^[^ \t]+[ \t]+in[ \t]*/, "", h)
    c = listcount(h)
    if (c < 0) { fk[d] = "O"; shp[d] = h; return }
    fk[d] = "M"; fct[d] = c
  }
  function emitframe(d,   m, a) {
    if (fk[d] == "U") {
      if (allt[d] ~ /(^|[^A-Za-z0-9_])break([^A-Za-z0-9_]|$)/) return
      printf "UNBOUND\t0\t%s\t%s\n", shp[d], allt[d]
      return
    }
    if (fk[d] == "O") { printf "OPEN\t0\t%s\t%s\n", shp[d], allt[d]; return }
    # A terminating while/until is what the native deny TELLS the model to
    # write, so its own pacing sleep is not priced at any interval. A bounded
    # loop nested inside one still is: its total is computable, and the
    # enclosing terminating frame contributes a factor of 1 rather than 0.
    if (fk[d] == "T") return
    m = fct[d]
    for (a = 1; a < d; a++) if (fk[a] == "M") m = m * fct[a]
    if (m <= 0) return
    printf "MULT\t%d\t-\t%s\n", m, dirt[d]
  }
  { buf = buf $0 "\n" }
  END {
    gsub(/;/, " ; ", buf)
    gsub(/\n/, " ; ", buf)
    n = split(buf, TOK, /[ \t]+/)
    depth = 0
    rem = ""
    for (k = 1; k <= n; k++) {
      tok = TOK[k]
      if (tok == "") continue
      w = kw(tok)
      if (w == "for" || w == "while" || w == "until") {
        depth++
        # The KEYWORD, not the raw token. A wrapper leaves its opening quote
        # attached (`eval "while true; ...` tokenizes to `"while`), and the
        # UNBOUND and OPEN branches feed allt[] back through `stmts`, where a
        # stray leading quote turns the whole span into one quoted word and the
        # sleep inside it disappears.
        lk[depth] = w; hdr[depth] = ""; dirt[depth] = ""; allt[depth] = w
        inh[depth] = 1; fk[depth] = "T"; fct[depth] = 0; shp[depth] = "-"
        continue
      }
      if (depth > 0 && inh[depth] && w == "do") {
        inh[depth] = 0
        setbound(depth)
        allt[depth] = allt[depth] " " tok
        continue
      }
      if (depth > 0 && !inh[depth] && w == "done") {
        allt[depth] = allt[depth] " " w
        emitframe(depth)
        t = allt[depth]
        depth--
        if (depth > 0) allt[depth] = allt[depth] " " t
        continue
      }
      if (depth > 0) {
        allt[depth] = allt[depth] " " tok
        if (inh[depth]) hdr[depth] = hdr[depth] " " tok
        else dirt[depth] = dirt[depth] " " tok
      } else rem = rem " " tok
    }
    while (depth > 0) {
      t = hdr[depth] " " dirt[depth]
      depth--
      if (depth > 0) dirt[depth] = dirt[depth] " " t; else rem = rem " " t
    }
    printf "FLAT\t1\t-\t%s\n", rem
  }'
}

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
      rest = substr($0, i + 2)
      sub(/^-/, "", rest)
      gsub(/[[:space:]]/, "", rest)
      gsub(/[\047"]/, "", rest)
      if (rest != "") {
        # Enter body state for EVERY heredoc, and decide separately whether to
        # emit. The old form only entered on a `.sh` target, so the body of a
        # `.md` heredoc was still scanned line by line and any line inside it
        # that quoted a `.sh` redirect re-armed capture. Writing this very
        # design document to a `.md` file denied, which is the self-reference
        # class the `.sh` bound exists to avoid and the opposite of what the
        # paragraph above claims.
        delim = rest
        capture = 1
        emit = (left ~ /\.sh[\047"]?[[:space:]]*$/) ? 1 : 0
      }
    }
    next
  }
  $0 == delim { capture = 0; emit = 0; next }
  emit { print }
')

while IFS= read -r -d '' stmt; do
  verbscan=$(printf '%s' "$stmt" | mask_heredoc | mask_comment)
  # Quote-masked, and kept for INGEST. `stmts` already emits an eval / `bash -c`
  # payload as its own statement, so accumulating here picks the payload up as
  # executable text while `echo "..."` prose stays masked out.
  ingest_stmt=$(printf '%s' "$verbscan" | mask_squote | mask_dquote)
  ingest_exempt=0

  if [ "$sleep_seen" -eq 0 ]; then
    case "$verbscan" in
      *sleep*)
        if printf '%s' "$verbscan" | cmdword_is sleep >/dev/null 2>&1; then
          sleep_seen=1
        else
          # A quoted payload handed to a SHELL is code, whatever lib.sh managed
          # to make of it. Measured 2026-09-20: `bash -c "for i in $(seq 1 30);
          # do sleep 60; done"` tokenizes to `bash -c "(); do sleep 60; done"` |
          # `for i in $` | `seq 1 30`, because the `-c` argument mask and the
          # command-substitution span collide, so no statement's command word is
          # `sleep` and a cmdword-only gate closed the door on a required deny.
          # The gate only OPENS the door: every total below is still summed with
          # `cmdword_is`, so `bash -c "grep sleep f"` still totals nothing.
          for sh_verb in eval bash sh zsh; do
            printf '%s' "$verbscan" | cmdword_is "$sh_verb" >/dev/null 2>&1 && { sleep_seen=1; break; }
          done
        fi
        ;;
    esac
  fi

  if [ "$cwd_accumulates" -eq 1 ] && printf '%s' "$verbscan" | cmdword_is cd >/dev/null 2>&1; then
    cd_op=$(printf '%s' "$verbscan" | args | sed -n '2p')
    # `--` is the end-of-options marker, not an option: `cd -- /home/saidler/Claude`
    # moves the cwd exactly as the bare form does. Dropping it here left cur_cwd
    # parked and the ~/Claude policy never saw the destination.
    if [ "$cd_op" = "--" ]; then
      cd_op=$(printf '%s' "$verbscan" | args | sed -n '3p')
    fi
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
  if printf '%s' "$ingest_stmt" | grep -qE '(^|[^-[:alnum:]])borg[[:space:]]+(ingest|reingest|reingest-failed)\b'; then
    stmt_ops=$(printf '%s' "$ingest_stmt" | grep -oE 'borg[[:space:]]+(ingest|reingest-failed|reingest)' | wc -l)
    # Same target counting the command-scope clause uses, so the ceiling means
    # the same thing in both places: `=1` must not admit five URLs.
    stmt_urls=$(printf '%s' "$ingest_stmt" | grep -oE 'https?://[^[:space:]"]+' | wc -l)
    [ "$stmt_urls" -gt "$stmt_ops" ] && stmt_ops="$stmt_urls"
    # Read-only operations are DROPPED from the operation list rather than
    # returning an allow for the command. Round 3 wrote this as "always allow"
    # and `sb borg log; sb borg ingest --file urls.txt` then never reached the
    # deny clauses at all.
    case "$ingest_stmt" in
      *--dry-run*) case "$ingest_stmt" in *reingest*) stmt_ops=0 ;; esac ;;
    esac
    if [ "$stmt_ops" -gt 0 ]; then
      # The door, anchored as a LEADING assignment on this statement so it
      # cannot be smuggled in from a heredoc body or a comment.
      door=$(printf '%s' "$ingest_stmt" | sed -n 's/^[[:space:]]*BULK_INGEST_ORDERED_BY_SCOTT=\([^[:space:];|&]*\).*/\1/p' | head -1)
      if [ -n "$door" ]; then
        case "$door" in
          ''|*[!0-9]*) deny "$INGEST_DOOR_DENY" ;;
        esac
        # <n> is a CEILING and it is compared. Round 3 called it a maximum and
        # then never compared it, so =0 allowed and =1 allowed five ingests.
        if [ "$stmt_ops" -le "$door" ]; then
          # This statement is out of scope now. Its ops are not counted and its
          # text never reaches the clauses, so a later ingest in the same
          # command is still judged on its own.
          stmt_ops=0
          ingest_exempt=1
        else
          deny "BULK_INGEST_ORDERED_BY_SCOTT=$door permits $door ingest occurrences and this statement carries $stmt_ops. Raise the ceiling deliberately or split the command."
        fi
      fi
      ingest_ops=$((ingest_ops + stmt_ops))
    fi
  fi

  # Every executable statement is in INGEST's command-scope window, which is the
  # named exception in the contract: the measured vector puts the ingest in a
  # statement stripped of its loop, so `echo while; sb borg ingest -- <url>`
  # must still deny. Only a door-exempted statement drops out.
  [ "$ingest_exempt" -eq 0 ] && ingest_scope="$ingest_scope
$ingest_stmt"

  if printf '%s' "$verbscan" | cmdword_is git >/dev/null 2>&1; then
    gtoks=" $(printf '%s' "$verbscan" | args | tr '\n' ' ') "
    case "$gtoks" in
      *" add "*)
        # Collected across the WHOLE command. PreToolUse fires before the Bash
        # call, so `git diff --cached` sees the index BEFORE this command's own
        # `git add` runs. The founding incident is exactly that shape and the
        # index holds none of its paths at hook time.
        git_add_args="$git_add_args $(printf '%s' "$verbscan" | args | sed -n '/^add$/,$p' | tail -n +2 | grep -v '^-' | tr '\n' ' ')" ;;
    esac
    case "$gtoks" in
      *" commit "*) git_commit_stmt="$verbscan" ;;
      *" push "*)   git_push_stmt="$verbscan" ;;
    esac
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

if [ "$ingest_ops" -gt 0 ]; then
  scan="$ingest_scope$ingest_heredocs"
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
    # `ingest --all`, not `reingest --all`: the narrower spelling left
    # `sb borg ingest --all` allowed while its sibling denied, and
    # rules/interaction.md names `--all` for BOTH verbs. The pattern still
    # matches `reingest --all`, which contains it.
    *"ingest --all"*)                 deny "$INGEST_DENY (--all is the largest bulk action available)" ;;
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

# PUBLIC-REPO. Runs once per command, after the statement walk, because the
# commit half needs every `git add` in the whole command and not only the one in
# its own statement.
if [ -n "${git_commit_stmt:-}${git_push_stmt:-}" ]; then
  gr=$(repo_root "${cur_cwd:-$payload_cwd}") || gr=""
  if [ -n "$gr" ] && in_scope "$gr"; then
    vis=$(repo_visibility "$gr")
    candidate=""

    if [ -n "${git_commit_stmt:-}" ]; then
      # `-m msg` and friends take operands that are not paths.
      cpaths=$(printf '%s' "$git_commit_stmt" | args | sed -n '/^commit$/,$p' | tail -n +2 | awk '
        /^-m$|^--message$|^--author$|^--date$|^-c$|^-C$|^--fixup$|^--squash$/ { skip = 1; next }
        skip { skip = 0; next }
        /^-/ { next }
        { print }')
      copts=$(printf '%s' "$git_commit_stmt" | args | sed -n '/^commit$/,$p' | tail -n +2 | grep '^-')
      only=0; include=0; all=0
      for o in $copts; do
        case "$o" in
          --only|-o)    only=1 ;;
          --include|-i) include=1 ;;
          --all)        all=1 ;;
          --*)          : ;;
          -*a*)         all=1 ;;
          -*i*)         include=1 ;;
        esac
      done
      # Per commit form, never one blanket union: unioning the whole index into
      # `--only <paths>` produces false denies.
      if [ "$only" -eq 1 ] && [ -n "$cpaths" ]; then
        candidate="$cpaths"
      elif [ -n "$cpaths" ] && [ "$include" -eq 0 ] && [ "$all" -eq 0 ] && [ -z "${git_add_args// /}" ]; then
        candidate="$cpaths"
      else
        for a in $git_add_args; do
          candidate="$candidate
$(expand_operand "$gr" "$a")"
        done
        [ -n "$cpaths" ] && candidate="$candidate
$cpaths"
        candidate="$candidate
$(git -C "$gr" diff --cached --name-only 2>/dev/null)"
        # -a reaches TRACKED files only, which bounds its severity.
        [ "$all" -eq 1 ] && candidate="$candidate
$(git -C "$gr" diff --name-only 2>/dev/null)"
      fi
      # The rule head reads "On `git commit` and `git push` ... deny if the path
      # set contains ... or a blob over 1 MB", and the deny text this branch
      # SHARES advertises the size check, but it existed only in the push branch:
      # `git add big.bin && git commit -m add` allowed a 2 MB blob. On commit the
      # bytes are still in the working tree rather than objects, so size is
      # measured there rather than through cat-file.
      if [ "$vis" = "public" ]; then
        while IFS= read -r cpath; do
          [ -n "$cpath" ] || continue
          [ -f "$gr/$cpath" ] || continue
          csize=$(stat -c %s "$gr/$cpath" 2>/dev/null) || continue
          case "$csize" in ''|*[!0-9]*) continue ;; esac
          [ "$csize" -gt "$BLOB_MAX" ] && deny "$PUBLIC_DENY (a blob over 1 MB: $cpath)"
        done <<CPATHS
$candidate
CPATHS
      fi
    fi

    if [ -n "${git_push_stmt:-}" ]; then
      # Redirects are stripped BEFORE tokenising, the same way the LN path does
      # it. Walking every refspec instead of just the second operand meant the
      # tokens of `2>&1` became refspecs of their own, and `git push origin
      # <branch>:main 2>&1 | tail -5` then denied on a source ref that cannot
      # resolve because it is a redirect. The single-refspec form never saw them.
      # Same class as the slack guard's `2>&1` target bug.
      # The redirect's OPERAND goes too, whether attached (`2>&1`) or separated
      # (`> /dev/null`). Stripping only the operator left `/dev/null` standing
      # as a refspec, which does not resolve, so a perfectly ordinary
      # `git push origin HEAD:main > /dev/null 2>&1` denied.
      pargs=$(printf '%s' "$git_push_stmt" | sed -E 's/[0-9]*>>?&?[[:space:]]*[^[:space:]]*//g' | args | sed -n '/^push$/,$p' | tail -n +2)
      ptoks=$(printf '%s' "$pargs" | grep -v '^-')
      remote=$(printf '%s' "$ptoks" | sed -n '1p')
      [ -n "$remote" ] || remote="origin"
      # EVERY refspec, not just the second operand, and the bulk forms. The
      # shipped code read `sed -n '2p'` and dropped operand 3 onward, so
      # `git push origin main dirty` walked only `main` and published `dirty`.
      # `--all` / `--mirror` carry no refspec at all and pushed every branch
      # past a guard that had nothing to walk. Both are named in the doc's
      # "cases to model" list.
      bulk=0
      case "
$pargs" in
        *"
--all"*|*"
--mirror"*) bulk=1 ;;
      esac
      if [ "$bulk" -eq 1 ]; then
        refspecs=$(git -C "$gr" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
      else
        refspecs=$(printf '%s' "$ptoks" | tail -n +2)
      fi
      if [ -z "$refspecs" ]; then
        refspecs=$(git -C "$gr" symbolic-ref --short HEAD 2>/dev/null)
      fi
      [ -n "$refspecs" ] || deny "$PUBLIC_DENY (no push source could be determined, so the range cannot be computed)"

    while IFS= read -r refspec; do
      [ -n "$refspec" ] || continue
      src="${refspec%%:*}"
      dst="${refspec#*:}"
      [ "$dst" = "$refspec" ] && dst="$src"
      src="${src#+}"
      # `@{u}..HEAD` describes HEAD, not the ref being pushed, and it errors on
      # a fresh branch, which is this repo's normal landing flow. The
      # destination is read from the REMOTE: a push is already a network
      # operation, so one ls-remote is not the hot path.
      # Non-empty is not resolvable. `git push origin nosuchref:main` has a
      # perfectly good-looking source string, and the range built from it makes
      # `git log` fail silently into an empty path set, which ALLOWS. The ref
      # has to actually resolve.
      if [ -z "$src" ] || ! git -C "$gr" rev-parse --verify --quiet "$src" >/dev/null 2>&1; then
        deny "$PUBLIC_DENY (the push source ref does not resolve, so the range cannot be computed)"
      fi
      remote_sha=$(git -C "$gr" ls-remote "$remote" "$dst" 2>/dev/null | awk 'NR==1{print $1}')
      if [ -z "$remote_sha" ]; then
        range="$src"
      elif git -C "$gr" cat-file -e "$remote_sha" 2>/dev/null; then
        range="$remote_sha..$src"
      else
        # Resolves on the remote, object absent locally, so rev-list cannot run.
        # Round 2's text fell straight through this row.
        deny "$PUBLIC_DENY (the push destination resolves remotely but its object is absent locally, so the range cannot be computed)"
      fi
      # --diff-merges=first-parent, because `git log --name-only` shows NO diff
      # for a merge commit, so bytes published through a merge RESOLUTION are
      # invisible to a plain walk. Measured on a synthetic repo whose merge
      # resolution alone added .env.
      candidate="$candidate
$(git -C "$gr" log --format= --name-only --diff-merges=first-parent "$range" 2>/dev/null)"
      # A filename cannot tell a currently-small file from a 4 MB blob earlier
      # in the pushed history, so size is measured over the RANGE.
      if [ "$vis" = "public" ]; then
        big=$(git -C "$gr" rev-list --objects "$range" 2>/dev/null \
          | git -C "$gr" cat-file --batch-check='%(objecttype) %(objectsize) %(rest)' 2>/dev/null \
          | awk -v m="$BLOB_MAX" '$1=="blob" && $2+0 > m+0 {print $3; exit}')
        [ -n "$big" ] && deny "$PUBLIC_DENY (a blob over 1 MB: $big)"
      fi
    done <<REFSPECS
$refspecs
REFSPECS
    fi

    if printf '%s' "$candidate" | grep -v '^$' | paths_are_sensitive; then
      hit=$(printf '%s' "$candidate" | grep -E "$SENSITIVE_RE" | head -1)
      if [ "$vis" = "public" ]; then
        deny "$PUBLIC_DENY (path: $hit)"
      elif revalidate_private "$gr"; then
        deny "$PUBLIC_DENY (path: $hit; the cached 'private' did not survive revalidation)"
      fi
    fi
  fi
fi

# SLEEP. Runs last: it is the least destructive rule here and the only one whose
# cost is paid on commands that are otherwise fine.
#
# Its ENTIRE DOMAIN is what the native check lets through. Probed 2026-09-20 on
# 2.1.278: `validateInput` runs BEFORE the PreToolUse hook chain, so a statement-
# 0 `sleep >= 25` is already refused and never reaches us. What does reach us is
# the three measured bypass classes: B1 position (`echo A; sleep 26`), B2
# chaining (`sleep 24; sleep 24`, which the native deny text names and does not
# enforce), and B3 loop-wrapping, which is the form that actually occurs: 488
# measured polling-loop sleeps, 486 of which ran, 15.9 hours of wall clock.
if [ "$sleep_seen" -eq 1 ] && [ "$run_bg" -eq 0 ]; then
  sleep_total_ms=0
  while IFS=$'\t' read -r kind mult shape text; do
    case "$kind" in
      UNBOUND)
        [ "$(sleep_ms "$text")" -gt 0 ] && deny "this loop sleeps and never terminates on its own (\`$shape\`, with no \`break\` anywhere in its body), so the foreground wait has no bound at all. $SLEEP_ADVICE"
        ;;
      OPEN)
        # Named, not totalled. The guard cannot compute this bound, and saying
        # which shape stopped it is the difference between a rule a reader can
        # work with and one that claims a number it does not have. The sentence
        # says THIS GUARD cannot bound it, not that it cannot be bounded: the
        # count in `for ((i=0; i<3; i++))` is plainly computable and this rule
        # simply does not compute it (audit Q2, 2026-09-20).
        [ "$(sleep_ms "$text")" -gt 0 ] && deny "this loop sleeps and its iteration count is not computable from its bound ($shape), so this guard cannot bound the foreground wait. $SLEEP_ADVICE"
        ;;
      MULT|FLAT)
        sleep_total_ms=$((sleep_total_ms + $(sleep_ms "$text") * mult))
        ;;
    esac
  done < <(printf '%s' "$command" | mask_heredoc | mask_comment | sleep_prep redir | sleep_prep data | loop_spans)
  if [ "$sleep_total_ms" -ge "$SLEEP_T1_MS" ]; then
    secs=$(LC_ALL=C awk -v m="$sleep_total_ms" 'BEGIN { s = m / 1000; if (s == int(s)) printf "%d", s; else printf "%g", s }')
    deny "this command waits ${secs}s in the foreground, summed across its statements and multiplied by each loop's iteration count. The block fires at 25s, which is where the harness's own check fires. $SLEEP_ADVICE"
  fi
fi

echo '{}'
