---
name: clauderize
description: Analyze a repository and generate a CLAUDE.md file with build/test commands, architecture overview, coding conventions, and key entry points. Use when setting up a repo for effective Claude Code usage, or when the user says "clauderize".
user-invocable: true
allowed-tools: [Bash, Read, Glob, Grep, Write, Edit, Agent]
argument-hint: "[path/to/repo]"
---

# Clauderize

Analyze a repository and generate a high-quality `CLAUDE.md` that gives Claude Code the context it needs to work effectively.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `path` | No | Path to the repo root. Defaults to current working directory |

## Step 1: Validate

- Confirm the target directory is a git repo (has `.git/`)
- Check if a `CLAUDE.md` already exists at the repo root
  - If yes: tell the user and ask whether to **update** or **replace** it
- Check for `.claude/` directory and note its presence (but don't modify it - that's `/dot-clauderize`)

## Step 2: Analyze the Repository

Gather the following information by reading files and exploring the codebase:

### 2a: Project Identity

- Repository name and description (from `package.json`, `Cargo.toml`, `pyproject.toml`, `README.md`, or GitHub)
- Primary language(s) and framework(s)
- License

### 2b: Build and Run Commands

Discover how to build, test, lint, and run the project:

| Source | Check for |
|--------|-----------|
| `.otto.yml` | otto tasks (ci, test, lint, check, build) |
| `Makefile` | make targets |
| `package.json` | npm/yarn/pnpm scripts |
| `Cargo.toml` | cargo commands, workspace members |
| `pyproject.toml` | uv/pytest/ruff commands |
| `Justfile` | just recipes |
| `docker-compose.yml` | docker compose commands |
| `Taskfile.yml` | task runner commands |

Prioritize what's actually used. If `.otto.yml` exists, `otto ci` is the primary CI command.

### 2c: Architecture Overview

- Directory structure (top-level layout, key directories)
- Entry points (main files, binary targets, API routes)
- Key modules and their responsibilities
- Database or storage layer (if any)
- External service integrations (if any)

### 2d: Coding Conventions

Detect from existing code and config:

- Formatter and linter config (rustfmt.toml, .prettierrc, ruff.toml, .eslintrc, etc.)
- Test patterns (where tests live, how they're structured)
- Import conventions
- Error handling patterns
- Any `.editorconfig` settings

### 2e: Key Files

Identify the most important files a developer (or Claude) should know about:

- Config files
- Entry points
- Core business logic modules
- Test fixtures or helpers
- CI/CD configuration

## Step 3: Generate CLAUDE.md

Write a `CLAUDE.md` at the repo root following this structure:

```markdown
# <Project Name>

<One-line description>

## Quick Reference

```
<most common commands: build, test, lint, run - in a quick-copy block>
```

## Architecture

<Brief overview of the codebase structure and key components>

## Build & Test

<Detailed commands for building, testing, linting, formatting>

## Coding Conventions

<Style, patterns, and conventions detected from the codebase>

## Key Files

<Table or list of the most important files and what they do>
```

### Writing Guidelines

- **Be concise.** Claude Code reads this every session - keep it scannable
- **Lead with commands.** The Quick Reference section is the most-used part
- **Skip the obvious.** Don't document what's clear from file names or standard patterns
- **Be specific.** "Run `otto ci`" beats "Run the CI pipeline"
- **No em dashes.** Use regular dashes, commas, or semicolons
- **No time estimates.**
- **Single test commands.** If there's a way to run a single test file or test function, document it (e.g., `cargo test test_name`, `pytest path/to/test.py::test_name`)

## Step 4: Verify

- Read back the generated `CLAUDE.md` and confirm it looks correct
- If the repo has an `.otto.yml`, verify the commands mentioned in CLAUDE.md match the otto tasks
- Report what was generated to the user

## Edge Cases

- **Monorepo/workspace**: Generate a root CLAUDE.md covering the workspace, and mention per-member details
- **Empty repo**: Generate a minimal CLAUDE.md with just the project name and a note that the repo is new
- **No build system detected**: Document what you can (language, structure) and note that build commands should be added manually
