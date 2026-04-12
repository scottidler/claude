---
name: otto
description: Otto task runner for builds and CI. Use when running tests, builds, CI pipelines, or when the user mentions otto, make, task runner, or .otto.yml.
allowed-tools: Bash(otto:*)
---

# Otto Task Runner

Otto is a Make replacement written in Rust. It runs tasks defined in `.otto.yml` with parallel execution, dependencies, and parameters.

## Quick Commands

```bash
otto ci        # Full CI pipeline (lint + check + test)
otto check     # Compile + clippy + format check
otto test      # Run tests
otto cov       # Coverage report
otto build     # Release build
otto clean     # Clean artifacts
otto install   # Install locally
```

**Always use `otto` instead of raw cargo/pytest/npm commands.** The `.otto.yml` defines the project's standard workflows.

## Running Otto

```bash
# Run default task (defined in otto.tasks)
otto

# Run specific task
otto ci
otto test

# Run with parameters
otto cov --fail-under 80

# Show task graph
otto Graph

# List available tasks
otto --help
```

## .otto.yml Structure

```yaml
otto:
  api: 1                    # API version (always 1)
  tasks: [ci]               # Default task(s) to run
  envs:                     # Environment variables
    VERSION: "$(git describe --tags --always)"

tasks:
  taskname:
    help: "Description shown in --help"
    before: [dep1, dep2]    # Dependencies (run first, in parallel)
    params:                 # CLI parameters
      --flag:
        default: "value"
        help: "Parameter description"
    bash: |
      # Shell commands here
      echo "Running task"
```

## Task Dependencies

Use `before` for parallel dependencies:

```yaml
tasks:
  ci:
    help: "Full CI pipeline"
    before: [lint, check, test]  # These run in parallel
    bash: |
      echo "✅ All CI checks passed!"
```

Otto runs `lint`, `check`, and `test` in parallel, then runs the `ci` task's bash.

## Parameters

Define CLI parameters for tasks:

```yaml
tasks:
  cov:
    help: "Run coverage"
    params:
      --fail-under:
        default: "0"
        help: "Minimum coverage percentage"
    bash: |
      if [ "${fail_under}" != "0" ]; then
        cargo llvm-cov --fail-under-lines "${fail_under}"
      else
        cargo llvm-cov
      fi
```

Usage: `otto cov --fail-under 80`

**Parameter variable names:** Use the flag name without `--` and with `-` replaced by `_`:
- `--fail-under` → `${fail_under}`
- `--output-dir` → `${output_dir}`

## Environment Variables

Define at the top level, available to all tasks:

```yaml
otto:
  envs:
    VERSION: "$(git describe --tags --always --dirty)"
    GIT_SHA: "$(git rev-parse --short HEAD)"

tasks:
  info:
    bash: |
      echo "Version: $VERSION"
      echo "SHA: $GIT_SHA"
```

## Standard Tasks

Every project should have these tasks:

| Task | Purpose |
|------|---------|
| `ci` | Full CI pipeline (runs in GitHub Actions) |
| `check` | Compile + lint + format check |
| `test` | Run all tests |
| `build` | Build release binary |
| `clean` | Remove build artifacts |

### Rust Project Template

```yaml
otto:
  api: 1
  tasks: [ci]
  envs:
    VERSION: "$(git describe --tags --always --dirty)"

tasks:
  lint:
    help: "Run whitespace linting"
    bash: whitespace -r

  check:
    help: "Compile + clippy + format"
    bash: |
      cargo check --all-targets --all-features
      cargo clippy --all-targets --all-features -- -D warnings
      cargo fmt --all --check
      echo "✅ All checks passed!"

  test:
    help: "Run tests"
    bash: cargo test --all-features

  cov:
    help: "Coverage report"
    params:
      --fail-under:
        default: "0"
        help: "Minimum coverage %"
    bash: |
      cargo llvm-cov --all-features --html
      echo "📄 Report: target/llvm-cov/html/index.html"

  ci:
    help: "Full CI pipeline"
    before: [lint, check, test]
    bash: echo "✅ All CI checks passed!"

  build:
    help: "Release build"
    bash: cargo build --release

  clean:
    help: "Clean artifacts"
    bash: cargo clean

  install:
    help: "Install locally"
    bash: cargo install --path .
```

### Python Project Template

```yaml
otto:
  api: 1
  tasks: [ci]

tasks:
  lint:
    help: "Run ruff linter"
    bash: uv run ruff check .

  format:
    help: "Check formatting"
    bash: uv run ruff format --check .

  typecheck:
    help: "Run mypy"
    bash: uv run mypy src/

  test:
    help: "Run pytest"
    bash: uv run pytest

  cov:
    help: "Coverage report"
    bash: |
      uv run pytest --cov=src --cov-report=html
      echo "📄 Report: htmlcov/index.html"

  ci:
    help: "Full CI"
    before: [lint, format, typecheck, test]
    bash: echo "✅ All CI checks passed!"

  clean:
    help: "Clean artifacts"
    bash: |
      rm -rf .pytest_cache .mypy_cache .ruff_cache
      rm -rf htmlcov .coverage
      find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
```

## Built-in Commands

Otto has built-in commands (capitalized):

```bash
otto Graph     # Show task dependency graph
otto History   # View execution history
otto Stats     # View execution statistics
otto Clean     # Clean old runs from ~/.otto/
otto Convert   # Convert Makefile to .otto.yml
otto Upgrade   # Upgrade otto to newer version
```

## Parallel Execution

Otto runs independent tasks in parallel by default:

```bash
otto -j 8 ci   # Limit to 8 parallel jobs (default: 16)
otto -t ci     # Enable TUI dashboard for monitoring
```

## Tips

- **One .otto.yml per project** — Put it in the project root
- **Use `before` for parallelism** — Dependencies run in parallel
- **Keep tasks focused** — One task, one purpose
- **Use `echo` for feedback** — Show progress and results
- **Use ✓/✅/❌ icons** — Visual feedback for success/failure

## Common Patterns

### Conditional execution

```yaml
tasks:
  deploy:
    params:
      --env:
        default: "staging"
    bash: |
      if [ "$env" = "production" ]; then
        echo "🚀 Deploying to PRODUCTION"
        # production deploy
      else
        echo "🧪 Deploying to staging"
        # staging deploy
      fi
```

### Fail fast

```yaml
tasks:
  validate:
    bash: |
      set -e  # Exit on first error
      check_one
      check_two
      check_three
```

### Progress output

```yaml
tasks:
  build:
    bash: |
      echo "=== Building ==="
      cargo build --release
      echo ""
      echo "✅ Build complete"
```

