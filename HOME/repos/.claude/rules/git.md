---
alwaysApply: true
---

# Git Safety

## Tags

- NEVER delete a git tag, locally or on remote. No exceptions. Even if a design doc says to delete a tag, DO NOT do it.
- NEVER run `git tag -d`, `git push --delete` for tags, or use any MCP tool to delete tags (e.g., `delete_tag`).
- If a tag needs to be moved or recreated, ask the user explicitly and let them do it.
- ALWAYS use annotated tags (`git tag -a -m "message"`), NEVER lightweight tags (`git tag`). No exceptions.
- ONLY create tags on `main` or `master`. NEVER tag dev, feature, or any other branch. No exceptions.
- NEVER introduce a per-crate or multi-scheme tag strategy (e.g. `taskstore-v0.3.0` + `taskstore-traits-v0.1.0`). Always use a single flat `v*` tag for the whole repo/workspace. If a design doc says otherwise, ASK the user before creating any tags.

## Branch names: no slash, mechanically enforced

- See `general.md`'s "Branch names" section for the slug rule and its relationship to the PR title. `branch-name-guard.sh` denies a slashed `git checkout -b` / `git branch` mechanically; there is nothing left here to compensate for.

## Branches (opposite of tags: delete merged ones freely, no asking)

- Branch safety protects **unmerged work, and nothing else**. Once a branch's
  contents are on `origin/main` (its PR is MERGED, or its commits / their
  squashed equivalent are in main), the branch ref is pure clutter with zero
  unique work to lose.
- **DELETE merged/superseded branches (local AND stale remote) as routine
  cleanup WITHOUT asking.** Do not pose "want these gone?". A merged branch has
  nothing to protect, so confirming is a time-wasting dumbass question. Just
  yeet it. (Scott, furious, 2026-07-03.)
- To classify before deleting: `git rev-list --left-right --count origin/main...<branch>` +
  the PR state. Merged / closed-superseded / commits-already-in-main -> delete
  silently. Only **stop and ask** when a branch has commits NOT in main
  (genuinely unmerged or abandoned work that a delete would destroy).
- This is the exact scope of "protect unmerged work"; it does NOT extend to tags
  (tags are never deleted, ever) or to unmerged branches.

## Pushing to main

- Before pushing to main on a `tatari-tv/*` repo, check BOTH live gates: don't infer from local git config, and never trust either gate alone:

```
gh api repos/OWNER/REPO/branches/main/protection   # classic branch protection (404 = none)
gh api repos/OWNER/REPO/rules/branches/main        # rulesets (repo + org level); [] = none
```

- Direct push allowed ONLY if classic protection is 404 AND the rules list is empty (or contains nothing push-blocking). Anything else → PR flow.
- Org-level rulesets (e.g. a `workflows` rule like "Tatari Org Security") are NOT bypassed by repo admin. `enforce_admins:false` only bypasses *classic* protection. A 404 on `/branches/main/protection` proves nothing about rulesets. This exact blind spot orphaned okta-auth-rs v0.2.0.
- Local `branch.main.pushremote=no_push` is a user-side guardrail against accidental `git push` with no remote, NOT proof the remote requires PRs; don't treat its presence as dispositive
- Never use `--force` / `--force-with-lease` on main without explicit user approval

## Tagging / releases: `bump release`, then `bump finish`

**The one invariant: never create or push a tag until the exact commit it points to is on `origin/<default>` and its CI is green.** `bump release` / `bump finish` (bump v0.4.0+) enforce it: they detect the gates, wait for green check runs on the exact sha, tag that sha, and push the tag by name.

- The standing release rulings and the superseded ones, each with its hall line: `~/repos/.claude/refs/release-rulings.md`.

- One release, two bare commands, each its own Bash call after a separate `cd <repo>`, run with `run_in_background` (the CI wait can pass the 600s foreground cap):
  - `bump release [-m|-M]`: ungated, it commits the version, pushes main, waits for CI, tags, pushes the tag, installs. Gated, run on the FEATURE branch with the work committed: it commits the version, pushes the branch, opens the PR itself (`Release: rides this PR (vX.Y.Z)`), and stops.
  - `bump finish`: gated, after the PR merges, from any worktree of the repo. It fast-forwards the default branch, waits for CI on the merged sha, tags, pushes the tag, installs.
- No `&&`, no env prefix, no wrapper: a bare `bump ...` matches the allow rule; anything chained or prefixed does not.
- A re-run after red CI reuses the pending version; it never bumps past it.
- NEVER create a bump-only release branch. The bump belongs INSIDE the feature PR; `bump release` refuses a branch whose diff is empty or version lines only. The one exception is Scott's explicit order for a version-only release: `bump release --standalone "<his exact words>"`, words quoted into the PR. Never invent the order.
- If a PR already merged without its bump, `bump finish` refuses; STOP and report. Do not invent a branch.
- A tag created on a branch is burnt and lost forever: squash-merge rewrites the SHA. The verbs never tag a branch.
- `bump --gates` shows both gates (classic protection AND repo/org rulesets) when you need to see them.
- Never `git push --tags`; `push.followTags` is `false` in dotfiles because a followTags push lands the tag even when the branch push is rejected (this orphaned okta-auth-rs v0.2.0)
- If a push to main is ever rejected after a tag exists locally: STOP. Do not push the tag, do not retry variations, do not change repo settings (merge methods, protection, rulesets); `intent-guard.sh`'s GH-WRITE rule denies the `gh api` and `gh repo edit` forms mechanically. Report the exact rejection to the user.
