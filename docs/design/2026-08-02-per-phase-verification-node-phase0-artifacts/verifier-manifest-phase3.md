Phase 3 verification: all five success criteria pass. Working tree left as committed (`otto ci` green, 182 tests).

## Phase 3 success criteria (doc:328-330)

**1. Deployed file is `0600` (metadata assert) — PASS**
- `write_secret_file` chmods `dest` to `SECRET_FILE_MODE` after rename: `src/age.rs:1413`; const is `0o600` at `src/age.rs:24`.
- Test asserts `mode_of(&dest) == 0o600`: `src/age.rs:2729`.
- Live: deployed two secrets, both `600`, bytes byte-exact (`decrypt_file` returns `Vec<u8>`, `src/age.rs:79`; written verbatim at `src/age.rs:1392`, no trimming).

**2. Temp never broader than `0600`, asserted via creation mode not post-hoc chmod — PASS**
- `OpenOptions...create_new(true).mode(SECRET_FILE_MODE)`: `src/age.rs:1295-1299`.
- Test stats the temp while the handle is open, before any write or rename: `src/age.rs:2734-2750`.
- Mutation-proven: deleting `.mode(SECRET_FILE_MODE)` fails only that test (`panicked at src/age.rs:2743`), while `test_deploy_secret_file_writes_0600` still passed — confirming the creation-mode assertion, not the final chmod, is what bites.

**3. Mid-batch failure: no partial for that entry, others deploy, non-zero exit — PASS**
- `deploy_secret_files` records and continues: `src/age.rs:1457-1468`; `main.rs:553-558` returns `Err` when `failed` is non-empty.
- Decrypt precedes any file creation (`src/age.rs:1438` before `:1440`), so a bad entry never touches the destination or creates its parent.
- Tests: `src/age.rs:2813` (no partial, no leftover temp), `src/age.rs:2840` (bad entry ordered first, good still deploys).
- Live, 3 entries with one corrupt `.age`: `exit=1`, two `deployed:` lines on stdout, `bad-key` absent, no `.tmp-` residue.

**4. Symlinked parent refused — PASS**
- `fs::symlink_metadata(parent)` + `file_type().is_symlink()`: `src/age.rs:1318-1326`.
- Test asserts the error and that nothing was written through the link: `src/age.rs:2780-2810`.
- Mutation-proven: gating the check off fails exactly that test (`panicked at src/age.rs:2800`).

**5. No plaintext in generated Bash or stdout — PASS**
- Structural: `ManifestType` has no secrets variant (`src/manifest.rs:7-21`); deploy never enters the render path.
- `main.rs:544-551` prints names and dests only; `DeployReport` holds names/paths/error text (`src/age.rs:1272-1275`).
- Test greps the rendered report for the marker: `src/age.rs:2880-2903`.
- Live: `grep -c` for the marker in captured stdout and stderr returned `0` and `0`.

Also verified from the Phase 3 bullet (doc:320-324): parent created at `0700` via `DirBuilderExt::mode` + recursive create + mode assert (`src/age.rs:1342-1359`, test `src/age.rs:2753`, live `700` on both created ancestors); `sync_all` → `rename` → chmod → parent `fsync` (`src/age.rs:1394,1405,1413,1419`); `--dry-run` prints `name -> path` and returns before `resolve_identity` (`src/main.rs:532-538`, test `src/main.rs:1165`); tilde expansion reaches deploy (`config.rs:43` via `load_from_standard_locations` → `load_manifest_spec` at `config.rs:246`; live `~/deployed/also` resolved under `$HOME`).

## Deviations

- **Doc self-contradiction, implementation followed the right half.** Phase 3 bullet says "canonicalize + assert" (doc:323); implementation uses `symlink_metadata` (`src/age.rs:1318`). The Architecture and Security sections (doc:170-177, doc:530-531) explicitly mandate `symlink_metadata` and call `canonicalize().is_symlink()` mechanically useless. **Acceptable** — the authoritative text won.
- **Only the immediate parent is checked, never ancestors** (`src/age.rs:1315-1318`). The doc offered two options (doc:171-173); the second (canonical vs literal path compare) would have caught a symlinked ancestor. So `~/.config/syncthing/cert.pem` deploys fine even if `~/.config` is a symlink. **Acceptable** on the doc's literal wording, but note the flip side for Phase 4: because an existing symlinked parent is *refused outright*, any `secrets.file` destination whose directory manifest itself symlinks will fail to deploy.
- **`Err(_)` catch-all treats every `symlink_metadata` failure as "missing"** (`src/age.rs:1336`). EACCES or ELOOP falls into the create branch and surfaces as "failed to create parent directory", misattributing the cause. Fails safe (creation then errors), but the message misleads. **Acceptable, sloppy** — a `NotFound` match with a pass-through for other errno values costs nothing.
- **Version bumped 0.3.3 → 0.4.0** (`Cargo.toml:3`, `Cargo.lock:1015`) inside the phase commit. Not called for anywhere in the doc, and a phase commit is not supposed to bump. **Unacceptable as scope** — it couples the phase to a release decision.

## Sibling-path inconsistencies

- **Trailing newline: same `.age` input, two treatments.** `env_escape` strips one trailing `\n` (`src/age.rs:121`); the file lane writes bytes verbatim (`src/age.rs:1392`). **Acceptable and in fact required** (an SSH key needs its newline, an env var must not carry one), but it is undocumented in the doc's contract sections.
- **No cross-block duplicate check.** `SecretsSpec` (`src/config.rs:196-203`) permits a name in both `env` and `file`; nothing in `config.rs` validates the intersection. The doc's fail-closed claim ("a `file` secret has no representation in the env lane", doc:133-135) then rests on operator discipline, not structure. **Not a Phase 3 deviation** (the doc never asks for the check) but a real gap in the advertised guarantee, and Phase 4 hand-declares 49 names.
- **Per-entry failure reporting differs by lane:** deploy → stderr + non-zero exit (`main.rs:549-558`); env → log-only `warn!`, exit 0 (`src/age.rs:1249`). **Acceptable** — doc:227-232 mandates exactly this asymmetry.
- **`secrets_deploy` bypasses the helper its sibling uses.** `main.rs:515-516` inlines the load + `resolve_secrets_dir` pair that `secrets_env_context` (`main.rs:606-616`) exists to encapsulate, and `resolve_secrets_dir`'s doc comment still reads "for `secrets env`" (`main.rs:564`, `:599`) despite deploy now being a caller. **Acceptable, cosmetic** — comment drift plus two duplicated lines.
- **No stderr banner on deploy** (`main.rs` deploy path vs `main.rs:662`). **Acceptable** — doc scopes the banner to the `.zshenv` fail-soft contract.
