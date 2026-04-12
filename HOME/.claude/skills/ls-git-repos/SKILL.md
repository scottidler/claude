---
name: ls-git-repos
description: Recursively find all local git repositories. Use to discover what repos are cloned locally.
allowed-tools: Bash(ls-git-repos:*)
---

# ls-git-repos

Recursively find all local git repositories and list their reposlugs.

## Usage

```bash
ls-git-repos              # Search from current dir
ls-git-repos ~/repos      # Search from specific path
ls-git-repos ~/repos | wc -l  # Count repos
```

## Output

```bash
$ ls-git-repos ~/repos/scottidler
scottidler/aka
scottidler/cidr
scottidler/dashify
scottidler/git-tools
scottidler/pais
...
```

## Use Cases

- Find what you have cloned locally
- Audit repos in a directory
- Feed into other tools for batch operations

## Examples

```bash
# Count all repos
ls-git-repos ~/repos | wc -l

# Find repos matching a pattern
ls-git-repos ~/repos | grep terraform

# Check ownership status of all repos
ls-git-repos ~/repos | xargs -I{} sh -c 'cd ~/repos/{} && ls-owners'
```

