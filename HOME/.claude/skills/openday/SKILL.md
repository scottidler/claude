---
name: openday
description: Open the day - create/populate today's journal note in the Obsidian vault with yesterday's digest highlights, carryover tasks, and 3 vault reading suggestions. Use when the user says "openday", "open the day", "open my day", "start my day", "morning ritual", or asks to set up today's journal/daily note.
---

# openday - the morning bracket

Creates and populates today's journal note in the vault at `~/repos/scottidler/obsidian`. The whole point is zero blank-page friction: Scott runs `/openday`, reads the result, edits the priorities, and goes. Keep total output SHORT - this is a launchpad, not a report.

## Steps

1. **Paths.** Today's note is `journal/YYYY/MM/YYYY-MM-DD.md` (create parent dirs as needed). If it already exists, do NOT overwrite - read it, then only fill in sections that are empty, and say so.

2. **Gather, in parallel where possible:**
   - Yesterday's journal note (`journal/.../<yesterday>.md`) if it exists: extract unchecked `- [ ]` tasks (these carry over) and any "tomorrow" notes.
   - The latest daily digest at `notes/ai/daily/` (most recent file): pull the 2-3 strongest theme sentences, with their `[[wikilinks]]` intact.
   - Oracle (MCP `mcp__oracle__knowledge_search`, load via ToolSearch if needed): one query built from what Scott is currently working on - derive it from recent git activity across `~/repos/scottidler/*` (last day); if there is none, fall back to the digest themes. Take the top 3 `status: unread` results as reading suggestions.
   - Calendar via `gws` (`gws calendar` - check `gws --help`); if `gws` is not installed or not authenticated, omit the Today section silently.

3. **Write the note** with this shape (daily notes deliberately omit the `domain:` frontmatter key - do not add one):

```markdown
---
title: YYYY-MM-DD
date: YYYY-MM-DD
type: daily
origin: authored
tags: []
---

# YYYY-MM-DD

## Priorities

- [ ] (carryover and suggested priorities - max 3, most important first)

## Today

(calendar entries if any, else omit section)

## From the digest

(2-3 theme lines with wikilinks)

## Suggested reading

- [[note-slug|Title]] - one-line why it's relevant today
(max 3)

## Log

(empty - filled during the day / by /closeday)
```

4. **Reply to Scott** with just: the note path, the priorities you carried over, and the one most relevant reading suggestion. Nothing else.

## Rules

- Never use em dashes anywhere.
- Filenames/paths lowercase-hyphenated.
- Do not mark anything reviewed/starred here - that is /closeday's job.
- If yesterday's journal doesn't exist, don't guilt-trip; just build today from the digest.
