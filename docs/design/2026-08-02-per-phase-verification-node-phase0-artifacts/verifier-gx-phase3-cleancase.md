## Phase 3 verification: `gx` lib decomposition (form `remote`, finalize the bin)

Verified against `docs/design/2026-07-17-gx-lib-decomposition.md:90-93` and `/var/tmp/p-gx.diff`, reading files in `/var/tmp/phase0-stage/gx`.

### Success criteria

**(1) Workspace is `local` + `remote` + `gx` bin, single flat version — PASS**
- `Cargo.toml:7` `members = ["local", "remote"]`; root package is `gx` (`Cargo.toml:16`) with `[[bin]]` only, no `[lib]` (`Cargo.toml:22-24`); `src/lib.rs` deleted (diff:688-716), `src/` now holds only `main.rs`.
- `cargo metadata --no-deps` → `[('local','0.6.3'), ('remote','0.6.3'), ('gx','0.6.3')]`; all three use `version.workspace = true` (`Cargo.toml:17`, `local/Cargo.toml:3`, `remote/Cargo.toml:3`) off `[workspace.package] version = "0.6.3"` (`Cargo.toml:13`).
- `remote` depends on `local` (`remote/Cargo.toml:14`); `local` does not depend on `remote` (`local/Cargo.toml:6-22`).

**(2) `otto ci` green — PASS** (ran each `ci` sub-task from `.otto.yml:163-167`)
- `lint`: `whitespace -r` → `✅ No trailing whitespace found`, rc=0.
- `local-boundary`: `bin/check-local-boundary.sh` → `local/src is clean`, rc=0.
- `check`: `cargo check --workspace --all-targets --all-features` rc=0; `cargo clippy --workspace --all-targets --all-features -- -D warnings` rc=0; `cargo fmt --all --check` rc=0.
- `test`: `cargo test --workspace --all-features` → `CARGO_TEST_RC=0`, 28 test targets, **0 failed** (largest: 252 in `remote`, 92 in `local`; e2e lifecycle suites included).
- Guard still bites (re-proved independently): appending `Command::new("git").args(["fetch","origin"])` to `local/src/utils.rs` → `BOUNDARY VIOLATION ... local/src/utils.rs:33`, rc=1; file restored, guard rc=0 after.

**(3) Full `gx --help` matrix behaves identically — PARTIAL / partly unverifiable**
- Matrix present and complete: `gx --help` lists `status, checkout, clone, create, apply, review, rollback, undo, cleanup, doctor, mcp, help` — all 10 named in the doc plus `rollback`.
- Every subcommand `--help` returns rc=0 (11/11); `gx --version` → `gx 0.6.3`.
- Live smoke: `gx status` in a scratch `myorg/myrepo` git repo → `main 5391f46 📍 myorg/myrepo / 📊 1 clean, 0 dirty, 0 errors`, rc=0; `gx doctor` rc=0.
- **Unverifiable:** "identically" against the pre-change binary. This working copy is not a git repo (`git log` → `fatal: not a git repository`), so the parent commit cannot be built and diffed. What I can show instead: the dispatch body in `remote/src/app.rs:269-447` is line-for-line the deleted `main.rs` `run_application` (diff:759-931), differing only in `cli::` → `crate::cli::` qualification and the `unreachable!` string (`remote/src/app.rs:445` vs diff:929).

### Deviations

1. **New `remote::app` module, not in the doc's Phase 3 list** — `remote/src/lib.rs:7`, `remote/src/app.rs:1-5`. The doc names 17 modules to move; `app` is new, holding dispatch lifted out of `main.rs`. **Acceptable** — it is the mechanism for "reduce the `gx` bin to a thin shim"; code moved verbatim.
2. **Four modules moved beyond the doc's list** — `confirm`, `crash`, `lock`, `git` (`remote/src/lib.rs:12,13,16,18`). Commit message says 21 modules; doc Phase 3 names 17. **Acceptable** — all four were in the deleted `src/lib.rs` (diff:700,701,706,704); leaving them would have kept a lib in the `gx` package, contradicting the thin-shim goal. `git` is required to realize Phase 2's `remote::git`.
3. **`build.rs` relocation forced a non-import test change** — `build.rs` → `remote/build.rs` with `rerun-if-changed` rewritten to `../.git/HEAD|refs/|packed-refs` (`remote/build.rs:23,24,28`), and `remote/tests/build_script_test.rs:18,23,24` assertions changed to match. AC #3 (`docs/design/…md:99`) claims "no existing test changes except import paths"; these are assertion-string changes, not import paths. **Acceptable on the merits** (the assertion tracks the file's new location; the stale-`GIT_DESCRIBE` guarantee is unchanged), but the AC as worded is now inaccurate.
4. **`remote` declared twice in the root manifest** — `[dependencies]` `Cargo.toml:33` and `[dev-dependencies]` `Cargo.toml:37`, with no feature difference (unlike `local`, whose dev entry adds `testutil` at `Cargo.toml:36`). Redundant. **Acceptable** — harmless to Cargo, but the dev-dep line is dead weight.
5. **Stale `gx::` paths in comments and guard output** — `remote/src/create.rs:8-9`, `remote/src/undo.rs:8`, and `bin/check-local-boundary.sh:53` which still tells the developer to "Move the offending logic to the remote half (gx::git / Phase 3 remote crate)"; `gx::git` no longer exists and Phase 3 is done. **Acceptable but stale** — the guard message now names a path that cannot be reached.

### Note (not a deviation)

`default-members = ["."]` (`Cargo.toml:10`) means a bare `cargo test` covers only the `gx` bin package. `otto ci` is unaffected: both `check` and `test` pass `--workspace` (`.otto.yml:25,28,39`).
