---
alwaysApply: true
---

# Session recall

- `session-recall-guard.sh` only fires on a pasted session id or one of: `previous|last|prior|earlier` + `session|conversation|chat`, `the session where`, `that doc|design|spec we wrote|made|did`. A recall ask carrying neither ("go find that earlier thing", "what did we land on") reaches no hook: resolve it here instead.
- Any ask to find, resume, search, or read a past Claude Code session -> invoke `Skill(session-recall)`. It owns clyde's session tools: `mcp__clyde__sessions_search`, `mcp__clyde__session_grep`, `mcp__clyde__session_read`, `mcp__clyde__sessions_ls`, `mcp__clyde__session_open`.
- Do this even when Scott names neither clyde nor an id: the ask is the trigger, not the vocabulary.
