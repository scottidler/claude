---
name: worktree
description: Create, switch, list, or prune git worktrees in a bare-container repo using the `worktree` CLI. Use whenever the user wants a new worktree or branch, says "create a worktree", "new worktree", "make a branch worktree", "spin up a worktree for X", or wants to list/prune worktrees. ALWAYS prefer this over raw `git worktree add` for any worktree request.
allowed-tools: Bash(worktree:*), Bash(~/.cargo/bin/worktree:*)
---

# worktree

`worktree` is Scott's Rust CLI for managing git worktrees in a bare-container layout
(`.bare` + sibling worktree dirs, as used by `second-brain`, etc.). It creates the
worktree, slugifying new branch names, and bases new branches on the remote default.

**Never use raw `git worktree add` for worktree requests. Use this CLI.**

## The binary-vs-function contract

There is a zsh function named `worktree` (in `~/.shell-functions.d/git-tools.sh`) that
wraps the binary so an interactive shell `cd`s into the chosen worktree. **That `cd`
only works in the user's interactive shell, not in a tool invocation.** When you (Claude)
run it, invoke the binary directly by full path so the shell function never shadows it:

```bash
~/.cargo/bin/worktree <branch>
```

The binary prints the resulting worktree path to stdout. Capture that path and operate
inside it (the directory is the worktree's checkout); do not try to `cd` the user's shell.

## Usage

```bash
# Create (or switch to) a worktree for a branch. New branch names are slugified;
# an existing local/remote branch is matched as-is. Prints the worktree path.
~/.cargo/bin/worktree voice

# List the container's worktrees (no switching)
~/.cargo/bin/worktree --list      # or -L

# Remove worktrees whose branch is merged into origin/<default>.
# Branch refs are kept; reflects the last fetch. Non-interactive needs -y.
~/.cargo/bin/worktree --prune -y

# Base a NEW worktree on a specific branch when the remote default can't be detected
~/.cargo/bin/worktree some-branch --default-branch main
```

## Notes

- Running with no `BRANCH` argument opens an interactive fzf picker - that is for the
  user at a terminal, not for tool use. Always pass an explicit branch.
- The new branch is created off the remote default branch unless `--default-branch` says
  otherwise.
- After creating, report the printed path to the user so they can `cd` there themselves.
