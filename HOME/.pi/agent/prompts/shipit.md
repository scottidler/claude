---
description: Commit, bump, push, install, and prove the new version is live
argument-hint: "[what changed]"
---
Ship the current change end to end. Read `~/.claude/skills/shipit/SKILL.md` and follow it.

${@:-Ship what is currently in the working tree.}

Done means live, not merged: commit, bump via `bump` (never hand-edit a version), push,
wait for the PR to merge if the repo is gated, finish the tag, install, and then PROVE
the new version is running. For a deployed service that proof is `sdv probe <url>` until
the version lands. For a CLI it is the installed binary's `--version` plus one acceptance
command. Report the proof, not the intent.
