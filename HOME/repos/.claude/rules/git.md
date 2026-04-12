---
paths:
  - "**/*"
---

# Git Safety

## Tags

- NEVER delete a git tag, locally or on remote. No exceptions. Even if a design doc says to delete a tag, DO NOT do it.
- NEVER run `git tag -d`, `git push --delete` for tags, or use any MCP tool to delete tags (e.g., `delete_tag`).
- If a tag needs to be moved or recreated, ask the user explicitly and let them do it.
- ALWAYS use annotated tags (`git tag -a -m "message"`), NEVER lightweight tags (`git tag`). No exceptions.
- ONLY create tags on `main` or `master`. NEVER tag dev, feature, or any other branch. No exceptions.

## Pushing to main

- NEVER push directly to main/master on `tatari-tv/*` repos. No exceptions. If `branch.main.pushremote=no_push` is set, that means PRs are required. Create a feature branch, push it, and open a PR. Do NOT bypass the guard with `git push origin main`. Do NOT offer direct push as an option. If the user needs to push directly to main, they will do it themselves by hand.
