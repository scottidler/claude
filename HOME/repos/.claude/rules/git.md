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

- Before pushing to main on a `tatari-tv/*` repo, check BOTH live gates — don't infer from local git config, and never trust either gate alone:

```
gh api repos/OWNER/REPO/branches/main/protection   # classic branch protection (404 = none)
gh api repos/OWNER/REPO/rules/branches/main        # rulesets (repo + org level); [] = none
```

- Direct push allowed ONLY if classic protection is 404 AND the rules list is empty (or contains nothing push-blocking). Anything else → PR flow.
- Org-level rulesets (e.g. a `workflows` rule like "Tatari Org Security") are NOT bypassed by repo admin. `enforce_admins:false` only bypasses *classic* protection. A 404 on `/branches/main/protection` proves nothing about rulesets — this exact blind spot orphaned okta-auth-rs v0.2.0.
- Local `branch.main.pushremote=no_push` is a user-side guardrail against accidental `git push` with no remote — NOT proof the remote requires PRs; don't treat its presence as dispositive
- Never use `--force` / `--force-with-lease` on main without explicit user approval

## Tagging / releases — use `tagit`, never hand-run the flow

**The one invariant: never create or push a tag until the exact commit it points to is confirmed on `origin/main`.** The `tagit` script (`~/bin/tagit`, source in claude repo `HOME/.claude/bin/tagit`) enforces this mechanically — gate detection, push-verify-then-tag ordering, orphan refusal. Do NOT improvise the flow with raw `git push`/`git tag`/`bump` sequencing.

- `tagit gates` — shows both gates and which flow applies (run this first if unsure)
- Ungated repo: `tagit release [bump args]` — runs `bump`, pushes main, VERIFIES it landed, then pushes the tag by name
- Gated repo: `tagit pr [-m|-M]` (version-bump PR, no tag) → merge it → `tagit tag` (annotated tag on merged main, pushed by name)
- `bump` directly is fine ONLY on ungated repos where you'll immediately `tagit release` semantics anyway; on gated repos NEVER run `bump` — it tags a commit that squash-merge will never put on main
- Never `git push --tags`; `push.followTags` is `false` in dotfiles because a followTags push lands the tag even when the branch push is rejected (this orphaned okta-auth-rs v0.2.0)
- If a push to main is ever rejected after a tag exists locally: STOP. Do not push the tag, do not retry variations, do not change repo settings (merge methods, protection, rulesets). Report the exact rejection to the user.
