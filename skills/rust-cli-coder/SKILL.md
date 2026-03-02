---
name: rust-cli-coder
description: Write Rust code using Scott's conventions. USE WHEN creating Rust CLIs, libraries, reviewing Rust code, or when the user mentions Rust, cargo, or CLI tools.
---

# Rust Coding Conventions

## Goal

Write Rust CLI code that is **easy to test**, **easy to reason about**, and capable of reaching **very high coverage (90–100%)** without brittle tests.

This skill emphasizes **separation of concerns**, **dependency injection**, and **data-first design**.

## Workflow Routing

| Intent | Workflow |
|--------|----------|
| new CLI project | workflows/new-cli.md |
| create new CLI | workflows/new-cli.md |
| scaffold CLI | workflows/new-cli.md |

---

# Part 1: Architecture for Testability

## 1. Separate "Shell" from "Core"

- `main.rs` is a **thin shell**
- All real logic lives in a library crate (`lib.rs`)

**Shell responsibilities:**
- Parse CLI args (clap)
- Call `run()`
- Print output
- Map errors to exit codes

**Core responsibilities:**
- Validate config
- Perform filesystem / HTTP / IMAP logic
- Return structured results (not printed text)

```
src/
├── main.rs    # Thin shell: parse args, call lib, print results
├── lib.rs     # Core: all business logic, fully testable
├── cli.rs     # Clap structs only
├── config.rs  # Config validation, defaults
└── ports/     # Traits for external dependencies
    ├── mod.rs
    ├── fs.rs
    └── http.rs
```

## 2. Return Data, Not Side Effects

Core logic should:
- Return `Result<T>` (preferably `eyre::Result`)
- Never call `process::exit`
- Never write directly to stdout/stderr

**Preferred pattern:**

```rust
// Core returns structured data
pub fn run<F: FileSystem>(config: Config, fs: &F) -> Result<RunResult> {
    // Business logic here
    Ok(RunResult {
        files_processed: 42,
        warnings: vec![],
        status: ExitStatus::Success,
    })
}

// Shell renders it
fn main() -> Result<()> {
    let args = Cli::parse();
    let config = Config::try_from(args)?;
    let result = mylib::run(config, &RealFs)?;

    // Shell decides how to display
    println!("{} files processed", result.files_processed);
    std::process::exit(result.status.code());
}
```

`RunResult` contains:
- Structured messages or events
- Counts, paths, or summaries
- Exit status (enum or value)

## 3. Clap: Parse First, Validate Second

Split argument handling into two stages:

**Stage 1: `Args` (parsing only)**

```rust
#[derive(Parser)]
pub struct Cli {
    #[arg(short, long)]
    pub config: Option<PathBuf>,

    #[arg(short, long)]
    pub output: Option<PathBuf>,

    #[arg(long)]
    pub dry_run: bool,
}
```

**Stage 2: `Config` (validation + defaults)**

```rust
pub struct Config {
    pub config_path: PathBuf,
    pub output_path: PathBuf,
    pub dry_run: bool,
}

impl TryFrom<Cli> for Config {
    type Error = eyre::Error;

    fn try_from(cli: Cli) -> Result<Self> {
        let config_path = cli.config
            .or_else(|| dirs::config_dir().map(|d| d.join("myapp/config.yml")))
            .ok_or_else(|| eyre::eyre!("No config path and no config dir"))?;

        let output_path = cli.output
            .unwrap_or_else(|| PathBuf::from("output.txt"));

        // Cross-flag validation
        if cli.dry_run && cli.output.is_some() {
            eyre::bail!("--dry-run and --output are mutually exclusive");
        }

        Ok(Config {
            config_path,
            output_path,
            dry_run: cli.dry_run,
        })
    }
}
```

Most tests target **Config**, not clap parsing.

---

## 4. Dependency Injection (Ports)

Never depend on concrete I/O in core. Filesystem, HTTP, IMAP, time, env, and randomness must be injected via **small, purpose-built traits**.

### Filesystem Port

