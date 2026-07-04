# Scott Idler

## This file is symlinked into place

- `~/.claude/CLAUDE.md` → `~/repos/scottidler/claude/HOME/.claude/CLAUDE.md`
- Edit/commit the real path, never the symlink

## Non-Negotiable: Root Cause Always

When something breaks or behaves unexpectedly, **never speculate, guess, or say "I don't know"**. Go find the answer. Check logs, inspect state, read files, run commands — whatever it takes. "I don't know", "probably", "likely", "fluke", "magic", or any hand-wavy non-answer is never acceptable. If the cause isn't known yet, the correct response is to go investigate until it is.

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
- `taste` — design/review judgment: pipeline discipline, quality bar, architecture & security instincts, phasing, evidence standards (always-on; mined from all sessions 2026-05..07)
- `cli` — CLI flag behavior: space-separated, no commas (always-on)
- `logging` — function-level debug logging (always-on)
- `python` / `rust` / `js-ts` / `yaml` — language-specific (path-scoped)

Tool rules — hard constraints on specific tools:
- `git` — tag/push/working-dir safety (always-on)
- `otto` — task-runner usage (always-on)

Safety:
- `safety` — file deletion; applies to all files (path-scoped `**/*`)
- `secrets` — age-encrypted secrets via `manifest age`; gh token picked by repo org (home vs work persona) (always-on)

@~/.claude/tools.md

## References

On-demand docs in `~/repos/.claude/refs/` — read when the scenario calls for it.

### environment.md
- Hostnames, Obsidian vault, dotfiles, `manifest` CLI + `manifest.yml` conventions
- Read when: referencing machines, obsidian, dotfiles, or manifest

### personas.md
- Home/work identity, GitHub accounts, SSH keys, Jira/Confluence
- Read when: GitHub, Jira, Slack, or identity-sensitive work, or when asked who the user is (role, title, job, experience)

### slack.md
- Slack mrkdwn, posting patterns, ID reference
- Read when: posting to Slack

### jira.md
- Jira issue types, ticket naming, acceptance criteria
- Read when: working on Jira tickets

### design-exemplars.md
- Worked examples of my design/review judgment with verbatim quotes + session provenance
- Read when: authoring or reviewing a design doc, running an implementation audit, or making a judgment call `rules/taste.md` doesn't settle

### dealing-with-large-files.md
- Safe decomposition of large source files
- Read when: splitting files over the size threshold

### refactor.md
- Bulk search-and-replace with the `replace` shell function
- Read when: mechanical cross-file renames

## graphify

- Skill at `~/.claude/skills/graphify/SKILL.md` — turns any input into a knowledge graph
- When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else
