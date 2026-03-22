---
name: dotfiles
description: Move a file into the scottidler/... dotfiles repo, commit it, and symlink it back via manifest. Use when the user wants to track a config file or dotfile in their dotfiles repo.
allowed-tools: Bash(*)
---

# Dotfiles

Move a file into the `scottidler/...` dotfiles repo at `~/...` and symlink it back into place via `manifest`.

## Arguments

`/dotfiles <filepath>` - the file to move into dotfiles management.

The filepath can be absolute or relative to the current working directory.

## How It Works

1. **Resolve** the absolute path of the file
2. **Check preconditions:**
   - File must exist
   - File must be a regular file (not already a symlink - if it is, error and report "already managed by dotfiles")
   - File must be under `$HOME` (otherwise there's no HOME-relative path)
3. **Compute the destination:** strip the `$HOME/` prefix and prepend `~/.../HOME/`
   - Example: `~/repos/CLAUDE.md` -> `~/.../HOME/repos/CLAUDE.md`
4. **Create parent directories** in the dotfiles repo if needed
5. **Move the file** into `~/.../HOME/...`
6. **Commit** in the `~/...` repo with a message like: `add HOME/repos/CLAUDE.md`
7. **Run `manifest --link '<substring>' | bash`** in `~/...` to create the symlink, where `<substring>` is a substring matching the filename (e.g. `CLAUDE` for `CLAUDE.md`)
8. **Verify** the original path is now a symlink pointing to the dotfiles repo

## Example

```
/dotfiles ~/repos/CLAUDE.md
```

Result:
- `~/.../HOME/repos/CLAUDE.md` contains the file
- `~/repos/CLAUDE.md` is a symlink -> `../../.../HOME/repos/CLAUDE.md`
- Committed in `~/...`

## Error Cases

- File does not exist: report and stop
- File is already a symlink: report "already managed by dotfiles" and stop
- File is not under `$HOME`: report and stop
- Commit or manifest fails: report the error output
