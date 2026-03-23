---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
  - "**/Cargo.lock"
  - "**/build.rs"
  - "**/clippy.toml"
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
- No underscores in .rs filenames - every source file should be a single word
- If a name would be compound, decompose it into a module directory with single-word files inside:
  - `config_loader.rs` -> `config/mod.rs` + `config/loader.rs`
  - `borg_log.rs` -> `borg/log.rs` (or rethink whether `borg` is already the module)
- This keeps every .rs filename one word and creates natural module boundaries

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
- Config at `~/.config/<project>/<project>.yml`
- Config defines WHAT rules look like, not WHETHER they run - scope is controlled via CLI flags, not `enabled: true/false` in config

## Logging

- Custom `--log-level`/`-l` CLI flag - NEVER use `RUST_LOG` env var
- Log to `~/.local/share/<project>/logs/<project>.log`
- Use `env_logger` with file target

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
