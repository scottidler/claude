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

## Tagging / releases: use `bump`, let it gate-check for you

**The one invariant: never create or push a tag until the exact commit it points to is confirmed on `origin/main`.** `bump` (v0.2.0+) enforces this: it detects branch-protection gates itself, plain `bump` REFUSES to tag on a gated default branch, and `bump --tag-only` verifies `HEAD == origin/<default>` before creating the tag. `bump` never pushes: it prints the exact push commands; you run them in the safe order (branch first, then the tag by explicit name).

- `bump --gates`: shows both gates (classic protection AND repo/org rulesets) and the recommended flow (run this first if unsure)
- Ungated repo: the version commit lands first, untagged, and the tag waits for green CI on that exact SHA, because a tag cut before CI can only be repaired by a second tag. Exact command sequence: `bump/SKILL.md` FLOW 1.
- Gated repo: `bump --no-tag [-m|-M]` on the FEATURE branch (version bump rides the feature PR, no tag) → open PR → merge → on updated main `bump --tag-only` (tags the merged commit) → `git push origin vX.Y.Z`
- Never run plain `bump` on a gated repo: it will refuse anyway, but `--no-tag` is the right call; `--tag-only` is the post-merge tag step
- NEVER create a bump-only release branch (`release-X.Y.Z` carrying just a version commit). The bump belongs INSIDE the feature PR. If a PR already merged without its bump: STOP and ask Scott. The default is to fold the bump into the next feature PR, not to invent a branch.
- A tag created on a branch is burnt and lost forever: squash-merge rewrites the SHA. On a feature branch the ONLY legal bump form is `bump --no-tag` (the git-release-guard hook enforces this).
- Never `git push --tags`; `push.followTags` is `false` in dotfiles because a followTags push lands the tag even when the branch push is rejected (this orphaned okta-auth-rs v0.2.0)
- If a push to main is ever rejected after a tag exists locally: STOP. Do not push the tag, do not retry variations, do not change repo settings (merge methods, protection, rulesets); `intent-guard.sh`'s GH-WRITE rule denies the `gh api` and `gh repo edit` forms mechanically. Report the exact rejection to the user.
