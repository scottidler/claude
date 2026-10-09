# Retro fixes: implementation notes

Design doc: `docs/design/2026-10-08-retro-fixes.md`

## Phase 0: Spike, zero code

### Design decisions
- Results recorded in a "Phase 0 results" block directly under the Phase 0 table, one paragraph per row with the exact stdout and the branch taken. The table rows stay as written so the pre-spike plan reads as it was. `docs/design/2026-10-08-retro-fixes.md`, Phase 0.
- The hook-env row was measured by running the probe from a scratch script under the Bash tool, both sandboxed and with the sandbox off. A PreToolUse hook is an unsandboxed child of the Claude process with its env, and the Bash tool inherits that same env. Registering a real throwaway hook would have meant editing the live `settings.json`, which the orchestrator ruled out.
- The rails -> shell hook order row was measured with the live pair (rails's `GH_PERSONA` injection and `rewrite-cd-read.py`'s per-invocation log) instead of a scratch hook. Both already run on every Bash call, and the log records the exact text the shell hook received, so nothing had to be registered.
- The fresh-session rule loading row was measured with `claude -p` in three scratch project dirs outside `~/repos` (cli.md in `rules/`, in `refs/`, and a dangling `rules/` symlink), each with a copy of `otto.md` as a positive control. The live `~/repos/.claude/rules/` was not touched.
- `scottidler/obsidian` is the home-private case, because `scottidler/bump` (the row's named target) is public.

### Deviations
- otto-in-clyde row: the row says clyde's tasks install `cargo-mutants`. They do, but only in the `mutants` task, which is NOT a `before:` of `ci` (`clyde/.otto.yml:146-153`). `otto ci` ran clean sandboxed and installed nothing. `otto mutants` was not run (a mutation-test run is costly and not what the row was asking); its `cargo install` reaches the same crates.io hosts the cold-fetch row proved.
- Hook-env row: measured by simulation (same env, same sandbox state as a hook), not by a registered PreToolUse hook. Same effect, without touching the live setup.
- Rails order row: measured against `rewrite-cd-read.py`, not `git-release-guard.sh` itself. Both are PreToolUse shell hooks on the same Bash event and receive the same `tool_input`.
- Fresh-session row: measured in scratch project dirs with `claude -p`, not via a scratch commit moving the live `cli.md`. The live move would change every running session.

### Tradeoffs
- Simulated hook env vs a real registered hook: the simulation cannot prove that the interactive Claude process env matches the Bash tool env byte for byte (the Bash tool also sources a shell snapshot). It does not change the verdict: the private-repo `UNKNOWN` came WITH the right token, and the `nopersona` case covers a hook env missing the persona vars. Both read `UNKNOWN`, never a false verdict.
- `--model haiku` for the rule-loading probe vs a stronger model: the question is a yes/no lookup over loaded instructions, and the in-session `OTTO=yes` control plus the `rl-yes` `CLI=yes` control show it answers truthfully in both directions.

### Open questions
- Private home repos read `UNKNOWN` permanently: GitHub returns HTTP 403 "Upgrade to GitHub Pro or make this repository public" on the classic-protection endpoint for a private repo on a free plan, with the correct token. Gates E/F as designed would deny every `gh pr create` and every `git push ... main` in `scottidler/obsidian`, `scottidler/keep`, and any other private home repo. The ruleset endpoint answers the same 403 (`gh api repos/scottidler/obsidian/rules/branches/main` -> `Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)`), so on this plan GitHub can enforce neither layer: the repo is ungated in fact. Options: (A) bump reads that specific 403 on both probes as `none (ungated)`, which is the truth on this plan; (B) Gates E/F fail closed there and Scott accepts the denials; (C) Gates E/F apply only to orgs where the probe can answer. Needs a decision before Phase 12, and (A) is a bump change outside this repo.
- Phase 12 waits on Scott applying the `pull_request` ruleset to `tatari-tv/marquee` main; `bump --gates` there still prints `Gates:  none (ungated)`.
- Phase 6's operator step should name removing the dangling `~/repos/.claude/rules/cli.md` and `logging.md` symlinks and a scoped manifest apply to link `refs/cli.md` and `refs/logging.md`. Measured harmless if left dangling (`rl-dangle`), but they are dead links.
- Out of scope, recorded so it is not lost: rails picks the `GH_PERSONA` from the hook's `cwd`, not from a `cd` inside the command, so `cd ~/repos/scottidler/x && gh ...` from a tatari-tv cwd gets `work`.

## Phase 1: Release rulings ref (fix 5)
### Design decisions
- Ref has an "In force" list and a "Superseded" heading, 24 lines total: `HOME/repos/.claude/refs/release-rulings.md`: the doc asks the superseded entries sit under their own heading so the next agent does not re-derive them.
- Pointer is one bullet right under the invariant paragraph of "Tagging / releases": `HOME/repos/.claude/rules/git.md`: keeps the invariant first.
- References entry placed alphabetically before `sccache-sandbox.md` with the same two-bullet shape as its siblings: `HOME/.claude/CLAUDE.md`.
- The 10-02 (a) and 10-07 (a)/(d)/(e) bullets cite the hall line of the lesson itself, read from the file, not the doc's range.

### Deviations
- Hall line numbers differ from the doc's: 10-02 (a) is `:1742` (doc `:1740`), lint-unused is `:1757` (doc `:1756`), 09-29 (a) is `:1660` (doc `:1652`, which is the crime bullet, not the lesson), 10-07 is `:2023-2027` (doc `:2021-2026`, which starts one line early). The ref cites the observed lines; the hall has grown since the doc was drafted.
- 10-07 (a), (d), (e) and 09-26's "one release command" are listed as in force; 10-05 (d) cited as `:1974`, which matched.
- `refs/` is referenced as `~/repos/.claude/refs/release-rulings.md` (the deployed path), matching how CLAUDE.md names the other refs.

### Tradeoffs
- Citing hall lines vs quoting rulings in full: lines keep the ref under 40 lines and the hall stays the ledger; the cost is line drift as the hall grows.

### Open questions
- The ref only resolves at `~/repos/.claude/refs/` after a scoped manifest apply, like the other refs (see Phase 6's open question on links). Not run here.

## Phase 2: Bridge-socket line (fix 8)
### Design decisions
- One bullet appended to the phantom-files bullet list, after the `excludedCommands` bullet: `HOME/.claude/CLAUDE.md`: the doc says "beside the phantom-files bullets", and both are sandbox-failure behavior.
- Bullet names the exact error string, says nothing recovers it, and says stop and tell Scott to restart: the doc's architecture paragraph, which also notes no hook can see it pre-call.

### Deviations
- None.

### Tradeoffs
- A prose bullet vs a hook: the doc states no hook can see the failure before the call, so a rule line is the only available mechanism.

### Open questions
- None.
