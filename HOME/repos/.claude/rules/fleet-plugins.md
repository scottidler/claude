---
paths:
  - "**/tatari-tv/marquee/**"
  - "**/tatari-tv/persona-cli/**"
  - "**/tatari-tv/clyde/**"
  - "**/tatari-tv/sdv/**"
  - "**/tatari-tv/slack-cli/**"
  - "**/tatari-tv/shepherd/**"
  - "**/tatari-tv/pagerduty-cli/**"
  - "**/tatari-tv/tatari-skills/**"
---

# Fleet repos publish MORE than a binary

`marquee`, `persona-cli`, `clyde`, `sdv`, `slack-cli`, `shepherd` and
`pagerduty-cli` each ship **four surfaces from one repo**, and a behavior change
usually touches all four:

1. the **CLI** (`src/cli.rs` help text, or the equivalent)
2. the **MCP server** (tool descriptions, request schemas, AND the handshake)
3. `plugin/`, **a published Claude Code plugin** consumed by `tatari-skills`
4. `README.md`

**`plugin/` is not scaffolding.** `tatari-skills/.claude-plugin/marketplace.json`
references it as a `git-subdir` "foreign ref" pinned to a release tag:

```json
{ "source": "git-subdir", "url": "https://github.com/tatari-tv/<repo>",
  "path": "plugin", "ref": "vX.Y.Z" }
```

`plugin/.claude-plugin/plugin.json` carries **no version** (the marketplace schema
forbids it on an entry). **The pinned `ref` IS the version.** So tagging in the
tool's own repo does not update the plugin; only editing that `ref` in
`tatari-skills` does.

There IS automation for the pin, so do not hand-bump one without checking:
`tatari-skills/.github/workflows/pointer-refs.yaml` runs
`bin/skillzy check-pointer-refs` every Monday 15:00 UTC (08:00 PT) and opens a PR
proposing the bumps. **It never auto-merges**, because a pin bump imports plugin
content reviewed in the source repo, so the human step is reviewing and merging
that PR. Bump the pin by hand only when you do not want to wait for Monday, and
say that you are short-circuiting the weekly PR. `tatari-skills/CLAUDE.md` is
authoritative on this; read it before touching `marketplace.json`.

`clyde`, `slack-cli` and `shepherd` have **no `CLAUDE.md`**, so this rule is the
only place that says any of it. Do not assume a repo without `CLAUDE.md` has no
publishing obligations.

## The one command that answers "is anything stale?"

In `tatari-skills`, **pull first**, then:

```bash
git pull --ff-only origin main && bin/skillzy check-pointer-refs
```

It prints every pointer plugin as `current` or `vOLD -> vNEW (plugin/ changed)`.
It reads the **local checkout**, so a stale local `main` reports a stale pin that
is already fixed on the remote. Measured 2026-09-21 on a stale local main: it
reported `persona: v1.8.4 -> v1.9.1` when `origin/main` already read `v1.9.1`.

Four pins were stale that day (`marquee`, `sdv`, `shepherd`, `slack`), so do not
assume the fleet is in sync. Grepping `tatari-skills/plugins/` for a command name
proves **nothing**: these plugins live in their own repos and are only referenced
there. That mistake is exactly how a two-release-stale `persona` pin went
unnoticed while its own repo was being worked on all session.

`tatari-skills/CLAUDE.md`'s pointer list can lag the registry: it named seven
entries while `check-pointer-refs` reported nine (`shepherd` and `ttv` were
added later). Trust the command over the prose.

## Before you tag ANY of these repos

Behavior changed? Check all four surfaces agree, not just the one you edited:

```bash
# from the tool's repo root: find every place the old wording/flag still lives
rg -n '<the old string>' src/ README.md plugin/
```

- A design doc that enumerates "the N places this appears" is a **floor, not a
  count**. Grep it yourself. On persona-cli the doc listed 9 sites; the real
  number was 10, and the missed one was in `plugin/`.
