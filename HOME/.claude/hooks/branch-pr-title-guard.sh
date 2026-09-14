#!/bin/bash
# branch-pr-title-guard.sh: PreToolUse guard: a PR's title MUST match its branch.
#
# Scott's standing rule (2026-07-23): the branch name is the source of truth for
# the PR title. Take the PR title, strip a leading conventional-commit
# `type(scope)!:` prefix, slugify the remainder (lowercase, non-alphanumeric runs
# -> '-', trim), and it MUST equal the head branch name. This makes it impossible
# to open a PR whose title and branch describe different things, on either vector:
#   - Bash:  gh pr create --title "..." [--head <branch>]
#   - MCP:   mcp__multi-account-github__create_pr {title, head}
#
# THE FIX DEPENDS ON THE BRANCH, which is why there are three denial texts. A
# branch holding a `/` or a `.` can never be matched by any title, because
# slugifying collapses both to `-`: the only fix is renaming the BRANCH. 24 of
# the 43 denials the 2026-09-12 audit measured were that shape, two sessions
# burned four consecutive retries against a demand no title could satisfy, and
# five branches were renamed AFTER the block, which general.md forbids once a PR
# is open. On main/master there is no branch to match at all and the fix is to
# create one. Everywhere else the branch is the source of truth and the TITLE is
# what moves. branch-name-guard.sh is the front half of this: it refuses the
# unmatchable branch at creation, so this text is the recovery path for branches
# that already exist.
#
# Parsing is lib.sh's. `stmts` splits the command (heredoc bodies and
# command-substitution spans arrive neutralized, and a `$( )`, backtick or
# `bash -c` body arrives as a record of its own), then mask_comment, then
# `cmdword_is gh`, so a `gh pr create` inside an echo, a grep pattern or a
# commit message is not a false positive. The title comes from
# `flag_value --title -t`, which returns RAW text: a title this hook cannot
# expand (`--title "$(gen-title)"`, `--title "$T"`) is UNKNOWABLE, not a
# mismatch, and passes through rather than being slugified into nonsense.
#
# The branch is resolved in the EFFECTIVE WORKTREE, in this order: `--head`,
# then `--repo` (a PR against a repo that is not this worktree cannot be judged
# from here), then the `cd` in effect at the statement, then a `git -C <dir>` in
# the chain, then the payload's `cwd`. Reading `git branch --show-current` from
# the hook process's own directory evaluated three commands against the wrong
# repo (2026-09-12 audit), and `--repo` was never read at all.
#
# Fails OPEN (passes through) whenever it cannot determine BOTH the title and the
# branch: it never blocks on ambiguity, only on a proven mismatch.
#
# Emits a PreToolUse "deny" decision (with a reason Claude sees), or passes through ({}).
. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')

# The SESSION's directory, which this hook process's cwd is not guaranteed to
# be. Same fail-open shape rewrite-cd-read.py:911-914 has used since 2026-09-03.
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"

# The \x01 a masker leaves behind: a title or branch carrying one came out of a
# command substitution, so its value is unknowable.
MASKCH=$(printf '\001')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Strip leading conventional-commit `type(scope)!:` prefix, lowercase, collapse
# non-alphanumeric runs to '-', trim leading/trailing '-'.
title_slug() {
  printf '%s' "$1" \
    | sed -E 's/^[[:space:]]*[A-Za-z]+(\([^)]*\))?!?:[[:space:]]*//' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# deny on a proven mismatch; return (allow) on match or on missing data.
check() {
  local title="$1" branch="$2" slug bslug
  [ -z "$title" ] && return 0
  [ -z "$branch" ] && return 0
  case "$title" in *'$'* | *'`'* | *"$MASKCH"*) return 0 ;; esac
  case "$branch" in *"$MASKCH"*) return 0 ;; esac
  slug=$(title_slug "$title")
  [ -z "$slug" ] && return 0
  [ "$slug" = "$branch" ] && return 0
  if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
    deny "You are on $branch. Create a feature branch first: \`git checkout -b $slug\`."
  fi
  case "$branch" in
    *[/.]*)
      bslug=$(title_slug "$branch")
      deny "Branch '$branch' can never match a title: slugifying collapses \`/\` and \`.\` to \`-\`. No PR exists yet, so rename the BRANCH: \`git branch -m $bslug\`, push it, then retry with title 'type(scope): $(printf '%s' "$bslug" | tr '-' ' ')'."
      ;;
  esac
  deny "Blocked: PR title must match the branch name (Scott's rule; branch is the source of truth). Branch is '$branch', but the title slugifies to '$slug'. Rewrite the TITLE so that stripping its 'type(scope):' prefix and slugifying the rest equals '$branch': e.g. 'type(scope): $(printf '%s' "$branch" | tr '-' ' ')'. Do NOT rename the branch."
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

# The LAST `git -C <dir>` in the chain whose target exists, so
# `git -C ../other status && gh pr create --title x` is judged in ../other.
# Existence is what disambiguates git's overload of the flag: `git switch -C
# <branch>` and `git commit -C <commit>` do not name directories.
dash_c_tree() {
  local d="" v st
  while IFS= read -r -d '' st; do
    printf '%s' "$st" | mask_comment | cmdword_is git || continue
    v=$(printf '%s' "$st" | flag_value '' -C)
    [ -z "$v" ] && continue
    case "$v" in
      /*) [ -d "$v" ] && d="$v" ;;
      *) [ -d "$cwd/$v" ] && d="$cwd/$v" ;;
    esac
  done < <(printf '%s' "$cmd" | stmts)
  printf '%s' "$d"
}

case "$tool" in
  mcp__multi-account-github__create_pr)
    title=$(printf '%s' "$input" | jq -r '.tool_input.title // ""')
    branch=$(printf '%s' "$input" | jq -r '.tool_input.head // ""')
    branch="${branch##*:}"   # strip any owner: prefix
    check "$title" "$branch"
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
    [ -z "$cmd" ] && { echo '{}'; exit 0; }
    # Statements are numbered off the records `stmts` emits, nested ones
    # included, because that is the index space `cd_at` walks.
    idx=0
    while IFS= read -r -d '' stmt; do
      idx=$((idx + 1))
      masked=$(printf '%s' "$stmt" | mask_comment)
      printf '%s' "$masked" | cmdword_is gh || continue
      printf '%s' "$masked" | grep -Eq '(^|[[:space:]])pr[[:space:]]+create([[:space:]]|$)' || continue
      title=$(printf '%s' "$stmt" | flag_value --title -t)
      branch=$(printf '%s' "$stmt" | flag_value --head -H)
      branch="${branch##*:}"
      if [ -z "$branch" ]; then
        dir=$(stmt_tree "$idx")
        # `--repo <owner>/<name>` puts the PR on a repository this hook cannot
        # read a branch from unless it IS the effective worktree. Unknowable
        # branch, so pass through rather than judging the title against
        # whatever branch happens to be checked out here.
        repo=$(printf '%s' "$stmt" | flag_value --repo -R)
        if [ -n "$repo" ]; then
          git -C "$dir" remote get-url origin 2>/dev/null | grep -Fq -- "$repo" || continue
        fi
        cdir=$(dash_c_tree)
        [ -n "$cdir" ] && [ "$dir" = "$cwd" ] && dir="$cdir"
        branch=$(git -C "$dir" branch --show-current 2>/dev/null)
      fi
      check "$title" "$branch"
    done < <(printf '%s' "$cmd" | stmts)
    ;;
esac

echo '{}'
exit 0
