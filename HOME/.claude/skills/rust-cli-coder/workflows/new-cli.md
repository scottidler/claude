# New Rust CLI Project Workflow

Use this workflow when creating a new Rust CLI tool from scratch.

## Prerequisites

- `scaffold` CLI installed (`cargo install scaffold` or available in PATH)
- Git configured with user.name and user.email

## Steps

### 1. Create Project with Scaffold

```bash
scaffold <project-name>
```

This creates the complete project structure with:
- Cargo.toml (edition 2024, build.rs)
- src/main.rs (logging, error handling)
- src/cli.rs (clap derive)
- src/config.rs (YAML config loading)
- build.rs (git describe versioning)
- .otto.yml (CI tasks)

### 2. Verify Project Structure

After scaffold completes, verify:

```bash
cd <project-name>
ls -la
```

Expected files:
```
Cargo.toml
build.rs
src/
  main.rs
  cli.rs
  config.rs
.otto.yml
```

### 3. Initial Build Check

```bash
otto check
```

This runs:
- cargo fmt --check
- cargo clippy
- cargo build

### 4. Add Project-Specific Dependencies

Use `cargo add` for any additional dependencies:

```bash
cargo add <crate-name> [--features <features>]
```

Common additions:
- `cargo add tokio --features full` (async runtime)
- `cargo add reqwest --features json` (HTTP client)
- `cargo add tempfile` (testing with temp dirs)

### 5. Implement Core Logic

1. Define CLI arguments in `src/cli.rs`
2. Add any config fields to `src/config.rs`
3. Implement command handlers in `src/main.rs` or new modules

### 6. Run CI

```bash
otto ci
```

This runs lint, check, and tests.

## Checklist

- [ ] Project created with scaffold
- [ ] Initial build passes
- [ ] CLI arguments defined
- [ ] Config struct updated
- [ ] Core logic implemented
- [ ] Tests written
- [ ] `otto ci` passes

