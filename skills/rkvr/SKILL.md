---
name: rkvr
description: Safe file deletion with archiving and recovery. Use rmrf instead of rm -rf to enable recovery of deleted files.
allowed-tools: Bash(rmrf:*), Bash(bkup:*), Bash(rcvr:*), Bash(ls-rmrf:*), Bash(ls-bkup:*), Bash(bkup-rmrf:*)
---

# RKVR - Recoverable File Operations

`rkvr` provides safe file deletion with automatic archiving and recovery. **Never lose files to accidental `rm -rf` again.**

## Commands

| Command | Purpose |
|---------|---------|
| `rmrf` | Delete files/dirs (archived for recovery) |
| `bkup` | Backup files/dirs (keep originals) |
| `rcvr` | Recover previously deleted/backed up files |
| `ls-rmrf` | List archived deletions |
| `ls-bkup` | List backups |
| `bkup-rmrf` | Backup then delete |

## Basic Usage

```bash
# Instead of: rm -rf old-project/
rmrf old-project/

# Backup before major changes
bkup important-config.yml

# List what's in the archive
ls-rmrf

# Recover a deleted file
rcvr 1234567890123456789   # Use timestamp from ls-rmrf
```

## Archive Locations

- **Deletions**: `/var/tmp/rmrf/`
- **Backups**: `/var/tmp/bkup/`

Each archive contains:
- `metadata.yml`: Original location, file tree
- Tar archives of directories
- Copies of individual files

## Configuration (`~/.config/rmrf/rmrf.cfg`)

```ini
[DEFAULT]
rmrf_path = /var/tmp/rmrf
bkup_path = /var/tmp/bkup
sudo = yes
keep = 30
threshold = 70
```

- `keep`: Days to keep archives before auto-cleanup
- `sudo`: Allow operations on root-owned files
- `threshold`: Fuzzy match threshold for searching

## Searching Archives

```bash
ls-rmrf config              # Fuzzy search for "config"
ls-rmrf node_modules        # Find deleted node_modules
ls-bkup terraform           # Find terraform backups
```

## Recovery Workflow

```bash
# 1. List archives to find timestamp
ls-rmrf myproject

# 2. Preview what's in the archive
# (ls-rmrf shows metadata with file tree)

# 3. Recover using the timestamp directory
rcvr 1704067200123456789
```

Files are restored to their **original location** (from `metadata.yml`).

## Safety Features

- Archives preserve ownership and permissions
- Sudo support for system files
- Automatic cleanup of old archives
- Fuzzy search to find files
- Metadata tracks original paths

