---
name: shipit
description: Ship code changes - commit, bump the version, push the branch then the tag by name, and install. Use when the user says "ship it", "shipit", or wants to commit+bump+push+install in one go. Also trigger on "release this", "push this out", or "cut a release and install" when the intent is to ship the current change end-to-end — prefer firing over asking.
---

# Ship It

"shipit" = ship the current change as a release: commit → bump → push (branch
first, tag by name) → install. **Hand the whole thing to the `release-driver`
agent.** It runs the release in an isolated context through the deterministic
`release` driver, so the tag/push logic — where every `~/HALL-OF-SHAME.md` failure
lives — has no room for the model to pick a wrong path or rationalize an orphan.

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
release [-m|-M] [--install "<cmd>"|--no-install]   # clean tree, on default branch
# gated repos pause at "waiting on PR merge"; after merge: release --finish
```

## Rules that never bend

- **Never** `git push --tags` / `--follow-tags` — push the branch, confirm it
  landed, then the tag by explicit name (`git push origin vX.Y.Z`).
- **Never** bump on a feature branch (the hook blocks it); the gated flow bumps on
  the default branch and rides a `release-*` branch through a PR.
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
