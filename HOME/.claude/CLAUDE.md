# Scott Idler

Auto-loaded rules live in `~/repos/.claude/rules/` — Claude Code includes them automatically (safety, git, general, log, otto are always-on; python, rust, js-ts, yaml are path-scoped via `paths:` frontmatter).

On-demand reference docs live in `~/repos/.claude/refs/`. Read them when the scenario calls for it:

- **environment.md** - Hostnames, Obsidian vault, repo/dotfile conventions *(read when referencing machines, obsidian, or dotfiles)*
- **personas.md** - Home/work identity, GitHub accounts, SSH keys, Jira/Confluence *(read when doing GitHub, Jira, Slack, or identity-sensitive work)*
- **slack.md** - Slack mrkdwn, posting patterns, ID reference *(read when posting to Slack)*
- **jira.md** - Jira issue types, ticket naming, acceptance criteria *(read when working on Jira tickets)*
- **dealing-with-large-files.md** - Safe decomposition of large source files *(read when splitting files over size threshold)*
- **refactor.md** - Bulk search-and-replace with the `replace` shell function *(read before mechanical cross-file renames)*
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.

@RTK.md
