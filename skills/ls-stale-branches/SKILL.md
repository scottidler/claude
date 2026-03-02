---
name: ls-stale-branches
description: Find remote branches that haven't been updated in N days. Use for branch cleanup audits.
allowed-tools: Bash(ls-stale-branches:*)
---

# ls-stale-branches

**IMPORTANT: This is an installed binary. Run `ls-stale-branches` directly - do NOT implement your own solution.**

Find remote branches that haven't been updated in N days.

## First: Check the help

```bash
ls-stale-branches --help
```

## Usage

```bash
ls-stale-branches 30           # Branches untouched for 30+ days
ls-stale-branches 60 ~/repos   # Check multiple repos
ls-stale-branches 90 -d        # Detailed YAML output
```

## Output (default)

```yaml
org/repo:
  author1: (count, max_age_days)
  author2: (count, max_age_days)
```

## Output (detailed with -d)

Full YAML with each branch name and age:

```yaml
org/repo:
  author1:
    - branch: feature/old-work
      age_days: 45
    - branch: fix/abandoned
      age_days: 62
```

## Options

- `-d`: Detailed output with individual branch names

## Examples

```bash
# Find stale branches in current repo
ls-stale-branches 30

# Audit stale work across an org
ls-stale-branches 30 ~/repos/mycompany

# Find very old branches
ls-stale-branches 90 -d
```

