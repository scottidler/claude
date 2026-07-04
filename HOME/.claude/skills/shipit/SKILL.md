---
name: shipit
description: Ship code changes - commit, bump the version, push, and install. Use when the user says "ship it", "shipit", or wants to commit+bump+push+install in one go. Also trigger on "release this", "push this out", or "cut a release and install" when the intent is to ship the current change end-to-end — prefer firing over asking.
---

# Ship It

## /shipit vs /bump — pick the right one

- **/shipit** (this skill) — there are UNCOMMITTED changes to ship end-to-end:
  commit → version → tag → push → install.
- **/bump** — the code is already committed (or already merged); only the version
  bump + tag remain.

"shipit" = ship the current change as a release. **Hand the whole thing to the
`release-driver` agent.** It runs the release in an isolated context through the
deterministic `release` driver, so the tag/push logic — where every
`~/HALL-OF-SHAME.md` failure lives — has no room for the model to pick a wrong
path or rationalize an orphan.

## The two flows the driver executes (there is no third)

- **UNGATED** (main accepts direct pushes): commit on main → `bump` (tags HEAD) →
  `git push origin main && git push origin vX.Y.Z` — branch AND tag together, tag
  by explicit name.
- **GATED** (main requires a PR): the version bump RIDES THE FEATURE PR
  (`bump --no-tag` on the feature branch) → push branch → PR → merge → pull main →
  `bump --tag-only` → `git push origin vX.Y.Z`. The tag exists only AFTER the
  merge, on updated main. Never a tag on a branch (squash rewrites the SHA — the
  tag is burnt forever). Never a bump-only release branch.

## What to do

1. **Pre-flight.** Confirm it's a git repo and there's something to ship: modified/
   untracked files, OR unpushed commits. If there are no changes and nothing
   unpushed, say so and stop. Determine the bump level: patch by default; `-m` for
   `--minor`; for `--major` confirm with the user first, then `-M`.

2. **Spawn the `release-driver` agent** with:
   - **LEVEL** — patch / minor / major from the flags above.
   - **MESSAGE** — a concise commit message you derive from the diff (you have the
     working context; pass it so the agent doesn't have to re-infer).
   - **INSTALL** — install command from CLAUDE.md (repo root, then `.claude/CLAUDE.md`
     — Quick Reference / Install / Build & Install sections, including any daemon
     restart); else `cargo install --path .` for a Rust crate; else `--no-install`.

   The agent commits the real files, runs `release` (which detects gated vs ungated
   and executes the right flow), babysits a gated PR to merge, finishes the tag,
   and verifies it's on `origin/<default>`. Relay its report.

## Doing it inline (only for a trivial ungated bump)

If you genuinely shouldn't spawn an agent (e.g. a tiny local-remote bump), do it by
hand — but follow the `bump` skill exactly:

```bash
# commit the real files by explicit path (NEVER git add -A — sweeps scratch assets)
git add <files> && git commit -m "<message>"
release [-m|-M] [--install "<cmd>"|--no-install]   # clean tree; main if ungated, feature branch if gated
# gated repos pause at "waiting on PR merge"; after merge: release --finish
```

## Rules that never bend

- **Never** `git push --tags` / `--follow-tags` — push the branch, confirm it
  landed, then the tag by explicit name (`git push origin vX.Y.Z`).
- **Never** a tag-creating bump off main — on a feature branch the only legal
  form is `bump --no-tag` (the hook enforces this); the tag comes after the merge
  via `bump --tag-only` on updated main.
- **Never** create a bump-only release branch. The bump rides the feature PR. If
  a PR already merged without its bump: STOP and ask Scott — default is to fold
  the bump into the next feature PR.
- **Never** hand-edit a version, create/delete a tag by hand, or tag a commit not
  yet on `origin/<default>`.
- **Push rejected after a tag exists locally?** STOP — don't push the tag, don't
  retry variations, don't change repo settings. Report the exact state. (This is the
  okta-auth-rs orphan vector.)

## Edge cases

- **No changes & nothing unpushed:** stop and say so.
- **Detached HEAD:** warn before proceeding.
- **Behind origin:** the driver refuses and tells you to pull/rebase first — do that,
  don't force anything.
- **Non-Rust repo:** commit + push as normal; bump is skipped unless CLAUDE.md
  documents a bump mechanism; install per CLAUDE.md or skipped.
- **Install fails:** report it but do NOT roll back the push — the code is shipped.
