---
name: gws
description: Scott's Google Workspace CLI (`~/.cargo/bin/gws`) for Drive, Sheets, Gmail, Calendar, Docs, Slides, Tasks, People, Chat, Classroom, Forms, Keep, Meet, and Admin Reports. Use when reading or writing Google Workspace data from the command line. This is the CLI, never the Workspace product itself.
---

# gws — Google Workspace CLI

`gws` is Scott's own CLI at `~/.cargo/bin/gws`. It maps directly onto the
Google Workspace REST APIs: one subcommand per service, then resource,
optional sub-resource, and method.

**This is always the CLI, never the Workspace product itself.**

## Personas

Two Google accounts, selected by the config dir env var
(`GOOGLE_WORKSPACE_CLI_CONFIG_DIR`). Wrapper scripts live in dotfiles
(`HOME/bin/`); pick the right one for the account context:

- `gws-work` (and bare `gws`) → `scott.idler@tatari.tv`
  - config dir `~/.config/gws/work`; this is the default, exported in `.zshenv`
- `gws-home` → `scott.a.idler@gmail.com`
  - config dir `~/.config/gws/home`; uses `GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file`

Notes:
- Bare `gws` always means **work** — never assume it's home; use `gws-home` explicitly.
- Tokens are **per-machine** (not synced/committed). A new machine re-auths via
  `gws auth login`; the OAuth client (`client_secret.json`) is the only reusable bit.
- Headless/SSH login: `gws auth login` prints a URL and serves the OAuth redirect on
  a `localhost:<port>` on that machine. If the browser is on a different box, forward
  that port (`ssh -L <port>:localhost:<port> <host>`) before approving.

## Form

```
gws <service> <resource> [sub-resource] <method> [flags]
gws schema <service.resource.method> [--resolve-refs]
```

## Inspect before you call

When unsure of a method's parameters or request body, read its schema first:

```
gws schema drive.files.list
gws schema gmail.users.messages.send --resolve-refs
```

## Services

- `drive` — files, folders, shared drives
- `sheets` — read/write spreadsheets
- `gmail` — send, read, manage email
- `calendar` — calendars and events
- `docs` — read/write Google Docs
- `slides` — read/write presentations
- `tasks` — task lists and tasks
- `people` — contacts and profiles
- `chat` — Chat spaces and messages
- `classroom` — classes, rosters, coursework
- `forms` — read/write Google Forms
- `keep` — Google Keep notes
- `meet` — Google Meet conferences
- `admin-reports` — audit logs and usage reports (alias: `reports`)

## Flags

- `--params <JSON>` — URL/query parameters
- `--json <JSON>` — request body for POST/PATCH/PUT
- `--upload <PATH>` — local file to upload as media (multipart)
- `--upload-content-type <MIME>` — MIME type (auto-detected from extension if omitted)
- `--output <PATH>` — output path for binary responses
- `--format <FMT>` — `json` (default), `table`, `yaml`, `csv`
- `--api-version <VER>` — override API version (e.g. `v2`, `v3`)
- `--page-all` — auto-paginate, one JSON line per page (NDJSON)
- `--page-limit <N>` — max pages with `--page-all` (default 10)
- `--page-delay <MS>` — delay between pages (default 100)

## Examples

```
gws drive files list --params '{"pageSize": 10}'
gws drive files get --params '{"fileId": "abc123"}'
gws sheets spreadsheets get --params '{"spreadsheetId": "..."}'
gws gmail users messages list --params '{"userId": "me"}'
```
