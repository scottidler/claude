---
name: slack
description: >-
  Slack toolkit - export a channel's full history (every message, thread reply, and
  shared file) to structured JSON + file bytes, and manage a local channel id<->name
  cache so channel lookups don't burn tokens. Use whenever the user wants to
  download, archive, back up, dump, or export a Slack channel; says "export
  #channel", "archive this channel", "grab the last 2 years of #foo", "save every
  message and file from <channel>"; or wants to look up / refresh / add a Slack
  channel ID by name ("what's the id for #foo", "refresh the slack ids", "add this
  channel"). Prefer this over the Slack MCP for any bulk or historical pull and for
  resolving channel IDs, even when the user doesn't mention files, JSON, or this skill.
allowed-tools: Bash(python3:*), Read
---

# slack

One stdlib script, `slack.py`, with four modes. It talks to the Slack Web API with
your **user** token, so it sees every channel you belong to (public or private) with
no bot to invite. Pure stdlib: no venv, no `uv`, no deps - run it with `python3`.

```bash
S=~/.claude/skills/slack/slack.py
python3 $S export CHANNEL DURATION [--outdir DIR] [--files-only]
python3 $S read   CHANNEL [--limit N] [--since 7d] [--thread TS]   # recent messages / a thread
python3 $S send   CHANNEL "text"  [--thread TS] [--raw]            # post (markdown auto-converted)
python3 $S search QUERY   [--count N]                              # keyword search messages
python3 $S refresh [--all]         # cache channels you belong to (--all = whole workspace)
python3 $S add    CHANNEL          # add/update one channel in the cache (by ID or name)
python3 $S find   SUBSTR           # fuzzy-search the local cache -> id (no API, no token)
```

## Why this exists

The Slack MCP resolves channel IDs live on every call and burns tokens doing it. The
cache (`~/repos/.claude/slack-ids.json`) is a lookup table: `find` turns `#foo` into
`Cxxxx` locally, so you hand the MCP an ID and skip its bad resolver. `refresh` keeps
the table current in bulk; `add` handles one-offs (e.g. a channel you just found).

## Prerequisites

- `TATARI_SLACK_TOOLKIT_API_TOKEN` in the environment (a user token from the "Tatari
  Slack Toolkit" Slack app; falls back to `SLACK_XOXP_TOKEN`). `find` alone needs no token -
  it only reads the local cache.
- For file **bytes** on `export`, the token must carry the **`files:read`** scope.
  Without it, messages/threads still export fully and file metadata + links are
  recorded; the script warns and you can re-run `export ... --files-only` once scoped.

## Modes

### export CHANNEL DURATION
Full-fidelity dump - far richer than the MCP's lossy CSV. Every message, every thread
reply, every Slack-hosted file's bytes.

- **CHANNEL** - name (with/without `#`) or ID (`Cxxxxxxxxxx`)
- **DURATION** - `2y`, `18m`, `12w`, `90d`, or `all` (since creation)

```bash
python3 $S export C0195L0G667 all
python3 $S export '#data-platform' 2y
python3 $S export <channel> all --files-only   # re-pull files after adding files:read
```

Resolution order: ID directly, else the cache, else the live API. Writes to
`~/slack-exports/<channel-name>/` (override with `--outdir`). A full-history run is
fine to launch in the background and poll the log.

Feed it an **ID** (always safe to paste, commit, or share) or a **name** (resolved by
your own token, never written into this repo). Examples use only IDs and public
channels on purpose: a private channel's **name** is confidential; its ID is not.

### read CHANNEL [--limit N] [--since DUR] [--thread TS]
Prints recent messages readably (mentions resolved to names, `<url|label>` unwrapped,
thread reply counts shown). `--limit` (default 50) or `--since 7d` for a window;
`--thread <ts>` reads a single thread instead.

### send CHANNEL TEXT [--thread TS] [--raw]
Posts a message. **By default it converts markdown to Slack mrkdwn** (encoded in the
script, not left to the caller): `**bold**`->`*bold*`, `*italic*`->`_italic_`,
`~~strike~~`->`~strike~`, `[label](url)`->`<url|label>`, `#` headings->`*bold*` lines,
`-`/`*`/`+` bullets->`•`. Code spans/fences pass through untouched. `--raw` skips
conversion and posts verbatim. `--thread <ts>` replies in a thread.

### search QUERY [--count N]
Keyword search across the workspace (Slack search syntax works: `in:#foo from:@bar`).
Prints `[time] #channel user: text` + permalink per hit. Needs `search:read`.

### refresh [--all]
Default: `users.conversations` - only the channels **you belong to** (fast, personal,
usually a few hundred not the whole workspace). This is the onboarding step for a new
user: one call gives them a tight, relevant cache. `--all` uses `conversations.list` to
pull every public+private channel in the workspace, for the rare time you need one
you're not in. Either way it's an upsert (never drops a channel you've left) and rewrites
only the `channels` section; `users`/`groups` are preserved. Cache misses still fall back
to the live API in resolution, so non-member lookups work regardless.

### add CHANNEL
Add/update one channel. `add C0195L0G667` -> `conversations.info` -> name -> upsert
(matches the workflow of grabbing an ID off a channel's About panel). Also takes a
name. DMs/group DMs are not cached (they have no name - excluded by design).

### find SUBSTR
Fuzzy substring match over cached names, printing `id  name` per hit. Zero API calls,
no token. This is the everyday verb.

## Export output (`~/slack-exports/<channel-name>/`)

- `messages.json` - top-level messages sorted by time; replies nested under
  `.replies[]`; each message keeps its inline `.files[]`, enriched with `local_path`
  and `download_status` (`downloaded` | `external` | `unavailable`).
- `files/` - downloaded bytes for Slack-hosted files.
- `files-index.json` - every file with `title`, `name`, `permalink`, `external_url`,
  `mimetype`, `size`, `local_path`.
- `users.json` - user id -> name / real_name map for resolving authors & mentions.
- `export-meta.json` - counts + time span.

## The cache: `~/repos/.claude/slack-ids.json`

Shape: `{"channels": {id: name}, "users": {id: username}, "groups": {id: [members]}}`.
Machine-generated and machine-consumed, so it's JSON (per conventions), not YAML.

- **Personal and out-of-repo.** It only holds channels *you* belong to and it contains
  **private channel names**, which are confidential. It is NOT bundled with the skill
  and must never be committed - `.gitignore` it in any repo it lands in. IDs are not
  secret; names of private channels are.
- Without the cache, name resolution still works - your token resolves names live.

## Notes

- **External files** (Google Drive/Docs links shared into Slack) can't be
  byte-downloaded via the Slack API - their bytes live in Drive. They're fully
  recorded (`title` + `external_url` + `permalink`); fetch them separately with `gws`.
- **Rate limits** are handled automatically: HTTP 429 `Retry-After` is honored, and on
  the 2025-05-29 special cap for `conversations.history`/`replies` the script adapts to
  15 objects/page + >=60s spacing. See the script header for details.
- **Sensitive data**: exports often contain contracts, SOC2 reports, and client data.
  Output lands in `~/slack-exports/` (NOT a git repo) by design - do not commit it.
- **Shipping via `tatari-skills`**: this skill ships with zero private names in it -
  only IDs and public channels in examples. The cache travels with nobody; each user
  generates their own.
