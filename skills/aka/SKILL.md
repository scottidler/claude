---
name: aka
description: High-performance shell alias manager. Use when managing shell aliases, querying alias expansions, or optimizing shell startup.
allowed-tools: Bash(aka:*)
---

# AKA - Also Known As

`aka` is a high-performance shell alias manager that replaces traditional shell alias definitions with a YAML-based configuration and optional daemon mode for sub-millisecond lookups.

## Key Concepts

- **YAML Config**: Aliases defined in `~/.config/aka/aka.yml` instead of scattered shell files
- **Daemon Mode**: Background daemon keeps aliases in memory for instant lookups
- **Global Aliases**: Expand anywhere in the command line (like zsh global aliases)
- **Frequency Tracking**: Tracks which aliases you use most

## Quick Reference

```bash
aka ls                    # List all aliases
aka ls -g                 # List global aliases only
aka ls git                # Filter aliases matching "git"
aka query "g st"          # Show expansion of "g st"
aka freq                  # Show usage frequency
aka freq --all            # Show all aliases including unused
aka daemon --status       # Check daemon status
aka daemon --start        # Start daemon
aka daemon --reload       # Reload config
```

## Configuration (`~/.config/aka/aka.yml`)

```yaml
aliases:
  g:
    command: git
    global: false

  gs:
    command: git status

  gco:
    command: git checkout

  # Global alias - expands anywhere
  L:
    command: "| less"
    global: true
```

## Daemon Status Icons

- ✅ Daemon healthy, config synced
- 🔄 Daemon healthy, config out of sync (reload needed)
- ⚠️ Stale socket (socket exists but process not running)
- ❗ Daemon not running
- ❓ Unknown state

## Shell Integration

Add to your `.zshrc`:

```bash
eval "$(aka shell-init zsh)"
```

This enables:
- Auto-expansion of aliases
- Tab completion for alias names
- Automatic daemon health checks

## Daemon Management

```bash
aka daemon --install      # Install as system service (systemd/launchd)
aka daemon --uninstall    # Remove system service
aka daemon --start        # Start daemon
aka daemon --stop         # Stop daemon
aka daemon --restart      # Restart daemon
aka daemon --reload       # Reload config without restart
aka daemon --status       # Show detailed status
```

## Performance

With daemon mode:
- **Direct mode**: ~5-10ms per alias lookup
- **Daemon mode**: <1ms per alias lookup

Use `aka daemon --timing-summary` to see performance stats.

