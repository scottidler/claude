#!/bin/bash
# Ship-it workflow runner for test project
set -e

PROJ_DIR="$(cat /home/saidler/.claude/skills/shipit-workspace/project-dir.txt)"
cd "$PROJ_DIR"

case "$1" in
  status)
    git status
    ;;
  diff)
    git diff
    ;;
  log)
    git log --oneline -5
    ;;
  remote)
    git remote -v
    ;;
  cargo-toml)
    cat Cargo.toml
    ;;
  main-rs)
    cat src/main.rs
    ;;
  claude-md)
    cat CLAUDE.md 2>/dev/null || cat .claude/CLAUDE.md 2>/dev/null || echo "NO_CLAUDE_MD"
    ;;
  add)
    shift
    git add "$@"
    ;;
  commit)
    shift
    git commit "$@"
    ;;
  bump)
    shift
    ~/.cargo/bin/bump "$@"
    ;;
  push)
    git push && git push --tags
    ;;
  install-echo)
    shift
    echo "WOULD RUN: $*"
    ;;
  all-preflight)
    echo "=== GIT STATUS ==="
    git status
    echo ""
    echo "=== GIT DIFF ==="
    git diff
    echo ""
    echo "=== GIT LOG ==="
    git log --oneline -5
    echo ""
    echo "=== REMOTES ==="
    git remote -v
    echo ""
    echo "=== CARGO.TOML ==="
    cat Cargo.toml
    echo ""
    echo "=== SRC/MAIN.RS ==="
    cat src/main.rs
    echo ""
    echo "=== CLAUDE.MD ==="
    cat CLAUDE.md 2>/dev/null || cat .claude/CLAUDE.md 2>/dev/null || echo "NO_CLAUDE_MD"
    ;;
  *)
    echo "Unknown command: $1"
    exit 1
    ;;
esac
