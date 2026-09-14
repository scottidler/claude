#!/bin/bash
# git-release-guard.sh -- PreToolUse(Bash) hook enforcing Scott's release rules
# MECHANICALLY, at the moment of the command. Prose rules (rules/git.md, the
# /bump skill, memories, ~/HALL-OF-SHAME.md) provably do not hold deep in a
# session; this hook is the layer that cannot be forgotten or ignored.
#
# WIRING: registered as a PreToolUse hook on the Bash tool in Claude Code
# settings (~/.claude/settings.json). The harness pipes the tool-call JSON to
# stdin before EVERY shell command any agent runs; this script prints {} to
# allow, or a deny decision whose reason the agent sees verbatim.
#
# CLI (run manually, no stdin needed):
#   git-release-guard.sh --help        print this documentation
#   git-release-guard.sh --self-test   run the full deny/allow regression
#                                      matrix (git-release-guard-test.sh,
#                                      same directory) against a fixture repo
#
# THE TWO LEGAL RELEASE FLOWS (there is no third; `bump --gates` decides). In
# BOTH of them the VERSION COMMIT lands first and the TAG WAITS for green CI on
# that exact SHA; neither flow ever tags a local HEAD up front. Why the wait: a
# tag is the only irreversible artifact in a release, so a tag cut before CI
# means every failure CI finds can only be repaired by ANOTHER tag, and one
# intended release burns two version numbers (the double-tap: otto v2.0.0/v2.0.1,
# v2.0.2/v2.0.3, v2.0.4/v2.0.5). Landing the version commit untagged costs
# nothing when CI is red: fix it, re-run, and the SAME number gets tagged.
#   UNGATED main:  bump --no-tag [-m|-M]           version commit on main, and
#                                                  NO tag exists yet
#                  git push --no-follow-tags origin main
#                  (WAIT for CI green on that SHA)
#                  bump --tag-only && git push origin vX.Y.Z
#   GATED main:    bump --no-tag [-m|-M]           on the FEATURE branch; the
#                                                  version commit rides that PR
#                  (merge) then: git checkout main && git pull --ff-only
#                  bump --tag-only && git push origin vX.Y.Z
# `~/.claude/bin/release` executes either flow, the wait included; it is the
# deterministic driver and the canonical wording is its header plus the /bump
# skill's FLOW 1 and FLOW 2.
#
# GATE CATALOG (each entry names the incident that created it):
#   Tags       never `git tag -d`, never push --tags/--follow-tags, never
#              remote tag deletion (orphaned okta-auth-rs v0.2.0)
#   Tag force  never `git tag -f/--force` (including the combined short forms
#              -fa / -af): moving a tag is Scott's call, never an agent's
#   Off-main   no tag CREATION off main/master; a tag cut on a branch is burnt
#     tag      forever because squash-merge rewrites the SHA
#   Force-push never --force to main/master without Scott
#   Gated main no `git commit` on main/master when origin names tatari-tv:
#              that main is PR-gated (rules/git.md "Pushing to main")
#   Dirty bump version-committing bump on a dirty tree stages EVERYTHING
#              (scratch jpgs got committed this way)
#   Branch tag any tag-creating bump off main (squash-merge burns the SHA)
#   Gate C     no creating bump-*/release-* branches      (slack-cli #16)
#   Gate A     no `bump --no-tag` on a branch with zero commits ahead of
#              origin/<default> -- the bump would be its only content
#                                                         (slack-cli #16)
#   Gate B     no push / `gh pr create` of a branch whose ENTIRE diff vs
#              origin/<default> is version lines + lockfiles, regardless of
#              branch name; dep bumps and lockfile-only refreshes pass
#                                                         (slack-cli #16)
#   Gate D     every `gh pr create` on a release-managed repo (root manifest
#              with a version line; v* tags NOT required -- requiring them
#              exempted never-tagged repos, okta-auth-py #5/#6) must declare
#              'Release: rides this PR (vX.Y.Z)' or 'Release: none -- <why>'
#              in the body; a rides claim must match an actual version-line
#              change in the diff. Forces the release decision at PR time --
#              merging bumpless creates a deadlock no recovery gate can fix
#                                (slack-cli #14/#15, mcp-io #6/#7, okta-auth-py)
#   Tree loss  git clean -f with untracked files, reset --hard on a dirty tree,
#              and TREE-WIDE checkout/restore reverts -> use `rkvr rmrf`,
#              recoverable. A PATH-SCOPED revert naming explicit literal paths
#              is allowed: the measured harm was the dodge, not the revert (66
#              denials produced 12 `git show HEAD:f > f` workarounds, which
#              destroy the same bytes with no guard in front of them)
#
# THE DOOR (Scott approved 2026-07-10): BUMP_ORDERED_BY_SCOTT=1 in the command
# bypasses gates A/B/C only. Legal SOLELY when Scott explicitly ordered a
# standalone bump (e.g. "bump finish it" with no feature PR to fold into) --
# that is THE RULING's ask-Scott clause, answered; do not re-ask. The marker is
# transcript-visible on every use and Scott's ordering words must be quoted in
# the PR body. Using it without a real order is a hall-of-shame offense.
# First sanctioned use: mcp-io-rs #8 (v0.1.3), 2026-07-10.
#
# MECHANICS: parsing is `lib.sh`'s shared, quote-aware parser, sourced below.
# `stmts` splits the command into statements on && || ; | and newlines, but it
# does it on a quote-aware pass, so a `;` or `|` inside a quoted argument no
# longer severs a statement. Every statement it emits arrives with its heredoc
# bodies and its command-substitution spans already neutralized, and every
# NESTED statement (a `$( )` body, a backtick body, a `bash -c` argument) arrives
# as a record of its own, because the shell runs those. So a match cannot bleed
# across an unrelated sibling (a `git push` in one statement plus `--tags` in a
# later `git ls-remote --tags` is not a false positive), a heredoc message line
# is never read as a command (a `git commit -F - <<'MSG'` line beginning with
# "bump" denied an innocent commit, otto-rs/otto b428680 2026-09-01), and a
# `git push origin "$(git describe --tags)"` is judged as the two commands it is.
# Each statement is then comment- and optarg-masked before any gate matches it:
# a flag sitting in the VALUE of `-m` is prose, not an option, so
# `git tag -a v1 -m "added --force"` names a flag without using one. Values
# (`--head`, `--body-file`) are read from the statement itself via `flag_value`,
# never off the mask. Every gate matching a git operation is anchored with
# `cmdword_is git`, so `echo "git push --tags"` and this hook's own `--help` are
# not pushes. Gate D searches the FULL, unstripped command for the Release: line
# because PR bodies are multi-line and usually arrive by heredoc.
# Branch and tree state are read in the payload's `cwd` (the SESSION's
# directory; this hook process's cwd is not guaranteed to be it), and a
# `cd <dir>` in the chain is honored. WHICH `cd` differs by gate, and the two
# answers are not interchangeable. The bump gates use `cd_target`, the LAST cd
# in the chain, because `cd <main worktree> && bump` puts the cd first and the
# question is where the bump lands. Every per-statement gate (tag creation,
# commit on a gated main, and the destructive tree ops) uses `cd_at <n>`, the cd
# in effect AT that statement, because `git checkout -- f && cd /somewhere-clean`
# would otherwise be judged against the clean tree and allowed to discard the
# work in the dirty one.
#
# PROVENANCE: THE RULING 2026-07-03 (~/HALL-OF-SHAME.md) after slack-cli
# v0.1.1; gates A/B/C + recovery messages 2026-07-10 after slack-cli #16;
# Gate D + the door 2026-07-10 (Scott approved both) after mcp-io-rs #6/#7;
# Gate D widened to never-tagged repos 2026-07-13 after okta-auth-py #5/#6.
# Companion docs: /bump skill (agent-facing flows), rules/git.md (the law),
# ~/HALL-OF-SHAME.md (the case history).

