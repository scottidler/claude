---
name: slackify
description: Reformat Claude's output for Slack and copy to clipboard as rich text. Use when the user wants to paste Claude output into Slack, or says "slackify", "for slack", "copy for slack", or "slack format".
allowed-tools: Bash(slackify:*)
---

# Slackify

Copies Claude's output to the clipboard as rich text that Slack renders correctly when pasted.

## How It Works

The script converts markdown to HTML via pandoc, then copies it to the clipboard as `text/html`. Slack's composer reads the HTML MIME type and renders bold, italic, headers, code blocks, lists, and links as formatted rich text - identical to composing natively in Slack.

## How To Use

When the user invokes `/slackify` or asks to format output for Slack:

1. Identify the most recent substantial output (the Q&A exchange, analysis, summary, etc.)
2. Include both the user's questions and Claude's responses as they appeared
3. Write it as clean markdown - do NOT attempt Slack mrkdwn syntax
4. Strip any leading 2-space terminal indentation from lines before piping
5. Pipe it through the script using a heredoc:

```bash
cat << 'EOF' | ~/.claude/skills/slackify/slackify.sh
## My Heading

**Bold text** and _italic text_ work naturally.

- Bullet lists
- Code: `inline code`

> Blockquotes too
EOF
```

6. Confirm with "Copied to clipboard - ready to paste in Slack"

## Rules

- Write standard markdown. pandoc handles the HTML conversion.
- Tables, headers, bold, italic, code blocks, links, lists all work.
- Do NOT use Slack mrkdwn syntax (`*bold*`). Use standard markdown (`**bold**`).
- Do NOT add emoji unless the original content had them.
- Do NOT use em dashes.
- Strip leading whitespace/indentation from all lines before piping.
- If the user provides specific text, send that text VERBATIM.

## Requirements

- `pandoc` (apt install pandoc)
- `wl-copy` (Wayland) or `xclip` (X11)
