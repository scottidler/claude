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

## Correctness Footguns

These are the bug classes that recurred across every Rust code review (otto, loopr, second-brain). Each one shipped to `main` at least twice. They are listed here so the next session writes the safe form the first time.

### UTF-8 and char boundaries

- NEVER byte-index or byte-slice a `&str`/`String` at a computed offset: `&s[..15]`, `&s[n..]`, `s.truncate(n)` all PANIC the moment a multibyte char straddles the boundary (cargo/test spew, non-ASCII filenames, em-dashes in titles all trigger it - confirmed live in all three repos)
  - Slice/truncate: use `s.get(..n)` (returns `None` on a bad boundary) or floor to a boundary with `s.char_indices()` / `s.floor_char_boundary(n)` before cutting
  - "First N chars": `s.chars().take(n).collect()`, never `&s[..n]`
- NEVER dedent, wrap, or scan by byte offset - operate on `char_indices()` so a U+2002 (or any multibyte whitespace) can't panic the pass
- Reading subprocess/file output line-by-line: `read_line` returns `InvalidData` on the first non-UTF-8 byte, and `while let Ok(_) = reader.read_line(..)` treats that error as EOF - silently dropping the rest of the output while the task still "succeeds". Read bytes (`read_until(b'\n')`) and `String::from_utf8_lossy` for display
- `from_utf8_lossy` is for DISPLAY only - never round-trip a file's bytes through it on a write path; it replaces invalid bytes with U+FFFD and corrupts binary/latin-1 files. Reject non-UTF-8 input with a typed error instead

### Filesystem mutation safety

- In-place `fs::write` is NOT atomic: a crash or a torn write leaves a truncated file, and on a synced tree (Syncthing, Dropbox) that truncation replicates everywhere. Write to a temp file IN THE TARGET'S OWN DIRECTORY (cross-filesystem rename fails from `/tmp`), `fsync`, then `rename` over the target; give the temp a unique name if parallel writers touch the same dir. Make this one shared helper / a `FileSystem` port method, not a per-site reimplementation
- A content-addressed / write-once cache built on non-atomic writes poisons permanently: the torn file keeps its hash name and is served forever. Atomic write fixes it; optionally validate the cache hit
- `fs::rename` and `fs::copy` SILENTLY CLOBBER the destination - that is data loss when the destination is a user file. Check-and-bail or uniquify the target name first
- Destructive ops (`remove_dir_all`, recursive delete, `--clean`) must (a) skip symlinked entries (`file_type().is_symlink()`) so they can't follow a link out of the intended root, and (b) `canonicalize()` the target and assert it is still under the root BEFORE deleting. A planted symlink otherwise deletes arbitrary paths (confirmed in otto's `clean`)

### Subprocess and async I/O hygiene

- EVERY `reqwest`/HTTP client gets an explicit `.timeout(...)` - a default client hangs forever on a stalled connection (bit all three repos). And call `error_for_status()` before streaming a body, or a 404 HTML page gets written as your "tarball"
- EVERY external command gets a wall-clock timeout AND `kill_on_drop(true)` on the tokio `Command`. Without `kill_on_drop`, a timed-out `git merge`/build keeps running and can land its mutation AFTER your function already returned `Err` - git advances, your DB doesn't, the retry races the orphan
- Drain stdout AND stderr concurrently while the child runs. Reading one pipe to completion before the other deadlocks the child once it fills the ~64 KB pipe buffer - it blocks on the pipe you aren't reading. (otto's concurrent-drain design is the reference; second-brain's fabric runner deadlocked exactly here)
- A backgrounded grandchild (`some-server &`) keeps the stdout pipe open and hangs a post-exit drain forever - bound the drain with a timeout and kill the process group
- Blocking work on the async runtime starves it: a blocking `std::process::Command::output()`, a `rusqlite` call, or fastembed/candle inference inside an `async fn` blocks the whole tokio worker. Route it through `spawn_blocking` (or `block_in_place`), and run the blocking part BEFORE taking any lock the async tasks need
- NEVER hold a lock (or a `tracing` span `Entered` guard) across `.await` or across a blocking subprocess - it serializes every task that needs the lock and can deadlock. Use `.instrument(span)` for spans; compute-then-lock for data. `clippy::await_holding_lock` catches the std-Mutex-across-await case but not the subprocess case - watch for it by hand

### Determinism

