---
name: dashify
description: Normalize filenames by lowercasing and replacing spaces/underscores with dashes. Use when cleaning up file names.
allowed-tools: Bash(dashify:*)
---

# Dashify

`dashify` normalizes filenames by:
- Converting to lowercase
- Replacing spaces, underscores, and commas with dashes
- Collapsing multiple dashes into one
- Removing leading/trailing dashes

## Usage

```bash
dashify "My File Name.txt"     # Renames to: my-file-name.txt
dashify .                      # Process all files in current directory
dashify -r ~/Downloads         # Recursively process directory
dashify file1.txt file2.txt    # Process specific files
```

## Examples

| Before | After |
|--------|-------|
| `My Document.pdf` | `my-document.pdf` |
| `CAPS_LOCK_FILE.txt` | `caps-lock-file.txt` |
| `weird,,file___name.md` | `weird-file-name.md` |
| `File With  Spaces.txt` | `file-with-spaces.txt` |

## Options

- `-r, --recursive`: Process files in subdirectories

## Use Cases

- Clean up downloaded files
- Normalize project assets
- Prepare files for web servers (URL-friendly names)
- Standardize naming conventions

