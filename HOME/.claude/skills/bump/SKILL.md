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

On main, code committed, clean tree. **The version commit lands first and the tag
waits for green CI on that exact SHA.** Never create the tag before CI has run.

```bash
bump --no-tag [-m|-M]                    # version commit on main — NO tag yet
git push --no-follow-tags origin main    # publish the commit; nothing irreversible yet
# WAIT for CI to go green on this SHA
bump --tag-only                          # refuses unless HEAD == origin/main
git push origin vX.Y.Z                   # by explicit name — NEVER --tags
```

`release` does all of that, including the wait. Run it instead of the above.

**Why the wait: the double-tap rule.** A tag is the only irreversible artifact in
a release. Tag before CI, and every failure CI finds can only be repaired by
ANOTHER tag, so one intended release burns two version numbers. otto
v2.0.0/v2.0.1, v2.0.2/v2.0.3 and v2.0.4/v2.0.5 are three consecutive instances of
exactly that. Landing the version commit untagged costs nothing when CI is red:
fix it, commit, re-run `release`, and it tags the SAME version instead of bumping
past it. **One intended release, one version number.**

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
- **The one exception — Scott explicitly orders a standalone bump** ("bump
  finish it" with nothing to fold into): that IS the answer to the ask-Scott
  clause. Do not re-ask; execute with the transcript-visible override marker on
  each gated command — `BUMP_ORDERED_BY_SCOTT=1 git checkout -b bump-X.Y.Z`,
  `BUMP_ORDERED_BY_SCOTT=1 bump --no-tag`, push + PR the same way — and QUOTE
  his ordering words in the PR body. Using the marker without a real order from
  Scott is a hall-of-shame offense. (First use: mcp-io-rs #8, 2026-07-10.)
- **Every PR on a release-managed repo declares its release intent** (Gate D,
  hook-enforced): the body carries `Release: rides this PR (vX.Y.Z)` (run
  `bump --no-tag` on the branch first — the hook verifies a version line actually
  changes) or `Release: none — <why>`. Decide at PR time, never after merge.
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
