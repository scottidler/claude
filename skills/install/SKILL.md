# Install Skill

Install the current Rust project locally.

## Usage

Run `/install` in any Rust project directory to install the binary.

## What It Does

Executes:
```bash
cargo install --path . --locked
```

This installs the current project's binary to `~/.cargo/bin/`.

## When to Use

- After making changes you want to use immediately
- After bumping a version
- When you need the latest local build installed
