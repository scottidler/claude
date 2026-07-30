---
paths:
  - "**/*"
---

# Safety Rules

## File Deletion

- NEVER use `rm` or `rm -rf`. Always use `rkvr rmrf` instead. This archives files before deleting, enabling recovery if needed.
- No exceptions. Even for temp files or known-safe deletions, use `rkvr rmrf`.

## Formatting

- NEVER use em dashes (the U+2014 character) in any output. Use `--`, a colon, parens, a comma, or split the sentence. Replacements per `rules/voice.md`; pick per site, never a blanket substitution.
- **Scope is everything, and SOURCE CODE IS IN SCOPE.** Documentation, code comments (`//`, `///`, `//!`, `#`, docstrings), string literals, Confluence, Jira, Slack, PR titles and bodies, commit messages, config files, and any external system. There is no code exemption.
  - This used to say "documentation, comments, Confluence, Jira, Slack, or any external system" and left code *implicit*. On 2026-07-30 `tatari-tv/clyde` was measured at **373 em-dash occurrences across 79 `.rs` files**, overwhelmingly in comments: the tree had read the silence as an exemption. Scott's call that day: "yes ammend and kill all em-dashes." Hence the explicit enumeration.
- **A convention with no lint re-accumulates**, which is why enforcement is a CI check and not this file alone. Repos enforce it in the `.otto.yml` `lint` task:

  ```
  if rg -n --type rust -g '!target' '\x{2014}' .; then
    echo "❌ Found em dash in Rust source."
    exit 1
  fi
  ```

  Scope the lint to the whole tree, not `*/src/`: 17 of clyde's 373 lived in `*/tests/` integration files, which a `grep -r … */src/` shape never walks. A lint narrower than the rule is a hole the tree drifts back through where CI cannot see it. `\x{2014}` keeps the lint file itself em-dash-free.
- The one legitimate need for the character in code is an assertion that em-dashes are ABSENT. Write it as `'\u{2014}'` so the assertion survives and the tree still carries no literal.

## Python Package Management

- NEVER use `pip install`. EVER. Always use `pipx` for installing Python tools/packages. No exceptions.

## Rust CLI Overrides

- A Rust variant of `tail` is installed at `~/.cargo/bin/tail` and shadows `/usr/bin/tail`. It has incompatible flags. In Bash commands, always use `/usr/bin/tail` instead of bare `tail`.
