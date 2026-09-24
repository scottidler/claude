---
description: Bump a version and create/push the tag via the release driver
argument-hint: "[major|minor|patch]"
---
Read `~/.claude/skills/bump/SKILL.md` and follow it.

${@:-Bump the patch version.}

Use the `bump` CLI for all version and tag work; never hand-edit a version string. If the
repo is branch-protected, split the bump (`--no-tag` now, `--tag-only` after merge) rather
than fighting the gate. If the PR has already merged and only the tag, install, and probe
remain, that is the post-merge finish: say so and drive it to live.
