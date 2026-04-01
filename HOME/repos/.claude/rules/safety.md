---
paths:
  - "**/*"
---

# Safety Rules

## File Deletion

- NEVER use `rm` or `rm -rf`. Always use `rkvr rmrf` instead. This archives files before deleting, enabling recovery if needed.
- No exceptions. Even for temp files or known-safe deletions, use `rkvr rmrf`.

## Formatting

- NEVER use em dashes (the — character) in any output destined for documentation, comments, Confluence, Jira, Slack, or any external system. Use regular dashes (-), commas, or semicolons instead.

## Python Package Management

- NEVER use `pip install`. EVER. Always use `pipx` for installing Python tools/packages. No exceptions.

## Rust CLI Overrides

- A Rust variant of `tail` is installed at `~/.cargo/bin/tail` and shadows `/usr/bin/tail`. It has incompatible flags. In Bash commands, always use `/usr/bin/tail` instead of bare `tail`.
