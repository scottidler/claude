---
name: bump
description: Bump a version and create/push a git tag via the deterministic `release` driver. Use whenever the user says "bump", "bump the version", "bump version", "cut a tag", "create a tag", "tag a release", "tag a new version", "release", or asks to increment or ship a new version — even if they don't mention Rust or say "bump" explicitly. Routes non-trivial releases to the release-driver agent.
---

# Releasing — `release` decides, you don't

The release problem is binary, and the `release` driver (`~/.claude/bin/release`)
makes the call mechanically so you can't pick the wrong path:

```
ungated  ->  bump tags HEAD          ->  push branch, then tag by name
gated    ->  bump --no-tag rides a PR ->  after merge, tag the merged tip by name
```

Every release failure in `~/HALL-OF-SHAME.md` is the model choosing wrong at one of
those decision points. Don't re-derive the flow from prose — run the driver.

## Default path: hand it off

For anything beyond a trivial local bump, give the whole release to the
**release-driver agent** — it commits the code, runs `release`, babysits a gated PR
to merge, finishes the tag, and verifies it isn't orphaned. That's the safe default.

Or run the driver yourself, on a **clean tree, on the default branch, code already
committed**:

```bash
release [-m|-M] [--install "<cmd>"|--no-install]   # ungated: ships; gated: opens PR + pauses
release --finish                                    # gated: after the PR merges
```

## `bump` directly — the primitive `release` calls

`release` is just a deterministic sequencer over `bump`. Reach for `bump` directly
only for a one-off the driver doesn't fit. `bump` is gate-aware and refuses to
orphan a tag:

```bash
bump --gates     # which flow applies (checks classic protection AND repo/org rulesets)
bump [-m|-M]     # UNGATED: bumps Cargo.toml + commits/amends + tags HEAD
bump --no-tag    # GATED: bumps + commits, NO tag (rides a PR branch)
bump --tag-only  # GATED post-merge: tags the merged tip (verifies HEAD == origin/<default>)
```

### Manual gated flow — bump runs ONLY on the default branch

The `git-release-guard` hook **blocks `bump` on any non-main branch**, so NEVER
bump on the feature branch. The flow:

```bash
# on main, code already committed, CLEAN tree:
bump --no-tag [-m|-M]               # version commit on main, no tag
git branch release-X.Y.Z            # capture it — name it release-* NEVER bump-* (bump-* trips the hook)
git reset --hard origin/main        # main back to identical-with-origin (tree is clean here)
git checkout release-X.Y.Z
git push -u origin release-X.Y.Z    # open a PR, get it merged
# after the PR merges:
git checkout main && git pull --ff-only origin main
bump --tag-only && git push origin vX.Y.Z   # tag by explicit name
```

### Manual ungated flow

```bash
bump [-m|-M]                                   # tags local HEAD
git push origin main && git push origin vX.Y.Z # branch FIRST; the && keeps the tag from escaping a rejected push
```

## Rules that never bend (see rules/git.md)

- **Never** `git push --tags` / `--follow-tags` — the tag lands even if the branch
  push is rejected (this orphaned okta-auth-rs v0.2.0). Push the branch, confirm it
  landed, then the tag by explicit name.
- **Never** hand-edit a `version =` line — `bump` owns it (on gated repos `bump
  --no-tag` does the edit without tagging).
- **Never** create or delete tags manually — `bump` / `bump --tag-only` make
  annotated tags; only Scott deletes a tag.
- **Never** tag a commit that isn't on `origin/<default>` yet.

## Options

```bash
bump               # patch (x.y.Z) — DEFAULT
bump -m            # minor (x.Y.0)
bump -M            # major (X.0.0)
bump -n            # dry run — preview, no changes
bump -a            # automatic commit message
bump --message "X" # custom commit message
bump --gates       # report gate status + recommended flow, then exit
bump --no-tag      # bump + commit, NO tag (gated; rides a PR)
bump --tag-only    # tag the merged commit (gated post-merge step)
bump --no-verify   # skip the gate probe (treat repo as ungated)
```

For Rust projects using `/rust-cli-coder` conventions, the version `bump` sets is
picked up by `build.rs` and exposed via `GIT_DESCRIBE` for clap's `--version`.
