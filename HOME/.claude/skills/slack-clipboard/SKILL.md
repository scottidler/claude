---
name: slack-clipboard
description: Share a chosen piece of Claude's output to the user's own Slack #clipboard channel, only after the user reviews and approves it. Use when the user explicitly says "slack-clipboard", "send to slack", or "post to clipboard". Do not trigger automatically or on incidental mentions of Slack.
allowed-tools: mcp__slack__conversations_add_message
---

# Slack Clipboard

Posts a selected snippet of Claude's output to the user's own `#clipboard` Slack channel (`C0ANJQAJC7N`) via the Slack MCP. This is the user's personal scratch channel, used as a cross-device clipboard.

This skill performs an EGRESS action: whatever is approved is copied out of the local Claude session into Slack, where it persists and may be visible to others with access to that channel. Treat anything posted as leaving the local context permanently.

## How To Use

Only run when the user explicitly invokes `/slack-clipboard` (or one of the trigger phrases above). Never post on an accidental or broad trigger, and never post the entire conversation history.

1. Select content by default scope: take only the single most recent substantial output (the latest answer, analysis, or summary). Do NOT gather the full conversation or earlier exchanges unless the user specifically asks for a wider selection.
2. Show the user a preview before sending: print the exact text that would be posted and state the target channel (`#clipboard`, `C0ANJQAJC7N`). Let the user trim, edit, or replace the selection.
3. Ask for explicit confirmation: "Post this to your Slack #clipboard channel? (yes/no)". Wait for a clear yes. Any non-affirmative answer, or silence, means do not send.
4. Only after an explicit yes, send the approved text to channel `C0ANJQAJC7N` using `mcp__slack__conversations_add_message`.
5. Confirm with "Sent to #clipboard".

## Rules

- If Claude composes or reworks the content (anything beyond verbatim relay), it goes out as Scott: keep it terse, direct, Slack-native, and free of em-dashes.
- Mandatory confirmation: never call the Slack MCP before completing steps 2 and 3 and receiving an explicit yes.
- Default to the most recent relevant snippet only; widen the selection solely on the user's request.
- Before sending, remind the user that anything posted leaves the local context and lands in a persistent Slack channel; let them redact secrets, credentials, or private content first.
- Send the approved text as-is - do not reformat, rewrite, or convert it beyond stripping leading 2-space terminal indentation from lines.
- Use `content_type: text/plain` (the Slack MCP strips formatting with text/markdown).
- Do NOT add emoji unless the approved content had them.
- Do NOT use em dashes.
- Always send to the user's own channel `C0ANJQAJC7N` (#clipboard); never to any other channel or destination.

## Known Limitations

The Slack MCP strips some characters (parentheses, apostrophes, plus signs, markdown bold markers). For higher-fidelity output, use `/slackify`.

## Two Separate Paths

This directory contains two distinct, non-overlapping mechanisms - be clear with the user about which one is running:

- The skill itself (`/slack-clipboard`): posts approved text directly to Slack via the Slack MCP. This is a network egress action.
- The bundled `slackify.sh` helper (used by the separate `/slackify` skill): does NOT talk to Slack or the network at all. It converts markdown to rich-text HTML and copies it to the LOCAL system clipboard for the user to paste into Slack manually. Nothing is sent anywhere by this script. It also discloses on stderr if it has to recover Wayland display variables from the terminal process.