- A `HashMap` serialized, hashed, or iterated for output gives a DIFFERENT order every run. That breaks content-addressed hashes (the cache never hits and files accumulate - otto), makes config round-trips un-diffable, and churns embeddings when a "first section" is read from a map. Use `IndexMap` (preserve author/insertion order) or `BTreeMap` (sorted) anywhere the iteration order is observable - serialization, hashing, "first match", emitted YAML/JSON
- NEVER fold wall-clock time into an identity or a content hash: a merge-commit's author/committer date, a `runs.timestamp` UNIQUE key, or an OCC token of "updated_at millisecond equality" all collide or differ spuriously. Two writes in the same millisecond defeat a millisecond-equality OCC token; pin commit dates (`GIT_*_DATE`) for reproducible SHAs; floor monotonic counters (`max(now, prev + 1)`)
- `std::collections::hash_map::DefaultHasher` is NOT stable across Rust releases - never persist its output (cache keys, fingerprints). A toolchain bump silently invalidates the whole cache. Use a pinned algorithm (FNV-1a, or a `fnv`/`twox-hash` dep)

### Typed values at seams, never strings

- NEVER parse semantic data back out of an error/`Display` string. otto extracted a failed task's name with `error.split_whitespace().nth(1)` (a spawn failure became a task literally named "such" and hung the scheduler), and round-tripped an exit code through `{:?}` -> parse -> `unwrap_or(1)` so every recorded code was wrong. Carry the name, exit code, and reason as typed fields on the error / channel payload from the start
- A channel/`JoinSet` payload that needs a name + exit status + reason gets a struct (`Result<T, TaskFailure { name, code, reason }>`), not a formatted string the consumer re-parses
- Detect a condition by matching a typed error variant, never `msg.contains("timed out")` / `err.to_string().contains("locked")`. Add the variant (`FabricError::Timeout`, a `Stale` OCC variant, a `Closed` shutdown variant) - string matching breaks the instant an upstream message is reworded, and conflates distinct failures (every non-zero `git merge` exit is NOT a conflict - sniff for `CONFLICT`/`Automatic merge failed` and route the rest as retryable)

### Don't let failures vanish

