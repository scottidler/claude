# Sandbox filesystem allowlist (why review-panel kept prompting)

## Symptom

Starting a review-panel run prompted:

> Yes, and always allow access to `<random-dir>/` from this project

every single time, despite `permissions.allow` already containing
`Read(/tmp/review-panel/**)`, `Bash(wc:*)`, and `/tmp/review-panel` being in
`permissions.additionalDirectories`. Accepting the prompt only persisted that one
run's `mktemp` dir, so the next run minted a new random dir and prompted again.

## Root cause

`settings.json` has `"sandbox": { "enabled": true }`. The sandbox is a **second,
independent layer** on top of the permission layer:

- The **permission layer** (`permissions.allow`, `additionalDirectories`) governs
  Claude's own Read/Edit/Bash tool gating.
- The **sandbox layer** governs what the sandboxed OS process can touch. By
  default it allows only the cwd + the session temp dir. The review-panel agent
  does `mktemp -d /tmp/review-panel/XXXXXXXX`, which is neither.

The sandbox FS allowlist does **NOT** honor `permissions.additionalDirectories` or
any `Read(...)`/`Bash(...)` rule. It has its own keys, so all the permission-layer
rules were satisfied yet the sandbox still prompted.

## Fix

Add the parent dir to the sandbox FS allowlist in `settings.json`. Entries are
directory-prefix grants, so the parent covers every random subdir:

```json
"sandbox": {
  "enabled": true,
  "excludedCommands": ["cargo *", "otto *", "release *"],
  "filesystem": {
    "allowRead":  ["/tmp/review-panel"],
    "allowWrite": ["/tmp/review-panel"]
  }
}
```

Sandbox config is read at session start — a session restart is required to load it.

## Schema reference

`sandbox.filesystem.{allowRead, denyRead, allowWrite, denyWrite}` — arrays of paths.
Path prefixes: `/abs` (filesystem root), `~/x` (home), `./x` or `x` (project root,
or `~/.claude` for user settings). Glob (`/**`) is not documented for the sandbox
layer — use the parent directory, not a glob.
