---
name: closeday
description: Close the day - log a dictated/typed recap into today's journal note, triage a handful of vault note statuses, pin or flag a few cold notes, and distill today's Claude sessions into the vault. Use when the user says "closeday", "close the day", "close my day", "end of day", "evening ritual", or wants to wrap up the day's notes.
---

# closeday - the evening bracket

Closes the loop the second-brain system otherwise lacks: capture happened all day; now 5 minutes of curation makes it compound. Keep it fast - if any step would take more than a couple of tool calls, degrade gracefully and move on.

Vault: `~/repos/scottidler/obsidian`. Today's journal: `journal/YYYY/MM/YYYY-MM-DD.md`. If it's missing, invoke the `openday` skill via the Skill tool first to create it, then continue here.

## Steps

1. **Recap.** If the user's message already contains their day recap, use it. Otherwise ask for it once - and remind them `dictate` exists (`~/repos/scottidler/second-brain/main/bin/dictate`, or `dictate` if on PATH): they can run it, speak, and paste. Append the recap under `## Log` in today's journal note with an `HH:MM` prefix. Check off any `- [ ]` priorities the recap says got done.

2. **Triage 5.** Query oracle (`mcp__oracle__recent_activity` or `knowledge_search`, load via ToolSearch) for notes ingested in the last ~3 days with `status: unread`. Present the 5 most relevant as a compact list (title + one-line tldr) and ask ONE question: which to mark reviewed / starred / skip. Apply the answers by editing each note's `status:` frontmatter field in place. If the user says "skip" or is clearly done, skip silently.

3. **Cold notes, 3 rows.** Read `system/views/cold-notes.md` - it is REGENERATED WEEKLY and says "do not edit manually", so treat it as strictly read-only. Take the first 3 rows whose target note lacks `pinned: true`, skipping football rows (bulk sports captures Scott triages separately). Ask keep/archive per row in the SAME question as step 2 if possible. "Keep" = set `pinned: true` in that note's frontmatter (this removes it from the next report); "archive" = record the note path under `## Log` in today's journal for Scott to act on (never delete anything yourself).

4. **Session distill.** Find today's Claude Code sessions via the clyde MCP tools if available (`mcp__clyde__sessions_ls` / `mcp__clyde__sessions_search`, load via ToolSearch), falling back to the `clyde` CLI. Pick the 1-2 most substantive (real engineering, not chat). For each, write a 5-10 line "what was learned / what was decided" distillation. Append these under `## Log` in the journal note as `### Sessions`. If any distillation is genuinely reusable knowledge (a root cause, a pattern, a gotcha), ALSO create `inbox/YYYY-MM-DD-<slug>.md` with the distillation as body and exactly this frontmatter (cortex will classify and promote it):

```markdown
---
title: <Readable Title>
date: YYYY-MM-DD
type: note
origin: generated
tags: []
---
```

5. **Reply** with: what was logged, which statuses changed, and one line about tomorrow (any carryover it should open with). Nothing else.

## Rules

- Never use em dashes.
- One combined question to the user maximum (step 2+3); everything else is autonomous.
- Never delete files. Status edits touch only the `status:` (and `pinned:`) frontmatter lines.
- If oracle/clyde are unavailable, do the steps that work and say which were skipped.