```rust
pub trait FileSystem {
    fn read_to_string(&self, path: &Path) -> Result<String>;
    fn write_string(&self, path: &Path, content: &str) -> Result<()>;
    fn exists(&self, path: &Path) -> bool;
    fn list_dir(&self, path: &Path) -> Result<Vec<PathBuf>>;
    fn create_dir_all(&self, path: &Path) -> Result<()>;
}

// Real implementation
pub struct RealFs;

impl FileSystem for RealFs {
    fn read_to_string(&self, path: &Path) -> Result<String> {
        std::fs::read_to_string(path).context("Failed to read file")
    }
    // ... other methods
}

// Test fake
#[cfg(test)]
pub struct MemFs {
    files: std::cell::RefCell<HashMap<PathBuf, String>>,
}

#[cfg(test)]
impl MemFs {
    pub fn new() -> Self {
        Self { files: RefCell::new(HashMap::new()) }
    }

    pub fn with_file(self, path: impl Into<PathBuf>, content: &str) -> Self {
        self.files.borrow_mut().insert(path.into(), content.to_string());
        self
    }
}
```

### HTTP Port

Expose **intent-level operations**, not raw HTTP:

```rust
pub trait ConfigFetcher {
    fn fetch_config(&self, url: &str) -> Result<ConfigData>;
    fn download_rules(&self, url: &str) -> Result<Vec<Rule>>;
}

// Test fake
#[cfg(test)]
pub struct MockConfigFetcher {
    pub config_response: Option<ConfigData>,
    pub should_fail: bool,
}
```

### IMAP Port

Core should not know the IMAP crate:

```rust
pub trait MailStore {
    fn search(&self, query: &str) -> Result<Vec<MessageId>>;
    fn fetch(&self, ids: &[MessageId]) -> Result<Vec<Message>>;
    fn store_flags(&self, ids: &[MessageId], flags: &[Flag]) -> Result<()>;
}
```

Fakes enable testing:
- Empty mailboxes
- Partial failures
- Weird server behavior

---

## 5. Generic Dependency Injection

Use generics to inject dependencies. Avoid `dyn` trait objects.

**Pattern: Generic parameters on `run`**

```rust
pub fn run<F, H>(config: Config, fs: &F, http: &H) -> Result<RunResult>
where
    F: FileSystem,
    H: ConfigFetcher,
{
    let content = fs.read_to_string(&config.input)?;
    let rules = http.download_rules(&config.rules_url)?;
    // ... process
    Ok(RunResult { /* ... */ })
}
```

**Pattern: `Deps` struct for many dependencies**

```rust
pub struct Deps<F, H, M> {
    pub fs: F,
    pub http: H,
    pub mail: M,
}

pub fn run<F, H, M>(config: Config, deps: &Deps<F, H, M>) -> Result<RunResult>
where
    F: FileSystem,
    H: ConfigFetcher,
    M: MailStore,
{
    let content = deps.fs.read_to_string(&config.input)?;
    // ...
}

// In main.rs
fn main() -> Result<()> {
    let deps = Deps {
        fs: RealFs,
        http: RealHttpClient::new(),
        mail: ImapClient::connect(&config.imap)?,
    };
    let result = mylib::run(config, &deps)?;
    // ...
}

// In tests
#[test]
fn test_run() {
    let deps = Deps {
        fs: MemFs::new().with_file("input.txt", "content"),
        http: MockConfigFetcher { config_response: Some(default_config()) },
        mail: MockMailStore::empty(),
    };
    let result = run(test_config(), &deps).unwrap();
    assert_eq!(result.files_processed, 1);
}
```

---

## 6. Testing Strategy

### Prefer Unit Tests Over E2E

**Use E2E tests sparingly.** Unit tests are faster, more reliable, and easier to debug.

| Test Type | Use When |
|-----------|----------|
| **Unit tests** | Default. Test functions with injected fakes. |
| **Integration tests** | Module boundaries, public API contracts. |
| **E2E tests** | Smoke tests only: "does the binary run?" |

E2E tests are expensive:
- Slow (spawn processes, set up fixtures)
- Flaky (timing, filesystem state, environment)
- Hard to debug (failures distant from root cause)

**Good E2E test:** Verify `--help` works.
**Bad E2E test:** Test every code path by spawning the binary.

