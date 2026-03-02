---
name: reposlug
description: Extract owner/repo slug from a git remote. Use for scripting and piping into other commands.
allowed-tools: Bash(reposlug:*)
---

# Reposlug

Extract the `owner/repo` slug from a git repository's remote.

## Usage

```bash
reposlug              # In a git repo, prints "owner/repo"
reposlug /path/to/repo
```

## Output

```bash
$ cd ~/repos/scottidler/pais
$ reposlug
scottidler/pais
```

## Use Cases

- Scripting and automation
- Piping into other git-tools commands
- Getting repo identity for API calls

## Examples

```bash
# Get current repo slug
reposlug

# Use in scripts
REPO=$(reposlug)
echo "Working on $REPO"

# Check multiple repos
for dir in ~/repos/scottidler/*; do
  echo "$(reposlug $dir)"
done
```