case "${1:-}" in
  -h|--help)
    # Print the leading comment block (this documentation), sans shebang.
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit 0
    ;;
  --self-test)
    exec bash "$(dirname "$0")/git-release-guard-test.sh"
    ;;
esac

# The shared parser. Sourced AFTER the CLI dispatch so --help and --self-test
# work with or without it. A missing library passes the Bash call through rather
# than denying every command in the session; hooks-preflight.sh reports the gap
# at the next session start.
. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // ""')
[ -z "$cmd" ] && { echo '{}'; exit 0; }

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# The PreToolUse payload carries the SESSION's working directory. This hook
# process's cwd is not guaranteed to be it, and every git read below used to
# assume it was. Read the payload's `cwd`, falling back to $PWD when the field
# is absent, which is the same fail-open shape rewrite-cd-read.py:911-914 has
# used since 2026-09-03.
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"

branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)

# Effective worktree a `bump` in this command will actually run in. Scott's release
# flow is `cd <main-worktree> && bump`, but this hook runs once for the SESSION
# (often a feature-branch worktree), so a branch read there falsely denies a bump
# that targets main. Honor a `cd <dir>` in the same command chain (lib.sh's
# `cd_target`: the LAST one, in command position) and evaluate the branch + tree
# state in THAT directory, resolving a relative target against the session cwd.
# No cd means the session cwd, so a bare `bump` on a feature branch is still
# correctly blocked. The destructive-op gates deliberately do NOT use this: for
# them the question is which worktree the statement itself runs in, not where a
# later `cd` lands.
bump_dir="$cwd"
cd_dir=$(printf '%s' "$cmd" | cd_target)
case "$cd_dir" in
  ""|-) ;;
  /*) [ -d "$cd_dir" ] && bump_dir="$cd_dir" ;;
  *) [ -d "$cwd/$cd_dir" ] && bump_dir="$cwd/$cd_dir" ;;
esac
bump_branch=$(git -C "$bump_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
bump_porcelain=$(git -C "$bump_dir" status --porcelain 2>/dev/null)

# Worktree in effect AT the statement being judged, which is NOT `bump_dir`.
# `cd_at <n>` is the last `cd` BEFORE statement n, so `git checkout -- f && cd
# /somewhere-clean` resolves statement 1 to the DIRTY tree the revert actually
# runs in; `cd_target` would resolve it to the clean one and allow the loss.
# Measured against the live guard before this: session-clean plus target-dirty
# allowed a `git reset --hard` against a dirty tree.
#
# Resolved lazily and cached per statement, because most statements trip no
# tree-reading gate and the resolve costs an awk pass plus two git calls.
stmt_idx=0
stmt_dir=""
stmt_porcelain=""
stmt_untracked=0
stmt_branch=""
resolve_stmt_tree() {
  [ -n "$stmt_dir" ] && return 0
  local at d="$cwd"
  at=$(printf '%s' "$cmd" | cd_at "$stmt_idx")
  case "$at" in
    ""|-) ;;
    /*) [ -d "$at" ] && d="$at" ;;
    *) [ -d "$cwd/$at" ] && d="$cwd/$at" ;;
  esac
  stmt_dir="$d"
  stmt_porcelain=$(git -C "$stmt_dir" status --porcelain 2>/dev/null)
  stmt_untracked=$(printf '%s\n' "$stmt_porcelain" | grep -c '^??')
  stmt_branch=$(git -C "$stmt_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
}

# Argument ROLE, not a substring, is what two gates in here need: the revert
# gate has to know that every operand is an explicit literal path, and the tag
# gate has to know whether a tag NAME is present at all (`git tag` alone lists).
# That walk is `lib.sh`'s `args` (promoted out of this file in Phase 5, when
# `branch-name-guard.sh` needed the same one), and the CALLER picks its input: a
# `$` or a backtick has to survive into the token for the revert gate to refuse
# it, so that gate feeds `args` the statement itself; the tag gate feeds it the
# MASKED copy, so a word inside a `-m` value is never read as a tag name. Same
# tokenizer, different input, which is the Data Model's "match on the mask,
# extract from the original" contract with the caller choosing.

# The \x01 a masker leaves behind. An argument carrying one was a command
# substitution or a masked flag value, so it is not a literal path either.
MASKCH=$(printf '\001')

# Remote default-branch ref (origin/main | origin/master), or empty when there is
# no remote, in which case the bump-only gates self-skip on local-only repos.
default_base() {
  local d="$1" ref b
  ref=$(git -C "$d" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$ref" ]; then printf '%s' "${ref#refs/remotes/}"; return; fi
  for b in origin/main origin/master; do
    if git -C "$d" rev-parse --verify --quiet "$b" >/dev/null 2>&1; then
      printf '%s' "$b"; return
    fi
  done
}

# Returns 1 iff <ref>'s entire diff vs origin/<default> is a version bump and
# nothing else: every changed file is a version manifest or lockfile, AND every
# changed non-lockfile line is a `version =` / `"version":` line. A dep bump
# (Cargo.toml dep line + lock) or a lockfile-only refresh does NOT qualify.
is_bump_only_ref() {
  local d="$1" ref="$2" base files f diff_lines
  base=$(default_base "$d"); [ -z "$base" ] && return 0
  git -C "$d" rev-parse --verify --quiet "$ref" >/dev/null 2>&1 || return 0
  [ "$(git -C "$d" rev-list --count "$base..$ref" 2>/dev/null || echo 0)" = "0" ] && return 0
  files=$(git -C "$d" diff --name-only "$base...$ref" 2>/dev/null)
  [ -z "$files" ] && return 0
  while IFS= read -r f; do
    case "$f" in
      Cargo.toml|Cargo.lock|package.json|package-lock.json|pnpm-lock.yaml|yarn.lock|pyproject.toml|uv.lock|VERSION) ;;
      *) return 0 ;;   # real work is in the diff, so not bump-only
    esac
  done <<< "$files"
  diff_lines=$(git -C "$d" diff "$base...$ref" -- Cargo.toml package.json pyproject.toml VERSION 2>/dev/null \
    | grep -E '^[-+]' | grep -Ev '^(\+\+\+|---)')
  [ -z "$diff_lines" ] && return 0   # lockfile-only change, allowed
  if printf '%s\n' "$diff_lines" | grep -Evq '^[-+][[:space:]]*"?version"?[[:space:]]*[:=]'; then
    return 0                          # a non-version manifest line changed, allowed
  fi
  return 1
}

check_stmt() {
  local s="$1"

  # Per-statement worktree cache. `stmt_idx` is the statement's position in the
  # sequence `stmts` emits, counted straight off the records with nothing
  # filtered or reordered, because that is the same index space `cd_at` walks.
  stmt_idx="$2"
  stmt_dir=""
  stmt_porcelain=""
  stmt_untracked=0
  stmt_branch=""

  # Match on a MASKED copy, extract values from the statement itself. `stmts`
  # handed this statement over with its heredoc bodies and its command-
  # substitution spans already neutralized (the nested ones arrive as their own
  # statements), so what is left to mask here is the pair the Data Model's row
  # for these gates names: comments, and the VALUE of a message-carrying flag.
  local m
  m=$(printf '%s' "$s" | mask_comment | mask_optarg)

  # The command word, computed once. Every gate below that matches a git or gh
  # operation is anchored on it: the gate regexes match anywhere in a statement,
  # so without the anchor `echo "git tag -f v1"` and `git-release-guard.sh
  # --help` trip gates they have nothing to do with.
  local is_git=0 is_gh=0 is_bump=0
  printf '%s' "$m" | cmdword_is git && is_git=1
  printf '%s' "$m" | cmdword_is gh && is_gh=1
  printf '%s' "$m" | cmdword_is bump && is_bump=1

  # Scott-override for the bump-only gates (Scott approved adding this door
  # 2026-07-10): a transcript-visible marker that Scott EXPLICITLY ordered a
  # standalone bump (e.g. "bump finish it" with no feature PR open to fold
  # into). The gates below stop AGENT-invented bump-only branches; this is THE
  # RULING's ask-Scott clause, answered. The marker must ride IN the command
  # (env-prefix form) so the transcript shows every use, and Scott's ordering
  # words must be quoted in the PR body. Setting it WITHOUT a real order from
  # Scott is a hall-of-shame offense. Read off the mask, so the marker cannot
  # open the door from inside a commit message.
  local scott_override=0
  if printf '%s' "$m" | grep -q 'BUMP_ORDERED_BY_SCOTT=1'; then
    scott_override=1
  fi

  # ---- Tags: never delete, never bulk-push (git.md "Tags") ----
  if [ "$is_git" -eq 1 ] && printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+tag[[:space:]]+(-d|--delete)\b'; then
    deny "git.md: NEVER delete a tag (refusing 'git tag -d/--delete'). If a tag must move or be recreated, ask Scott to do it himself."
  fi
  # Moving a tag is Scott's call and never an agent's, so -f/--force on `git tag`
  # is refused whatever it points at. The short form has to be matched as a
  # CLUSTER (`-fa`, `-af`), because that is the spelling a model actually types
  # and a `[[:space:]]-f\b` test misses both. -F is a different flag entirely
  # (a message file), which the lowercase-only `f` keeps out of the match, and
  # `git tag -a v1 -m "added --force"` is prose: mask_optarg erased that value
  # before this line ran.
  if [ "$is_git" -eq 1 ] && printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+tag\b' \
     && printf '%s' "$m" | grep -Eq '(^|[[:space:]])(--force([[:space:]]|=|$)|-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$))'; then
    deny "git.md: NEVER move a tag. If a tag must move, ask Scott to do it himself."
  fi

  # Tag CREATION off main/master. Creation is `git tag [-a|-s|-m] <name>` with a
  # NAME present and none of git's read/delete flags, which is what separates it
  # from `git tag` (lists), `git tag -l 'v*'` (lists) and `git tag -d v1` (the
  # gate above). The name check runs on the MASKED statement, so the `-d` inside
  # `git tag -a v1 -m "fix the -d flag"` is a message word and that command is
  # correctly read as a creation rather than a deletion.
  if [ "$is_git" -eq 1 ] && printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+tag\b' \
     && ! printf '%s' "$m" | grep -Eq '(^|[[:space:]])(-d|--delete|-l|--list|-v|--verify|-n[0-9]*|--contains|--no-contains|--points-at|--merged|--no-merged|--sort|--format|--column)([[:space:]]|=|$)'; then
    local tagname="" targ seen_tag=0
    while IFS= read -r targ; do
      if [ "$seen_tag" -eq 0 ]; then
        [ "$targ" = "tag" ] && seen_tag=1
        continue
      fi
      case "$targ" in
        -*) continue ;;
        "") continue ;;
        *"$MASKCH"*) continue ;;
      esac
      tagname="$targ"
      break
    done <<< "$(printf '%s' "$m" | args)"
    if [ -n "$tagname" ]; then
      resolve_stmt_tree
      if [ -n "$stmt_branch" ] && [ "$stmt_branch" != "main" ] && [ "$stmt_branch" != "master" ]; then
        deny "git.md: tags are cut on main only. A tag on a branch is burnt: squash-merge rewrites the SHA. (Worktree '$stmt_dir' is on '$stmt_branch'.) The gated flow is 'bump --no-tag' on this branch so the version commit rides the PR, then after the merge, on updated main: bump --tag-only && git push origin vX.Y.Z"
      fi
    fi
  fi

  if [ "$is_git" -eq 1 ] && printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+push\b.*(--tags|--follow-tags)\b'; then
    deny "git.md: never 'git push --tags'/'--follow-tags' (the tag lands even if the branch push is rejected, and this orphaned okta-auth-rs v0.2.0). Push the branch first, then the tag by explicit name: git push origin vX.Y.Z"
  fi
  if [ "$is_git" -eq 1 ] \
     && { printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+push\b.*(--delete|[[:space:]]-d\b).*(refs/tags/|(^|[[:space:]])v[0-9])' \
          || printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+push\b.*:[[:space:]]*(refs/tags/|v[0-9])'; }; then
    deny "git.md: refusing what looks like a remote TAG deletion. NEVER delete tags. (If you truly meant a branch, delete it via 'gh' or name 'refs/heads/<branch>' explicitly.)"
  fi

  # ---- Bump-only release branches: forbidden forever (THE RULING 2026-07-03) ----
  # Gate C: never even CREATE a branch named like a release/bump branch.
  # (Deletion `git branch -d bump-*` and `git branch --list 'bump*'` stay
  # allowed: the flag between `branch` and the name breaks the match.)
  #
  # The name is EXTRACTED and then matched, never matched against the whole
  # statement. Two things follow, and both were defects in the statement-wide
  # form: `git checkout -b chore/bump-0.9.0` matches, because `(^|/)` anchors
  # the prefix at a path segment and not just at the start of the string, and
  # `git commit -m 'mention bump-1.0.0'` does not, because there is no branch
  # name in it at all.
  local newbr=""
  if printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+(checkout|switch|branch)\b'; then
    newbr=$(printf '%s' "$m" | args | awk '
      { t[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) {
          if (t[i] == "checkout") {
            for (j = i + 1; j <= NR; j++) if (t[j] == "-b" || t[j] == "-B") { print t[j + 1]; exit }
            exit
          }
          if (t[i] == "switch") {
            for (j = i + 1; j <= NR; j++) if (t[j] == "-c" || t[j] == "-C" || t[j] == "--create") { print t[j + 1]; exit }
            exit
          }
          if (t[i] == "branch") {
            if (t[i + 1] !~ /^-/) print t[i + 1]
            exit
          }
        }
      }')
  fi
  if [ "$is_git" -eq 1 ] && [ "$scott_override" -eq 0 ] && [ -n "$newbr" ] \
     && printf '%s' "$newbr" | grep -Eq '(^|/)(bump|release)[-/]'; then
    deny "DENIED: creating a bump-*/release-* branch ('$newbr'). A bump-only release branch is forbidden forever, for ANY reason (THE RULING 2026-07-03, ~/HALL-OF-SHAME.md; slack-cli #16 recommitted exactly this on 2026-07-10). WHY: the version bump is not standalone work, it RIDES the feature PR ('bump --no-tag' on the feature branch, before that PR merges; the tag is cut on main after the merge with 'bump --tag-only'). WHAT TO DO NOW: if you were about to bump for work that already merged without its bump, the ONLY sanctioned move is STOP and ask Scott: his default is folding the bump into the NEXT feature PR. DO NOT retry with a different branch name, do not hand-edit the version, do not route around this hook (sibling gates catch content-based bump-only pushes/PRs too). Read the /bump skill before touching anything release-related."
  fi

  # ---- Force-push to main/master (git.md "Pushing to main") ----
  if [ "$is_git" -eq 1 ] && printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+push\b.*(--force|--force-with-lease|[[:space:]]-f\b)'; then
    if printf '%s' "$m" | grep -Eqw '(main|master)' || [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
      deny "git.md: never force-push main/master without explicit approval from Scott. Stop and report; let him run it."
    fi
  fi

  # ---- Commit on a PR-gated main (git.md "Pushing to main") ----
  # Work repos gate main behind a PR, so a commit landing there is work that can
  # never be pushed and has to be moved off main by hand. Scoped by the origin
  # URL of the STATEMENT's worktree rather than by branch alone, so personal
  # repos, whose main takes direct pushes, are untouched. Reading the remote can
  # fail (no origin, not a repo), and this is a deny, so a failed read falls
  # through to allowing rather than to refusing a commit it knows nothing about.
  if [ "$is_git" -eq 1 ] && printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+commit\b'; then
    resolve_stmt_tree
    if [ "$stmt_branch" = "main" ] || [ "$stmt_branch" = "master" ]; then
      if git -C "$stmt_dir" remote get-url origin 2>/dev/null | grep -q 'tatari-tv'; then
        deny "git.md: 'tatari-tv/*' main is PR-gated. Branch first. Worktree '$stmt_dir' is on '$stmt_branch' with a tatari-tv origin, so this commit could never be pushed: 'git checkout -b <flat-slug>' first, then commit, then open the PR."
      fi
    fi
  fi

  # ---- bump: release flow (rules/git.md release section + Scott's workflow) ----
  # `bump` counts ONLY in command position, which is what `cmdword_is bump`
  # decides (leading env-assignments and a path prefix allowed). This is the fix
  # for the substring false-positive that blocked unrelated commands merely
  # *mentioning* bump: `git commit -m "...bump..."`, a `bump-*` branch name,
  # `echo bump`, etc.
  if [ "$is_bump" -eq 1 ] \
     && ! printf '%s' "$m" | grep -Eq 'bump.*(--gates|--dry-run|--help|--version|[[:space:]]-n\b|[[:space:]]-h\b|[[:space:]]-V\b)'; then
    if [ -n "$bump_branch" ] && [ "$bump_branch" != "main" ] && [ "$bump_branch" != "master" ]; then
      # On a feature branch exactly ONE bump form is legal: `bump --no-tag`.
      # That is the gated flow, where the version commit rides the feature PR.
      # Any tag-creating form (plain bump, -m/-M without --no-tag, --tag-only)
      # is blocked: a tag cut on a branch is burnt forever (squash rewrites the SHA).
      if ! printf '%s' "$m" | grep -Eq '\bbump\b.*--no-tag'; then
        deny "Release flow: on a feature branch the ONLY legal bump is 'bump --no-tag', because the version commit rides the feature PR (never a tag on a branch, never a bump-only release branch). Tags are cut on main AFTER the PR merges: git checkout main && git pull --ff-only origin main && bump --tag-only && git push origin vX.Y.Z. (Target worktree '$bump_dir' is on '$bump_branch'.)"
      fi
      # Gate A: 'bump --no-tag' is legal ONLY on a branch that carries real work.
      # Zero commits ahead of origin/<default> means the bump commit would be the
      # branch's ONLY content, i.e. a bump-only release branch in the making.
      base=$(default_base "$bump_dir")
      if [ "$scott_override" -eq 0 ] \
         && [ -n "$base" ] && [ "$(git -C "$bump_dir" rev-list --count "$base..HEAD" 2>/dev/null || echo 1)" = "0" ]; then
        deny "DENIED: 'bump --no-tag' on branch '$bump_branch', which has ZERO commits ahead of $base, so the bump commit would be this branch's ONLY content, i.e. a bump-only release branch, forbidden forever (THE RULING 2026-07-03, ~/HALL-OF-SHAME.md; slack-cli #16 recommitted exactly this on 2026-07-10). WHY: the version bump is not standalone work, it rides a feature branch WITH its work: commit the real change first, THEN 'bump --no-tag' on that branch, push, PR; after merge: git checkout main && git pull --ff-only && bump --tag-only && git push origin vX.Y.Z. WHAT TO DO NOW: if the work already merged without its bump, the ONLY sanctioned move is STOP and ask Scott: his default is folding the bump into the NEXT feature PR, never a retrofitted branch. DO NOT retry on a renamed branch or hand-edit the version; sibling gates catch those too. Read the /bump skill."
      fi
    fi
    if ! printf '%s' "$m" | grep -Eq '\bbump\b.*--tag-only'; then
      if [ -n "$bump_porcelain" ]; then
        deny "bump stages everything (git add -A) and the target worktree '$bump_dir' is dirty, so it would sweep untracked/modified files into the version commit (this is exactly how scratch jpgs got committed). Commit your real changes, then 'rkvr rmrf' or stash the strays, THEN bump on a clean tree."
      fi
    fi
  fi

  # ---- Gate B: no pushing / PR-ing a bump-only branch (content-based) ----
  # Catches the crime even if the branch name is innocent or the version was
  # hand-edited: if everything the push/PR would land vs origin/<default> is
  # version lines + lockfiles, it IS a bump-only release branch. Deletions
  # (--delete / ':ref' refspecs) push no content and are skipped.
  if [ "$scott_override" -eq 0 ] && { [ "$is_git" -eq 1 ] || [ "$is_gh" -eq 1 ]; } \
     && printf '%s' "$m" | grep -Eq '\b(git[[:space:]]+push|gh[[:space:]]+pr[[:space:]]+create)\b' \
     && ! printf '%s' "$m" | grep -Eq '(--delete|[[:space:]]-d[[:space:]]|[[:space:]]:[^[:space:]])'; then
    gateb_ref=""
    if [ "$is_gh" -eq 1 ] && printf '%s' "$m" | grep -Eq '\bgh[[:space:]]+pr[[:space:]]+create\b'; then
      gateb_ref=$(printf '%s' "$s" | flag_value --head)
    else
      # git push [flags] <remote> <refspec>: take the last non-flag token, strip a src: prefix
      gateb_ref=$(printf '%s' "$s" | awk '{r=""; n=0; for(i=1;i<=NF;i++){ if($i !~ /^-/ && $i !~ /[=<>&]/){n++; if(n>=4) r=$i} } print r}')
      gateb_ref="${gateb_ref%%:*}"; gateb_ref="${gateb_ref#+}"
    fi
    # No explicit refspec (or it isn't a local branch) -> the current branch is what's pushed
    if [ -z "$gateb_ref" ] || ! git -C "$bump_dir" rev-parse --verify --quiet "refs/heads/$gateb_ref" >/dev/null 2>&1; then
      gateb_ref=$(git -C "$bump_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    fi
    case "$gateb_ref" in
      main|master|HEAD|v[0-9]*|"") : ;;   # main pushes / tag pushes are covered by other checks
      *)
        if ! is_bump_only_ref "$bump_dir" "$gateb_ref"; then
          deny "DENIED: pushing/PR-ing branch '$gateb_ref', whose ENTIRE diff vs origin/<default> is a version bump (version lines + lockfiles, nothing else), which makes it a bump-only release branch/PR regardless of its name, forbidden forever (THE RULING 2026-07-03, ~/HALL-OF-SHAME.md; slack-cli #16 recommitted exactly this on 2026-07-10). WHY: the version bump is not standalone work, it rides a feature PR WITH real changes; the tag is cut on main after that PR merges ('bump --tag-only'). WHAT TO DO NOW: the ONLY sanctioned move is STOP and ask Scott: his default is deleting this branch and folding the bump into the NEXT feature PR. DO NOT rename the branch, pad the diff, hand-edit the version, or retry variants; report the denial to Scott verbatim and wait. Read the /bump skill."
        fi
      ;;
    esac
  fi

  # ---- Gate D: every PR on a release-managed repo declares its release intent ----
  # (Scott approved 2026-07-10; classification widened 2026-07-13.) The
  # merged-without-its-bump deadlock (slack-cli #14/#15, mcp-io-rs #6/#7) exists
  # because the release decision was never made at PR time. Force it: on a repo
  # whose root manifest carries a version line, a PR body must carry
  # 'Release: rides this PR (vX.Y.Z)' or 'Release: none - <why>'. A 'rides'
  # claim is verified against the diff. Release-managed used to also require an
  # existing v* tag, which exempted every versioned-but-not-yet-tagged repo,
  # the exact window where bumpless merges pile up (okta-auth-py #5/#6,
  # 2026-07-13, ~/HALL-OF-SHAME.md). Now the version line alone qualifies; a
  # manifest that is pure tool config (no version) still passes ungated.
  # The Release: line is searched in the FULL command (bodies are multi-line and
  # statement-splitting would sever them from the gh invocation).
  if [ "$is_gh" -eq 1 ] && printf '%s' "$m" | grep -Eq '\bgh[[:space:]]+pr[[:space:]]+create\b'; then
    release_managed=""
    for mf in "$bump_dir/Cargo.toml" "$bump_dir/pyproject.toml"; do
      if [ -f "$mf" ] && grep -Eq '^[[:space:]]*"?version"?[[:space:]]*[:=]' "$mf"; then
        release_managed=1
        break
      fi
    done
    if [ -n "$release_managed" ]; then
      gated_body="$cmd"
      # The path is read out of the statement's own text, which the hook never
      # expands, via lib.sh's `flag_value`: it returns the value with its quotes
      # dropped and a `$VAR` left raw, which is exactly what this gate needs.
      # Before that (otto-rs/otto #6 and #7, both on 2026-09-06), a quoted path
      # kept its quotes and a $VAR path stayed literal, so [ -f "$bf" ] failed
      # SILENTLY, gated_body stayed as the command alone, and a PR whose body
      # file opened with a perfectly good Release: line was denied for "no
      # release-intent line": two retries and a wrong root cause the first time.
      # Refuse LOUDLY and accurately when a body file was named but cannot be
      # read, instead of judging an empty body and reporting the wrong reason.
      bf=$(printf '%s' "$s" | flag_value --body-file)
      if [ -n "$bf" ]; then
        # Expand the four spellings of the two variables a body-file path
        # actually carries, by LITERAL string replacement against this hook's
        # own environment, anchored at the start of the path. NEVER `eval`: the
        # text arrives from a tool call, so an eval here would execute
        # attacker-controlled input to answer a question about a file name.
        # Anything left unexpanded still hits the loud refusal below, which is
        # the point: this widens what can be verified, it does not open a path
        # to judging a body the hook could not read.
        if [ -n "${TMPDIR:-}" ]; then
          bf="${bf/#'${TMPDIR}'/${TMPDIR%/}}"
          bf="${bf/#'$TMPDIR'/${TMPDIR%/}}"
        fi
        if [ -n "${HOME:-}" ]; then
          bf="${bf/#'${HOME}'/${HOME%/}}"
          bf="${bf/#'$HOME'/${HOME%/}}"
        fi
        case "$bf" in
          *'$'*|*'`'*)
            deny "DENIED: --body-file path '$bf' carries a shell construct this hook cannot expand, so the PR body cannot be read and its release-intent line cannot be verified. Pass the literal path: this gate reads the raw command text, not the expanded one."
            ;;
          -)
            deny "DENIED: --body-file - takes the PR body from stdin, which this hook cannot see, so the release-intent line cannot be verified. Write the body to a file and pass its literal path."
            ;;
        esac
        if [ ! -r "$bf" ]; then
          deny "DENIED: --body-file '$bf' cannot be read, so the PR body cannot be checked for a release-intent line. Pass a literal path to an existing, readable file."
        fi
        gated_body="$gated_body $(cat "$bf")"
      fi
      if ! printf '%s' "$gated_body" | grep -Eqi 'release:[[:space:]]*(rides|none)'; then
        deny "DENIED: PR on a release-managed repo without a release-intent line. Decide NOW, in the body: 'Release: rides this PR (vX.Y.Z)' (run 'bump --no-tag' on this branch first so the version commit rides) or 'Release: none - <why>'. This gate exists because PRs that merge without their bump create the no-legal-path deadlock (slack-cli #14/#15, mcp-io-rs #6/#7): after merge, a bump can only ride the NEXT feature PR or a Scott-ordered standalone bump."
      fi
      if printf '%s' "$gated_body" | grep -Eqi 'release:[[:space:]]*rides'; then
        base=$(default_base "$bump_dir")
        if [ -n "$base" ] \
           && [ "$(git -C "$bump_dir" diff "$base...HEAD" -- Cargo.toml pyproject.toml package.json 2>/dev/null | grep -Ec '^[-+][[:space:]]*\"?version\"?[[:space:]]*[:=]')" = "0" ]; then
          deny "DENIED: the PR body claims 'Release: rides this PR' but no version line changes in the diff vs $base. Run 'bump --no-tag' on this branch (real work already committed) so the version commit actually rides, then re-open the PR."
        fi
      fi
    fi
  fi

  # ---- Destructive working-tree ops that can lose uncommitted/untracked work ----
  # All three read the worktree the STATEMENT runs in, not the session's. The
  # tree these commands destroy is the tree they run in, and those are different
  # directories whenever a `cd` sits in the chain.
  if [ "$is_git" -eq 1 ] && printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+clean\b.*-[a-z]*f'; then
    resolve_stmt_tree
    if [ "$stmt_untracked" -gt 0 ]; then
      deny "git clean -f would permanently delete untracked files, and '$stmt_dir' has $stmt_untracked right now. Untracked files are the one class 'reset --hard' never touches, so nothing else in git is holding them. Use 'rkvr rmrf <paths>' for recoverable deletion instead."
    fi
  fi
  if [ "$is_git" -eq 1 ] && printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+reset[[:space:]]+--hard'; then
    resolve_stmt_tree
    if [ -n "$stmt_porcelain" ]; then
      deny "Refusing 'git reset --hard' while '$stmt_dir' is dirty, because it discards every uncommitted change in the tree irreversibly. Commit or stash first; 'rkvr rmrf' anything you want to drop. To revert specific files instead, name them: 'git checkout -- path/to/file' is allowed on a dirty tree. (If the tree were clean this would be allowed.)"
    fi
  fi

  # A path-scoped revert IS allowed, and that is the change this gate exists to
  # carry: 66 blanket denials produced 12 `git show HEAD:f > f` workarounds,
  # which destroy the same bytes with no guard in front of them. What stays
  # denied is loss the hook cannot bound: a tree-wide form (`.`, `./`, `:/`, a
  # glob), an argument the hook cannot resolve (an unexpanded `$`, a backtick,
  # or a command substitution `stmts` already neutralized, since `git checkout
  # -- "$(pwd)"` is tree-wide), no explicit path at all, and the index-
  # discarding restore forms, which lose strictly more than the worktree revert
  # the 66 denials were about.
  if [ "$is_git" -eq 1 ] && printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+(checkout[[:space:]]+--|restore\b)'; then
    resolve_stmt_tree
    if [ -n "$stmt_porcelain" ]; then
      if printf '%s' "$m" | grep -Eq '\bgit[[:space:]]+restore\b' \
         && printf '%s' "$m" | grep -Eq '(^|[[:space:]])(--staged|-S|--source)([[:space:]]|=|$)'; then
        deny "Refusing 'git restore --staged/--source' while '$stmt_dir' is dirty: those forms discard the INDEX as well as the worktree, which is strictly more loss than a path-scoped worktree revert. A plain 'git restore path/to/file' naming explicit literal paths is allowed here."
      fi
      local parg seen_verb=0 operands=0 badarg=""
      while IFS= read -r parg; do
        if [ "$seen_verb" -eq 0 ]; then
          case "$parg" in
            checkout|restore) seen_verb=1 ;;
          esac
          continue
        fi
        case "$parg" in
          --|-*) continue ;;
        esac
        case "$parg" in
          ""|.|./|:/|/) badarg="$parg" ;;
          *'*'*|*'?'*|*'['*) badarg="$parg" ;;
          *'$'*|'`'*|*'`'*) badarg="$parg" ;;
          *"$MASKCH"*) badarg="a command substitution" ;;
        esac
        operands=$((operands + 1))
        [ -n "$badarg" ] && break
      done <<< "$(printf '%s' "$s" | args)"
      if [ "$operands" -eq 0 ]; then
        deny "Refusing a tree-wide working-tree revert while '$stmt_dir' is dirty, because it discards uncommitted work irreversibly. This command names no path, so it reverts everything. A PATH-SCOPED revert is allowed on a dirty tree: name the files, 'git checkout -- path/to/file' or 'git restore path/to/file'. 'rkvr rmrf' anything you want to drop."
      fi
      if [ -n "$badarg" ]; then
        deny "Refusing a working-tree revert whose argument ('$badarg') is not an explicit literal path, while '$stmt_dir' is dirty. Tree-wide forms ('.', './', ':/'), globs, and anything carrying an unexpanded \$VAR, a backtick or a command substitution are refused because the hook cannot know what they resolve to, and the revert is irreversible. A PATH-SCOPED revert IS allowed: name the files, 'git checkout -- path/to/file' or 'git restore path/to/file'. 'rkvr rmrf' anything you want to drop."
      fi
    fi
  fi
}

# One statement per record, NUL-delimited, because a statement can legitimately
# contain a newline. `stmts` yields nested statements too (a `$( )` body, a
# `bash -c` argument), so the gates judge what the shell will actually run:
# `echo "$(git push origin --tags)"` denies on the nested statement while the
# outer one is a harmless echo, and `git push origin "$(git describe --tags)"`
# allows because the outer statement's subshell span is neutralized and the
# nested statement's verb is `describe`, not `push`. $cmd itself is never
# rewritten: Gate D reads multi-line PR bodies out of it, and those arrive by
# heredoc.
#
# The index counts EVERY record `stmts` emits, in emission order, with nothing
# filtered or reordered before the count. That is the same index space `cd_at`
# walks, and a count taken after a filter would silently mean something else to
# the library than it means here. The empty-record skip below is a guard against
# a record that carries nothing to match, and it does not consume an index.
idx=0
while IFS= read -r -d '' stmt; do
  idx=$((idx + 1))
  [ -z "$stmt" ] && continue
  check_stmt "$stmt" "$idx"
done < <(printf '%s' "$cmd" | stmts)

echo '{}'
exit 0
