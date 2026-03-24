---
name: slack-clipboard
description: Send Claude's output to Slack #clipboard channel. Use when the user says "slack-clipboard", "send to slack", "post to clipboard", or wants to share output via Slack.
allowed-tools: mcp__slack__conversations_add_message
---

# Slack Clipboard

Sends Claude's output to the `#clipboard` Slack channel (`C0ANJQAJC7N`) via the Slack MCP.

## How To Use

When the user invokes `/slack-clipboard`:

1. Identify the most recent substantial output (the Q&A exchange, analysis, summary, etc.)
2. Send it verbatim to channel `C0ANJQAJC7N` using `mcp__slack__conversations_add_message`
3. Confirm with "Sent to #clipboard"

## Rules

- Send the conversation text VERBATIM - do not reformat, rewrite, or convert it
- Include both the user's questions and Claude's responses as they appeared
- Strip leading 2-space terminal indentation from lines
- Use `content_type: text/plain` (the Slack MCP strips formatting with text/markdown)
- Do NOT add emoji unless the original content had them
- Do NOT use em dashes
- Always send to channel `C0ANJQAJC7N` (#clipboard)

## Known Limitations

The Slack MCP strips some characters (parentheses, apostrophes, plus signs, markdown bold markers). For higher-fidelity output, use `/slackify` which copies rich text to the system clipboard for manual paste.