### Test Config Validation

```rust
#[test]
fn test_config_requires_output_when_not_dry_run() {
    let cli = Cli { dry_run: false, output: None, ..default() };
    let result = Config::try_from(cli);
    assert!(result.is_err());
}

#[test]
fn test_config_rejects_dry_run_with_output() {
    let cli = Cli { dry_run: true, output: Some("out.txt".into()), ..default() };
    let result = Config::try_from(cli);
    assert!(result.is_err());
}
```

### Test Core Logic with Fakes

```rust
#[test]
fn test_processes_all_files_in_directory() {
    let fs = MemFs::new()
        .with_file("input/a.txt", "content a")
        .with_file("input/b.txt", "content b");

    let config = Config { input: "input".into(), ..default() };
    let result = process_directory(&config, &fs).unwrap();

    assert_eq!(result.files_processed, 2);
}

#[test]
fn test_handles_empty_directory() {
    let fs = MemFs::new();
    let config = Config { input: "empty".into(), ..default() };
    let result = process_directory(&config, &fs).unwrap();

    assert_eq!(result.files_processed, 0);
}
```

### Use tempfile for Real FS When Needed

```rust
use tempfile::TempDir;

#[test]
fn test_with_real_filesystem() {
    let temp = TempDir::new().unwrap();
    let input = temp.path().join("input.txt");
    std::fs::write(&input, "test content").unwrap();

    // Test with RealFs if you must
    let result = my_function(&input, &RealFs).unwrap();
    assert!(result.output_path.exists());
}
```

---

# Part 2: Conventions and Tooling

## Creating New Rust CLI Projects

**Always use `scaffold` instead of `cargo new`** for CLI projects:

```bash
scaffold <project-name>
```

This sets up the complete project structure with all conventions pre-configured.

### What scaffold provides

- **Cargo.toml** with correct edition (2024) and build.rs
- **src/main.rs** with logging setup and error handling
- **src/cli.rs** with clap derive pattern
- **src/config.rs** with YAML config loading
- **build.rs** for git describe versioning
- **.otto.yml** for CI/CD tasks

## Core Dependencies

| Purpose | Crate | Notes |
|---------|-------|-------|
| CLI parsing | `clap` | With `derive` feature |
| Error handling | `eyre` | For CLIs (use `thiserror` for libraries) |
| Logging | `log` + `env_logger` | File output |
| Serialization | `serde` + `serde_yaml` | With `derive` feature |
| JSON output | `serde_json` | For pipeline/machine output |
| Async runtime | `tokio` | With `full` feature |
| Parallelism | `rayon` | For `par_iter` |
| Terminal colors | `colored` | |
| Directory paths | `dirs` | For config/data dirs |

### Adding dependencies

Use `cargo add`, never hardcode versions:

```bash
cargo add clap --features derive
cargo add eyre
cargo add serde --features derive
```

## Error Handling

**For binaries (CLIs):** Use `eyre::Result` with `.context()`:

```rust
use eyre::{Context, Result};

fn load_config(path: &Path) -> Result<Config> {
    let content = fs::read_to_string(path)
        .context("Failed to read config file")?;

    let config: Config = serde_yaml::from_str(&content)
        .context("Failed to parse config file")?;

    Ok(config)
}
```

