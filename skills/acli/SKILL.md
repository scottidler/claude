---
name: acli
description: Atlassian CLI for Jira, Confluence, and other Atlassian products. Use when working with Jira issues, Confluence pages, or Atlassian administration.
allowed-tools: Bash(acli:*)
---

# Atlassian CLI (acli)

Command-line interface for interacting with Atlassian products including Jira, Confluence, and more.

## Quick Commands

```bash
# Authentication
acli auth login                    # Interactive login
acli auth status                   # Check auth status

# Jira
acli jira issue list               # List issues
acli jira issue view KEY-123       # View specific issue
acli jira issue create             # Create new issue
acli jira issue edit KEY-123       # Edit issue
acli jira issue transition KEY-123 # Transition issue status

# Confluence
acli confluence page list          # List pages
acli confluence page view PAGE-ID  # View page
acli confluence page create        # Create page
acli confluence search "query"     # Search content
```

## Products

| Command | Product |
|---------|---------|
| `acli jira` | Jira Cloud |
| `acli confluence` | Confluence Cloud |
| `acli assets` | Assets (formerly Insight) |
| `acli admin` | Atlassian Admin |
| `acli brie` | Brie |
| `acli rovodev` | Rovo Dev AI coding agent (Beta) |

## Jira Commands

### Issues

```bash
# List issues (with JQL)
acli jira issue list --jql "project = PROJ AND status = Open"
acli jira issue list --project PROJ

# View issue details
acli jira issue view PROJ-123
acli jira issue view PROJ-123 --comments

# Create issue
acli jira issue create --project PROJ --type Task --summary "Summary"
acli jira issue create --project PROJ --type Bug --summary "Bug title" --description "Details"

# Edit issue
acli jira issue edit PROJ-123 --summary "New summary"
acli jira issue edit PROJ-123 --assignee username

# Transition issue
acli jira issue transition PROJ-123 --status "In Progress"
acli jira issue transition PROJ-123 --status "Done"

# Add comment
acli jira issue comment PROJ-123 --body "Comment text"
```

### Projects

```bash
acli jira project list             # List all projects
acli jira project view PROJ        # View project details
```

### Sprints & Boards

```bash
acli jira sprint list --board 123
acli jira sprint active --board 123
acli jira board list
```

## Confluence Commands

### Pages

```bash
# List pages
acli confluence page list --space SPACE
acli confluence page list --space SPACE --limit 50

# View page
acli confluence page view PAGE-ID
acli confluence page view PAGE-ID --format markdown

# Create page
acli confluence page create --space SPACE --title "Page Title" --body "Content"
acli confluence page create --space SPACE --title "Page Title" --file content.md

# Update page
acli confluence page update PAGE-ID --title "New Title"
acli confluence page update PAGE-ID --body "New content"

# Delete page
acli confluence page delete PAGE-ID
```

### Spaces

```bash
acli confluence space list
acli confluence space view SPACE
```

### Search

```bash
acli confluence search "search query"
acli confluence search "search query" --space SPACE
```

## Rovo Dev (AI Agent)

```bash
acli rovodev --help                # View Rovo Dev commands
```

## Configuration

```bash
acli config view                   # View current config
acli config set KEY VALUE          # Set config value
```

## Tips

- Use `acli [command] --help` to see all options for any command
- JQL queries in Jira allow powerful filtering
- Output can often be formatted as JSON with `--output json`
- Use `acli feedback` to report issues or request features
