---
name: ls-owners
description: Analyze CODEOWNERS files and detect unowned code paths. Use for code ownership audits.
allowed-tools: Bash(ls-owners:*)
---

# ls-owners

Analyze CODEOWNERS files and detect unowned code paths.

## Usage

```bash
ls-owners                    # Check current repo
ls-owners ~/repos            # Check all repos under path
ls-owners -o unowned         # Show only unowned repos
ls-owners -o partial         # Show only partially owned
ls-owners -d                 # Detailed output with paths
```

## Output Status

- **owned**: All code paths have CODEOWNERS entries
- **partial**: Some paths are unowned
- **unowned**: Missing or empty CODEOWNERS

## Features

- Shows top authors (from git history) for unowned repos to suggest owners
- Respects CODEOWNERS file patterns
- Can scan multiple repos at once

## Configuration

List ex-employees to exclude from author suggestions:

```bash
# Create exclusion list
mkdir -p ~/.config/ls-owners/mycompany
echo "former.employee@company.com" >> ~/.config/ls-owners/mycompany/ex-employees
```

## Options

- `-o <status>`: Filter by ownership status (owned, partial, unowned)
- `-d`: Detailed output showing individual paths

## Examples

```bash
# Audit all repos in an org
ls-owners ~/repos/mycompany

# Find repos that need CODEOWNERS
ls-owners ~/repos -o unowned

# Get detailed ownership for a repo
ls-owners -d
```

