---
name: clone
description: Smart git clone with org-specific SSH keys, versioning, and mirror support. Use instead of git clone.
allowed-tools: Bash(clone:*)
---

# Clone

Smart git clone replacement with org-specific SSH keys, versioning, and mirror support.

## Usage

```bash
clone <repospec> [revision]
clone scottidler/pais                    # Clone to ./scottidler/pais (bare + worktrees)
clone scottidler/pais main               # Clone and checkout main
clone scottidler/pais --flat             # Legacy single-checkout layout (no bare container)
clone scottidler/pais --versioning       # Clone to scottidler/pais/<sha>
clone scottidler/pais --mirrorpath ~/mirrors  # Use local mirror for speed
```

## Layout: bare container + worktrees (default)

A normal `clone` now produces a **bare container** with per-branch worktrees,
not a single flat checkout:

```
<org>/<repo>/
  .bare/          # the bare git repo (shared object store)
  .git            # file pointing at .bare
  main/           # worktree for the main branch
  <branch>/       # one worktree dir per branch you add
```

Each branch lives in its own sibling directory, so multiple branches are checked
out at once with a shared object store (cheap, no re-clone). Use `--flat` to opt
back into the legacy single-checkout layout.

### Add a worktree

```bash
# From inside an existing bare container (e.g. the repo's main/ dir or its root):
clone --worktree <branch>        # add a worktree for <branch>, then cd into it
```

`--worktree` creates the branch's worktree directory as a sibling of `main/` and
`cd`s into it. The repospec is optional when run inside a container — it's
inferred from where you're standing.

### Migrate an existing flat checkout

```bash
clone --migrate                  # convert the checkout you're standing in -> bare container
clone --migrate --dry-run        # show what would happen (worktrees, rescues, removals); change nothing
clone scottidler/pais --migrate  # migrate a named repo's flat checkout
```

`--migrate` converts a flat single-checkout repo into the bare + worktrees layout
in place. Always pair the first run with `--dry-run` to preview the rescued
branches and any removals before committing to the conversion.

## Key Features

- **Org-specific SSH keys**: Configure `~/.config/clone/clone.cfg` with per-org SSH keys
- **Bare + worktrees by default**: multiple branches checked out side by side, shared object store (`--flat` for legacy single checkout)
- **Worktree add**: `--worktree <branch>` adds a worktree to an existing container and cd's in
- **Migrate**: `--migrate` converts a flat checkout into the bare layout in place (`--dry-run` to preview)
- **Auto-stash**: If updating an existing repo with changes, auto-stashes them
- **Versioning mode**: Creates `repo/sha` structure for pinned checkouts
- **Mirror support**: `--mirrorpath` for fast clones from local bare repos

## Configuration (`~/.config/clone/clone.cfg`)

```ini
[org.default]
sshkey = ~/.ssh/id_ed25519

[org.mycompany]
sshkey = ~/.ssh/mycompany_ed25519
```

## Options

- `--worktree <branch>`: Add a worktree for `<branch>` to an existing bare container, then cd into it
- `--migrate`: Convert a flat checkout into a bare container; with no repospec, migrates the checkout you're standing in
- `--dry-run`: With `--migrate`, print what would happen (worktrees, rescues, removals) without changing anything
- `--flat`: Use the legacy single-checkout layout instead of bare + worktrees
- `--versioning`: Create versioned checkout at `<repo>/<sha>`
- `--mirrorpath <path>`: Use local mirror for faster clones
- `--clonepath <path>`: Specify base path for clones
- `--remote <url>`: Git URL base for clone (default `ssh://git@github.com`)

## Example Workflow

```bash
# Clone all repos from an org
ls-github-repos mycompany | while read repo; do
  clone "$repo" --clonepath ~/repos
done
```

