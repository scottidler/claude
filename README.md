# claude

Public repo for Scott's Claude Code configuration: skills, agents, output styles, hooks, and always-on rules. Deployed via [`manifest`](https://github.com/scottidler/manifest) (a Rust CLI that renders `manifest.yml` into a Bash install script); companion private repo `scottidler/keep` layers secrets and private config on top (e.g. the voice corpus).

Note: the root `CLAUDE.md` in this repo is a *symlink* to `HOME/.claude/CLAUDE.md` — it is the deployed personal-instructions file (what loads at `~/.claude/CLAUDE.md` on Scott's machines), not a description of this repo's own structure. This README is that description.

## How it works

```bash
cd ~/repos/scottidler/claude
manifest | bash          # deploy everything
manifest -l '*' | bash   # just the link section
```

`manifest.yml` sections in use:

| Section | Purpose |
|---------|---------|
| `link` | symlinks `HOME/.claude/*` (and others) into `$HOME/.claude/*`, recursive |
| `github` | clones third-party skill repos and links specific subpaths into `~/.claude/skills/` |
| `pipx` | isolated CLI installs (e.g. a Google Slides MCP server) |
| `script` | freeform setup steps — e.g. wiring MCP server credentials, registering user-scope MCP servers via `claude mcp add-json` (since `~/.claude.json` isn't version-controlled) |

## Layout

| Path | Purpose |
|------|---------|
| `HOME/.claude/` | deployed Claude Code config: `CLAUDE.md`, `WHOAMI.md`, `tools.md`, `agents/`, `skills/`, `hooks/`, `output-styles/`, `statusline.sh` + `statusline.d/` |
| `HOME/repos/.claude/` | deployed to `~/repos/.claude/`: repo-root `CLAUDE.md`, `rules/` (always-on and path-scoped conventions: `general`, `taste`, `voice`, `cli`, `git`, `otto`, `safety`, `secrets`, language rules), `refs/` (on-demand docs: `environment`, `personas`, `slack`, `jira`, `design-exemplars`, etc.) |
| `HOME/advisor/` | advisor-related config |
| `bin/` | standalone scripts (e.g. `check-review-panel`) |
| `docs/` | dated incident/investigation notes (e.g. sandbox filesystem allowlist, release-guard fixes) |
| `docs/design/` | design docs for features (gating authority, voice-corpus wiring, reviewer preflight guard, per-phase verification) |

## Conventions

- Edit files under `HOME/`, never the deployed copy in `$HOME` — the repo is the source of truth, `manifest` just symlinks it into place.
- Rules in `HOME/repos/.claude/rules/` are either always-on or path-scoped (frontmatter controls which); refs in `HOME/repos/.claude/refs/` are read on demand, not auto-loaded.
- Private/sensitive material (voice corpus, secrets) does not live here — see `scottidler/keep`.

