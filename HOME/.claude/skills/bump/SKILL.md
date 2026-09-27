---
name: bump
description: Bump a version and create/push a git tag via `bump release` / `bump finish`. Use whenever the user says "bump", "bump the version", "bump version", "cut a tag", "create a tag", "tag a release", "tag a new version", "release", or asks to increment or ship a new version, even if they don't mention Rust or say "bump" explicitly. Also fires on the post-merge arc: "the PR merged, finish the bump", "finish the release", "tag it now that it's merged", "it merged, ship it". Routes non-trivial releases, and every post-merge finish, to the release-driver agent, which owns the back half (tag, install, probe or acceptance) in an isolated context.
---

# Releasing: two bare commands

## /bump vs /shipit: pick the right one

- **/shipit**: there are UNCOMMITTED changes to ship end-to-end: commit, version, tag, push, install.
- **/bump** (this skill): the code is already committed (or already merged); you need the version bump + tag done correctly.

Both end in the same two commands. `bump` reads the gates itself (classic
protection AND repo/org rulesets) and picks the flow. Never infer gates yourself.

## The contract

```
cd <repo>                                  # its own Bash call
bump release [-m|-M]                       # bare: no &&, no env prefix, no wrapper
# gated: the PR merges, then
bump finish                                # bare, from any worktree
# Scott ordered a version-only release:
bump release --standalone "<his exact words>"
```

- Run `bump release` and `bump finish` with `run_in_background`: the CI wait runs
  up to `--ci-timeout` (default 1800s), past the Bash tool's 600s foreground cap.
  Read the result when the harness reports the exit.
- A bare `bump ...` matches the `Bash(bump:*)` allow rule. Anything chained or
  prefixed does not, and that is where every auto-mode denial came from.

## UNGATED (main accepts direct pushes)

On main, code committed, clean tree: `bump release [-m|-M]`. It commits the
version, pushes main, waits for green CI on that exact sha, tags the sha, pushes
the tag by name, and installs.

**The double-tap rule.** A tag is the only irreversible artifact in a release.
Tag before CI and every failure CI finds can only be repaired by ANOTHER tag
(otto v2.0.0/v2.0.1, v2.0.2/v2.0.3, v2.0.4/v2.0.5). So the tag waits for CI. If
CI is red, fix it, commit, re-run `bump release`: it tags the SAME pending version
instead of bumping past it. One intended release, one version number.

## GATED (main requires a PR)

On the FEATURE branch, work committed: `bump release [-m|-M]`. It commits the
version as its own commit, pushes the branch, opens the PR itself with a title
derived from the branch and a body ending `Release: rides this PR (vX.Y.Z)`, and
stops. After the PR merges: `bump finish`, from any worktree. It fast-forwards the
default branch where it is checked out, waits for CI on the merged sha, tags it,
pushes the tag by name, and installs.

## The PR already merged: hand the finish to the driver

"It merged, finish the bump" is the **FINISH entry** of the `release-driver`
agent. Spawn it with `ENTRY: finish`, the merged PR url, REPO, INSTALL, KIND, and
either DEPLOY-URL (a deployed service) or ACCEPTANCE (a CLI). It runs
`bump finish` and proves the version is live. If the merge never carried a bump,
`bump finish` refuses: **STOP and report.** The default is to fold the bump into
the next feature PR.

The driver returns "installed at vX.Y.Z, shakedown not run". Running
`/cli-shakedown` is the caller's step.

## Refusals: read them, do what they name

Every refusal names its one exact next command. The ones that matter:

- **Bump-only branch** (diff empty or version lines only): never create one. The
  bump belongs INSIDE the feature PR.
- **Standalone door**: if Scott already ordered a version-only release in this
  session, re-run with `bump release --standalone "<his exact words>"`; the words
  are quoted into the PR. Otherwise STOP and report. Never invent the order, never
  re-ask one he gave.
- **Branch name not its own slug**: run the `git branch -m <slug>` it prints.
- **Behind / diverged**: run the `git pull --ff-only` or `git pull --rebase` it
  prints, then re-run.
- **CI red, truncated, or never registered**: no tag exists. Fix and re-run; a
  repo whose workflows never run on push declares `ci: none` in a committed
  `bump.yml`. Never reach for `--no-ci-gate`; that flag is for Scott at a terminal.

## FORBIDDEN: no exceptions

- **Never** tag a branch, run a tag-creating `bump` off main, or create a tag by hand.
- **Never** `git push --tags` / `--follow-tags`.
- **Never** hand-edit a `version =` line: `bump` owns it.
- **Never** delete a tag; only Scott does.
- **Never** wrap, chain, or env-prefix the two verbs.

## `bump` reference

```bash
bump release [-m|-M] [-n] [--install "<cmd>"|--no-install] [--standalone "<words>"] [--ci-timeout SECS]
bump finish  [-n] [--install "<cmd>"|--no-install] [--ci-timeout SECS]
bump --gates       # which flow applies (classic protection AND repo/org rulesets)
bump -n            # dry run of a plain bump
```

For Rust projects using `/rust-cli-coder` conventions, the version `bump` sets is
picked up by `build.rs` and exposed via `GIT_DESCRIBE` for clap's `--version`.
