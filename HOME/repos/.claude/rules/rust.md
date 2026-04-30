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
paths: "**/*.rs, **/Cargo.toml, **/Cargo.lock, **/build.rs, **/clippy.toml"
---

# Rust Coding Conventions

## Project Setup

- Use `scaffold <name>` for new CLI projects, never `cargo new`
- Use `cargo add` for dependencies - never edit Cargo.toml versions directly. This ensures the latest version, not whatever the LLM remembers from training
- Edition 2024 - do not comment on it, fuss about it, or attempt to change it

## Architecture: Shell/Core Split

- `main.rs` is a thin shell: parse args, call lib, print results, map errors to exit codes
- `lib.rs` holds all business logic, fully testable
- Core functions return `Result<T>` - never call `process::exit` or print to stdout/stderr from core
- Return structured data (e.g. `RunResult`), not side effects
- Don't wedge unrelated logic into lib.rs - split into focused modules (e.g. `age.rs`, `config.rs`)

```
src/
  main.rs    # thin shell
  lib.rs     # core logic
  cli.rs     # clap structs only
  config.rs  # validation, defaults
  ports/     # traits for external deps
```

## CLI: Clap Derive

- Two-stage: `Cli` (parsing only) -> `Config` (validation + defaults via `TryFrom`)
- Test `Config` validation, not clap parsing
- Use `GIT_DESCRIBE` from build.rs for version, not `CARGO_PKG_VERSION`
- `--help` should show required external tool dependencies and XDG log path

## Error Handling

- CLIs: `eyre::Result` with `.context()` - never `anyhow`
- Libraries: `thiserror` with typed error enums consumers can match on
- Never use `.unwrap()` in production code - only allowed in `#[cfg(test)]` blocks
- `.expect("reason")` is acceptable in production when justified with a clear reason
- Chain exceptions with `#[from]` and contextual messages
- Never `anyhow` or `thiserror` in CLI code - eyre only

## Naming and Style

### File and module names
- Maximum file size: 1500 lines per .rs file - if a file exceeds this, decompose it into a module directory (see `rules/dealing-with-large-files.md` for safe decomposition technique)
- No underscores in .rs filenames - every source file should be a single word
- If a name would be compound, decompose it into a module directory with single-word files inside:
  - `config_loader.rs` -> `config/mod.rs` + `config/loader.rs`
  - `borg_log.rs` -> `borg/log.rs` (or rethink whether `borg` is already the module)
- This keeps every .rs filename one word and creates natural module boundaries

### Module style: mod.rs vs Rust 2018
- Use the **Rust 2018+ style** throughout: the module entry point is `foo.rs`, submodules live in `foo/` alongside it
- Do NOT mix styles within the same codebase - consistency matters more than which style is chosen
- The pre-2018 `mod.rs` style is valid but creates "sea of `mod.rs` tabs" confusion in editors; migrating away from it is a tree-wide mechanical pass, never mixed into a feature or decomposition refactor
- When decomposing a large file `foo.rs` into a module: keep `foo.rs` as the entry point, extract submodules into `foo/*.rs`

### Variable names
- NEVER prefix variables with `_` to suppress unused warnings - this is a crutch that hides real problems
- The only exception is bare `_` for genuinely discarded values (e.g. `let _ = sender.send(...)`)
- Unused variables must be removed or wired up, not silenced

### Dead code
- NEVER use `#[allow(dead_code)]` - dead code must be removed or connected
- During active transitions this can be temporarily tolerated, but must be cleaned up before code is considered complete

### Naming consistency across layers
- NEVER use different names for the same concept across struct fields, JSON keys, and IPC params
- If a handler expects `target_status`, the struct field and variable name must also be `target_status`

### Constants - no magic numbers in production code
- NEVER hardcode numeric literals for durations, timeouts, intervals, sizes, or limits in production code
- Define a module-level `const` with an ALL_CAPS name instead: `const POLL_INTERVAL_MS: u64 = 100;`
- Tests are exempt - inline literals in `#[cfg(test)]` blocks are fine
- If the value is user-tunable, expose it as a config field that defaults to the const

### Imports
- NEVER use `use foo::Bar as _;` to bring a trait into scope just to call its methods. The `as _` form is unreadable noise that hides what's actually being imported. If a trait method is needed, write `use foo::Bar;` plainly. If the only reason a trait is being imported is to enable a fallback that isn't actually needed, delete the fallback instead - the absence of the import is evidence the code was wrong.

### General
- Imports grouped: std, external crates, internal modules
- Line length under 100 chars
- Always use `cargo fmt`, never `rustfmt` directly

## Config and Serialization

### YAML/config field naming
- Config file fields use hyphens, not underscores (e.g. `log-level`, not `log_level`)
- Use `serde(rename)` or `#[serde(rename_all = "kebab-case")]` to translate to Rust's snake_case
- Add a comment in scaffold config templates showing this convention

### Serde alignment
- Struct field names must align with their serialized JSON/YAML key names - don't rename unless converting kebab-case to snake_case
- If the JSON key is `tool`, the struct field is `tool` - not something different

