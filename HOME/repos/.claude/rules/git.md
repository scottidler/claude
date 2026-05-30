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

## Working Directory

- `git -C /some/path` is ONLY valid when targeting a repo that is NOT the current working directory. If CWD is already the repo, run `git` directly. Never use `-C` as a "safety" anchor when you're already there.

## Pushing to main

- Before pushing to main on a `tatari-tv/*` repo, check the repo's **live** branch protection — don't infer from local git config:

```
gh api repos/OWNER/REPO/branches/main/protection
```

- HTTP 404 "Branch not protected" → direct push allowed: `git push origin main`
- Protection rules returned → PR flow required: create a feature branch, push it, open a PR
- Local `branch.main.pushremote=no_push` is a user-side guardrail against accidental `git push` with no remote — NOT proof the remote requires PRs; don't treat its presence as dispositive
- Under PR flow, tags are applied AFTER the PR merges, not before: commit on branch → push → open PR → merge → pull main → `bump` on main → push main + tag (tagging pre-merge orphans the tag if the PR is squashed)
- Never use `--force` / `--force-with-lease` on main without explicit user approval
