---
name: bump
description: Bump a version and create/push a git tag via the deterministic `release` driver. Use whenever the user says "bump", "bump the version", "bump version", "cut a tag", "create a tag", "tag a release", "tag a new version", "release", or asks to increment or ship a new version — even if they don't mention Rust or say "bump" explicitly. Routes non-trivial releases to the release-driver agent.
---

# Releasing — `release` decides, you don't

## /bump vs /shipit — pick the right one

- **/shipit** — there are UNCOMMITTED changes to ship end-to-end: commit → version → tag → push → install.
- **/bump** (this skill) — the code is already committed (or already merged); you need the version bump + tag done correctly.

Both funnel into the same two flows. **There are exactly two flows and no third.**
Which one applies is decided by whether the default branch is protected — and the
`release` driver (`~/.claude/bin/release`) / `bump --gates` makes that call
mechanically. Never infer gates yourself; every failure in `~/HALL-OF-SHAME.md`
is the model choosing wrong at one of these decision points.

## FLOW 1 — UNGATED (main accepts direct pushes)

On main, code committed, clean tree. Tag HEAD, then push the branch AND the tag
together:

```bash
bump [-m|-M]                                    # bumps Cargo.toml + commits + tags HEAD
git push origin main && git push origin vX.Y.Z  # branch first; && keeps the tag from escaping a rejected push
```

## FLOW 2 — GATED (main requires a PR)

**The version bump rides the FEATURE PR. The tag is cut only AFTER the merge, on
updated main.** A tag created on a branch is burnt and lost forever — squash-merge
rewrites the SHA — which is why `bump` and the hook both refuse it.

```bash
# on the FEATURE branch, code committed, BEFORE the PR merges:
bump --no-tag [-m|-M]        # version commit joins the feature PR — NO tag exists yet
git push origin <branch>     # PR → CI → review → merge

# after the PR merges:
git checkout main && git pull --ff-only origin main
bump --tag-only              # refuses unless HEAD == origin/main — physically cannot orphan
git push origin vX.Y.Z       # by explicit name — NEVER --tags
```

## FORBIDDEN — no exceptions

- **Never create a bump-only release branch** (`release-X.Y.Z` carrying just a
  version commit). The bump belongs INSIDE the feature PR. If a PR already merged
  without its bump: **STOP and ask Scott** — the default is to fold the bump into
  the next feature PR, not to invent a branch. Hard-enforced by the
  `git-release-guard` hook as of 2026-07-10 (after slack-cli #16 recommitted this
  crime): it denies creating `bump-*`/`release-*` branches, denies `bump --no-tag`
  on a branch with zero commits ahead of `origin/<default>`, and denies any
  `git push`/`gh pr create` whose entire diff vs `origin/<default>` is version
  lines + lockfiles.
- **Never tag on a branch, never `bump`/`bump -m`/`bump -M` on a branch.** The
  only legal bump off main is `bump --no-tag` (the hook enforces this).
- **Never** `git push --tags` / `--follow-tags` — the tag lands even if the
  branch push is rejected (this orphaned okta-auth-rs v0.2.0).
- **Never** hand-edit a `version =` line — `bump` owns it.
- **Never** create or delete tags manually — `bump` / `bump --tag-only` make
  annotated tags; only Scott deletes a tag.
- **Never** tag a commit that isn't on `origin/<default>` yet.

## Default path: hand it off

For anything beyond a trivial local bump, give the whole release to the
**release-driver agent** — it runs `release`, babysits a gated PR to merge,
finishes the tag, and verifies it isn't orphaned. That's the safe default.

Or run the driver yourself (clean tree, code already committed — on main if
ungated, on the feature branch if gated):

```bash
release [-m|-M] [--install "<cmd>"|--no-install]   # ungated: ships; gated: bumps the branch, opens PR, pauses
release --finish                                    # gated: after the PR merges — pulls main, tags, pushes tag by name
```

## `bump` reference — the primitive `release` calls

```bash
bump               # patch (x.y.Z) — DEFAULT; UNGATED main only (tags HEAD)
bump -m / -M       # minor / major
bump -n            # dry run — preview, no changes
bump --gates       # which flow applies (checks classic protection AND repo/org rulesets)
bump --no-tag      # GATED: bump + commit, NO tag — run on the FEATURE branch, rides the PR
bump --tag-only    # GATED post-merge: tags the merged tip (verifies HEAD == origin/<default>)
bump -a            # automatic commit message
bump --message "X" # custom commit message
bump --no-verify   # skip the gate probe (treat repo as ungated)
```

For Rust projects using `/rust-cli-coder` conventions, the version `bump` sets is
picked up by `build.rs` and exposed via `GIT_DESCRIBE` for clap's `--version`.