### Config format
- YAML for human-readable config - never TOML (except Cargo.toml where required)
- JSON for machine/pipeline output
- Detect terminal with `std::io::IsTerminal` to choose format

### Config precedence
- CLI flags > environment variables > config file values
- Config at `dirs::config_dir()/<project>/<project>.yml` (Linux: `~/.config/`, macOS: `~/Library/Application Support/`)
- Config defines WHAT rules look like, not WHETHER they run - scope is controlled via CLI flags, not `enabled: true/false` in config

### Platform path testing

Every CLI project must test platform path resolution in `src/config/tests.rs`:

```rust
#[test]
fn test_platform_config_dir_resolves() {
    assert!(dirs::config_dir().is_some());
}

#[cfg(target_os = "macos")]
#[test]
fn test_macos_config_dir_is_library_application_support() {
    let home = std::env::var("HOME").unwrap();
    let expected = std::path::PathBuf::from(home).join("Library").join("Application Support");
    assert_eq!(dirs::config_dir().unwrap(), expected);
}

#[cfg(target_os = "linux")]
#[test]
fn test_linux_config_dir_defaults_to_home_config() {
    if std::env::var("XDG_CONFIG_HOME").is_err() {
        let home = std::env::var("HOME").unwrap();
        let expected = std::path::PathBuf::from(home).join(".config");
        assert_eq!(dirs::config_dir().unwrap(), expected);
    }
}
```

When testing `Config::load()` via the platform path (not an explicit path), set `XDG_CONFIG_HOME` to a tempdir on Linux. On macOS `dirs::config_dir()` uses system APIs and ignores `$HOME` - use explicit paths for full isolation in tests that load config.

Note: env var mutation is not safe with parallel tests. If a test sets `XDG_CONFIG_HOME`, run that test file with `RUST_TEST_THREADS=1` or add the `serial_test` crate.

The scaffold generates these tests automatically in `src/config/tests.rs`.

### Platform-native paths via `dirs` - When in Rome

Use the `dirs` crate for config and data directories. It returns platform-native paths: on Linux it follows XDG (`$XDG_CONFIG_HOME` / `~/.config`, `$XDG_DATA_HOME` / `~/.local/share`); on macOS it uses `~/Library/Application Support`. This is correct - do not override it.

- Config: `dirs::config_dir().join(project_name).join(format!("{}.yml", project_name))`
- Logs: `dirs::data_local_dir().join(project_name).join("logs")`

**NEVER hardcode `~/.config/` or `~/.local/share/` in user-facing strings.** Those paths are Linux-specific. Error messages, `after_help` text, and log output must use the runtime-computed value from `dirs`, not a hardcoded string. A hardcoded `~/.config/` on macOS tells users to put config in the wrong place - the code will never find it.

## Logging

- Custom `--log-level`/`-l` CLI flag - NEVER use `RUST_LOG` env var
- Log to `dirs::data_local_dir()/<project>/logs/<project>.log`
- Use `env_logger` with file target

### Function-level instrumentation (mandatory)

Every non-trivial function must log its entry at the appropriate level:

- `debug!` at the top of every async handler, pipeline stage, and background worker
- Include function name and key params: `debug!("my_fn: param_a={} param_b={:?}", a, b);`
- Completion points (doc counts, item counts, status) log at `info!` or `debug!`
- Tight loops that would spam (per-item validation, per-record iteration) use `trace!`
- `warn!` for recoverable failures (retry paths, skipped items, partial results)
- `error!` / `bail!` for unrecoverable failures that propagate out

The guiding principle: at `debug` level the log should tell the full story of a pipeline run - what entered, what was produced, what was skipped - without reading the source.

### Function-level instrumentation with `tracing` (when a project overrides the `log` default)

