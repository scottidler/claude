---
paths:
  - "**/*"
---

# Safety Rules

## File Deletion

- The rule is about intent, not the `rm` binary itself (Scott, 2026-09-13): "if its a build directory, we can rebuild the files and it only costs us time and compilation. other artifacts cant be easily recovered or reproduced, thats why they get the rmrf." Regenerable build output may be removed with plain `rm`/`rm -rf`. Everything else, anything that cannot be reproduced, goes through `rkvr rmrf`, which archives to a three-week bin before deleting.
- The regenerable set (rails carries the same table, `HOME/.claude/skills/rails/hooks/index.ts`). Match is positional: the basename below AND the toolchain file that produces it in the parent directory, never a bare basename.
  - `target` next to `Cargo.toml`
  - `node_modules`, `dist`, `build`, `out`, `coverage`, `.next`, `.turbo`, `.parcel-cache` next to `package.json`
  - `dist`, `build`, `.venv`, `venv`, `.tox`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `*.egg-info` next to `pyproject.toml`, `setup.py`, `setup.cfg` or `requirements.txt`; additionally `.tox` next to `tox.ini` and `.pytest_cache` next to `pytest.ini`
  - `.gradle` next to `build.gradle`, `build.gradle.kts` or `settings.gradle`; `.terraform` next to any `*.tf`
  - `__pycache__` anywhere (it only ever holds bytecode)
  - `pom.xml` is deliberately not an anchor for `target`: a tracked Maven `target/` in one work repo holds data files, not only classes. `bin/` and `vendor/` are deliberately not in the set (tracked in 18 and 6 repos respectively; `general.md` mandates `bin/`).
- Scar tissue, why the match is positional and never a bare basename: `crates/loopr/src/target/tests.rs` is a tracked Rust source module named `target`, not a build directory. The anchor check is what tells them apart.
- A path outside the set that is still regenerable build output gets a trailing `# regenerable` comment on the `rm` stage. That marker asserts intent and is audited; it should never ride on a path in a home or repo tree that is not obviously build output.
- CI-teardown exception: a repo's own pipeline may use plain `rm`/`rm -rf` to clean its own workspace between runs. `rkvr` protects files on Scott's machines, not a CI runner's throwaway checkout (Scott, 2026-07-08: "rkvr is meant for protecting files on MY SYSTEM!").
- Anything the set, the marker and the CI-teardown case do not cover goes through `rkvr rmrf`. No other exceptions.

## Formatting

- NEVER use em dashes (the U+2014 character) in any output. Use a colon, parens, a comma, or split the sentence. Replacements per `rules/voice.md`; pick per site, never a blanket substitution.
- **Scope is everything, and SOURCE CODE IS IN SCOPE.** Documentation, code comments (`//`, `///`, `//!`, `#`, docstrings), string literals, Confluence, Jira, Slack, PR titles and bodies, commit messages, config files, and any external system. There is no code exemption.
  - This used to say "documentation, comments, Confluence, Jira, Slack, or any external system" and left code *implicit*. On 2026-07-30 `tatari-tv/clyde` was measured at **373 em-dash occurrences across 79 `.rs` files**, overwhelmingly in comments: the tree had read the silence as an exemption. Scott's call that day: "yes ammend and kill all em-dashes." Hence the explicit enumeration.
- **A convention with no lint re-accumulates**, which is why enforcement is a CI check and not this file alone. Repos enforce it in the `.otto.yml` `lint` task:

  ```
  if rg -n --type rust -g '!target' '\x{2014}' .; then
    echo "❌ Found em dash in Rust source."
    exit 1
  fi
  ```

  Scope the lint to the whole tree, not `*/src/`: 17 of clyde's 373 lived in `*/tests/` integration files, which a `grep -r … */src/` shape never walks. A lint narrower than the rule is a hole the tree drifts back through where CI cannot see it. `\x{2014}` keeps the lint file itself em-dash-free.
- The one legitimate need for the character in code is an assertion that em-dashes are ABSENT. Write it as `'\u{2014}'` so the assertion survives and the tree still carries no literal.

## Python Package Management

- NEVER use `pip install`. EVER. Always use `pipx` for installing Python tools/packages. No exceptions.
