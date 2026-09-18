---
name: session-recall
description: Pull relevant prior Claude Code sessions (via the clyde MCP server) into the current task's context. Use when the user says "session recall", "find that session", "the session where we", "that doc/design/spec we wrote/made/did", "previous session", "last session", "prior conversation", or pastes a session id (a UUID). Make sure to use this whenever the user is pointing at a prior session or its content, even if he doesn't mention clyde, sessions, or a session id at all.
---

# session-recall - go find that prior session

Scott's Claude Code sessions are catalogued by clyde (title, tags, summary, repo/branch, dates, full transcript) and exposed read-only over MCP. This skill front-loads that prior work instead of re-deriving it or guessing at a session's contents from memory.

## Steps

1. Load clyde tools if not present: ToolSearch `select:mcp__clyde__sessions_search,mcp__clyde__sessions_ls,mcp__clyde__session_open,mcp__clyde__session_grep,mcp__clyde__session_read`. All five, because steps 2 and 3 call `session_open` and `sessions_ls`: loading only three forces a second ToolSearch, which is the round trip this skill exists to avoid.

2. If the user named a session id (a UUID, or a unique prefix of one), skip straight to `session_open` with `id` to resolve it (resume command, staged path, or unavailable), then `session_read` with `id` (optional `offset`, `limit`) to page the transcript, or `session_grep` with `id` and `query` (optional `context_lines`, `limit`) to jump straight to the relevant part.

3. Otherwise, run `sessions_search` with `query` (a few content words, not a sentence) and optional `limit`, `include_archived`, `sort` (`relevance` default, or `recency`). If a repo, date range, tag, or model is the better filter, use `sessions_ls` instead (`repo`, `since`, `tag`, `model`, `limit`, `include_archived`; no `query`).

4. From the search or list hits, pick the session(s) that match, then use `session_read` or `session_grep` (same `id` + params as step 2) to pull the actual content, not just the summary.

5. If the MCP tools are unavailable, fall back to the CLI: `clyde session search`, `clyde session ls`, and `clyde session export --id <id> --with-body` for transcript content (`--max-body-bytes` caps the read at a message boundary). There is no CLI equivalent of `session_grep`'s substring search: grep the exported body instead. **`clyde session resume` is not a read path and is not a stand-in for `session_open`**: it resolves the session's recorded cwd, chdirs there, and fork/execs `claude --resume <id>`, replacing the current process. Never reach for it to inspect a session.

6. Weave what you found into the task: cite the session id (or resume command) and quote or summarize the relevant part, don't just say a session exists.

## Rules

- This is a context-loading step, not a deliverable: keep the recall summary to a few lines, then get on with the actual task.
- Zero relevant results is a fine answer - say so in one line and proceed; do not pad.
- Watch the naming traps: `sessions_search` and `sessions_ls` are plural, `session_open`, `session_grep`, `session_read` are singular. It's `context_lines` (not `context` or `-C`), `include_archived` (not `archived`), `since` with no `until`. `id` takes any unique prefix, not only a full UUID. `session_grep.query` is a plain case-insensitive substring; `sessions_search.query` is full-text search, same field name, different language.
