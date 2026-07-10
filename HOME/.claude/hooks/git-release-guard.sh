#!/bin/bash
# git-release-guard.sh — PreToolUse(Bash) guard enforcing rules/git.md AT THE MOMENT
# of the command, not relying on an always-on rule staying salient deep in a session.
#
# Blocks the specific footguns that have actually bitten:
#   - tag-creating bump on a feature branch (a tag cut on a branch is burnt forever;
#     `bump --no-tag` IS allowed there — the version bump rides the feature PR)
#   - bump-only release branches, three ways (THE RULING 2026-07-03; recommitted
#     verbatim as slack-cli PR #16, 2026-07-10 — prose alone provably does not hold):
#       * creating a branch named bump-*/release-*
#       * `bump --no-tag` on a branch with ZERO commits ahead of origin/<default>
#         (the bump commit would be the branch's only content)
#       * pushing / opening a PR for a branch whose entire diff vs origin/<default>
#         is version lines + lockfiles (catches hand-edited bumps too)
#   - version-committing bump w/ dirty tree (bump stages EVERYTHING; this committed scratch jpgs)
#   - git push --tags / --follow-tags     (a follow-tags push escapes even if branch push fails)
#   - tag deletion (local or remote)      (git.md: NEVER delete a tag)
#   - force-push to main/master           (needs explicit human approval)
#   - git clean -f* with untracked present / reset --hard|checkout-- with a dirty tree
#
# Each check runs PER STATEMENT (the command is split on && || ; | and newlines), so a
# greedy match can't bleed across an unrelated later sub-command — e.g. a 'git push' in
# one statement plus '--tags' in a later 'git ls-remote --tags' is NOT a false positive.
#
# Emits a PreToolUse "deny" decision (with a reason Claude sees) or passes through ({}).

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // ""')
[ -z "$cmd" ] && { echo '{}'; exit 0; }

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
porcelain=$(git status --porcelain 2>/dev/null)
untracked=$(printf '%s\n' "$porcelain" | grep -c '^??')

# Effective worktree a `bump` in this command will actually run in. Scott's release
# flow is `cd <main-worktree> && bump`, but this hook runs once at the SESSION CWD
# (often a feature-branch worktree), so a branch read there falsely denies a bump
# that targets main. Honor a `cd <dir>` in the same command chain (the LAST one wins)
# and evaluate the branch + tree state in THAT directory. No cd -> the session CWD,
# so a bare `bump` on a real feature branch is still correctly blocked.
bump_dir="."
cd_target=$(printf '%s\n' "$cmd" \
  | grep -oE '\bcd[[:space:]]+("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:]&|;]+)' \
  | tail -n1 | sed -E 's/^cd[[:space:]]+//; s/^["'"'"']//; s/["'"'"']$//')
if [ -n "$cd_target" ] && [ "$cd_target" != "-" ] && [ -d "$cd_target" ]; then
  bump_dir="$cd_target"
fi
bump_branch=$(git -C "$bump_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
bump_porcelain=$(git -C "$bump_dir" status --porcelain 2>/dev/null)

# Remote default-branch ref (origin/main | origin/master), or empty when there is
# no remote — the bump-only gates self-skip on local-only repos.
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
      *) return 0 ;;   # real work is in the diff — not bump-only
    esac
  done <<< "$files"
  diff_lines=$(git -C "$d" diff "$base...$ref" -- Cargo.toml package.json pyproject.toml VERSION 2>/dev/null \
    | grep -E '^[-+]' | grep -Ev '^(\+\+\+|---)')
  [ -z "$diff_lines" ] && return 0   # lockfile-only change — allowed
  if printf '%s\n' "$diff_lines" | grep -Evq '^[-+][[:space:]]*"?version"?[[:space:]]*[:=]'; then
    return 0                          # a non-version manifest line changed — allowed
  fi
  return 1
}

