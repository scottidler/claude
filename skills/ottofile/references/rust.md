# Rust Templates

## Single-Crate (`rust-crate`)

```yaml
otto:
  api: 1
  tasks: [ci]
  envs:
    VERSION: "$(git describe --tags --always --dirty 2>/dev/null || echo 'dev')"

tasks:
  lint:
    help: "Run whitespace linting"
    bash: |
      whitespace -r

  check:
    help: "Run all quality checks (compile, clippy, format)"
    bash: |
      echo "=== Checking compilation ==="
      cargo check --all-targets --all-features
      echo ""
      echo "=== Running Clippy ==="
      cargo clippy --all-targets --all-features -- -D warnings
      echo ""
      echo "=== Checking format ==="
      cargo fmt --all --check

  test:
    help: "Run all tests"
    bash: |
      cargo test --all-features

  cov:
    help: "Run tests with coverage via llvm-cov"
    after: [cov-report]
    bash: |
      # Inline contents of bash/rust-cov.sh here

  cov-report:
    help: "Display coverage report"
    params:
      --fail-under:
        default: "0"
        help: "Minimum line coverage percentage (0 = no threshold)"
      --json:
        default: "false"
        help: "Output raw JSON coverage data"
      --details:
        default: "false"
        help: "Show detailed per-file coverage"
    bash: |
      # Inline contents of bash/cov-report.sh here

  ci:
    help: "Full CI pipeline (lint + check + test in parallel)"
    before: [lint, check, test]
    bash: |
      echo "All CI checks passed!"

  build:
    help: "Build release binary"
    bash: |
      cargo build --release

  clean:
    help: "Clean build artifacts"
    bash: |
      cargo clean

  install:
    help: "Install binary locally via cargo"
    bash: |
      cargo install --path .
```

**Variations**:
- If the crate is a **library only** (no `src/main.rs`, no `[[bin]]`), omit the `install` task.

---

## Workspace (`rust-workspace`)

Same as `rust-crate` with these changes:

- `check`, `test`, `build`, `cov` all add `--workspace` flag:
  ```
  cargo check --workspace --all-targets --all-features
  cargo clippy --workspace --all-targets --all-features -- -D warnings
  cargo test --workspace --all-features
  cargo build --release --workspace
  cargo llvm-cov --workspace --all-features --json --output-path "$JSON_FILE"
  ```

- `install` iterates over workspace members:
  ```yaml
  install:
    help: "Install all workspace binaries locally via cargo"
    bash: |
      for bin in $(cargo metadata --no-deps --format-version 1 \
        | jq -r '.packages[].targets[] | select(.kind[] == "bin") | .name'); do
        echo "Installing $bin..."
        cargo install --path "$(cargo metadata --no-deps --format-version 1 \
          | jq -r --arg name "$bin" '.packages[] | select(.targets[] | select(.name == $name)) | .manifest_path' \
          | xargs dirname)"
      done
  ```

---

## Service (`rust-service`)

Same as `rust-crate` with these changes:

- Add `GIT_SHA` to envs:
  ```yaml
  envs:
    VERSION: "$(git describe --tags --always --dirty 2>/dev/null || echo 'dev')"
    GIT_SHA: "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  ```

- Add `run` task after `build`:
  ```yaml
  run:
    help: "Run the service locally"
    bash: |
      cargo run
  ```

- Remove `install` task (services are deployed, not installed as local binaries)

---

## Examples Variation

If the crate has `examples/*.sh`, add these tasks:

```yaml
  build-for-examples:
    help: "Build release binary for examples"
    bash: |
      cargo build --release --quiet

  examples:
    help: "Run all examples in parallel"
    before: [build-for-examples]
    foreach:
      glob: "examples/*.sh"
      as: example
      parallel: true
    bash: |
      name=$(basename "${example}")
      export PATH="$PWD/target/release:$PATH"
      export EXAMPLE_DIR=$(mktemp -d)
      trap "rm -rf $EXAMPLE_DIR" EXIT

      if bash "${example}"; then
        echo "✅ $name passed"
      else
        echo "❌ $name failed"
        exit 1
      fi

  examples-serial:
    help: "Run all examples sequentially (for debugging)"
    before: [build-for-examples]
    foreach:
      glob: "examples/*.sh"
      as: example
      parallel: false
    bash: |
      name=$(basename "${example}")
      export PATH="$PWD/target/release:$PATH"
      export EXAMPLE_DIR=$(mktemp -d)
      trap "rm -rf $EXAMPLE_DIR" EXIT

      echo "--- Running $name ---"
      if bash "${example}"; then
        echo "✅ $name passed"
      else
        echo "❌ $name failed"
        exit 1
      fi
      echo ""
```
