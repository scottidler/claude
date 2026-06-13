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
- **Determine the push flow NOW, before any bump or tag — flow decides whether you may tag at all.** Run `bump --gates` — it checks BOTH live gates (classic protection AND repo/org rulesets) and prints the flow. A 404 on classic protection alone is NOT a green light; org required-workflow rulesets (e.g. "Tatari Org Security") reject direct pushes even for admins — this orphaned claude-pricing v0.2.0 and okta-auth-rs v0.2.0.
  - `Gates: none (ungated)` → direct-push flow. `Gates: … (gated)` → PR flow.
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

`bump` is gate-aware: plain `bump` refuses to tag on a gated repo, and `bump --tag-only`
verifies `HEAD == origin/<default>` before tagging — so it can't orphan a tag. What you run
depends on the flow from Step 1:

- **Direct-push flow:** run `bump` here. `-a` (you committed in Step 3), plus `-m` for `--minor`; for `--major`, confirm with the user first ("Major bump - are you sure?"), then `-M`. `bump` bumps Cargo.toml, commits/amends, and tags local HEAD. The branch + tag get pushed (in the safe order) in Step 5.
- **PR flow:** run `bump --no-tag` here (plus `-m`/`-M` as above). It bumps the version and commits but creates NO tag, so the bump can ride your feature branch / PR. The tag is created only AFTER the PR merges, via `bump --tag-only` (Step 5). Never run plain `bump` on a gated repo — it would refuse anyway, but `--no-tag` is the right call.

### Step 5: Push

Use the flow from Step 1 — do not re-detect by hand, and NEVER run `git push --tags` in any flow (tags are pushed by explicit name, only after the commit they point to is on origin).

**Direct-push flow** — `bump` (Step 4) already tagged local HEAD. Push the branch FIRST, then the tag by explicit name. The `&&` ordering is the safety: if the branch push is rejected, the tag never escapes.

```bash
git push origin main && git push origin vX.Y.Z
```

`vX.Y.Z` is the tag `bump` just created (`git tag --points-at HEAD --list 'v*'`). If the main push is rejected, STOP — do not push the tag, do not retry variations, do not change repo settings. Report the rejection to the user.

**PR flow** — `bump --no-tag` (Step 4) bumped the version with NO tag, so the bump rides your feature branch in a single PR:

1. Make sure those commits are on a feature branch (generate a name from the commit message, e.g. `add-cli-expansion`; `git checkout -b <branch-name>` if you bumped on `main` locally)
2. Push the branch ONLY: `git push --no-follow-tags -u origin <branch-name>`
3. Create a PR: `gh pr create --title "<title>" --body "<summary>"`
4. Report the PR URL, then STOP and wait for the PR to merge (review/CI gated). You cannot tag yet.
5. **After the PR merges**, tag the merged commit:
   ```bash
   git checkout main && git pull --ff-only origin main
   bump --tag-only            # verifies HEAD == origin/main, then creates the annotated tag
   git push origin vX.Y.Z     # push the tag by explicit name
   ```
   `bump --tag-only` refuses unless HEAD is exactly `origin/main`, so the tagged commit is provably on origin before the tag exists; an existing correct tag at HEAD is a no-op, one pointing elsewhere is refused.

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
- **Branch protection**: `bump --gates` is the detection method — it checks both live layers (classic protection AND repo/org rulesets; org rulesets are not bypassed by repo admins). Never decide from the classic endpoint alone, and never infer from `branch.main.pushremote=no_push` (that's only an accidental-push guardrail). Don't ask the user; run the probe and adapt.
- **Orphaned tag (tag not on main)**: happens if you tagged on a stale local main, or tagged before a protected/ruleset-gated push that then got rejected, or tagged before a squash-merge. NEVER delete the tag to fix it (git.md: only the user deletes/recreates tags). Recovery: STOP and report the exact state to the user — re-pointing or superseding a live tag is their decision. Prevention is structural: plain `bump` refuses on a gated repo, and `bump --tag-only` refuses to create a tag unless HEAD is exactly `origin/main`.
- **Already pushed**: if `git log origin/main..HEAD` is empty and there are no local changes, everything is already shipped - say so and stop
