---
name: dotfiles
description: Move a file into a scottidler manifest-managed repo, commit it, and symlink it back into place via manifest. Use this whenever the user wants to track, manage, or version-control a config file or dotfile — including phrasings like "track this in dotfiles", "manifest this file", "symlink this into my dotfiles", "put this under dotfiles management", or "stop keeping this as a loose file". Trigger even when the user doesn't say "dotfiles" but is clearly asking to move a config/rc/CLAUDE.md file into the repo and symlink it back.
allowed-tools: Bash(*)
---

# Dotfiles

Move a file into a `scottidler` manifest-managed repo and symlink it back into place via `manifest`.

## Which repo

Two repos under `~/repos/scottidler/` are manifest-managed (each has a `HOME/` tree and its own `manifest.yml`):

- `~/repos/scottidler/dotfiles` — general configs and dotfiles (shell, git, `.cargo/config.toml`, systemd units, etc.). **This is the default.**
- `~/repos/scottidler/claude` — Claude config only: `~/.claude/**`, `CLAUDE.md`, skills, rules.

Pick by file type: a Claude-config file goes to `claude`, everything else to `dotfiles`. Below, `$REPO` is whichever one you picked.

## Arguments

`/dotfiles <filepath>` - the file to move into manifest management.

The filepath can be absolute or relative to the current working directory.

## How It Works

1. **Resolve** the absolute path of the file
2. **Check preconditions:**
   - File must exist
   - File must be a regular file (not already a symlink - if it is, error and report "already managed by dotfiles")
   - File must be under `$HOME` (otherwise there's no HOME-relative path)
3. **Compute the destination:** strip the `$HOME/` prefix and prepend `$REPO/HOME/`
   - Example: `~/repos/CLAUDE.md` -> `$REPO/HOME/repos/CLAUDE.md`
4. **Create parent directories** in `$REPO/HOME/...` if needed
5. **Move the file** into `$REPO/HOME/...`
6. **Commit** in `$REPO` with a message like: `add HOME/repos/CLAUDE.md`
7. **Run `manifest --link '<substring>' | bash`** in `$REPO` to create the symlink, where `<substring>` is a substring matching the filename (e.g. `CLAUDE` for `CLAUDE.md`)
   - `manifest --link` only *generates* the bash script to stdout; it does **nothing** until piped to `bash`. Always pipe.
   - The pattern is a PLAIN substring (manifest fuzzy-matches Exact→IgnoreCase→Prefix→Contains), NOT a glob. `cargo` works; `*cargo*` matches nothing and emits an empty links section.
   - If you moved the file (step 5) there is no `.orig`. If you *copied* it instead (leaving the original real file in place), `manifest`'s `linker()` backs the original up to `<path>.orig` before symlinking — clean those up with `rkvr rmrf <path>.orig` after verifying the symlink target is byte-identical.
8. **Verify** the original path is now a symlink pointing into `$REPO/HOME/`

## Example

```
/dotfiles ~/repos/CLAUDE.md
```

`CLAUDE.md` is Claude config, so `$REPO` = `~/repos/scottidler/claude`. Result:
- `~/repos/scottidler/claude/HOME/repos/CLAUDE.md` contains the file
- `~/repos/CLAUDE.md` is a symlink -> `/home/saidler/repos/scottidler/claude/HOME/repos/CLAUDE.md` (manifest's `linker()` emits an **absolute** target via `realpath`, not a relative one)
- Committed in `~/repos/scottidler/claude`

## Error Cases

- File does not exist: report and stop
- File is already a symlink: report "already managed by dotfiles" and stop
- File is not under `$HOME`: report and stop
- Commit or manifest fails: report the error output
