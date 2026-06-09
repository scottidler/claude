<!-- WORKAROUND: YAML array syntax for paths: is broken in Claude Code.
     See https://github.com/anthropics/claude-code/issues/26868
     Fix: use alwaysApply: true for catch-all rules -->
---
alwaysApply: true
---

# General Coding Conventions

- Cross-language preferences that apply to all projects

## Naming Conventions

- Universal rule: **lowercase, hyphenated, prefer single words**

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
- NEVER embed expected/future version numbers in doc filenames or content as release predictions — bumping drifts (a commit sneaks in, a different bump level, a skipped release), and readers grepping the version hit the wrong doc
  - Fine: versions that are historical facts when written — `shakedown-v0.6.4.md` (the shaken-down version already existed)
  - Fine: "the next patch release," "the release that lands these fixes," "the follow-up release"
  - Not fine: filenames or doc bodies that pre-name a release before it is cut
  - To record which version shipped the work, add it after the fact — `Shipped in: v0.6.5` once the tag exists

## Config Files

- YAML for human-readable config - never TOML (except where tooling mandates it like Cargo.toml, pyproject.toml)
- Config lives at `~/.config/<project>/<project>.yml`
- Config precedence: CLI flags > environment variables > config file > defaults
- Config defines WHAT rules look like, not WHETHER they run - scope is controlled via CLI flags
  - **Carve-out: selecting which algorithm/methodology is *active* is legitimate config.** The rule above forbids gating whether a fixed *governance rule* runs (that is CLI-flag scope). It does NOT forbid choosing the system's behavior - e.g. which retrieval methods/stages a server composes for a query. Selecting the active methodology IS the shape of the config, and an explicit `enabled: true/false` per method is the clearest expression of it. This applies when there is no per-invocation CLI surface to carry the choice (e.g. an MCP server whose queries arrive over the protocol, not the command line). Reference: `second-brain/docs/design/2026-06-06-configurable-retrieval-pipeline.md`.

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
