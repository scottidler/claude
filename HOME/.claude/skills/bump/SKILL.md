---
name: bump
description: Version bumping tool for Rust projects. Use when incrementing versions, creating git tags, or releasing new versions.
---

# Version Bumping with `bump`

Use `bump` to increment versions, commit changes, and create git tags in one step.

## TRIPWIRE: check the gates BEFORE running bump

`bump` tags local HEAD the moment it runs. On a repo whose main is gated (branch
protection or any repo/org ruleset), that SHA will never land on main (squash-merge
rewrites it) — the tag is orphaned the moment it's pushed. So, first:

```bash
tagit gates
```

- `flow: direct` → safe; prefer `tagit release [bump args]` (runs bump, pushes main, verifies it landed, then pushes the tag by name)
- `flow: pr` → do NOT run `bump`. Use `tagit pr` (version-bump PR, no tag) then, after it merges, `tagit tag`. (Once bump ships `--no-tag`/`--tag-only` per `bump/docs/design/2026-06-12-gated-repo-tagging.md`, those replace tagit.)

## Workflows

**bump** handles three scenarios:

1. **Uncommitted changes** - stages, commits, and tags
2. **Committed but unpushed** - amends the commit, adds tag
3. **Committed and pushed** - creates new version bump commit, adds tag

## Standard Workflow (uncommitted changes)

```bash
# 1. Make your code changes (leave them unstaged)
# 2. Run bump
bump

# 3. Push the branch FIRST and verify it lands, THEN the tag by explicit name
#    (never `git push --tags`; push.followTags is off for the same reason):
git push origin main && git push origin vX.Y.Z
```

## Agent/CI Workflow (already committed)

```bash
# Agent commits changes
git add .
git commit -m "Implement feature X"

# Run bump - amends commit and tags (if unpushed)
bump -a
# Output: Amended commit and tagged v0.1.6

git push origin main && git push origin v0.1.6   # branch first, tag by name - never --tags
```

## What bump does

1. Updates version in Cargo.toml (patch bump by default)
2. Syncs Cargo.lock
3. Either:
   - **Uncommitted changes**: stages all, commits with message, tags
   - **Unpushed commit**: amends previous commit with version bump, tags
   - **Pushed commit**: creates new commit, tags
4. Creates an annotated git tag (e.g., v0.2.3)

## Options

```bash
bump               # Patch bump (x.y.Z) - DEFAULT
bump -m            # Minor bump (x.Y.0)
bump -M            # Major bump (X.0.0)
bump -n            # Dry run - preview without applying
bump -a            # Automatic commit message
bump --message "X" # Custom commit message
```

## Commit Message Behavior

| Flag | Behavior |
|------|----------|
| `--message "msg"` | Use provided message |
| `-a` / `--automatic` | Generate "Bump version to vX.Y.Z" |
| (neither) | Auto-generate for version-only changes, or open editor |

When you have changes beyond Cargo.toml, bump opens your editor (`$VISUAL` → `$EDITOR` → `vim`) with a template showing staged files.

## Integration with Rust Projects

For Rust projects using the `/rust-cli-coder` conventions, the version set by bump is picked up by `build.rs` and exposed via the `GIT_DESCRIBE` environment variable, which clap uses for `--version` output.

## What NOT to Do

- Don't run `bump` on a gated repo (see TRIPWIRE above) — its tag can never land on main
- Don't manually edit version in Cargo.toml — use `bump` (exception: the gated PR flow, where `tagit pr` edits it because bump would tag prematurely)
- Don't create tags manually — `bump`/`tagit tag` create annotated tags
- Don't EVER run `git push --tags` — push the branch first, verify it landed, then push the tag by explicit name (`git push origin vX.Y.Z`)
