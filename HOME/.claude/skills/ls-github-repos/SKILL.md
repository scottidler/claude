---
name: ls-github-repos
description: List repos under a GitHub org or user with filters for visibility (public/private/internal), language, and archived status. Use whenever you need to enumerate an org's repos, check whether repos are public or private, find repos by language, list archived repos, see repo creation dates, or feed a repo list into a pipeline (bulk clone, audits). ALWAYS prefer this over looping `gh api repos/...` per repo or paginating `gh repo list` — one invocation answers "which of these repos are private?" for a whole org.
allowed-tools: Bash(ls-github-repos:*)
---

# ls-github-repos

List all repositories under a GitHub organization or user, one `org/repo` slug
per line — pipe-friendly. From `scottidler/git-tools` (v0.4.2 at last audit).

```
ls-github-repos [OPTIONS] <NAME>
```

`<NAME>` is the org or user (e.g. `tatari-tv`, `scottidler`).

## All knobs

| flag | meaning |
|---|---|
| `-r, --repo-type <user\|org>` | REQUIRED for users — default is `org`, there is NO auto-detect. `ls-github-repos scottidler -r user` |
| `--visibility <public\|internal\|private>...` | FILTER to only these visibilities (space-separated, repeatable — never commas) |
| `--show-visibility` | prefix each line with its visibility: `private tatari-tv/slack-cli` |
| `-l, --lang <LANG>...` | filter by primary language (space-separated): `-l rust python` |
| `-A, --archived` | include archived repos (excluded by default) |
| `-a, --age` | prefix creation date, sorted oldest-first: `2016-02-06 tatari-tv/philo` |
| `-t, --token-path <PATH>` | token-file directory (default `~/.config/github/tokens`) |
| `--log-level <LEVEL>` | error, warn, info, debug, trace (default INFO) |
| `-V, --version` | print version |

## Recipes

```bash
# Which of an org's repos are public vs private? (one call, whole org)
ls-github-repos tatari-tv --show-visibility | grep -E 'clyde|marquee|sdv'

# Is a specific repo private?
ls-github-repos tatari-tv --show-visibility | grep 'okta-auth-rs$'

# All public repos in the org
ls-github-repos tatari-tv --visibility public

# All Rust repos
ls-github-repos tatari-tv -l rust

# A user's repos (MUST pass -r user)
ls-github-repos scottidler -r user

# Oldest repos first, with dates
ls-github-repos tatari-tv -a | head

# Bulk clone an org
ls-github-repos tatari-tv | while read repo; do clone "$repo"; done
```

## Auth (two tiers, in order)

1. `~/.config/ls-github-repos/ls-github-repos.yml` maps name → env var
   (this is the live setup — no token files needed):
   ```yaml
   tokens:
     scottidler: GITHUB_PAT_HOME
     tatari-tv: GITHUB_PAT_WORK
   ```
   Those env vars are loaded by the dotfiles secret decrypt in interactive
   shells. In a spawned/agent shell they may be absent — if the tool errors
   with "env var ... is not set", decrypt per `rules/secrets.md`.
2. Fallback: a raw token file at `<token-path>/<NAME>` (e.g.
   `~/.config/github/tokens/tatari-tv`, chmod 600).

## Gotchas

- `-r user` is mandatory for user accounts; the org default gives a wrong/empty
  answer for users. No auto-detect.
- Filters compose: `--visibility private -l rust -A` works.
- `--show-visibility` changes the line format — anchor greps on the END of the
  line (`grep 'name$'`), not the start.
- Archived repos are hidden unless `-A`; a "missing" repo is often just archived.
