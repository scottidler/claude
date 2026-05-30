<!-- WORKAROUND: YAML array syntax for paths: is broken in Claude Code.
     See https://github.com/anthropics/claude-code/issues/26868
     Fix: use alwaysApply: true for catch-all rules -->
---
alwaysApply: true
---

# CLI Conventions

Cross-language conventions for command-line tool behavior.

For flag *naming* (hyphens, kebab-case, mirroring config fields), see `general.md`. This file covers flag *behavior*: how values are passed, parsed, and structured.

## List-valued flags - no comma separation

When a flag accepts multiple values, use **space separation** or **repeated flags**. Never comma separation.

- Right: `cmd --fix mistype duplicate raw-title` (space-separated)
- Right: `cmd --fix mistype --fix duplicate --fix raw-title` (repeated flag)
- Wrong: `cmd --fix mistype,duplicate,raw-title` (comma-separated)

Why: commas in CLI args are awkward to type, ambiguous when values can themselves contain commas or shell special characters, and break shell completion. Space-separated and repeated-flag forms follow standard Unix convention (`grep -e foo -e bar`, `find ... -name foo -name bar`, `xargs -I {} ...`).

This is a hard rule. Even when a clap/click/argparse feature exists to enable comma-splitting (clap's `value_delimiter`, click's `type=click.STRING.split(",")`, etc.), do not use it.

### Implementation

**Clap (Rust):**

```rust
// Right: space-separated, optional (no flag = None, --fix alone = Some(vec![]))
#[arg(long, num_args = 0..)]
fix: Option<Vec<String>>,

// Right: repeated flag
#[arg(long, action = ArgAction::Append)]
fix: Vec<String>,

// Wrong - never do this
#[arg(long, value_delimiter = ',')]
fix: Vec<String>,
```

**Click (Python):** use `nargs=-1` for variadic positional, or `multiple=True` for repeated option. Do not split on `,` manually.

**argparse (Python):** `nargs='*'` or `action='append'`. Do not use `type=lambda s: s.split(',')`.

## Enum-valued flags - case-insensitive

When a flag accepts a set of named values (e.g. `--fix mistype duplicate`, `--log-level debug`), the parser must accept any case. `duplicate`, `Duplicate`, and `DUPLICATE` all match the same value.

Why: tools often display the names in upper or mixed case for emphasis (audit output's `[DUPLICATE]`, log filter's `INFO`/`WARN`), and users will naturally type back what they saw. Forcing one canonical case creates friction with zero semantic benefit. The canonical *internal* form is lowercase-hyphenated (per `general.md`); the *input* form is whatever the user typed.

### Implementation

**Clap (Rust):** derive `ValueEnum` with `rename_all = "kebab-case"`, and set `ignore_case = true` on the arg.

```rust
#[derive(ValueEnum, Clone)]
#[clap(rename_all = "kebab-case")]
enum FixKind {
    Mistype,
    OrphanReplace,
    Blocked,
    RawTitle,
    Duplicate,
}

#[arg(long, num_args = 0.., ignore_case = true)]
fix: Option<Vec<FixKind>>,
```

**Click (Python):** `click.Choice([...], case_sensitive=False)`.

**argparse (Python):** wrap the type with `lambda s: s.lower()` or use a custom type that lowercases before matching.

## No `--dry-run` on opt-in destructive flags

If a destructive operation is gated behind an explicit flag (`--fix`, `--prune`, `--clean`), the user has already opted in. Don't add a `--dry-run` that previews what would happen. The user knows the consequences when they pass the flag.

Exception: operations whose default behavior is destructive (e.g. a `delete` subcommand that always deletes) may warrant a `--dry-run` because there's no opt-in gate.

When destructive operations need recovery, use archival tools (`rkvr rmrf` in shell, or shell out to `rkvr` from Rust/Python) rather than `--dry-run` + irreversible delete. Recoverability beats prediction.
