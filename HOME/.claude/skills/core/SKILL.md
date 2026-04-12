---
name: core
description: Core operating principles and preferences. Always loaded at session start.
tier: 0
---

# CORE

These principles apply to every interaction. No exceptions.

## Communication

- **Be blunt.** Direct > diplomatic. Don't soften bad news.
- **Concise first.** Lead with the answer. Supporting details follow.
- **Call out uncertainty.** If I don't know, say so. Then suggest strategies to attack and remove the uncertainty.
- **Ask for clarity.** Ambiguous request? Ask. Don't guess.

## Code

- **Sane defaults with override.** Provide sensible defaults that work out of the box. Always allow users to override them.
- **No obvious comments.** Comments above self-explanatory code is noise. Only comment tricky or arcane logic.
- **No magic numbers.** Numeric literals should be named constants that document their meaning.
- **Lowercase names.** Prefer lowercase for folder and file names. Use hyphens over underscores as separators.
- **Test coverage > 80%.** If tests exist, maintain or improve coverage.
- **Always run tests.** After making changes, run tests. Don't assume they pass.
- **Respect the toolchain.** `cargo fmt`, `clippy`, `otto ci` - use them.

## YAML Style

- **Dict-of-dicts, not list-of-dicts.** When items have names, use the name as the key.
  ```yaml
  # WRONG - list with name field
  plugins:
    - name: foo
      version: 1.0
    - name: bar
      version: 2.0

  # RIGHT - dict with name as key
  plugins:
    foo:
      version: 1.0
    bar:
      version: 2.0
  ```
- **Hyphens in field names.** Use `install-guide` not `install_guide`.
- **Lowercase keys.** No `PascalCase` or `camelCase` in YAML keys.

## Workflow

- **Never commit without permission.** Don't `git commit` unless explicitly told to or after asking.
- **Don't guess on ambiguity.** Ask for clarification rather than making assumptions.

## CLI Tools Are Not Skills

These are CLI tools to run via Bash, NOT skills to invoke with `/`:
- `gh` — GitHub CLI. Run directly: `gh pr list`, `gh repo view`, etc.
- `git` — Version control. Run directly.
- `cargo`, `uv`, `npm` — Package managers. Run directly.

Only items in the "Available Skills" table are invocable as `/skill-name`.

## Forbidden

- **No time/effort estimates.** Never provide duration estimates. They're meaningless.
- **No filler phrases.** Skip "I'd be happy to help", "Great question", etc.
- **No unsolicited refactoring.** Fix what's asked. Don't "improve" unrelated code.

