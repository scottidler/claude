---
name: allow-readonly
description: Stop a subcommand CLI from prompting for permission on its read-only commands by auto-allowlisting them in global settings.json. Use whenever a CLI keeps asking for approval on harmless read operations, or the user says "fix the permissions for <cli>", "stop asking for perms", "<cli> should never ask for perms", "allow all the readonly commands", "add global perms for the readonly stuff", or is annoyed that listing/getting/searching keeps triggering a prompt. Discovers the CLI's command tree, classifies every method as read-only / mutating / ambiguous, and merges Bash allow rules for the read-only ones only. Never allows a mutating verb.
---

# allow-readonly

Turn "why is `<cli>` prompting me AGAIN to run a `list`" into zero prompts for
every read-only operation, without ever hand-allowing a write.

The trick: for subcommand CLIs shaped like
`<cli> <group> <resource> [sub] <method> [flags]` (gws, gcloud-style, kubectl,
most clap/cobra apps), whether a command **mutates state is decided by the final
token** (the method verb). Claude Code permission patterns support a `*`
wildcard **at any position**, and a single `*` spans multiple whitespace-
separated segments (confirmed against the permission docs: `Bash(git * main)`
matches `git push origin main`). So one rule — `Bash(<cli> * <verb>:*)` — allows
that verb across every group/resource at any depth (`gws drive files get`), and
the trailing `:*` enforces a **word boundary** so `get:*` matches `... get
--flag` but NOT `getThumbnail`. That's why this skill enumerates read-only verbs
at the token level rather than guessing a prefix.

The user is annoyed — the whole point is one command, then done.

## Procedure

1. **Confirm the CLI is installed and subcommand-shaped.** Run `<cli> --help`.
   If it prints a command list (a `Commands:` / `Available Commands:` /
   `SERVICES:` section), it fits. Note whether the *top level* is parseable — a
   few CLIs (gws) print a prose blurb + JSON at the root and need the top-level
   groups seeded explicitly.

2. **Discover + classify** with the bundled walker:

   ```
   python3 <skill-dir>/discover.py <cli>
   # if the root isn't parseable, seed the top-level groups:
   python3 <skill-dir>/discover.py gws --seed "drive sheets gmail calendar \
       admin-reports docs slides tasks people chat classroom forms keep meet"
   ```

   It walks the whole `--help` tree, collects every leaf method token, and
   prints three buckets — **readonly**, **ambiguous**, **mutating** — plus the
   candidate `Bash(<cli> * <verb>:*)` rules for the readonly set. The verb
   classification tables live at the top of `discover.py`; extend them there if
   a CLI uses a house verb the tables don't know.

3. **Review the ambiguous bucket WITH the user.** These are tokens with no
   clear read/write verb root (e.g. `resolve`, `endActiveConference`, `query`
   in some tools). Never auto-allow them. Show the short list, ask which are
   read-only, then re-run with `--include-ambiguous` (which folds ALL ambiguous
   tokens in — so only do that once you've confirmed they're all safe, otherwise
   add the approved ones by hand). If the user just wants the obvious wins, ship
   the readonly bucket and skip the ambiguous ones.

4. **Merge into global settings** — `~/.claude/settings.json` (real path
   `~/repos/scottidler/claude/HOME/.claude/settings.json`; edit the real path,
   never the symlink). Use the bundled merge helper so it's idempotent and
   preserves the file:

   ```
   python3 <skill-dir>/discover.py <cli> --seed "..." --rules-only \
     | python3 <skill-dir>/merge.py ~/repos/scottidler/claude/HOME/.claude/settings.json
   ```

   `merge.py` adds each rule to `permissions.allow`, **dedupes**, leaves every
   existing entry untouched, and NEVER writes to `deny`/`ask`. It prints what it
   added and what was already present.

5. **Also allow obvious top-level read commands** the walk can't bucket — e.g.
   `gws schema ...` (schema inspection), `<cli> version`, `<cli> help`. Add
   these by hand as `Bash(<cli> schema:*)` etc. only when clearly read-only.

6. **Report** the added rules and the skipped (mutating + un-confirmed
   ambiguous) counts. **Tell the user the allowlist may only take effect in a
   new session** — if it's still prompting, restart the session.

## Hard rules

- **Read-only only.** Mutating verbs (`create/update/delete/patch/set/send/
  upload/move/trash/...`) are NEVER added, even if the user says "allow
  everything" — if they truly want a whole namespace, that's a broad
  `Bash(<cli> <group> *)` rule they add deliberately, not this skill's job.
- **Never delete or rewrite** existing rules (see the no-unrequested-deletes
  rule). Merge is additive + dedup only.
- **Global by default.** This is about a CLI being annoying everywhere, so it
  belongs in the user's global settings, not a project `.claude/settings.json` —
  unless the user asks for project scope.
- **Ambiguous → confirm.** When a verb's intent isn't obvious, ask; default to
  NOT allowing.

## Why token-level, not a broad `Bash(<cli> *)`

A blanket `Bash(gws *)` (or per-group `Bash(gws drive *)`) also stops the
prompts — but it allows `delete`, `update`, `send`, everything. This skill keeps
the safety boundary intact: reads flow without friction, writes still prompt.
