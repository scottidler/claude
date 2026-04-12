---
name: modern-tools
description: Find and track modern Unix tool replacements installed on this system. Use when discovering what modern CLI tools are available, updating the tool inventory, or checking for new tools to install.
allowed-tools: Bash(which:*), Bash(ls:*), Bash(cat:*), Read, Write
---

# Modern Tools Inventory

Track modern replacements for classic Unix tools installed on this system.

## Usage

- `/modern-tools` - Scan system and display current inventory
- `/modern-tools scan` - Rescan and update the inventory file
- `/modern-tools missing` - Show recommended tools not yet installed

## Inventory Location

`~/.claude/skills/modern-tools/inventory.yaml`

## Tool Mappings

Scan for these modern replacements:

| Classic | Modern | Check Locations |
|---------|--------|-----------------|
| ls | eza, exa, lsd | cargo, system |
| cat | bat, batcat | cargo, system |
| grep | rg (ripgrep) | cargo, system |
| find | fd, fdfind | cargo, system |
| cd | zoxide | cargo |
| sed | sd | cargo |
| du | dust, ncdu | cargo, system |
| df | duf | cargo, system |
| diff | delta | cargo, system |
| ps | procs | cargo |
| top | btop, bottom, ytop, htop | cargo, system |
| man | tldr | cargo |
| curl | xh, httpie | cargo, system |
| ping | gping | cargo |
| wc (code) | tokei | cargo |
| cut | choose | cargo |
| xxd | hexyl | cargo |
| time | hyperfine | cargo |

## Scan Locations

1. `~/.cargo/bin/` - Rust tools installed via cargo
2. System PATH via `which` - System-installed tools
3. `~/.local/bin/` - User-local installs
4. Mise-managed tools via `mise list`

## Inventory Format

```yaml
# ~/.claude/skills/modern-tools/inventory.yaml
generated: 2026-01-04T12:00:00Z
tools:
  eza:
    replaces: ls
    location: ~/.cargo/bin/eza
  rg:
    replaces: grep
    location: ~/.cargo/bin/rg
  zoxide:
    replaces: cd
    location: ~/.cargo/bin/zoxide
missing:
  - name: hyperfine
    replaces: time
    install: cargo install hyperfine
  - name: choose
    replaces: cut
    install: cargo install choose
```

## Scan Procedure

1. For each tool in the mappings table:
   - Check `~/.cargo/bin/<tool>`
   - Check `which <tool>`
2. Write findings to inventory file
3. Report summary: installed count, missing count

## Example Output

```
Modern Tools Inventory
======================

Installed (14):
  eza (ls)        ~/.cargo/bin/eza
  bat (cat)       ~/.cargo/bin/bat
  rg (grep)       ~/.cargo/bin/rg
  fd (find)       ~/.cargo/bin/fd
  zoxide (cd)     ~/.cargo/bin/zoxide
  sd (sed)        ~/.cargo/bin/sd
  dust (du)       ~/.cargo/bin/dust
  delta (diff)    /usr/bin/delta
  procs (ps)      ~/.cargo/bin/procs
  btop (top)      /usr/bin/btop
  tldr (man)      ~/.cargo/bin/tldr
  tokei (wc)      ~/.cargo/bin/tokei
  starship        ~/.cargo/bin/starship
  jq              ~/.local/share/mise/...

Not Installed (4):
  hyperfine (time)  cargo install hyperfine
  choose (cut)      cargo install choose
  hexyl (xxd)       cargo install hexyl
  gping (ping)      cargo install gping
```
