---
name: ls-github-repos
description: List all repositories under a GitHub organization or user. Use for discovering and cloning org repos.
allowed-tools: Bash(ls-github-repos:*)
---

# ls-github-repos

List all repositories under a GitHub organization or user.

## Usage

```bash
ls-github-repos scottidler           # List all repos for user
ls-github-repos mycompany            # List all repos for org
ls-github-repos mycompany -A         # Include archived repos
ls-github-repos mycompany -a         # Show with creation date
```

## Requirements

- GitHub token at `~/.config/github/tokens/<name>` (where `<name>` is the org/user)
- Auto-detects if the name is a user or organization

## Token Setup

```bash
mkdir -p ~/.config/github/tokens
echo "ghp_your_token_here" > ~/.config/github/tokens/scottidler
echo "ghp_org_token_here" > ~/.config/github/tokens/mycompany
chmod 600 ~/.config/github/tokens/*
```

## Options

- `-A`: Include archived repositories
- `-a`: Show creation date alongside repo name

## Examples

```bash
# List all repos for a user
ls-github-repos scottidler

# Clone all repos from an org
ls-github-repos mycompany | while read repo; do
  clone "$repo" --clonepath ~/repos
done

# Find repos created this year
ls-github-repos mycompany -a | grep "2024"
```