**For libraries:** Use `thiserror` for typed errors consumers can match on:

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum LibError {
    #[error("not found: {id}")]
    NotFound { id: String },

    #[error("invalid input: {0}")]
    InvalidInput(String),

    #[error("io error: {0}")]
    Io(#[from] std::io::Error),

    #[error("parse error: {0}")]
    Parse(#[from] serde_yaml::Error),
}

pub type Result<T> = std::result::Result<T, LibError>;

// Usage in lib code
pub fn load(id: &str) -> Result<Data> {
    let path = find_path(id).ok_or_else(|| LibError::NotFound { id: id.into() })?;
    let content = std::fs::read_to_string(&path)?;  // auto-converts via #[from]
    let data: Data = serde_yaml::from_str(&content)?;
    Ok(data)
}
```

Callers can then match on specific variants:

```rust
match mylib::load("config") {
    Ok(data) => use_data(data),
    Err(LibError::NotFound { id }) => create_default(&id),
    Err(LibError::Parse(e)) => eprintln!("Fix your YAML: {e}"),
    Err(e) => return Err(e.into()),
}
```

**Never use `.unwrap()` in production code.**

## Async vs Sync vs Parallel

| Scenario | Approach |
|----------|----------|
| I/O-bound (network, files) | async (tokio) |
| CPU-bound, many independent items | `par_iter` (rayon) |
| CPU-bound, complex dependencies | threads |
| Simple, sequential | sync |

```rust
use rayon::prelude::*;

let results: Vec<_> = files
    .par_iter()
    .map(|f| process_file(f))
    .collect();
```

## Logging Setup

Log to `~/.local/share/<project>/logs/<project>.log`:

```rust
fn setup_logging() -> Result<()> {
    let log_dir = dirs::data_local_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(env!("CARGO_PKG_NAME"))
        .join("logs");

    fs::create_dir_all(&log_dir)?;
    let log_file = log_dir.join(format!("{}.log", env!("CARGO_PKG_NAME")));

    let target = Box::new(fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_file)?);

    env_logger::Builder::from_default_env()
        .target(env_logger::Target::Pipe(target))
        .init();

    Ok(())
}
```

## CLI Structure (clap derive)

```rust
#[derive(Parser)]
#[command(
    name = "myapp",
    about = "Description of what this tool does",
    version = env!("GIT_DESCRIBE"),
)]
pub struct Cli {
    #[arg(short, long)]
    pub config: Option<PathBuf>,

    #[arg(short, long)]
    pub verbose: bool,
}
```

Use `GIT_DESCRIBE` from build.rs, not `CARGO_PKG_VERSION`.

## Configuration Pattern

| Format | Use Case |
|--------|----------|
| **YAML** | Human-readable config (preferred) |
| **JSON** | Machine-generated, API responses |
| **TOML** | When required (Cargo.toml) |

Config lives at `~/.config/<project>/<project>.yml`.

## Build Script (build.rs)

```rust
fn main() {
    let git_describe = std::process::Command::new("git")
        .args(["describe", "--tags", "--always"])
        .output()
        .and_then(|o| if o.status.success() {
            Ok(String::from_utf8_lossy(&o.stdout).trim().to_string())
        } else {
            Err(std::io::Error::other("git describe failed"))
        })
        .unwrap_or_else(|_| env!("CARGO_PKG_VERSION").to_string());

    println!("cargo:rustc-env=GIT_DESCRIBE={}", git_describe);
    println!("cargo:rerun-if-changed=.git/HEAD");
}
```

## CI/CD with Otto

```bash
otto ci      # Full CI: lint + check + test
otto check   # Compile + clippy + format check
otto test    # Run tests
otto build   # Release build
```

## Terminal Output

```rust
use colored::*;

println!("{} Operation completed", "✓".green());
println!("{} Processing...", "→".blue());
eprintln!("{} Failed to connect", "✗".red());
```

### Output Format Detection

```rust
use std::io::IsTerminal;

fn output_data<T: Serialize>(data: &T) -> Result<()> {
    if std::io::stdout().is_terminal() {
        println!("{}", serde_yaml::to_string(data)?);  // Human-readable
    } else {
        println!("{}", serde_json::to_string(data)?);  // Machine-parseable
    }
    Ok(())
}
```

## Code Style

- **Imports:** Group by std, external crates, internal modules
- **Line length:** Under 100 characters
- **Format:** Always run `cargo fmt`

## Version Bumping

See the `/bump` skill.

## What NOT to Do

- ❌ Don't use `anyhow` — use `eyre` for CLIs
- ❌ Don't use `.unwrap()` in production
- ❌ Don't hardcode dependency versions
- ❌ Don't use `cargo new` — use `scaffold`
- ❌ Don't use `dyn` for dependency injection — use generics
- ❌ Don't test clap parsing — test Config validation
- ❌ Don't write E2E tests for every code path
- ❌ Don't call `process::exit` in library code
- ❌ Don't print to stdout/stderr from core logic
