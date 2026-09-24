---
description: Watch the named PR to green, work every review thread, report blockers
argument-hint: "<PR url or number>"
---
Read `~/.claude/skills/babysit/SKILL.md` and follow it.

Babysit: ${@:-the PR already named in this session}

Only touch PRs this session has named. Never enumerate my open PRs and never pick one I
did not name. Drive CI to green, fix the failures, work every CodeRabbit and human review
thread to resolution, and report only what actually needs me. When it merges and a bump
rode it, finish the bump, install, and probe until the version is live.
