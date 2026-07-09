---
name: slack
description: >-
  Read, post, search, and export Slack from the terminal via your own user token, which
  sees every channel you belong to (public or private, no bot to invite). This is the
  primary way to touch Slack and is PREFERRED OVER the Slack MCP for all of it. Use for
  ANY of these:
  READ - read or summarize a thread, recent messages, or a shared Slack permalink ("read
  this Slack message", "summarize this thread", "summarize this permalink", "what's in
  #channel", "catch me up on #foo", or any "tatari.slack.com/archives/..." link the user
  pastes and asks about);
  POST / SEND - post a message to a NAMED channel or reply in a specific thread as Scott,
  markdown auto-converted to mrkdwn and signed :giga-claude: ("send this to #channel",
  "message #channel", "reply in that thread", "ping #foo about X"); sharing a snippet of
  Claude's OWN output to your personal clipboard channel is slack-clipboard, not this;
  SEARCH - keyword-search messages across the workspace ("search Slack for X", "find that
  message about Y", "did anyone post about Z");
  PREVIEW - render a draft to your own self-DM before sending it for real;
  EXPORT - full-history archive of a channel (messages, threads, files) to JSON + file
  bytes ("export #channel", "archive this channel", "grab the last 2 years of #foo");
  ID CACHE - look up / refresh / add a channel ID by name ("what's the id for #foo",
  "refresh the slack ids", "add this channel").
  Trigger even when the user doesn't say "slack.py", "user token", or name this skill -
  any request to read, send, reply to, search, back up, or resolve Slack belongs here.
allowed-tools: Bash(python3:*), Read
---

# slack

One stdlib script, `slack.py`, with eight subcommands (`read` `send` `search` `preview` `export` `refresh` `add` `find`). It talks to the Slack Web API with
your **user** token, so it sees every channel you belong to (public or private) with
no bot to invite. Pure stdlib: no venv, no `uv`, no deps - run it with `python3`.

```bash
S=~/.claude/skills/slack/slack.py
python3 $S export CHANNEL DURATION [--outdir DIR] [--files-only]
python3 $S read   CHANNEL [--limit N] [--since 7d] [--thread TS]   # recent messages / a thread
python3 $S send   CHANNEL "text"  [--thread TS] [--raw]            # post (markdown auto-converted)
python3 $S preview "text"         [--raw]                         # render to your OWN self-DM first
python3 $S search QUERY   [--count N]                              # keyword search messages
python3 $S refresh [--all]         # cache channels you belong to (--all = whole workspace)
python3 $S add    CHANNEL          # add/update one channel in the cache (by ID or name)
python3 $S find   SUBSTR           # fuzzy-search the local cache -> id (no API, no token)
```

## Voice

Anything composed by Claude and posted via `send`/`preview` goes out as Scott.
Before drafting message text (not verbatim user text), read `~/Claude/writing/VOICE.md`
and match the chat register: lowercase where natural, terse one-liners, flat verdicts,
no em-dashes, no filler.

## Why this exists

The Slack MCP resolves channel IDs live on every call and burns tokens doing it. The
cache (`~/repos/.claude/slack-ids.json`) is a lookup table: `find` turns `#foo` into
`Cxxxx` locally, so you hand the MCP an ID and skip its bad resolver. `refresh` keeps
the table current in bulk; `add` handles one-offs (e.g. a channel you just found).

## Prerequisites

- **Token: `TATARI_SLACK_TOOLKIT_API_TOKEN`** (falls back to `SLACK_XOXP_TOKEN`) - a
  personal Slack user token (xoxp) on the Tatari workspace, scoped to Scott (`@escote`),
  minted from Scott's own **"Tatari Slack Toolkit"** Slack app (App ID `A0BEEAAJ16D`,
  created 2026-06-30 - the same app that seeded the `valet` token-broker). A *user* token,
  so it sees every channel you belong to (public or private) with no bot to invite. `find`
  alone needs no token - it only reads the local cache.
- Granted scopes: `channels:history` `groups:history` `im:history` `mpim:history`
  `channels:read` `groups:read` `im:read` `mpim:read` `search:read` `users:read`
  `files:read` `chat:write` `files:write` `im:write` `mpim:write` - the full
  read/write/search/export set (`search:read` is present, so `search` works).
  Notably **missing `usergroups:read`**, so listing the members of a Slack usergroup
  (`<!subteam^…>` / `@group` mentions) returns `missing_scope`; add `usergroups:read` to
  the Tatari Slack Toolkit app and re-mint if usergroup enumeration is needed.
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

### preview TEXT [--raw]
Same as `send` (including markdown->mrkdwn conversion), but always posts to **your own
self-DM** - a safe sandbox to eyeball how a message will render before sending it to a
real channel. Opens the self-DM once via `im:write`, caches its id, then posts via
`chat:write`. No channel argument.

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
