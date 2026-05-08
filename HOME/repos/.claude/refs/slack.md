# Slack Conventions

## Identity

- Slack username: `@escote` (Tatari workspace)
- This is the work persona - same context as `escote-tatari` on GitHub

## Posting Pattern: Significant Channel Messages

When posting something substantive to a channel, use a two-message structure:

1. **Top-level post** - title only, prefixed with `:thread:` and signed with `:giga-claude:` inline:
   ```
   :thread: [concise title summarizing the topic] :giga-claude:
   ```

2. **Thread reply** - full body of the message, ending with `:giga-claude:` on its own last line:
   ```
   [detailed content here]

   :giga-claude:
   ```

This pattern keeps channels scannable while preserving full detail in the thread.

**Skip this pattern when already posting inside a thread** - just post the content directly, signed as usual.

## Signing

Every message must end with `:giga-claude:` alone on the last line. No exceptions.

```
[message content]

:giga-claude:
```

## Formatting (mrkdwn)

Slack uses its own `mrkdwn` dialect - not standard Markdown:

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

- No em dashes - use regular dashes, commas, or semicolons instead
- Standard Markdown headers (`#`, `##`) do not render in Slack

## ID Reference

**READ `~/repos/.claude/slack-ids.yml` immediately when any Slack work begins.**
Do NOT call `channels_list`, `users_list`, or any list tool to find IDs — use the file.

The file contains:
- `channels:` - all workspace channels, keyed `ID: name`
- `users:` - DM channel IDs for manager, peers, direct reports, SRE + Data Platform
- `groups:` - MPDMs containing 2+ org members

Search it with `grep` for the channel or user name you need.

## Tool Usage

- Post a message: `mcp__slack__conversations_add_message`
  - For thread replies, pass the parent message's `ts` as `thread_ts`
- Read channel history: `mcp__slack__conversations_history` (requires channel ID or `#name`)
- Read a thread: `mcp__slack__conversations_replies` (requires channel ID + `thread_ts`)
- List channels: `mcp__slack__channels_list`
- Search messages: `mcp__slack__conversations_search_messages`

## Etiquette

- Never use `@channel` or `@here` unless the user explicitly asks
- Keep top-level channel messages concise - details belong in threads
- Use the `slackify` skill to reformat Claude output for Slack before posting
