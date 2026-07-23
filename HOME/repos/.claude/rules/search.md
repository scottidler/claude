---
alwaysApply: true
---

# Search: prefer rg / fd, fall back to grep / find

## The rule

- Searching file **contents** -> `rg` (ripgrep). Finding files **by name/type**
  -> `fd`. Use these first, every time.
- Fall back to `grep` / `find` ONLY when the modern tool is genuinely
  unavailable. Check with `command -v rg` / `command -v fd` (on Debian, fd may
  be `fdfind`) before reaching for the old tool.
- The built-in Grep tool already uses ripgrep -- prefer it over shelling out to
  raw `grep -r`.

## Why (this froze a pane, 2026-07-22)

- `~/repos` holds ~1.67M filesystem entries; ~78% is regenerable junk
  (`node_modules`, Rust `target/`, `.venv`, `.git` objects, caches).
- `rg` / `fd` honor `.gitignore` **and** the global `~/.config/git/ignore`, so
  they prune that junk automatically -- `rg --files ~/repos` walks ~405K files,
  a raw `find` walks ~1.48M. A recursive `grep`/`find` over that tree runs for
  minutes and reads as a hang.
- `find` and `grep` are VCS-blind by design: no ignore file (repo-local or
  global) will EVER make them skip `node_modules`/`target`. Only the tool
  choice fixes it.

## Never brute-force a huge multi-repo root

- Do NOT run raw `find ~/repos ...` or `grep -r ... ~/repos` across the whole
  repo root. Scope to the specific repo(s) named in the task.
- If a broad sweep is truly needed, use `rg`/`fd` (which prune) -- never the
  VCS-blind tools -- and still scope as narrowly as the task allows.
