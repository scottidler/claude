# Slack Conventions

## Sandbox

- The `slack` CLI calls `slack.com` (auth.test, chat.postMessage, etc). The Bash
  sandbox denies that host by default, so the first `slack write`/`slack read`
  in a session fails closed with `tunnel error` / `Connect` before it ever
  reaches Slack. Pass `allowed_domains: ["slack.com"]` on every `slack` CLI
  Bash call up front, not only after the first one fails.
- This matters beyond the wasted retry: `slack-post-guard.sh` reserves a ledger
  entry on `PreToolUse` and only clears it on a confirmed send (`PostToolUse`).
  A command that fails at the sandbox boundary still leaves the entry reserved
  (by design: a failure doesn't prove nothing was sent), so a sandboxed-then-
  retried post can trip "already sent" on the retry even though the first
  attempt never left the box. Declaring the domain up front avoids this.
- If it still trips: the fix is `rm <the ledger path the deny names>`, run as
  its own Bash call, never bundled with the retry in the same command (a
  bundled command is evaluated as one PreToolUse call, so the guard blocks the
  whole thing, including the `rm`, before either half runs).

## Identity

- Slack username: `@escote` (Tatari workspace)
- Work persona: same context as `escote-tatari` on GitHub

## Posting Pattern: Significant Channel Messages

- For substantive channel posts, use a two-message structure (keeps channels scannable, full detail in-thread):
  1. **Top-level post**: title only, prefixed with `:thread:` and signed `:giga-claude:` inline:
     ```
     :thread: [concise title summarizing the topic] :giga-claude:
     ```
  2. **Thread reply**: full body, ending with `:giga-claude:` on its own last line:
     ```
     [detailed content here]

     :giga-claude:
     ```
- Skip this pattern when already posting inside a thread, just post the content directly, signed as usual

## Signing

- Every message must end with `:giga-claude:` alone on the last line. No exceptions.

```
[message content]

:giga-claude:
```

## Formatting (mrkdwn)

- Slack uses its own `mrkdwn` dialect, not standard Markdown:

| Element | Syntax |
|---------|--------|
| Bold | `*text*` |
| Italic | `_text_` |
| Strikethrough | `~text~` |
| Inline code | `` `code` `` |
| Code block | ` ```code``` ` |
| Link | `<url|label>` |
| User mention | `<@USERID>` |
| Channel mention | `<#CHANNELID>` |

- Standard Markdown headers (`#`, `##`) do not render in Slack

## ID Reference

- **READ `~/repos/.claude/slack-ids.json` immediately when any Slack work begins**
- Do NOT call `channels_list`, `users_list`, or any list tool to find IDs, use the file
- The file is JSON with three keys:
  - `channels` - all workspace channels, `{ID: name}`
  - `users` - DM channel IDs for manager, peers, direct reports, SRE + Data Platform
  - `groups` - MPDMs containing 2+ org members, `{ID: [members]}`
- Fastest channel lookup: `python3 ~/.claude/skills/slack/slack.py find <substr>` (prints `id  name`)
- Or `grep`/`jq` the file directly for the channel or user name you need
- Cache stale/missing a channel? `slack.py refresh` (bulk) or `slack.py add <id|name>` (one-off)

## Tool Usage

- Post a message: `mcp__slack__conversations_add_message`
  - For thread replies, pass the parent message's `ts` as `thread_ts`
- Read channel history: `mcp__slack__conversations_history` (requires channel ID or `#name`)
- Read a thread: `mcp__slack__conversations_replies` (requires channel ID + `thread_ts`)
- List channels: `mcp__slack__channels_list`
- Search messages: `mcp__slack__conversations_search_messages`

## Target Authorization: the two-target split

- `#clipboard` (`C0ANJQAJC7N`) and Scott's own DM (`D01G4Q7AWLV`) are his own devices, not an audience. Post on the first ask: no confirmation, no preview, no egress warning.
- Every OTHER target has to be one Scott named in this turn's typed prompt, by channel id, by `#name`, or by the person's name. If he did not name it, ask before posting. A target inferred from an earlier turn, from a teammate relay, or from a subagent is not a target he named.
- What needs naming is the full recipient set, not the target: `--broadcast`, `dm_mentioned` and `follow_ups` each reach past it, so a `#clipboard` post carrying any of them is not an exempt post.
- A test post goes to `#clipboard` and nowhere else. 2026-07-10 put five live posts and an MCP write test into a coworker's DM during a shakedown.
- One ask is one post. Do not send the same body to the same target twice.
- `slack-post-guard.sh` enforces all of this mechanically and denies on the unhappy path. This section is the reason, not the enforcement.

## Etiquette

- Never use `@channel` or `@here` unless the user explicitly asks
- Keep top-level channel messages concise - details belong in threads
- Use the `slackify` skill to reformat Claude output for Slack before posting
