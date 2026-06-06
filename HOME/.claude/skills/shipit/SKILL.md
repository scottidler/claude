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
- **Sync `main` with origin BEFORE anything else.** `git fetch origin main` then `git pull --ff-only origin main` (or rebase your local commits onto it). NEVER `bump`/tag on a stale local main: `bump` tags `HEAD`, so if local main is behind origin, the tag lands on an off-main commit and is orphaned the moment you push (cr v0.1.8 was orphaned exactly this way). If the working tree is dirty, stash or commit first, sync, then continue.
- **Determine the push flow NOW, before any bump or tag — flow decides whether you may tag at all.** Check BOTH live gates (a 404 on classic protection does NOT mean "safe to push directly"):
  1. Classic branch protection: `gh api repos/OWNER/REPO/branches/main/protection` (protection rules returned → PR flow)
  2. Repository + org rulesets: `gh api repos/OWNER/REPO/rulesets` — an `active` ruleset (especially a **required-workflow** ruleset like `Tatari Org Security`) forces PR flow EVEN when classic protection is 404 AND even for org admins. `enforce_admins:false` only bypasses *classic* protection; it does NOT bypass org required-workflow rulesets. claude-pricing's direct push was rejected by exactly this despite admin + 404-able classic protection.
  - Direct-push flow ONLY if BOTH gates are clear. Otherwise PR flow.
  - Do NOT infer protection from `branch.main.pushremote` — `no_push` is only an accidental-push guardrail, NOT proof a PR is required (per git.md).
- **Cardinal rule for the rest of this skill: never create or push a tag before the commit it points to is confirmed on `origin/main`.** Under PR flow that means the bump+tag happen only AFTER the PR merges (Step 5), never before.

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

**Gate on the flow decided in Step 1 — `bump` creates a tag, so WHEN you run it matters:**

- **PR flow (protected / ruleset-gated main): do NOT bump or tag here.** Commit your changes on a feature branch (Step 5 PR flow), open the PR, and run `bump` only AFTER the PR merges and you've pulled the merged main. Tagging now would orphan the tag, because the squash-merged commit on main is a different SHA than your local HEAD. This is the trap that orphaned claude-pricing v0.2.0.
- **Direct-push flow only:** bump now, then Step 5 pushes main + tag together.

Bump levels (direct-push flow, or post-merge on main):

- Default: patch bump (no args to `bump`)
- If `--minor` or `-m`: run `bump -m`
- If `--major` or `-M`: confirm with the user first ("Major bump - are you sure?"), then run `bump -M`
- Use `bump -a` for an automatic commit message if you already committed separately

```bash
bump -a          # patch (default)
bump -a -m       # minor
bump -a -M       # major
```

After bumping, before pushing the tag, verify the tag is reachable from `origin/main` (or will be by the push you're about to make): `git merge-base --is-ancestor "$(git rev-list -n1 vX.Y.Z)" origin/main`. If it is NOT and you're about to push, STOP — you're about to create an orphaned tag.

### Step 5: Push

First, detect whether `main` is protected on the LIVE remote. This is authoritative - never infer protection from local git config:

```bash
gh api repos/OWNER/REPO/branches/main/protection
```

Use the flow already determined in Step 1 (both classic protection AND rulesets checked). If PR flow:

1. Generate a branch name from the commit message (e.g., `feat/add-cli-expansion`)
2. Create and checkout the branch: `git checkout -b <branch-name>`
3. Push the branch ONLY — **never** `git push origin --tags` here. The tag does not exist yet under PR flow (Step 4 deferred it), and pushing a tag before the merge orphans it: `git push origin <branch-name> -u`
4. Create a PR: `gh pr create --title "<title>" --body "<summary>"`
5. Report the PR URL, then STOP and wait for the PR to merge (review/CI gated). You cannot tag yet.
6. **After the PR merges:** `git checkout main && git pull --ff-only origin main`, then run the Step 4 `bump` on the now-current main, then `git push origin main && git push origin vX.Y.Z`. The tag is created on the real merged commit, so it lands on main, not orphaned. (If the repo squash-merges and you tagged earlier anyway, the tag is already orphaned — do NOT delete it per git.md; supersede it with a fresh clean bump, or ask the user to delete+recreate.)

If BOTH gates were clear (direct-push flow), push directly:

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
- **Branch protection**: decide from TWO live checks, not one. Classic: `gh api repos/OWNER/REPO/branches/main/protection` (rules returned -> PR flow). Rulesets: `gh api repos/OWNER/REPO/rulesets` (any `active` ruleset, especially required-workflow ones -> PR flow EVEN if classic protection is 404, EVEN for admins). A 404 on classic protection alone is NOT a green light. `branch.main.pushremote=no_push` is ONLY an accidental-push guardrail, NOT a PR-required signal. Don't ask the user; detect from both live gates and adapt.
- **Orphaned tag (tag not on main)**: happens if you tagged on a stale local main, or tagged before a protected/ruleset-gated push that then got rejected, or tagged before a squash-merge. NEVER delete the tag to fix it (git.md: only the user deletes/recreates tags). Recovery: bring main up to the right version with a fresh clean bump that lands on main (a new tag superseding the orphan), or ask the user to delete+recreate the orphan on the correct commit. Prevent it by following Step 1 (sync main, check both protection gates) and the "never tag before the commit is on origin/main" rule.
- **Already pushed**: if `git log origin/main..HEAD` is empty and there are no local changes, everything is already shipped - say so and stop
