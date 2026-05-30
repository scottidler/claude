<!-- WORKAROUND: YAML array syntax for paths: is broken in Claude Code.
     See https://github.com/anthropics/claude-code/issues/26868
     Fix: use alwaysApply: true for catch-all rules -->
---
alwaysApply: true
---

# CLI Conventions

- Cross-language conventions for command-line tool *behavior* (how values are passed, parsed, structured)
- For flag *naming* (hyphens, kebab-case, mirroring config fields), see `general.md`

## List-valued flags — no comma separation

- Use space separation or repeated flags for multi-value flags; never comma separation
- Right: `cmd --fix mistype duplicate raw-title` (space-separated)
- Right: `cmd --fix mistype --fix duplicate --fix raw-title` (repeated flag)
- Wrong: `cmd --fix mistype,duplicate,raw-title` (comma-separated)
- Why: commas are awkward to type, ambiguous when values contain commas/shell specials, and break completion; space/repeated forms follow Unix convention (`grep -e foo -e bar`, `find -name foo -name bar`)
- Hard rule: do not use comma-splitting features (clap `value_delimiter`, click `STRING.split(",")`, etc.)

### Implementation

- Clap (Rust):

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

- Click (Python): `nargs=-1` (variadic positional) or `multiple=True` (repeated option); never split on `,` manually
- argparse (Python): `nargs='*'` or `action='append'`; never `type=lambda s: s.split(',')`

## Enum-valued flags — case-insensitive

- A flag accepting named values (`--fix mistype`, `--log-level debug`) must accept any case: `duplicate`, `Duplicate`, `DUPLICATE` all match
- Why: tools display names in upper/mixed case (`[DUPLICATE]`, `INFO`/`WARN`) and users type back what they saw; forcing one case is friction with no benefit
- Canonical *internal* form is lowercase-hyphenated (per `general.md`); *input* form is whatever the user typed

### Implementation

- Clap (Rust): derive `ValueEnum` with `rename_all = "kebab-case"`, set `ignore_case = true` on the arg

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

- Click (Python): `click.Choice([...], case_sensitive=False)`
- argparse (Python): wrap the type with `lambda s: s.lower()`, or a custom type that lowercases before matching

## No `--dry-run` on opt-in destructive flags

- If a destructive op is gated behind an explicit flag (`--fix`, `--prune`, `--clean`), the user already opted in — don't add a `--dry-run` preview
- Exception: ops whose *default* behavior is destructive (e.g. a `delete` subcommand) may warrant `--dry-run`, since there's no opt-in gate
- For recovery, use archival tools (`rkvr rmrf`, or shell out to `rkvr`) rather than `--dry-run` + irreversible delete — recoverability beats prediction
