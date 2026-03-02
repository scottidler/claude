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
clone scottidler/pais                    # Clone to ./scottidler/pais
clone scottidler/pais main               # Clone and checkout main
clone scottidler/pais --versioning       # Clone to scottidler/pais/<sha>
clone scottidler/pais --mirrorpath ~/mirrors  # Use local mirror for speed
```

## Key Features

- **Org-specific SSH keys**: Configure `~/.config/clone/clone.cfg` with per-org SSH keys
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

- `--versioning`: Create versioned checkout at `<repo>/<sha>`
- `--mirrorpath <path>`: Use local mirror for faster clones
- `--clonepath <path>`: Specify base path for clones

## Example Workflow

```bash
# Clone all repos from an org
ls-github-repos mycompany | while read repo; do
  clone "$repo" --clonepath ~/repos
done
```

