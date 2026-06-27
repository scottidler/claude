#!/bin/bash
# git-release-guard.sh — PreToolUse(Bash) guard enforcing rules/git.md AT THE MOMENT
# of the command, not relying on an always-on rule staying salient deep in a session.
#
# Blocks the specific footguns that have actually bitten:
#   - bump on a feature branch            (release flow is PR -> merge -> bump off main)
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
      deny "Release flow: NEVER bump on a feature branch (the bump's target worktree '$bump_dir' is on '$bump_branch'). Scott's flow is PR -> merge -> bump OFF main. Open/merge the PR, then bump on main (e.g. 'cd <main-worktree> && bump'). A skill's 'finalize/ship' step does NOT authorize this."
    fi
    if ! printf '%s' "$s" | grep -Eq '\bbump\b.*--tag-only'; then
      if [ -n "$bump_porcelain" ]; then
        deny "bump stages everything (git add -A) and the target worktree '$bump_dir' is dirty — it would sweep untracked/modified files into the version commit (this is exactly how scratch jpgs got committed). Commit your real changes, then 'rkvr rmrf' or stash the strays, THEN bump on a clean tree."
      fi
    fi
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