When a project uses `tracing` + `tracing-subscriber` instead of `log` + `env_logger` (e.g., multi-crate daemons, async services needing span hierarchy that survives across tasks — justify the override in the project's vision doc), use `#[tracing::instrument]` on function declarations instead of hand-rolled `debug!("fn_name: a={a}")` calls.

**The default pattern:**

```rust
#[tracing::instrument(level = "debug", skip_all, fields(work_id = %work.id, plan_id = %plan.id, dep_count = deps.len()))]
pub fn run_implementer(work: &Work, plan: &Plan, deps: &Deps<...>) -> Result<Bundle> {
    // warn!/error! inside inherit work_id/plan_id/dep_count automatically
}
```

**Rules:**

1. **`skip_all` + explicit `fields(...)`, never bare `#[instrument]`.** The default captures every parameter via `Debug`, which pulls full records, prompts, and stdouts into span fields - expensive, noisy, occasionally leaks secrets. `skip_all` then list the specific fields you want.
2. **`level = "..."` matches function role.** Entry-level orchestrators → `info`. Per-iteration helpers → `debug`. Tight-loop helpers → `trace`. The span's level gates both the span and events emitted inside it.
3. **`%var` for `Display`, `?var` for `Debug`.** Prefer `%` when the type has a meaningful `Display` (typed IDs, paths). Use `?` when only `Debug` exists.
4. **`ret` and `err` when the outcome matters.** `#[instrument(ret, err)]` logs the return at span close and auto-logs `Err` variants at `error!`. Use on FSM transitions, store writes, external-call wrappers.
5. **Required fields by scope (project-specific — generalize from your domain):** every function should carry the identifying keys of its scope as span fields, so `warn!`/`error!` emissions inside inherit them. Missing a scope key forces log-reconstruction - exactly what this section exists to prevent.

**Why this matters for `warn!` / `error!` specifically:** `tracing` events inside an instrumented function inherit the enclosing span's fields automatically. An event emitted inside `run_implementer` above renders as:

```
 WARN ralph.implementer{work_id=w-00042 plan_id=p-0007 dep_count=3}: crate::agents: retrying after tool failure
```

The emission site doesn't restate the fields. Adding a new parameter to the `#[instrument]` attribute propagates context to every `warn!`/`error!` inside without touching the call sites.

**When NOT to use `#[tracing::instrument]`:** tiny pure helpers, `Drop` impls (deadlock risk if subscriber's writer is held by a panicking thread), `impl Display`/`impl Debug` on hot types (recursion risk). For those, emit `tracing::debug!` / `warn!` directly with inline fields.

## Dependency Injection

- Use generics for DI, never `dyn` trait objects or `Box<dyn ...>`
- Small purpose-built traits (ports): `FileSystem`, `ConfigFetcher`, `MailStore`
- Test fakes (`MemFs`, `MockConfigFetcher`), not mocks
- `Deps<F, H, M>` struct when many dependencies

## Core Dependencies

| Purpose | Crate |
|---------|-------|
| CLI parsing | `clap` (derive feature) |
| Error handling | `eyre` (CLIs) / `thiserror` (libs only) |
| Logging | `log` + `env_logger` |
| Serialization | `serde` + `serde_yaml` |
| JSON | `serde_json` |
| Async | `tokio` (full feature) |
| Parallelism | `rayon` |
| Colors | `colored` |
| Directories | `dirs` |

## Crate-Level Deny Attributes

Scaffold templates enforce these at the crate root:
- `#![deny(clippy::unwrap_used)]` - catches unwraps in production code; tests get `#[allow(clippy::unwrap_used)]`
- `#![deny(dead_code)]` - use `deny` not `forbid` (forbid breaks derive macros)
- `#![deny(unused_variables)]` - prevents the `_variable` crutch

## Clippy

- Configure `clippy.toml` to not limit function arguments (`too-many-arguments-threshold`)
- The scaffold project provides the standard clippy.toml
- Clippy runs with `-D warnings` (deny all warnings) in CI

## Testing

- Unit tests with injected fakes are the default
- `.unwrap()` is allowed in test code
- E2E tests sparingly - smoke tests only ("does the binary run?")
- Use `tempfile::TempDir` when real filesystem is needed
- Test edges and errors, not just happy path
- Shared test fixtures: create reusable mini-environments (e.g. mini-vaults in /tmp) with complete isolation between tests

### Test file placement

- Tests live in their own files, NEVER as `#[cfg(test)] mod tests { ... }` blocks at the bottom of a source file
- Use the Rust 2018+ submodule pattern:
  - For module `src/foo.rs`, declare `#[cfg(test)] mod tests;` at the bottom (just the declaration), and put the test bodies in `src/foo/tests.rs`
  - For the crate root (`src/lib.rs`), declare `#[cfg(test)] mod tests;` and put bodies in `src/tests.rs`
  - Inside the test file, `use super::*;` gives access to the parent module's private items (submodule privilege is preserved across the file boundary)
- Rationale: keeps production source files focused on production code; test bodies and fixtures can grow without blowing out the main file's line count; cleaner diffs and blame on `src/foo.rs`; matches the 2018+ module style used everywhere else in the tree
- This is NOT optional - inline `mod tests` blocks are drift and must be extracted on sight

## Async vs Sync

| Scenario | Approach |
|----------|----------|
| I/O-bound | async (tokio) |
| CPU-bound, independent items | `par_iter` (rayon) |
| Simple, sequential | sync |

## Workspaces

- Use Cargo workspaces when multiple related binaries share code
- Look at `git-tools` or `aws-tools` repos for workspace patterns
- Shared schema/types go in a common crate within the workspace
- `.otto.yml` must be adapted for workspace builds

## CI

- Use `otto ci` for full CI pipeline (lint + check + test)
- `otto cov` for coverage (not part of ci, runs separately)
- `cov-report` follows `cov` as an "after" task

## Version Bumping

- Use the `bump` CLI tool, never manually edit version in Cargo.toml
- `bump` (patch), `bump -m` (minor), `bump -M` (major)
- Ship flow: commit, `bump -a`, `git push && git push --tags`, `cargo install --path .`
- Daemon binaries need `systemctl --user restart <service>` after install

## Development Process

- Create a design doc first (`/create-design-doc`) then execute via `/how-to-execute-a-plan` - don't jump straight to code for non-trivial features
- Prototype before wrapping - try running bare commands first to verify they work before building Rust wrappers around them
- When scaffolding, verify with `otto ci` immediately - a fresh scaffold should pass out of the gate
- All crates added via `cargo add` to get latest versions, not training-data versions
