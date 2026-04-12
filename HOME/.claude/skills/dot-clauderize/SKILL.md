---
name: dot-clauderize
description: Scaffold a .claude/ directory with project-specific settings, permissions, and commands for a repository. Use when setting up per-repo Claude Code configuration for team collaboration, or when the user says "dot-clauderize".
user-invocable: true
allowed-tools: [Bash, Read, Write, Edit, Glob, Grep, Agent]
argument-hint: "[path/to/repo]"
---

# Dot-Clauderize

Scaffold a `.claude/` directory with project-specific configuration so that anyone using Claude Code on this repo gets the right permissions, commands, and settings automatically.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `path` | No | Path to the repo root. Defaults to current working directory |

## Step 1: Validate

- Confirm the target directory is a git repo (has `.git/`)
- Check if `.claude/` already exists
  - If yes: tell the user and ask whether to **update** (merge new config) or **replace** (start fresh)
- Check if `CLAUDE.md` exists (recommend running `/clauderize` first if not)

## Step 2: Analyze the Repository

Determine what configuration the project needs:

### 2a: Detect Build/Test Tooling

| Language/Framework | Permissions to auto-allow |
|-------------------|--------------------------|
| Rust | `cargo build`, `cargo test`, `cargo clippy`, `cargo fmt`, `cargo add` |
| Python (uv) | `uv run`, `uv pip`, `pytest`, `ruff` |
| Node.js (npm) | `npm test`, `npm run *`, `npx` |
| Node.js (yarn) | `yarn test`, `yarn run *` |
| Node.js (pnpm) | `pnpm test`, `pnpm run *` |
| Go | `go build`, `go test`, `go vet` |
| Otto | `otto ci`, `otto test`, `otto check`, `otto lint`, `otto build` |
| Docker | `docker compose up`, `docker compose down` |
| Make | `make *` |

Only include permissions relevant to the detected tooling.

### 2b: Detect Common Workflows

Look for patterns that suggest useful slash commands:

- CI pipeline (otto, make, npm scripts) -> `/ci` command
- Database migrations -> `/migrate` command
- Code generation (protobuf, openapi, sqlc) -> `/generate` command
- Deployment scripts -> `/deploy` command
- Seed/fixture data -> `/seed` command

### 2c: Assess Team vs Solo

- Check git log for multiple committers
- Check for CODEOWNERS file
- Check if repo is under an org (e.g., `tatari-tv/`) vs personal (`scottidler/`)

This informs how much configuration to generate - team repos benefit from more explicit settings.

## Step 3: Scaffold .claude/

### 3a: Create settings.json

```json
{
  "permissions": {
    "allow": [
      "<tool-specific commands from Step 2a>"
    ]
  }
}
```

Only include the `permissions.allow` array. Don't add empty or placeholder sections.

### 3b: Create Commands (if applicable)

Only create commands for workflows detected in Step 2b. Each command is a markdown file in `.claude/commands/`.

Command file format:

```markdown
---
description: <what this command does>
---

<prompt for Claude Code to execute>
```

Example `.claude/commands/ci.md`:

```markdown
---
description: Run the full CI pipeline
---

Run the CI pipeline for this project. Use `otto ci` if available, otherwise fall back to running lint, check, and test tasks individually. Report any failures clearly.
```

Keep commands minimal - only create ones that encode non-obvious project-specific workflows.

### 3c: Update .gitignore

Add `.claude/` entries to `.gitignore` for user-specific files that should NOT be committed:

```
# Claude Code - user-specific
.claude/memory/
.claude/settings.local.json
```

But `.claude/settings.json` and `.claude/commands/` SHOULD be committed (they're team config).

## Step 4: Report

Tell the user what was created:

- List of files created/modified
- Summary of permissions added
- Commands created (if any)
- Reminder to commit `.claude/settings.json` and `.claude/commands/` to git
- Reminder that `.claude/memory/` and `.claude/settings.local.json` are gitignored (user-specific)

## Edge Cases

- **Solo personal repo**: Generate minimal config (just permissions). Skip commands unless there's a clear workflow
- **Monorepo/workspace**: Generate root-level `.claude/` config covering the whole workspace
- **Existing .claude/ with custom config**: Preserve existing settings and commands, only add new ones. Never remove user customizations
- **No CLAUDE.md**: Warn the user and suggest running `/clauderize` first, but proceed anyway
