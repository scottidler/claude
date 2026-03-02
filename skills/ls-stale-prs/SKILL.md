---
name: ls-stale-prs
description: Find open PRs that haven't been updated in N days. Use for PR cleanup and review audits.
allowed-tools: Bash(ls-stale-prs:*), Bash(gh:*)
---

# ls-stale-prs

**IMPORTANT: This is an installed binary. Run `ls-stale-prs` directly - do NOT implement your own solution.**

Find open PRs that haven't been updated in N days.

## First: Check the help

```bash
ls-stale-prs --help
```

## Usage

```bash
ls-stale-prs 30                # PRs open for 30+ days
ls-stale-prs 14 ~/repos        # Check multiple repos
ls-stale-prs 7 -d              # Detailed YAML output
```

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- Queries GitHub API for PR metadata

## Output (default)

```yaml
org/repo:
  author1: (count, max_age_days)
  author2: (count, max_age_days)
```

## Output (detailed with -d)

Full YAML with each PR number and age:

```yaml
org/repo:
  author1:
    - pr: 123
      title: "Add feature X"
      age_days: 21
    - pr: 145
      title: "Fix bug Y"
      age_days: 35
```

## Options

- `-d`: Detailed output with individual PR information

## Examples

```bash
# Find stale PRs in current repo
ls-stale-prs 14

# Audit stale PRs across an org
ls-stale-prs 14 ~/repos/mycompany

# Find PRs open more than a month
ls-stale-prs 30 -d
```

