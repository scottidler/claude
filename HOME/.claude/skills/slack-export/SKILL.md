---
name: slack-export
description: >-
  Export a Slack channel's full history - every message, thread reply, and shared
  file - to structured JSON plus downloaded file bytes. Use whenever the user wants
  to download, archive, back up, dump, or export a Slack channel; says "export
  #channel", "archive this channel", "grab the last 2 years of #foo", "save every
  message and file from <channel>", or wants Slack data in JSON for later analysis.
  The user supplies the CHANNEL (name or ID) and how far back (DURATION). Prefer
  this over the Slack MCP for any bulk or historical channel pull, even when the
  user doesn't mention files, JSON, or this skill.
allowed-tools: Bash(python3:*), Read
---

# slack-export

Exports a Slack channel to full-fidelity JSON via the Slack Web API - far richer
than the Slack MCP, which returns lossy CSV with no files. Captures every message,
every thread reply, and downloads every Slack-hosted file's bytes.

## Inputs

- **CHANNEL** - channel name (with or without `#`) or ID (`Cxxxxxxxxxx`)
- **DURATION** - how far back: `2y`, `18m`, `12w`, `90d`, or `all` (since creation)

## Prerequisites

- `SLACK_XOXP_TOKEN` in the environment (a user token; sees any channel the user
  is a member of).
- For file **bytes**, the token must carry the **`files:read`** OAuth scope. Without
  it, messages/threads still export fully and file metadata + links are recorded;
  the script warns and you can re-run `--files-only` once the scope is added. (The
  script preflights the scope itself and warns if it's missing.)

## How to use

Run the script with the channel and duration:
```bash
python3 ~/.claude/skills/slack-export/slack_export.py security-external-questionnaires 2y
python3 ~/.claude/skills/slack-export/slack_export.py C022DNJB4H4 all
python3 ~/.claude/skills/slack-export/slack_export.py '#ask-security' 90d
```

It resolves the channel (ID directly, else `~/repos/.claude/slack-ids.yml`, else the
API), computes the time window, and writes to `~/slack-exports/<channel-name>/`
(override with `--outdir`). A long run (full history) is fine to launch in the
background and poll the log.

To pull files after adding `files:read` to a prior metadata-only run:
```bash
python3 ~/.claude/skills/slack-export/slack_export.py <channel> all --files-only
```

## Output (`~/slack-exports/<channel-name>/`)

- `messages.json` - top-level messages sorted by time; replies nested under
  `.replies[]`; each message keeps its inline `.files[]`, enriched with
  `local_path` and `download_status` (`downloaded` | `external` | `unavailable`).
  So each message self-contains who sent it, what they said, and the file attached.
- `files/` - downloaded bytes for Slack-hosted files.
- `files-index.json` - every file with `title`, `name`, `permalink`,
  `external_url`, `mimetype`, `size`, `local_path`.
- `users.json` - user id -> name / real_name map for resolving authors & mentions.
- `export-meta.json` - counts + time span.

## Notes

- **External files** (Google Drive/Docs links shared into Slack) cannot be
  byte-downloaded via the Slack API - their bytes live in Drive. They're fully
  recorded (`title` + `external_url` + `permalink`); fetching them is a separate
  Google Drive pull (`gws`).
- **Rate limits** are handled automatically: HTTP 429 `Retry-After` is honored, and
  on the 2025-05-29 special cap for `conversations.history`/`replies` the script
  adapts to 15 objects/page + >=60s spacing. See the script header for details.
- **Sensitive data**: channel exports often contain contracts, SOC2 reports, and
  client data. Output lands in `~/slack-exports/` (NOT a git repo) by design - do
  not commit it.
