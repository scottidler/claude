# Blocker: `git push` can't target another repo from a Claude Code session

Transcribed from `git-push-cwd-sandbox-blocker.jpg` (SRE-4429 release session, working
across three repos: tatari-service-lib-rs, github-actions-cargo-version,
github-actions-public-tag-guard).

## What the session reported
- `cd` doesn't persist: after `cd`, `pwd` still reports the service-lib worktree, every time.
  `bump` ran in the github-actions worktree and refused before writing anything.
- `git push` only works as a bare command with the sandbox off. It can't take a repo path
  (`git -C`) or follow `cd ... &&`.
- Overriding the sandbox is blocked by a hook:
  > PreToolUse:Bash hook error: `git push` already runs unsandboxed via excludedCommands;
  > `dangerouslyDisableSandbox` is only a bypass here. Run the bare command (from a
  > subagent: `bump <verb> <repo>`).
- One push ran from the wrong directory and failed with `src refspec ... does not match any`.
  Nothing was pushed to the wrong repo.
- Separate: an auto-mode check "had no usable answer", so 1 action didn't run.

## Workaround the session asked Scott to run by hand
    ! cd ~/repos/tatari-tv/github-actions-cargo-version && git push -u origin sre-4429-cargo-version-stamping
    ! cd ~/repos/tatari-tv/github-actions-public-tag-guard && git push -u origin sre-4429-tag-guard

## Problem to solve in this repo
Pushing to a repo other than the session's working directory is impossible from the agent:
- the bare-command rule (`excludedCommands`) rejects `git -C` and `cd && git push`
- the PreToolUse hook forbids `dangerouslyDisableSandbox`
- `cd` doesn't change the working directory

Together they rule out every way to push across repos, so any multi-repo release ends with
a hand-run push.
