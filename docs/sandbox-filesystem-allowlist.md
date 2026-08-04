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

## Round 2 (2026-08-04): allowlisting the run dir was not enough

The fix above covered the panel's own `RUN_DIR`. It did **not** cover two other
things that write outside it, and those became the single largest cause of
review-panel failure: **37% of all 149 panel dispatches from 2026-07-13 to
08-03** died in about 3 seconds with an 82-byte output.

### What was still writing outside the allowlist

1. **The reviewer scripts' own scratch files.** `architect/script.sh` and
   `staff-engineer/script.sh` hardcoded bare `/tmp` for their pidfile, trace,
   and last-message files, one directory ABOVE `/tmp/review-panel`:

   ```
   mktemp: Read-only file system (os error 30) at path "/tmp/architect-trace.XXXXXX"
   mktemp: Read-only file system (os error 30) at path "/tmp/staff-engineer-last.XXXXXX"
   ```

   Fixed in the scripts: everything now goes to `${TMPDIR:-/tmp}`, and both
   preflight `[ -w "$SCRATCH" ]` and exit **3** with an actionable message rather
   than a cryptic mktemp error.

2. **The reviewer CLIs' own state dirs.** Even with the scripts fixed, codex
   still failed at startup because it writes under `~/.codex`:

   ```
   WARNING: proceeding, even though we could not create PATH aliases: Read-only file system (os error 30)
   Error: failed to initialize in-process app-server client: Read-only file system (os error 30)
   ```

   `~/.codex` holds sessions, history, `shell_snapshots`, and sqlite state;
   `~/.gemini` holds `history/`, `tmp/`, and `projects.json`. Both are now in
   `allowWrite`.

### The general lesson

**Allowlisting the directory YOUR code writes to is only half the job.** Every
external CLI you shell out to has its own state dir, and it will hit the same
read-only mount. When a wrapped CLI fails with `os error 30`, check three
places, in this order:

1. the scratch paths your own script chose (`$TMPDIR`, never bare `/tmp`)
2. the CLI's state dir (`~/.codex`, `~/.gemini`, `~/.config/<tool>`)
3. anything the CLI opens that is derived from `$PWD`

### Current review-panel-relevant entries

```json
"sandbox": {
  "enabled": true,
  "filesystem": {
    "allowWrite": [
      "/tmp/review-panel",
      "/home/saidler/.ssh/agent",
      "/home/saidler/.local/share",
      "/home/saidler/.cache",
      "/home/saidler/.codex",
      "/home/saidler/.gemini"
    ],
    "allowRead": [
      "/tmp/review-panel",
      "/home/saidler/.codex",
      "/home/saidler/.gemini"
    ]
  }
}
```

### Optional belt-and-braces: excludedCommands

If a future CLI update writes somewhere new and the whack-a-mole resumes, exempt
the two reviewer scripts outright, the same way `cargo`/`otto`/`release` already
are:

```json
"excludedCommands": [
  "cargo *", "otto *", "release *",
  "*architect/script.sh *",
  "*staff-engineer/script.sh *"
]
```

This trades sandbox coverage of the reviewers for guaranteed completeness. It is
NOT applied by default: the `allowWrite` entries above should be sufficient, and
keeping the reviewers sandboxed is worth more than saving the next debug round.

### Verifying after a restart

```bash
bin/check-review-panel
```

Exit 0 means both seats produced a real review with the sandbox ON.

## Schema reference

`sandbox.filesystem.{allowRead, denyRead, allowWrite, denyWrite}` — arrays of paths.
Path prefixes: `/abs` (filesystem root), `~/x` (home), `./x` or `x` (project root,
or `~/.claude` for user settings). Glob (`/**`) is not documented for the sandbox
layer — use the parent directory, not a glob.
