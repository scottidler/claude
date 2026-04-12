---
name: bump
description: Version bumping tool for Rust projects. Use when incrementing versions, creating git tags, or releasing new versions.
---

# Version Bumping with `bump`

Use `bump` to increment versions, commit changes, and create git tags in one step.

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

# 3. Push commit and tags:
git push && git push --tags
```

## Agent/CI Workflow (already committed)

```bash
# Agent commits changes
git add .
git commit -m "Implement feature X"

# Run bump - amends commit and tags (if unpushed)
bump -a
# Output: Amended commit and tagged v0.1.6

git push && git push --tags
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

- Don't manually edit version in Cargo.toml — use `bump`
- Don't create tags manually — `bump` creates annotated tags
- Don't forget to push tags — always run `git push --tags` after bump
