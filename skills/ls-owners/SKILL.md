---
name: ls-owners
description: Analyze CODEOWNERS files and detect unowned code paths. Use for code ownership audits.
allowed-tools: Bash(ls-owners:*), Read, Grep, Glob
---

# ls-owners

Analyze CODEOWNERS files and detect unowned code paths across one or many repos.

## Arguments

The ARGUMENTS line contains the target path and optional flags. Parse it as:

```
ls-owners [OPTIONS] [PATH]
```

- `PATH`: directory to scan (default: current working directory)
  - If PATH is a git repo, analyze that single repo
  - If PATH contains git repos as subdirectories, scan all of them
- `-o <status>`: filter output to only show repos matching status: `owned`, `partial`, `unowned`
- `-d`: detailed mode - show individual unowned paths within partial repos

## Implementation

For each git repo found, determine ownership status:

### Step 1: Find CODEOWNERS

Look for CODEOWNERS in these locations (first match wins):
1. `.github/CODEOWNERS`
2. `CODEOWNERS`
3. `docs/CODEOWNERS`

### Step 2: Classify each repo

- **owned**: CODEOWNERS exists and has a `*` catch-all rule (all paths covered)
- **partial**: CODEOWNERS exists but no `*` catch-all (some paths may be uncovered)
- **unowned**: no CODEOWNERS file, or file is empty

### Step 3: For unowned/partial repos, find suggested owners

Run `git -C <repo> shortlog -sne --all HEAD 2>/dev/null | head -5` to get top committers.
If an ex-employees exclusion file exists at `~/.config/ls-owners/<org>/ex-employees`, filter those emails out.

### Step 4: For partial repos in detailed mode (-d)

Parse CODEOWNERS patterns and identify which top-level directories lack coverage.

## Output Format

Print results as a clean table using `column` or `printf` for alignment. Use these exact markers for status:

```
STATUS     REPO                              SUGGESTED OWNERS
[owned]    airflow-dags
[owned]    auth-svc
[partial]  python-tatari-config-manager       @data-platform-team (from CODEOWNERS)
[unowned]  hackathon-cranberries              alice@co.com (45%), bob@co.com (30%)
[unowned]  claude-cron                        carol@co.com (60%), dave@co.com (20%)
```

### Rules

- Sort output: `owned` first, then `partial`, then `unowned` (each group sorted alphabetically)
- SUGGESTED OWNERS column:
  - For `owned` repos: leave blank
  - For `partial` repos: show the teams/users from the CODEOWNERS file
  - For `unowned` repos: show top 3 committers with commit share percentage
- After the table, print a summary line:
  ```
  Summary: 233 owned, 11 partial, 62 unowned (306 total)
  ```
- If `-o` filter is set, only show matching rows (but always show the summary with all counts)
- Use a single `bash` script to do the scanning - run it with `bash -e` to catch errors
- For large scans (>50 repos), show a progress indicator to stderr

## Ex-employee Filtering

Derive the org name from the path (e.g., `~/repos/tatari-tv/` -> `tatari-tv`).
Check for `~/.config/ls-owners/<org>/ex-employees` (one email per line).
Exclude matching emails from the suggested owners list.

## Examples

```bash
# Audit all repos in an org
ls-owners ~/repos/mycompany

# Find repos that need CODEOWNERS
ls-owners -o unowned ~/repos/mycompany

# Get detailed ownership for a repo
ls-owners -d ~/repos/mycompany/some-repo

# Show only partially owned repos with detail
ls-owners -o partial -d ~/repos/mycompany
```

