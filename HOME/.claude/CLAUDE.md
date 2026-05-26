# Scott Idler

## Glossary

- **gws** — Scott's Google Workspace CLI at `~/.cargo/bin/gws`. Subcommands per service: `drive`, `sheets`, `gmail`, `calendar`, `docs`, `slides`, `tasks`, `people`, `chat`, `classroom`, `forms`, `keep`, `meet`, `admin-reports`. Form: `gws <service> <resource> [sub-resource] <method> --params '{...}' --json '{...}'`. Use `gws schema <service.resource.method>` to inspect a method's shape. NOT the Workspace product itself — always the CLI.

## Symlinked dotfiles

`~/.claude/` and `~/repos/.claude/` are symlinked into the dotfiles repo at `~/repos/scottidler/claude/HOME/`. Edit the real path directly.

## Never estimate time, effort, or cost

Do not produce time estimates, effort estimates, sizing, or cost projections — no "1-2 hours," no "couple of days," no "small fix vs. large refactor" framing, no story points, no t-shirt sizes. You do not have the calibration to make these estimates accurately, and confidently wrong estimates are worse than no estimate. If asked "how long," answer with what is known: the scope of the change, the files affected, the steps required, the unknowns that block progress. Let the human do the sizing.

Auto-loaded rules live in `~/repos/.claude/rules/` — Claude Code includes them automatically (safety, git, general, log, otto are always-on; python, rust, js-ts, yaml are path-scoped via `paths:` frontmatter).

On-demand reference docs live in `~/repos/.claude/refs/`. Read them when the scenario calls for it:

- **environment.md** - Hostnames, Obsidian vault, dotfiles, and the `manifest` CLI + `manifest.yml` conventions *(read when referencing machines, obsidian, dotfiles, or manifest)*
- **personas.md** - Home/work identity, GitHub accounts, SSH keys, Jira/Confluence *(read when doing GitHub, Jira, Slack, or identity-sensitive work)*
- **slack.md** - Slack mrkdwn, posting patterns, ID reference *(read when posting to Slack)*
- **jira.md** - Jira issue types, ticket naming, acceptance criteria *(read when working on Jira tickets)*
- **dealing-with-large-files.md** - Safe decomposition of large source files *(read when splitting files over size threshold)*
- **refactor.md** - Bulk search-and-replace with the `replace` shell function *(read before mechanical cross-file renames)*
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.

@RTK.md
