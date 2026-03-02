# Installing gx Plugin

This plugin provides multi-repo Git operations using the `gx` CLI tool.

## Prerequisites

1. **gx CLI** must be installed and available in PATH
   ```bash
   cargo install --git https://github.com/scottidler/gx
   ```

2. **Git** must be configured with your identity
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "you@example.com"
   ```

## Verification

After installation, verify the setup:

```bash
# Check gx is installed
gx --version

# Check gx can find repos
gx status
```

## Usage

The plugin provides:
- **Skills** for Claude Code to perform multi-repo operations
- **Agents** for autonomous repository management
- **Commands** for batch operations

See the skills/ directory for available capabilities.
