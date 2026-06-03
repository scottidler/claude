---
paths:
  - "**/*.rs"
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
- Bare `_` is allowed for genuinely discarded values (e.g. `let _ = sender.send(...)`)
- Unused variables must be removed or wired up, not silenced
- **Drop-guard exception:** RAII guards whose entire purpose is their `Drop` side-effect (mutex guards, tracing-subscriber guards, telemetry guards, scoped-id guards) MAY be bound as `let _guard = ...` or `let _name = ...`. The compiler warns even for `Drop` types; the underscore keeps the binding alive for the scope while signaling "no by-name use intended; work happens on Drop." Do NOT use bare `let _ = ...` for guards - that drops the temporary immediately and defeats the guard.
  - Examples in this codebase: `let _guard = self.update_lock.lock().await;` (`store/bundles.rs`, `store/works.rs`), `let _g = tracing::subscriber::set_default(sub);` (test fixtures), `let _id_guard = ScopedIdGuard::new(...);` (daemon spawn-task wrappers)
  - This is the only place the `_name` prefix is acceptable; any other use is the crutch this rule forbids

### Dead code
- NEVER use `#[allow(dead_code)]` - dead code must be removed or connected
- During active transitions this can be temporarily tolerated, but must be cleaned up before code is considered complete

### Naming consistency across layers
- NEVER use different names for the same concept across struct fields, JSON keys, and IPC params
- If a handler expects `target_status`, the struct field and variable name must also be `target_status`

### Collection type names: plural-s, not "List" suffix
- When a type represents a collection, use the plural form rather than appending `List`
- Prefer `Plans` over `PlanList`, `RecordsResult` over `RecordListResult`, `Bundles` over `BundleList`
- The plural-s already carries "collection of"; `List` is noise
- Applies to struct names, enum variant names, and IPC method/result names
- Exception: stdlib / ecosystem conventions that use `List` as a specific type (e.g. `LinkedList`) stay as-is

### Constants - no magic numbers in production code
- NEVER hardcode numeric literals for durations, timeouts, intervals, sizes, or limits in production code
- Define a module-level `const` with an ALL_CAPS name instead: `const POLL_INTERVAL_MS: u64 = 100;`
- Tests are exempt - inline literals in `#[cfg(test)]` blocks are fine
- If the value is user-tunable, expose it as a config field that defaults to the const

### Imports
- NEVER use `use foo::Bar as _;` to bring a trait into scope just to call its methods - the `as _` form is unreadable noise that hides what's imported; write `use foo::Bar;` plainly
- If the only reason to import a trait is to enable a fallback that isn't needed, delete the fallback instead - the absent import is evidence the code was wrong

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
- Config at `xdg_config_dir()/<project>/<project>.yml` - `~/.config/` (or `$XDG_CONFIG_HOME`) on every platform, macOS included (see "Platform paths" below; do NOT use `dirs::config_dir()`)
- Config defines WHAT rules look like, not WHETHER they run - scope is controlled via CLI flags, not `enabled: true/false` in config

### Platform path testing

- Every CLI project must test path resolution in `src/config/tests.rs` - assert the env-honoring behavior and the `$HOME` fallback, NOT a platform-specific path (no `#[cfg(target_os)]` branches, no `~/Library/Application Support` assertion):

```rust
use std::sync::Mutex;

// Serialize all env-var-touching tests to prevent parallel races.
static ENV_LOCK: Mutex<()> = Mutex::new(());

#[test]
fn test_xdg_data_dir_honors_env_and_falls_back() {
    let guard = ENV_LOCK.lock().unwrap();
    let prior = std::env::var("XDG_DATA_HOME").ok();

    let dir = TempDir::new().unwrap();
    unsafe { std::env::set_var("XDG_DATA_HOME", dir.path()) };
    assert_eq!(xdg_data_dir().as_deref(), Some(dir.path()));

    // Unset -> fall back to $HOME/.local/share, never ~/Library/... on mac.
    unsafe { std::env::remove_var("XDG_DATA_HOME") };
    assert!(xdg_data_dir().unwrap().ends_with(".local/share"));

    match prior {
        Some(v) => unsafe { std::env::set_var("XDG_DATA_HOME", v) },
        None => unsafe { std::env::remove_var("XDG_DATA_HOME") },
    }
    drop(guard);
}
```

- Env-var mutation isn't safe with parallel tests - serialize every env-touching test behind a `static ENV_LOCK: Mutex<()>` (shown above), or run the file with `RUST_TEST_THREADS=1`. Edition 2024 requires `unsafe {}` around `set_var` / `remove_var`
- The scaffold generates these tests automatically in `src/config/tests.rs` (one each for `xdg_config_dir` and `xdg_data_dir`)

### Platform paths: XDG on every platform via helpers

- Resolve config and data/log directories to the XDG layout on EVERY platform, **including macOS** - via `xdg_config_dir()` / `xdg_data_dir()` helpers, NOT the `dirs` crate's `config_dir()` / `data_local_dir()`
- Why: `dirs::config_dir()` / `dirs::data_local_dir()` honor `$XDG_CONFIG_HOME` / `$XDG_DATA_HOME` **only on Linux**. On macOS they call system APIs and return `~/Library/Application Support`, ignoring the env vars; so a tool that advertises `~/.local/share/<proj>/logs/...` in `--help` is lying on a Mac, and config the user drops in `~/.config` is silently never found. This bit `tatari-tv/pagerduty-cli` (logs landed in `~/Library/Application Support`)
- The scaffold generates these helpers into `src/config.rs`:

```rust
/// XDG config dir, honoring `$XDG_CONFIG_HOME` and falling back to `$HOME/.config`.
fn xdg_config_dir() -> Option<PathBuf> {
    if let Ok(dir) = std::env::var("XDG_CONFIG_HOME") {
        let path = PathBuf::from(dir);
        if path.is_absolute() {
            return Some(path);
        }
    }
    dirs::home_dir().map(|h| h.join(".config"))
}

/// XDG data dir, honoring `$XDG_DATA_HOME` and falling back to `$HOME/.local/share`.
pub fn xdg_data_dir() -> Option<PathBuf> {
    if let Ok(dir) = std::env::var("XDG_DATA_HOME") {
        let path = PathBuf::from(dir);
        if path.is_absolute() {
            return Some(path);
        }
    }
    dirs::home_dir().map(|h| h.join(".local").join("share"))
}
```

- Config: `xdg_config_dir().join(project_name).join(format!("{}.yml", project_name))`
- Logs: `xdg_data_dir().join(project_name).join("logs")`
- `dirs::home_dir()` is still fine; it is correct on every platform; only `dirs::config_dir()` / `dirs::data_local_dir()` are banned
- `after_help` SHOULD advertise the log path (`~/.local/share/<proj>/logs/<proj>.log`); the helpers make that hardcoded string true on every platform; you do NOT need to interpolate a runtime value to be "honest," the XDG path is now the real path
- Reference implementation: `tatari-tv/pagerduty-cli` (`src/config.rs`); the `scaffold` tool itself dogfoods the same helpers

## Logging

- Custom `--log-level`/`-l` CLI flag - NEVER use `RUST_LOG` env var
- Log to `xdg_data_dir()/<project>/logs/<project>.log` (XDG on every platform, NOT `dirs::data_local_dir()`; see "Platform paths" above)
- Use `env_logger` with file target

### Function-level instrumentation (mandatory)

- The language-agnostic "every function tells its story at DEBUG" rule lives in `rules/logging.md`; this section is the Rust implementation contract (`log + env_logger` below, or the `#[tracing::instrument]` pattern next)
- Every non-trivial function must log its entry at the appropriate level:
  - `debug!` at the top of every async handler, pipeline stage, and background worker
  - Include function name and key params: `debug!("my_fn: param_a={} param_b={:?}", a, b);`
  - Completion points (doc counts, item counts, status) log at `info!` or `debug!`
  - Tight loops that would spam (per-item validation, per-record iteration) use `trace!`
  - `warn!` for recoverable failures (retry paths, skipped items, partial results)
  - `error!` / `bail!` for unrecoverable failures that propagate out
- Guiding principle: at `debug` level the log tells the full story of a run — what entered, what was produced, what was skipped — without reading the source

### Function-level instrumentation with `tracing` (when a project overrides the `log` default)

- When a project uses `tracing` + `tracing-subscriber` instead of `log` + `env_logger` (multi-crate daemons, async services needing span hierarchy that survives across tasks — justify the override in the project's vision doc), use `#[tracing::instrument]` on function declarations instead of hand-rolled `debug!("fn_name: a={a}")` calls

Default pattern:

```rust
#[tracing::instrument(level = "debug", skip_all, fields(work_id = %work.id, plan_id = %plan.id, dep_count = deps.len()))]
pub fn run_implementer(work: &Work, plan: &Plan, deps: &Deps<...>) -> Result<Bundle> {
    // warn!/error! inside inherit work_id/plan_id/dep_count automatically
}
```

Rules:

1. **`skip_all` + explicit `fields(...)`, never bare `#[instrument]`** — the default captures every param via `Debug` (pulls full records, prompts, stdouts into span fields: expensive, noisy, can leak secrets); `skip_all` then list the specific fields you want
2. **`level = "..."` matches function role** — entry-level orchestrators → `info`, per-iteration helpers → `debug`, tight-loop helpers → `trace`; the span's level gates both the span and events inside it
3. **`%var` for `Display`, `?var` for `Debug`** — prefer `%` for types with meaningful `Display` (typed IDs, paths), `?` when only `Debug` exists
4. **`ret` and `err` when the outcome matters** — `#[instrument(ret, err)]` logs the return at span close and auto-logs `Err` at `error!`; use on FSM transitions, store writes, external-call wrappers
5. **Required fields by scope (project-specific)** — every function carries its scope's identifying keys as span fields so `warn!`/`error!` inside inherit them; a missing scope key forces log-reconstruction, exactly what this section prevents

- Why this matters for `warn!`/`error!`: events inside an instrumented function inherit the enclosing span's fields automatically, e.g.:

```
 WARN ralph.implementer{work_id=w-00042 plan_id=p-0007 dep_count=3}: crate::agents: retrying after tool failure
```

- The emission site doesn't restate the fields; adding a param to the `#[instrument]` attribute propagates context to every `warn!`/`error!` inside without touching call sites
- When NOT to use `#[tracing::instrument]`: tiny pure helpers, `Drop` impls (deadlock risk if the subscriber's writer is held by a panicking thread), `impl Display`/`impl Debug` on hot types (recursion risk) — emit `tracing::debug!`/`warn!` directly with inline fields

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

- Scaffold templates enforce these at the crate root:
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
- Rationale: keeps production source files focused on production code; test bodies and fixtures can grow without blowing out the main file's line count; cleaner diffs and blame on `src/foo.rs`; matches the 2018+ module style used everywhere else
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
