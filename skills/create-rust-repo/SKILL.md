---
name: create-rust-repo
description: Create a new Rust CLI repo on GitHub with README, .gitignore, license, clone it, and scaffold it. Use when creating a new Rust project from scratch.
user-invocable: true
allowed-tools: Bash(gh:*), Bash(clone:*), Bash(scaffold:*), Bash(cd:*), Bash(ls:*), Bash(git:*)
---

# Create Rust Repo

End-to-end creation of a new Rust CLI project: GitHub repo, clone, scaffold, commit, push.

## Arguments

```
/create-rust-repo <owner>/<name> [--description "..."] [--private]
```

- `owner`: GitHub user or org (e.g., `scottidler`, `tatari-tv`)
- `name`: repo name
- `--description`: optional repo description
- `--private`: create as private repo (default: public)

## Steps

### 1. Determine the right GitHub account

- `scottidler` or any non-tatari org: use `GH_TOKEN="$GITHUB_PAT_HOME"`
- `tatari-tv`: use `GH_TOKEN="$GITHUB_PAT_WORK"`

### 2. Create the GitHub repo

```bash
GH_TOKEN="$TOKEN" gh repo create <owner>/<name> \
  --public \
  --add-readme \
  --gitignore Rust \
  --license mit \
  --description "..."
```

Verify the repo URL is returned successfully before proceeding.

### 3. Clone the repo

**NOTE:** `clone` here is a custom CLI tool (installed at `~/.cargo/bin/clone`), NOT `git clone`. It handles org-specific SSH keys, auto-stash, directory structure, AND persona wire-up (git user.name, user.email, user.signingkey per org from `~/.config/clone/clone.cfg`). This means the repo's git identity is automatically correct for the org - no manual config needed. Always run it from `~/repos`.

```bash
cd ~/repos && clone <owner>/<name>
```

### 4. Scaffold the project

```bash
cd ~/repos/<owner> && scaffold <name> --force --no-git
```

- `--force`: directory already has files from the clone (README, .gitignore, LICENSE)
- `--no-git`: repo is already a git repo from the clone
- Do NOT use `--no-verify` - let scaffold verify the build

### 5. Commit and push

```bash
cd ~/repos/<owner>/<name>
git add -A
git commit -m "Add scaffold for Rust CLI project"
git push
```

Git identity (name, email, signing key) was already configured by `clone` in step 3 - no manual config needed.

## Example

```
/create-rust-repo scottidler/mytool --description "A tool that does things"
```

Produces a ready-to-develop Rust CLI project at `~/repos/scottidler/mytool` with:
- GitHub repo with README, Rust .gitignore, MIT license
- Scaffolded Rust CLI (clap, eyre, env_logger, serde_yaml, colored)
- Initial commit pushed to `main`
