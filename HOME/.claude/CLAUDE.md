# Scott Idler

## This file is symlinked into place

- `~/.claude/CLAUDE.md` → `~/repos/scottidler/claude/HOME/.claude/CLAUDE.md`
- Edit/commit the real path, never the symlink

## Never estimate

- No time, effort, or cost estimates — no hours, days, story points, or t-shirt sizes
- No "small fix vs. large refactor" sizing framing
- You lack the calibration; a confidently wrong estimate is worse than none
- If asked "how long," answer with scope: files affected, steps required, unknowns that block progress
- Let the human do the sizing

## Rules

Auto-loaded from `~/repos/.claude/rules/`, grouped by purpose.

Conventions — how I write code & config:
- `general` — naming, files, config, deps, CI, version control (always-on)
- `cli` — CLI flag behavior: space-separated, no commas (always-on)
- `logging` — function-level debug logging (always-on)
- `python` / `rust` / `js-ts` / `yaml` — language-specific (path-scoped)

Tool rules — hard constraints on specific tools:
- `git` — tag/push/working-dir safety (always-on)
- `otto` — task-runner usage (always-on)

Safety:
- `safety` — file deletion; applies to all files (path-scoped `**/*`)

@~/.claude/tools.md

## References

On-demand docs in `~/repos/.claude/refs/` — read when the scenario calls for it.

### environment.md
- Hostnames, Obsidian vault, dotfiles, `manifest` CLI + `manifest.yml` conventions
- Read when: referencing machines, obsidian, dotfiles, or manifest

### personas.md
- Home/work identity, GitHub accounts, SSH keys, Jira/Confluence
- Read when: GitHub, Jira, Slack, or identity-sensitive work

### slack.md
- Slack mrkdwn, posting patterns, ID reference
- Read when: posting to Slack

### jira.md
- Jira issue types, ticket naming, acceptance criteria
- Read when: working on Jira tickets

### dealing-with-large-files.md
- Safe decomposition of large source files
- Read when: splitting files over the size threshold

### refactor.md
- Bulk search-and-replace with the `replace` shell function
- Read when: mechanical cross-file renames

## graphify

- Skill at `~/.claude/skills/graphify/SKILL.md` — turns any input into a knowledge graph
- When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else
