---
name: vault-recall
description: Pull relevant prior knowledge from Scott's Obsidian vault (via the oracle MCP) into the current task's context. Use at the start of substantive research, design, or learning tasks - or when the user says "vault recall", "check the vault", "what do I have on this", "have I saved anything about", or references their second brain / saved notes / ingested videos on a topic. Make sure to use this whenever starting research, design, or learning work on a topic Scott may have saved notes about, even if he doesn't mention the vault, oracle, or his notes at all.
---

# vault-recall - what do I already know about this?

Scott ingests ~10 notes/day (YouTube, articles, GitHub) into an Obsidian vault indexed by the oracle MCP server (user-scoped, available in every session). This skill front-loads that prior knowledge instead of re-deriving or re-searching the web for things he already saved.

## Steps

1. Load oracle tools if not present: ToolSearch `select:mcp__oracle__knowledge_search,mcp__oracle__domain_brief,mcp__oracle__find_similar`.

2. Run `knowledge_search` with a query built from the task at hand (2-6 content words, not a sentence - e.g. task "help me design retry logic for the borg ingest pipeline" becomes query "retry backoff ingestion pipeline"). Default pipeline (no mode), `detail: tldr`, `limit: 8`. If the topic clearly belongs to one domain, pass `domain` to sharpen it; valid domains are ai, tech, football, work, writing, music, spanish, life, homelab, diy, resources, system.

3. If results look thin, retry once with `mode: bm25` for proper nouns (tool names, people) - vector search can miss exact-name matches.

4. Filter to the 2-4 results that would actually change the work. For each, if more depth is needed, read the note file directly (path is in the result) rather than re-querying.

5. Weave what you found into the task: cite as `[[note-slug]]` or the note title, state the claim it contributes, and flag notes with `trace.available: true` when exact wording matters (the staged source has the verbatim transcript).

## Rules

- This is a context-loading step, not a deliverable: keep the recall summary to a few lines, then get on with the actual task.
- Zero relevant results is a fine answer - say so in one line and proceed; do not pad.
- Results with `status: unread` that were highly relevant are worth mentioning to Scott ("you saved this but haven't read it").