- A spawned task's `JoinHandle`/`JoinSet` that is never awaited (or whose `JoinError` is discarded) swallows panics entirely - the work silently dies, the dependent graph deadlocks, and with daemon stdio at `/dev/null` there is zero evidence. Reap handles (`try_join_next` with a `warn!` on a non-cancel `JoinError`) and install a panic hook in any daemon/background-worker binary
- Inside a spawned task body, EVERY early `?` exit must still send its completion message - an early `?` before the `tx.send(..)` makes `rx.recv()` block forever. Wrap the body so all exit paths report exactly once
- `.ok()` / `let _ = ...` / `filter_map(|r| r.ok())` on anything that can fail for a real reason silently drops it. A `StateManager::try_new()` that is `.ok()` stops recording history with no log; a `filter_map(.ok())` drops rows. At minimum `warn!` the discarded error (this is the logging rule's failure clause, in code form)
- Defaults fail CLOSED: an empty allowlist denies all (not accepts all), a hostname lookup error returns "not local" (not local), a missing/invalid value errors rather than silently widening access. Every fail-open default in the reviews was a security hole
- NEVER load config from the current working directory as a silent fallback (`./oracle.yml`, re-rooting `-C` to the enclosing git toplevel for a write command). Any directory could then reconfigure the tool. Resolve config from the XDG path / the explicitly named path, and log which file actually loaded
- A derived `#[derive(Default)]` can produce an INVALID value (`interval_secs = 0` -> `tokio::time::interval(0)` panics; `jobs = 0` -> scheduler hangs). Hand-write `impl Default` (or validate at load) for any field whose zero value is illegal, and validate numeric ranges (`-j 0`, `nargs: "0:5"` underflow) at parse/config time

### Schema is law (serde)

- Put `#[serde(deny_unknown_fields)]` on every config/IPC struct you own. Without it a typo is silent data loss: otto's top-level `task:` (for `tasks:`) parsed to a config with ZERO tasks and exited 0; a `befor:` dropped a dependency. The error naming the unknown field IS the feature
  - Carve-out: a deliberately forward-compatible envelope (a wire frame meant to tolerate newer peers) stays tolerant - document that exemption in the crate where it lives; the strict default applies to everything else
- Model a fixed vocabulary as an `enum`, not free strings. A `find_links.direction` or `quality` field that is a `String` returns empty results on a typo instead of failing deserialization; scattered `"assisted"`/`"unread"` literals drift from the type. Derive the schema/validation vocab from `Enum::all()` so it can't fall out of sync with the type

### When the project uses SQLite (rusqlite)

- Set `busy_timeout` (a named const) and `synchronous=NORMAL` under WAL at connection open. Without `busy_timeout`, a concurrent cross-process writer gets an instant `SQLITE_BUSY` that surfaces as silently-missing history
- Map `Err(QueryReturnedNoRows)` to `Ok(None)` in ONE helper and propagate everything else. The common `.ok()` shortcut turns a real `SQLITE_BUSY` under write contention into a false "row doesn't exist" (then an INSERT-on-existing-PK or a dropped edge)
- Run each migration step AND its `set_version` inside ONE transaction, and make the DDL idempotent (`pragma_table_info` check before `ALTER`). A crash between a bare `ALTER` and the version bump bricks the DB forever ("duplicate column name" on every subsequent open). Snapshot the DB before the first run of a schema change, per the migration-verification rule
- Every user value is bound via `params![]` - no string-interpolated SQL, ever (the reviews found exactly one interpolated value and it was the lone injection surface)

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
  - **Carve-out:** selecting which *algorithm/methodology* is active (not gating whether a fixed governance rule runs) is legitimate config, and an explicit per-method `enabled: true/false` is the clearest expression - especially when there is no per-invocation CLI surface (e.g. an MCP server). See `general.md` and `second-brain/docs/design/2026-06-06-configurable-retrieval-pipeline.md`.

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

#### Unwrap policy, and what is still allowed

- The helpers return `Option<PathBuf>` (`None` only when BOTH `$HOME` and the relevant `$XDG_*_HOME` are unset - an environment where nothing in the tool works). At the call site:
  - operator-facing log/config setup in `main` may `.unwrap_or_else(|| PathBuf::from("."))`
  - internal daemon paths (SQLite DBs, lock files, state dirs) use `.expect("xdg_data_dir() returned None (set HOME or XDG_DATA_HOME)")` - panic-with-a-clear-message beats inventing a path. NEVER fabricate a `~/`-prefixed or relative fallback string: a literal `~` is not expanded by the OS and creates a directory named `~` under CWD
- Only `dirs::config_dir()` / `dirs::data_local_dir()` are banned. Still fine:
  - `dirs::home_dir()` - correct on every platform; the helpers are built on it
  - `dirs::cache_dir()` / `dirs::data_dir()` **when you are reading where a THIRD-PARTY tool stores things** - e.g. probing the `hf-hub` / `fastembed` model cache under `~/.cache`. There you must match the external tool's own resolution, not impose the XDG helper. (Do NOT route your OWN cache through these - own caches follow the XDG-data helper.)
- One source of truth per project: define the two helpers once (a `config` module, or a shared crate like `vault::paths` / `telemetry::xdg` in a workspace) and have every config/data/log site call them - no project should call `dirs::config_dir()` / `dirs::data_local_dir()` directly anywhere. (second-brain was migrated to this in 2026-06; it formerly used `dirs::*_dir() + .expect()` directly, which is why an older carve-out lived here.)
- `after_help` SHOULD advertise the log path. The `xdg_*` helpers make the default `~/.local/share/<proj>/logs/<proj>.log` true on every platform (macOS included), so a **hardcoded** string is honest *only when `$XDG_DATA_HOME` / `$XDG_CONFIG_HOME` are unset*. If the user sets either, logs/config move and the hardcoded `--help` string becomes a lie - the helpers fix the *platform* divergence, not the *env-override* one
- So render the path at runtime from the same source the logger uses, and inject it - `--help` then stays accurate under the env override and can never drift from where the logger actually writes:

  ```rust
  // one source of truth: log_dir() feeds both the logger and --help
  let after_help = format!("Logs are written to: {}", log_dir().join("<proj>.log").display());
  let args = Cli::from_arg_matches(&Cli::command().after_help(after_help).get_matches())?;
  ```

  A hardcoded `after_help` literal is an acceptable shortcut only for tools that will never honor `$XDG_DATA_HOME`; when in doubt, render it
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
- Prefer a lint over prose whenever one exists - a convention that only lives in this file gets violated (every repo reviewed had drifted CLI/`dirs`/`RUST_LOG` violations that *were* already documented here). Add these at the crate root and let `-D warnings` enforce them:
  - `#![deny(clippy::string_slice)]` - bans `&s[a..b]` on strings, the panic-on-non-char-boundary footgun (see "UTF-8 and char boundaries"); tests may `#[allow(...)]`
  - `#![deny(clippy::await_holding_lock)]` - catches a `std::sync` `MutexGuard`/`RwLockGuard` held across `.await` (deadlock / serialized async). It does NOT catch a guard held across a blocking subprocess or a `tokio::sync` guard - those stay a review concern
  - Consider `clippy::indexing_slicing` (bans `v[i]`) where panics-from-indexing have bitten; it is noisy on hot indexing code, so scope it per-module rather than crate-wide if it fights you

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
