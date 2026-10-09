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
