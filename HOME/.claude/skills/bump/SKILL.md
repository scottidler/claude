---
name: bump
description: Version bumping tool for Rust projects. Use when incrementing versions, creating git tags, or releasing new versions.
---

# Version Bumping with `bump`

Use `bump` to increment versions, commit changes, and create git tags in one step.

## Gated repos: bump checks the gates itself

`bump` tags local HEAD the moment it runs. On a repo whose default branch is gated (classic
branch protection or any repo/org ruleset), that SHA will never land on main (squash-merge
rewrites it) — the tag would be orphaned the moment it's pushed. `bump` now **detects this
and refuses to tag** by default, printing the gated flow instead. To see the verdict and the
recommended flow up front:

```bash
bump --gates
```

- `Gates: none (ungated)` → `bump [-m|-M]`, then `git push origin main && git push origin vX.Y.Z`
- `Gates: … (gated)` → `bump --no-tag [-m|-M]` (the version bump rides your PR branch); after
  the PR merges, on updated main: `bump --tag-only`, then `git push origin vX.Y.Z`

If `gh` is missing or unauthenticated, `bump` can't verify gates: it warns and proceeds as
ungated (tagging is local and recoverable — the push is the dangerous step). `--no-verify`
skips the probe deliberately.

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

## Gated Workflow (PR required)

On a gated default branch the version bump must ride a PR, and the tag is created only
after the merge — `bump` enforces this (plain `bump` refuses; `--tag-only` verifies first).

```bash
# On your feature branch: bump the version WITHOUT tagging
bump --no-tag                         # (or --no-tag -m / -M)
git push origin my-feature            # open a PR, get it merged

# After the PR merges, on the merged default branch:
git checkout main && git pull --ff-only origin main
bump --tag-only                       # verifies HEAD == origin/main, then tags
git push origin vX.Y.Z                # push the tag by explicit name
```

`bump --tag-only` refuses unless the tree is clean, you're on the remote default branch,
and HEAD is **exactly** `origin/<default>` — so it can't tag an unmerged or stale commit.
An existing tag already at HEAD is a no-op; one pointing elsewhere is refused (manual tag
surgery, never bump's job).

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
bump --gates       # Report gate status + recommended flow, then exit
bump --no-tag      # Bump + commit, but create NO tag (gated repos; rides a PR branch)
bump --tag-only    # Tag the merged commit (post-merge step for gated repos)
bump --no-verify   # Skip the gate probe (treat repo as ungated)
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

- Don't try to force a tag on a gated repo — plain `bump` refuses by design; use `bump --no-tag` then `bump --tag-only` after merge (see Gated Workflow above)
- Don't manually edit version in Cargo.toml — use `bump` (on gated repos, `bump --no-tag` does the edit without tagging)
- Don't create tags manually — `bump` / `bump --tag-only` create annotated tags
- Don't EVER run `git push --tags` — push the branch first, verify it landed, then push the tag by explicit name (`git push origin vX.Y.Z`)