check_stmt() {
  local s="$1"

  # ---- Tags: never delete, never bulk-push (git.md "Tags") ----
  if printf '%s' "$s" | grep -Eq '\bgit[[:space:]]+tag[[:space:]]+(-d|--delete)\b'; then
    deny "git.md: NEVER delete a tag (refusing 'git tag -d/--delete'). If a tag must move or be recreated, ask Scott to do it himself."
  fi
  if printf '%s' "$s" | grep -Eq '\bgit[[:space:]]+push\b.*(--tags|--follow-tags)\b'; then
    deny "git.md: never 'git push --tags'/'--follow-tags' (the tag lands even if the branch push is rejected — this orphaned okta-auth-rs v0.2.0). Push the branch first, then the tag by explicit name: git push origin vX.Y.Z"
  fi
  if printf '%s' "$s" | grep -Eq '\bgit[[:space:]]+push\b.*(--delete|[[:space:]]-d\b).*(refs/tags/|(^|[[:space:]])v[0-9])' \
     || printf '%s' "$s" | grep -Eq '\bgit[[:space:]]+push\b.*:[[:space:]]*(refs/tags/|v[0-9])'; then
    deny "git.md: refusing what looks like a remote TAG deletion. NEVER delete tags. (If you truly meant a branch, delete it via 'gh' or name 'refs/heads/<branch>' explicitly.)"
  fi

  # ---- Bump-only release branches: forbidden forever (THE RULING 2026-07-03) ----
  # Gate C: never even CREATE a branch named like a release/bump branch.
  # (Deletion `git branch -d bump-*` and `git branch --list 'bump*'` stay allowed —
  # the flag between `branch` and the name breaks the match.)
  if printf '%s' "$s" | grep -Eq '\bgit[[:space:]]+(checkout[[:space:]]+-b[[:space:]]+|switch[[:space:]]+(-c|--create)[[:space:]]+|branch[[:space:]]+)(bump|release)([-/]|[[:space:]]|$)'; then
    deny "THE RULING (2026-07-03): never create a bump-*/release-* branch — a bump-only release branch is forbidden forever, for ANY reason (slack-cli #16 was exactly this). The version bump rides the FEATURE branch via 'bump --no-tag'. If the work already merged without its bump: STOP and ask Scott (default: fold the bump into the next feature PR)."
  fi

  # ---- Force-push to main/master (git.md "Pushing to main") ----
  if printf '%s' "$s" | grep -Eq '\bgit[[:space:]]+push\b.*(--force|--force-with-lease|[[:space:]]-f\b)'; then
    if printf '%s' "$s" | grep -Eqw '(main|master)' || [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
      deny "git.md: never force-push main/master without explicit approval from Scott. Stop and report; let him run it."
    fi
  fi

  # ---- bump: release flow (rules/git.md release section + Scott's workflow) ----
  # Match `bump` ONLY in command position — the first token of the statement
  # (after optional leading env-assignments and an optional path prefix). This is
  # the fix for the substring false-positive that blocked unrelated commands
  # merely *mentioning* bump: `git commit -m "...bump..."`, a `bump-*` branch
  # name, `echo bump`, etc. A statement is already split on && || ; |, so the
  # command word is unambiguous here.
  if printf '%s' "$s" | grep -Eq '^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*([^[:space:]]*/)?bump([[:space:]]|$)' \
     && ! printf '%s' "$s" | grep -Eq 'bump.*(--gates|--dry-run|--help|--version|[[:space:]]-n\b|[[:space:]]-h\b|[[:space:]]-V\b)'; then
    if [ -n "$bump_branch" ] && [ "$bump_branch" != "main" ] && [ "$bump_branch" != "master" ]; then
      # On a feature branch exactly ONE bump form is legal: `bump --no-tag`.
      # That is the gated flow — the version commit rides the feature PR.
      # Any tag-creating form (plain bump, -m/-M without --no-tag, --tag-only)
      # is blocked: a tag cut on a branch is burnt forever (squash rewrites the SHA).
      if ! printf '%s' "$s" | grep -Eq '\bbump\b.*--no-tag'; then
        deny "Release flow: on a feature branch the ONLY legal bump is 'bump --no-tag' — the version commit rides the feature PR (never a tag on a branch, never a bump-only release branch). Tags are cut on main AFTER the PR merges: git checkout main && git pull --ff-only origin main && bump --tag-only && git push origin vX.Y.Z. (Target worktree '$bump_dir' is on '$bump_branch'.)"
      fi
      # Gate A: 'bump --no-tag' is legal ONLY on a branch that carries real work.
      # Zero commits ahead of origin/<default> means the bump commit would be the
      # branch's ONLY content — i.e. a bump-only release branch in the making.
      base=$(default_base "$bump_dir")
      if [ -n "$base" ] && [ "$(git -C "$bump_dir" rev-list --count "$base..HEAD" 2>/dev/null || echo 1)" = "0" ]; then
        deny "Branch '$bump_branch' has ZERO commits ahead of $base — 'bump --no-tag' here would mint a bump-only release branch, forbidden forever (THE RULING 2026-07-03; slack-cli #16 was this exact crime). The bump belongs on a feature branch WITH its work, before that PR merges. If the work already merged without its bump: STOP and ask Scott (default: fold the bump into the next feature PR — never invent a branch)."
      fi
    fi
    if ! printf '%s' "$s" | grep -Eq '\bbump\b.*--tag-only'; then
      if [ -n "$bump_porcelain" ]; then
        deny "bump stages everything (git add -A) and the target worktree '$bump_dir' is dirty — it would sweep untracked/modified files into the version commit (this is exactly how scratch jpgs got committed). Commit your real changes, then 'rkvr rmrf' or stash the strays, THEN bump on a clean tree."
      fi
    fi
  fi

  # ---- Gate B: no pushing / PR-ing a bump-only branch (content-based) ----
  # Catches the crime even if the branch name is innocent or the version was
  # hand-edited: if everything the push/PR would land vs origin/<default> is
  # version lines + lockfiles, it IS a bump-only release branch. Deletions
  # (--delete / ':ref' refspecs) push no content and are skipped.
  if printf '%s' "$s" | grep -Eq '\b(git[[:space:]]+push|gh[[:space:]]+pr[[:space:]]+create)\b' \
     && ! printf '%s' "$s" | grep -Eq '(--delete|[[:space:]]-d[[:space:]]|[[:space:]]:[^[:space:]])'; then
    gateb_ref=""
    if printf '%s' "$s" | grep -Eq '\bgh[[:space:]]+pr[[:space:]]+create\b'; then
      gateb_ref=$(printf '%s' "$s" | grep -oE '\-\-head(=|[[:space:]]+)[^[:space:]]+' | head -1 | sed -E 's/--head(=|[[:space:]]+)//')
    else
      # git push [flags] <remote> <refspec> — take the last non-flag token, strip a src: prefix
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
          deny "Branch '$gateb_ref' vs origin/<default> contains ONLY a version bump (version lines + lockfiles, nothing else) — that is a bump-only release branch/PR, forbidden forever (THE RULING 2026-07-03; slack-cli #16 was this exact crime). The bump rides a feature PR with real work. If the work already merged without its bump: STOP and ask Scott (default: fold the bump into the next feature PR)."
        fi
      ;;
    esac
  fi

  # ---- Destructive working-tree ops that can lose uncommitted/untracked work ----
  if printf '%s' "$s" | grep -Eq '\bgit[[:space:]]+clean\b.*-[a-z]*f' && [ "$untracked" -gt 0 ]; then
    deny "git clean -f would permanently delete untracked files (there are some now). Use 'rkvr rmrf <paths>' for recoverable deletion instead."
  fi
  if printf '%s' "$s" | grep -Eq '\bgit[[:space:]]+(reset[[:space:]]+--hard|checkout[[:space:]]+--|restore\b)' && [ -n "$porcelain" ]; then
    deny "Refusing a destructive working-tree op (reset --hard / checkout -- / restore) while the tree is dirty — it discards uncommitted/untracked work irreversibly. Commit or stash first; 'rkvr rmrf' anything you want to drop. (If the tree were clean this would be allowed.)"
  fi
}

# Split the command into statements on && || ; | and newlines, then check each one.
# (A greedy regex within a statement can't reach across into an unrelated sibling.)
split=$(printf '%s' "$cmd" | sed -E 's/&&/\n/g; s/\|\|/\n/g; s/;/\n/g; s/\|/\n/g')
while IFS= read -r stmt; do
  [ -z "$stmt" ] && continue
  check_stmt "$stmt"
done <<< "$split"

echo '{}'
exit 0
