#!/bin/bash
# branch-name-guard.sh: PreToolUse(Bash) guard: a NEW branch name is a flat
# lowercase slug.
#
# rules/git.md "Branch names": the name is a flat slug (`retire-general-plugin`),
# never a type/scope path (`chore/retire-general-plugin`), never `_`, never
# uppercase. The conventional-commit type belongs in the PR TITLE. Why it is
# absolute: branch-pr-title-guard.sh slugifies the title to compare it to the
# branch, and slugifying collapses `/` and `.` to `-`, so a slashed branch can
# never be matched by ANY title and its PR becomes unopenable. Twelve slashed
# branches were created 2026-06-26 to 2026-09-12 (2026-09-12 audit, item 5),
# one of them burning four consecutive blocked `gh pr create` attempts. The
# prose rule landed after the fact with nothing enforcing it; this is the hook.
#
# WIRING: PreToolUse on Bash, appended to the array in ~/.claude/settings.json.
# Registration order does NOT pick which reason a model sees: measured over
# seven runs 2026-09-14, the surfacing reason is the one from the LAST hook to
# COMPLETE, a race no slot controls. So this deny text stands on its own and
# names the flat slug to use. A command that trips BOTH this guard and
# git-release-guard.sh's Gate C (`git checkout -b chore/bump-0.9.0`) converges
# in at most two round trips whichever reason surfaces: Gate C's says not to
# create the release branch at all, this one says what a legal name looks like.
#
# Parsing is lib.sh's. `stmts` splits the command (heredoc bodies and
# command-substitution spans arrive already neutralized, and a `$( )`, backtick
# or `bash -c` body arrives as a record of its own, because the shell runs it),
# then mask_comment, then `cmdword_is git` / `cmdword_is gh`. NO mask_optarg,
# per the Data Model's row: the branch name is the thing being judged. It is not
# needed for the false-positive class either, because the name is read by
# argument ROLE off `args`: a quoted `-m` message is ONE argument, so
# `git tag -a v1 -m "switch -c Bad/Name"` has no token equal to `switch`.
#
# Known limit, stated rather than papered over: Scott drives worktrees through
# the `worktree` CLI, which hands the branch name to git internally where no
# command-text matcher can see it. Every measured case was a `git checkout -b`
# or `gh pr create --head` shape; a slashed branch created through that CLI is
# the CLI's fix, not this hook's.
#
# Emits a PreToolUse "deny" decision (with a reason Claude sees), or {}.
. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
[ -z "$cmd" ] && { echo '{}'; exit 0; }

# The SESSION's directory, which this hook process's cwd is not guaranteed to
# be. Same fail-open shape rewrite-cd-read.py:911-914 has used since 2026-09-03.
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"

# The \x01 a masker leaves behind. A name carrying one came out of a command
# substitution, so what it expands to is unknowable and it passes through.
MASKCH=$(printf '\001')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# branch-pr-title-guard.sh:title_slug, verbatim, so the name this guard OFFERS
# is a name that guard will accept beside a matching title.
slugify() {
  printf '%s' "$1" \
    | sed -E 's/^[[:space:]]*[A-Za-z]+(\([^)]*\))?!?:[[:space:]]*//' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# Worktree the statement at index <n> runs in: the `cd` in effect AT it, not the
# last `cd` in the chain, resolving a relative target against the session cwd.
stmt_tree() { # stmt_tree <statement index>
  local at d="$cwd"
  at=$(printf '%s' "$cmd" | cd_at "$1")
  case "$at" in
    ""|-) ;;
    /*) [ -d "$at" ] && d="$at" ;;
    *) [ -d "$cwd/$at" ] && d="$cwd/$at" ;;
  esac
  printf '%s' "$d"
}

# [[:upper:]] rather than [A-Z]: a bracket RANGE in a glob follows the locale's
# collation order, which in a UTF-8 locale matches lowercase letters too.
judge() { # judge <offered new branch name>
  local n="$1" slug
  [ -z "$n" ] && return 0
  case "$n" in *"$MASKCH"*) return 0 ;; esac
  case "$n" in
    *[/_]* | -* | *-) ;;
    *[[:upper:]]*) ;;
    *) return 0 ;;
  esac
  slug=$(slugify "$n")
  [ -z "$slug" ] && return 0
  deny "Blocked: branch '$n'. Branch names are a flat lowercase slug: no \`/\`, no \`_\`, no uppercase. Use \`$slug\`. The conventional-commit type goes in the PR TITLE, never the branch (rules/git.md)."
}

# The NEW name a git statement would create, by argument position. `branch`
# anchors where Gate C anchors (git-release-guard.sh's bump-name gate), which is
# what keeps `git branch -d x` and `git branch --list 'x*'` out: the flag
# between `branch` and the name breaks the match. A rename is the sanctioned fix
# for a bad name, so `-m` is judged on where it LANDS: the last operand.
new_names() { # new_names <masked statement>
  printf '%s' "$1" | args | awk '
    { t[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (t[i] == "checkout") {
          for (j = i + 1; j <= NR; j++) if (t[j] == "-b" || t[j] == "-B") { print t[j + 1]; break }
          exit
        }
        if (t[i] == "switch") {
          for (j = i + 1; j <= NR; j++) if (t[j] == "-c" || t[j] == "-C" || t[j] == "--create") { print t[j + 1]; break }
          exit
        }
        if (t[i] == "branch") {
          if (i < NR && t[i + 1] !~ /^-/) { print t[i + 1]; exit }
          move = 0
          last = ""
          for (j = i + 1; j <= NR; j++) {
            if (t[j] == "-m" || t[j] == "-M" || t[j] == "--move") { move = 1; continue }
            if (t[j] ~ /^-/) continue
            last = t[j]
          }
          if (move && last != "") print last
          exit
        }
        if (t[i] == "worktree") {
          for (j = i + 1; j <= NR; j++) if (t[j] == "add") break
          for (k = j + 1; k <= NR; k++) if (t[k] == "-b" || t[k] == "-B") { print t[k + 1]; break }
          exit
        }
      }
    }'
}

# Statements are numbered off the records `stmts` emits, nested ones included,
# because that is the index space `cd_at` walks.
idx=0
while IFS= read -r -d '' stmt; do
  idx=$((idx + 1))
  masked=$(printf '%s' "$stmt" | mask_comment)

  if printf '%s' "$masked" | cmdword_is git; then
    while IFS= read -r name; do
      judge "$name"
    done <<< "$(new_names "$masked")"
    continue
  fi

  # `gh pr create --head <name>` names a branch that USUALLY already exists, and
  # an existing branch is not a new name: judging it would demand a rename of
  # something with commits on it. So this fires only when the name has no local
  # ref. An `owner:branch` form is split on the LAST `:`, the same as
  # branch-pr-title-guard.sh does.
  printf '%s' "$masked" | cmdword_is gh || continue
  printf '%s' "$masked" | grep -Eq '(^|[[:space:]])pr[[:space:]]+create([[:space:]]|$)' || continue
  head=$(printf '%s' "$stmt" | flag_value --head -H)
  head="${head##*:}"
  [ -z "$head" ] && continue
  git -C "$(stmt_tree "$idx")" show-ref --verify --quiet "refs/heads/$head" && continue
  judge "$head"
done < <(printf '%s' "$cmd" | stmts)

echo '{}'
exit 0