- **A tag is immutable bytes.** A doc site missed inside a tag costs a whole new
  release, not an edit. That asymmetry is why the grep is cheap before `bump` and
  expensive after.
- Before pointing the `tatari-skills` pin at a tag, **read that tag's `plugin/`**:
  `git show <tag>:plugin/skills/<name>/SKILL.md`. Never trust release notes or
  intent.

## CLI and MCP are one binary and must change together

Every command has two entry points over the same core: the CLI path
(`commands/<cmd>.rs::run`) and the MCP path (`mcp.rs::<cmd>_result`). Both must
call the same pure functions.

- Change the request struct AND **the handler body**. A handler that forwards only
  some fields lets the rest deserialize and get silently dropped, and neither a
  schema test nor a helper test notices.
- `#[tool(description = ...)]` is what clients see. The `///` doc comment above it
  is **not exported**, so editing only the `///` changes nothing.
- **Write one test that runs the CLI path and the MCP path over the SAME fixture
  and asserts equal output.** Per-path tests both pass while the two disagree.
- The MCP handshake version must come from the **same source as the CLI's
  `--version`** (`GIT_DESCRIBE` via `build.rs`), never `CARGO_PKG_VERSION`. Two
  sources agree only on a clean tagged build and diverge everywhere else
  (`1.9.1` vs `v1.9.1`).

## A registered MCP client keeps serving the OLD binary after install

`cargo install` replaces the binary on disk, but a long-lived stdio child keeps
running the code it started with. After shipping, the CLI and the MCP tools answer
the same question differently until that child restarts.

- **Always tell Scott to reconnect (`/mcp`) or restart the session after an
  install.** `<tool> --version` proves nothing about the running MCP child.
- Fastest staleness tell: the child advertises a **stale tool schema**. Query the
  tool's parameters and look for fields the current release added. Or compare the
  handshake's `result.serverInfo.version` to `<tool> --version`.
- There is no auto-reload and no version gate. Restarting is the whole mechanism;
  do not claim otherwise.

## Sequence when a change touches `plugin/`

1. Fix `plugin/` in the tool's repo **alongside the code**, same PR.
2. Ship a tag from that repo (the usual `bump` flow: `bump --no-tag` on the
   feature branch, `bump --tag-only` after merge).
3. Verify the tag's `plugin/` with `git show <tag>:plugin/...`.
4. Bump `ref` in `tatari-skills/.claude-plugin/marketplace.json` to that tag, as
   its own PR in that repo.

Step 4 is a **pointer-ref edit with no version field touched**, which
`tatari-skills/bin/checks/bumps.py` documents as the sanctioned "per-release
ref-bump path". It is NOT a manual version bump and NOT a forbidden bump-only
branch, so do not name the branch `bump-*` or `release-*` (a hook denies those on
name alone). Validate with `bin/skillzy validate` and
`bin/skillzy check-pointer-refs`.

## Scar tissue (2026-09-21, persona-cli, three tags for one feature)

Both of these shipped because verification was scoped to the design doc rather
than to the repo's published surfaces:

- **v1.9.1** existed only because `plugin/skills/lookup/SKILL.md` still documented
  `--terminated` as additive *inside the v1.9.0 tag*. The docs phase fixed
  `src/cli.rs`, `README.md` and seven `src/mcp/tools.rs` sites and never opened
  `plugin/`.
- **v1.9.2** existed only because the MCP handshake reported `CARGO_PKG_VERSION`
  while the CLI reported `GIT_DESCRIBE`, so the two disagreed and staleness was
  undetectable. The MCP-parity phase had edited that exact file.

A design review reads the doc, an implementation audit walks the plan's bullets,
and a CLI shakedown exercises the binary. **None of those reads `plugin/`, and
none performs an MCP handshake.** Four green gates keyed off one artifact are one
check wearing four hats. At least one check must start from the surface list
above rather than from the plan.
