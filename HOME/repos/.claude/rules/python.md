<!-- WORKAROUND: YAML array syntax for paths: is broken in Claude Code.
     The internal CSV parser receives a JS Array object instead of a string,
     causing path matching to silently fail. Rules never load even when
     matching files are read/written.

     Bug: https://github.com/anthropics/claude-code/issues/26868
       "When I configure a rule file under .claude/rules/*.md with multiple
        entries in the paths array, Claude Code CLI does not handle them
        correctly. It appears that only one path is honored; adding a second
        (or more) path entries causes the rule to not be applied as expected."

     See also: https://github.com/anthropics/claude-code/issues/16853
       "Rules with paths: frontmatter in .claude/rules/ subdirectories are
        never automatically loaded into context when reading or editing files
        that match the specified glob patterns."

     Fix: use comma-separated string format + alwaysApply: false -->
---
alwaysApply: false
paths: "**/*.py, **/pyproject.toml, **/uv.lock, **/.python-version"
---

# Python Coding Conventions

## Package Manager: uv

- Always use `uv` - never pip, poetry, or pipenv
- `uv init`, `uv add`, `uv add --dev`, `uv run`
- Commit `uv.lock` to git

## Code Understanding: pyr

Before modifying unfamiliar Python code, use `pyr` to understand structure:
```bash
pyr dump                    # everything: functions, classes, enums
pyr function                # list all functions with signatures
pyr class                   # classes with fields and methods
pyr -t src/ dump            # target specific directories
```

## Project Structure

```
myproject/
  pyproject.toml
  uv.lock
  .python-version
  .otto.yml
  src/myproject/
    __init__.py
    main.py
  tests/
    conftest.py
    test_main.py
```

- Use `src/` layout
- Build system: `hatchling`
- Python >= 3.11

## Linting and Formatting: ruff

- Use `ruff` for everything - never black, flake8, or isort separately
- `uv run ruff check .` / `uv run ruff check --fix .`
- `uv run ruff format .`
- Line length: 120
- Rules: E, F, I, UP, B, SIM

## Type Hints: mypy strict

- Always use type hints, run mypy in strict mode
- `X | None` not `Optional[X]`
- `list`, `dict`, `set` directly, not `List`, `Dict`, `Set` from typing
- `collections.abc` for abstract types: `Sequence`, `Mapping`, `Iterable`

## Testing: pytest

- `uv run pytest` - never run pytest directly
- Fixtures in `conftest.py`
- Type-annotate test functions with `-> None`

## CLI Applications

- Use `argparse` from standard library
- Entry points via `[project.scripts]` in pyproject.toml

## Docstrings

- Google-style docstrings with Args, Returns, Raises sections

## Error Handling

- Create specific exception classes for your domain
- Use `raise ... from e` to chain exceptions
- Catch specific exceptions, never bare `except:`
- Include context in error messages

## Config Files

| Format | Use Case |
|--------|----------|
| YAML | Human-readable config (preferred) |
| JSON | Machine-generated, API responses |
| TOML | When required (pyproject.toml) |
| XML | Never |

## Logging

- Standard `logging` module
- `logging.basicConfig` with format string

## Imports

- Group: stdlib, third-party, local (ruff handles this with I rule)

## Naming

- `snake_case` for functions, variables
- `PascalCase` for classes
- `UPPER_SNAKE_CASE` for constants
- `_private` prefix for internals

### Module and file names
- Prefer single-word module/file names
- If a name would be compound (e.g. `config_loader.py`), decompose into a package with single-word files:
  - `config_loader.py` -> `config/__init__.py` + `config/loader.py`
  - `data_parser.py` -> `data/__init__.py` + `data/parser.py`
- This creates natural package boundaries and keeps every .py filename one word

## CI

- Use `otto ci` for full CI pipeline (lint + format + typecheck + test)
