---
name: shipit
description: Ship code changes - commit, bump version, push with tags, and install. Use when the user says "ship it", "shipit", or wants to commit+bump+push+install in one go.
---

# Ship It

Commit, bump, push, and install in one shot. Default workflow for shipping changes.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--minor` / `-m` | No | Minor version bump (x.Y.0) instead of patch |
| `--major` / `-M` | No | Major version bump (X.0.0) instead of patch |
| `--no-install` | No | Skip the install step |
| `--no-bump` | No | Skip bump entirely (just commit and push) |

## Steps

### Step 1: Pre-flight checks

- Verify the current directory is a git repo
- Check for modified or untracked files via `git status`
- If there are no changes AND no unpushed commits, inform the user and stop
- If there are no changes but there ARE unpushed commits, skip to Step 4 (bump) or Step 5 (push)
- Check if this is a Rust project (has `Cargo.toml`) to determine if bump applies
- Detect push protection from the LIVE remote (authoritative): `gh api repos/OWNER/REPO/branches/main/protection` - HTTP 404 "Branch not protected" means direct push; protection rules returned means PR flow. Do NOT infer protection from `branch.main.pushremote` - `no_push` is only an accidental-push guardrail, NOT proof a PR is required (per git.md)

### Step 2: Discover install command

Before committing, determine the install command for Step 5:

1. **Check CLAUDE.md** (repo root, then `.claude/CLAUDE.md`) for install instructions
   - Look in the "Quick Reference" section or any "Install" / "Build & Install" section
   - Look for commands like `cargo install`, `systemctl restart`, `daemon --reinstall`, etc.
   - If the CLAUDE.md documents a multi-step install (e.g., `cargo install --path . && systemctl --user restart foo`), use the full command sequence
2. **Fallback for Rust projects**: if no CLAUDE.md install command found and `Cargo.toml` exists, use `cargo install --path .`
3. **Fallback for non-Rust projects**: skip install

Store the discovered install command for use in Step 5. If a CLAUDE.md install command was found, mention it to the user during the report ("Using install command from CLAUDE.md: ...").

### Step 3: Commit

- Run `git status` to see all changes (modified + untracked)
- Run `git diff` to understand what changed (both staged and unstaged)
- Run `git log --oneline -5` for commit message style reference
- Stage all modified and untracked files with `git add` (use specific file names, not `git add -A`)
  - NEVER stage files that look like secrets (.env, credentials, keys, tokens) - warn the user
- Write a concise, descriptive commit message based on the actual changes
- Commit

### Step 3.5: Sync with remote BEFORE bumping (critical ordering)

**`bump` creates a git tag and amends the commit locally. NEVER run it against a stale local branch.** If the remote has advanced (e.g. someone else already bumped, or CI pushed), bumping first produces a tag that collides with the remote's tag and an orphaned local commit, and the push will be rejected - leaving a stale local tag that the no-tag-deletion rule then makes painful to clean up.

So, before Step 4, ALWAYS sync:

```bash
git fetch origin
git log --oneline HEAD..origin/$(git branch --show-current)   # commits on remote not local
```

- If the remote has NO commits you lack → proceed to Step 4.
- If the remote HAS advanced → rebase onto it FIRST: `git rebase origin/$(git branch --show-current)`. Resolve any conflicts (including a version-line conflict if the remote already bumped - pick the next-higher version so you don't collide with a tag that already exists). Re-run the build/tests. ONLY THEN proceed to Step 4.
- If the version you're about to bump to is already a tag on the remote (`git ls-remote --tags origin`), skip past it to the next free version. Never create a local tag for a version that already exists remotely.

The invariant: **fetch + rebase happen before any tagging.** Tagging is hard to undo; syncing is not.

### Step 4: Bump

Skip this step if `--no-bump` was passed or no `Cargo.toml` exists.

- Default: patch bump (no args to `bump`)
- If `--minor` or `-m`: run `bump -m`
- If `--major` or `-M`: confirm with the user first ("Major bump - are you sure?"), then run `bump -M`
- Always use `bump -a` flag for automatic commit message since we already committed in Step 3

```bash
bump -a          # patch (default)
bump -a -m       # minor
bump -a -M       # major
```

### Step 5: Push

First, detect whether `main` is protected on the LIVE remote. This is authoritative - never infer protection from local git config:

```bash
gh api repos/OWNER/REPO/branches/main/protection
```

If it returns HTTP 404 "Branch not protected", direct push is allowed - use the direct push below. If it returns protection rules, switch to the **PR flow**. (`branch.main.pushremote=no_push` is only a local accidental-push guardrail that blocks bare `git push`; it is NOT proof a PR is required, so never decide the flow from it - see git.md.) PR flow:

1. Generate a branch name from the commit message (e.g., `feat/add-cli-expansion`)
2. Create and checkout the branch: `git checkout -b <branch-name>`
3. Push the branch: `git push origin <branch-name> -u && git push origin --tags`
4. Create a PR: `gh pr create --title "<title>" --body "<summary>"`
5. Report the PR URL

If no push protection is detected, push directly:

```bash
git push origin $(git branch --show-current) && git push origin --tags
```

Always push to `origin` explicitly - never rely on the default pushremote (which may be `no_push`).

If push fails due to upstream changes, inform the user rather than force-pushing.

### Step 6: Install

Skip this step if `--no-install` was passed or no install command was discovered in Step 2.

Run the install command discovered in Step 2. Examples:

```bash
# Simple Rust binary
cargo install --path .

# Daemon with systemd service
cargo install --path . && systemctl --user restart myservice

# Workspace member
cargo install --path crates/mybinary

# Custom install from CLAUDE.md
make install && sudo systemctl restart myservice
```

If install fails, report the error but do NOT roll back the push - the code is already shipped.

### Step 7: Report

Summarize what was done:
- Commit message and hash
- Version bump (old -> new), if applicable
- Push status
- Install command used and its source (CLAUDE.md or fallback)
- Install status

## Non-Rust Projects

For non-Rust projects (no `Cargo.toml`):
- Commit and push work as normal
- Bump is skipped (unless the project has its own bump mechanism documented in CLAUDE.md)
- Install uses whatever CLAUDE.md documents, or is skipped

## Edge Cases

- **No changes**: stop and inform the user
- **Detached HEAD**: warn the user before proceeding
- **Unpushed commits already exist**: include them in the push, mention it
- **Cargo workspace**: check CLAUDE.md first, then look for binary targets
- **Push rejected**: do NOT force push - tell the user to pull/rebase first
- **Daemon projects**: CLAUDE.md should document the full install+restart command sequence
- **Branch protection**: decide from the LIVE check `gh api repos/OWNER/REPO/branches/main/protection` - protection rules returned -> PR flow (feature branch, push, open PR); HTTP 404 "Branch not protected" -> direct push. `branch.main.pushremote=no_push` is ONLY an accidental-push guardrail, NOT a PR-required signal - never infer PR flow from it (it misfires on unprotected tatari-tv repos like persona-cli). Don't ask the user; detect from live protection and adapt.
- **Already pushed**: if `git log origin/main..HEAD` is empty and there are no local changes, everything is already shipped - say so and stop
