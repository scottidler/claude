---
name: slack-clipboard
description: Share a chosen piece of Claude's output to the user's own Slack #clipboard channel. Use when the user explicitly says "slack-clipboard", "send to slack", or "post to clipboard". Do not trigger automatically or on incidental mentions of Slack.
allowed-tools: mcp__slack__chat_post_message
---

# Slack Clipboard

Posts a selected snippet of Claude's output to the user's own `#clipboard` Slack channel (`C0ANJQAJC7N`) via the Slack MCP. This is the user's personal scratch channel, used as a cross-device clipboard.

`#clipboard` is a private channel that Scott is the only member of. Posting there is not sharing with anyone: it is moving his own text between his own devices. Treat it like a clipboard, not like publishing.

## How To Use

Only run when the user explicitly invokes `/slack-clipboard` (or one of the trigger phrases above). Never post on an accidental or broad trigger, and never post the entire conversation history.

1. Select content by default scope: take only the single most recent substantial output (the latest answer, analysis, or summary). Do NOT gather the full conversation or earlier exchanges unless the user specifically asks for a wider selection.
2. Post it to channel `C0ANJQAJC7N` using `mcp__slack__chat_post_message`, with `no_mentions: true` so `@`/`#` tokens in the content stay content.
3. Reply with the permalink the call returns, and nothing else. No preview beforehand, no summary of what was sent.

**Do NOT ask for confirmation.** The target is always Scott's own private channel, so the invocation IS the authorization. Asking "post this? (yes/no)" after he said to post it is the failure mode this skill exists to avoid. Same for his own DM: no confirmation there either.

## Rules

- If Claude composes or reworks the content (anything beyond verbatim relay), it goes out as Scott: keep it terse, direct, Slack-native.
- No confirmation gate, no preview, no egress warning. Post on the first ask.
- Default to the most recent relevant snippet only; widen the selection solely on the user's request.
- One exception to posting immediately: if the selection contains an actual credential VALUE (a token, key, or password, not an env var name), stop and say which line, because Slack retention keeps it. Nothing else earns a pause.
- Send the text as-is - do not reformat, rewrite, or convert it beyond stripping leading 2-space terminal indentation from lines.
- Pass `no_mentions: true`. Leave `raw` unset so Markdown converts to Slack mrkdwn.
- Do NOT add emoji unless the selected content had them.
- Always send to the user's own channel `C0ANJQAJC7N` (#clipboard); never to any other channel or destination.

## Known Limitations

The Slack MCP strips some characters (parentheses, apostrophes, plus signs, markdown bold markers). For higher-fidelity output, use `/slackify`.

## Two Separate Paths

This directory contains two distinct, non-overlapping mechanisms - be clear with the user about which one is running:

- The skill itself (`/slack-clipboard`): posts approved text directly to Slack via the Slack MCP. This is a network egress action.
- The bundled `slackify.sh` helper (used by the separate `/slackify` skill): does NOT talk to Slack or the network at all. It converts markdown to rich-text HTML and copies it to the LOCAL system clipboard for the user to paste into Slack manually. Nothing is sent anywhere by this script. It also discloses on stderr if it has to recover Wayland display variables from the terminal process.
