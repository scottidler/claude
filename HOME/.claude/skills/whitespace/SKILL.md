---
name: whitespace
description: Remove trailing whitespace from files. Use as a linting step or to clean up code before commits.
allowed-tools: Bash(whitespace:*)
---

# Whitespace

`whitespace` removes trailing whitespace from files with parallel processing for speed.

## Usage

```bash
whitespace                  # Check current directory
whitespace -r               # Recursive
whitespace -r src/          # Specific directory
whitespace --dry-run        # Preview changes without modifying
whitespace -r .             # Common: recursive from current dir
```

## Options

- `-r, --recursive`: Process subdirectories
- `-n, --dry-run`: Show what would be changed without modifying files
- `-t, --threads N`: Number of parallel threads (default: CPU count)
- `-c, --config FILE`: Custom config file

## Output

```bash
$ whitespace -r src/
src/main.rs (12-14,28)
src/lib.rs (5,7-9)

🧹 2 files cleaned
```

Shows:
- Files with changes
- Line numbers (ranges collapsed: `12-14` instead of `12,13,14`)
- Summary with count

## Integration with Otto

Add to `.otto.yml` as a lint step:

```yaml
tasks:
  lint:
    help: "Run linting checks"
    bash: "whitespace -r"
```

## Configuration (`~/.config/whitespace/whitespace.yml`)

```yaml
processing:
  threads: 8

patterns:
  include:
    - "*.rs"
    - "*.py"
    - "*.js"
  exclude:
    - "*.min.js"
    - "target/"
    - "node_modules/"
```

## Exit Codes

- `0`: No trailing whitespace found (or all cleaned)
- Non-zero: Files had trailing whitespace (useful for CI)

