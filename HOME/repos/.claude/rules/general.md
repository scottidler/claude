---
paths:
  - "**/*"
---

# General Coding Conventions

Cross-language preferences that apply to all projects.

## Naming Conventions

The universal rule: **lowercase, hyphenated, prefer single words**.

### Directories
- `bin/` for scripts and executables, never `scripts/`
- All directories lowercase, hyphenated when multi-word
- Prefer single-word directory names when possible
- Never concatenate words (e.g. `configloader/`) - hyphenate if needed (`config-loader/`) but prefer single words (`config/`)

### Files
- Lowercase, hyphenated for docs, configs, shell scripts, and non-code files
- No spaces in filenames, ever - "drives me bonkers"
- No underscores - hyphens always (except where language convention requires it: Rust/Python source files use snake_case)
- Prefer single-word filenames over compound names
- Examples: `design-doc.md`, `deploy-config.yml`, `run-tests.sh`

### Source files: decompose compound names into modules
- If a source file name would be compound (two+ words), turn it into a module directory instead
- The first word becomes the module/package directory, the second word becomes a single-word file inside it
- This applies to Rust (.rs) and Python (.py) - see language-specific rules for details
- Example: instead of `config_loader.py` -> `config/__init__.py` + `config/loader.py`
- Example: instead of `config_loader.rs` -> `config/mod.rs` + `config/loader.rs`
- If you can't name it in one word, it's probably a module boundary, not a longer filename

### YAML/JSON/config keys
- Hyphens, not underscores (e.g. `log-level`, not `log_level`)
- Language deserializers handle the translation to underscores (e.g. serde `rename_all = "kebab-case"`)

### CLI flags
- Long flags use hyphens: `--log-level`, `--dry-run`, `--preserve-paths`
- Same naming as the corresponding config file field

### Branch names
- Lowercase, hyphenated: `fix-auth-bug`, `add-viewport-support`

### Slugs and generated titles
- Lowercase, hyphenated
- For auto-generated titles, use an LLM to extract 3-5 most significant words, then slugify

## Documentation

- Design docs at `docs/design/YYYY-MM-DD-feature-name.md`
- All doc filenames lowercase, hyphenated
- No ALL CAPS filenames (e.g. `changelog.md` not `CHANGELOG.md`) except `CLAUDE.md`

## Config Files

- YAML for human-readable config - never TOML (except where tooling mandates it like Cargo.toml, pyproject.toml)
- Config lives at `~/.config/<project>/<project>.yml`
- Config precedence: CLI flags > environment variables > config file > defaults
- Config defines WHAT rules look like, not WHETHER they run - scope is controlled via CLI flags

## Dependencies

- Never add dependencies from LLM training memory - always use the package manager's add command to get the latest version
  - Rust: `cargo add`
  - Python: `uv add`
  - JS/TS: whatever the project uses (npm/pnpm/yarn)

## CI

- Use `otto ci` for full CI pipeline
- `whitespace -r` in every lint task across all project types

## Version Control

- Commit messages: concise, focused on the "why"
- Use `bump` for version bumping
