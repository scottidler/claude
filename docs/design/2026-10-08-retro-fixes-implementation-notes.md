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

## Phase 3: security-guidance off (fix 12)
### Design decisions
- `enabledPlugins["security-guidance@claude-plugins-official"]` set to `false`: `HOME/.claude/settings.json:1069`: the doc's line number matched exactly.
- Staged only that hunk: the file carries an unrelated uncommitted `"model": "opus"` -> `"fable"` change (line 745) that belongs to Scott and stays in the working tree.

### Deviations
- None.

### Tradeoffs
- Partial staging via `git apply --cached --unidiff-zero` vs committing the whole file: the model change is not this phase's.

### Open questions
- None.

## Phase 4: excludedCommands shrink (fix 6)
### Design decisions
- Removed `cargo *`, `otto *`, `journalctl *` from `sandbox.excludedCommands`: `HOME/.claude/settings.json:1150`: Phase 0 proved all three run sandboxed (cold cargo fetch, otto in clyde, marker runs); `systemctl *` and the other entries stay.
- Dropped the `excludedCommands` line from the Fix snippet and rewrote the belt-and-braces snippet: `docs/sandbox-filesystem-allowlist.md`: both restated the removed heads (and a stale `release *` entry that is not in `settings.json`).
- Supersession of `enforcement-core.md:357` recorded under Resolved Decisions in the design doc.
- Staged only the phase hunks with `git apply --cached --unidiff-zero`; the unrelated `"model": "opus"` -> `"fable"` hunk stays in the working tree.

### Deviations
- `HOME/.claude/agents/review-panel.md:90-91` has no list to update: those lines scope `/tmp/review-panel`, and the file mentions `excludedCommands` only for the two seat scripts (lines 137-222), never `cargo`/`otto`/`journalctl` (`rg` found none). No edit made there; recorded in Resolved Decisions.
- `HOME/.claude/skills/rails/hooks/index.test.ts` edited though the phase did not list it: its test "the settings.json this repo ships reads as the live list" pinned the old ten-plus entries and failed `otto ci`. Added `SHIPPED_EXCLUDED` for that one test; `EXCLUDED` stays as a labeled fixture with `cargo`/`otto`/`journalctl` as stand-in heads because ~45 classification tests use `cargo` as the excluded head and test hook logic, not the shipped list.

### Tradeoffs
- Rewrote the doc snippet vs deleting the sentence: the optional belt-and-braces idea is still valid for the seat scripts, so it stays with the stale heads removed.

### Open questions
- None.

### Fresh-session verification (observed)
Method: `claude -p --no-session-persistence --model haiku --allowedTools=Bash` from a scratch dir outside any repo, probe crate (append-open on `~/HALL-OF-SHAME.md` plus `SANDBOX_RUNTIME`) with a one-task `otto.yml` running `cargo run -q`. The probe was rebuilt from the Phase 0 description; the Phase 0 original was not preserved.
- `cargo --version && git status .` in the scratch dir: `cargo 1.98.0 (797e8a9bc 2026-08-05)`, then `fatal: not a git repository` (rc 128; the scratch dir is not a repo; not a denial).
- bare `cargo run -q` in the probe: `append-open: Read-only file system (os error 30)`, `SANDBOX_RUNTIME=1` (sandboxed, built and ran).
- bare `otto ci` in the probe: `[ci] append-open: Read-only file system (os error 30)`, `[ci] SANDBOX_RUNTIME=1`, `[ci] finished successfully  0s`.
- bare `otto ci` in `~/repos/scottidler/bump`: `rc=0` (first fresh run, in-session echo), last lines `[ci] ✅ All CI checks passed!` / `[ci] finished successfully  0s`. A second run's rc echo came back empty (the subagent used bash `PIPESTATUS` under zsh), but it printed the same pass lines.

## Phase 5: Review-panel run dir (fix 9)
### Design decisions
- Run dir is `~/.cache/review-panel/runs/`; the three `/tmp/review-panel` settings entries (`additionalDirectories`, `allowWrite`, `allowRead`) are deleted, found by content since lines shifted — HOME/.claude/settings.json — `~/.cache` is already in `allowWrite`.
- Step 0 prunes with `find ~/.cache/review-panel/runs -mindepth 1 -maxdepth 1 -mtime +14 -exec rm -rf {} +` before `mktemp -d` — HOME/.claude/agents/review-panel.md — the rails wrapper rule passes it because the literal path sits under the `runs/` scratch prefix.
- `SCRATCH` gains `~/.cache/review-panel/runs` and `homedir() + '/.cache/review-panel/runs'`; `rounds/` stays outside — HOME/.claude/skills/rails/hooks/index.ts — rails compares literal prefixes, and a wrapper `rm` must not reset the round cap.
- `docs/sandbox-filesystem-allowlist.md` keeps its history and gains a "Round 3" section; only the "Current entries" block was corrected.
- New test asserts `sudo rm -rf` on `runs/x` (tilde and absolute) is not denied and on `rounds/x` (both forms) is — HOME/.claude/skills/rails/hooks/index.test.ts.
### Deviations
- The criterion's `rm -rf ~/.cache/review-panel/...` is tested through the wrapper form (`sudo rm -rf ...`): `SCRATCH` is consulted only by `wrapperDenied`, and a bare `rm -rf` takes the rkvr rewrite path instead. Same effect, correct seam.
- Test bite proven against the old `index.ts` (from `HEAD`): the new case fails there.
### Tradeoffs
- `homedir()` for the absolute form vs a hardcoded `/home/saidler`: portable across hosts (ripr), evaluated once at load.
### Open questions
- None.

## Phase 6: Steering trim (fix 14)
### Design decisions
- Deleted `HOME/.claude/tools.md` and its `@` include in `HOME/.claude/CLAUDE.md`; `git mv` of `cli.md` and `logging.md` to `HOME/repos/.claude/refs/` with frontmatter stripped; pointers added at `agents/phase-implementer.md` (Implement step) and `agents/review-panel.md` (standards-filter bullet).
- Four `taste.md` sections (pipeline, design doc as source of truth, phasing, evidence standards) moved verbatim to `refs/process-taste.md`; `taste.md` keeps a three-line pointer where they were. Pointers added in `skills/create-design-doc/SKILL.md` (step 0), `skills/how-to-execute-a-plan/SKILL.md` (above Execution Mode), and `agents/review-panel.md`.
- `voice.md` gained `alwaysApply: true`. `CLAUDE.md` Rules list drops `cli`/`logging`; References section gained `process-taste.md`, `cli.md`, `logging.md` entries.
- Always-on byte total: for each `HOME/repos/.claude/rules/*.md`, include it if line 1 is not `---` or its frontmatter has `alwaysApply: true`; add `wc -c` of `HOME/.claude/CLAUDE.md`, `HOME/.claude/WHOAMI.md`, `HOME/repos/CLAUDE.md`. Result: 57,569 bytes (<= 60,150).
- Fresh-session check (Phase 0 method, scratch dir under `$TMPDIR`, outside `~/repos`, `claude -p --no-session-persistence --tools "" --model haiku`): scratch project with `rules/otto.md` (positive control), `refs/cli.md`, and a dangling `rules/cli.md` symlink (the live post-phase state). Output: `CLI=no` / `OTTO=yes`, rc=0.
### Deviations
- Updated references the doc did not list, all live: `HOME/.pi/agent/extensions/rules/index.ts` (dropped `tools.md` from `INLINE_FILES` and the now-unneeded `ALWAYS_ON_EXTRAS` voice special case, since `voice.md` declares `alwaysApply`), `HOME/.pi/agent/AGENTS.md` (two `tools.md` pointers now say `~/.cargo/bin` / `--help`), `README.md` (tree row), comments in `hooks/inline-skill-tokens.py` and `hooks/inline/matcher.py` (`rules/logging.md` -> `refs/logging.md`). Same effect, correct seam: the references would otherwise dangle.
- `.otto.yml` lint: em-dash list entry `rules/cli.md` retargeted to `refs/cli.md` (plus `refs/process-taste.md` added so moved taste text stays linted), and the frontmatter check changed from "only voice.md lacks frontmatter" to "every rule has frontmatter", since `voice.md` now declares it. Without both, `otto ci` lint failed.
- `HOME/.claude/bin/gen-tools` left untouched: it still writes `~/.claude/tools.md`. It is now an orphan generator; not deleted because the doc did not say to.
### Tradeoffs
- `ALWAYS_ON_EXTRAS` removed from the pi extension rather than kept: it was a workaround for voice's missing frontmatter, which this phase fixes.
### Open questions
- Retire `HOME/.claude/bin/gen-tools` (its output file is gone and nothing includes it)?
- Operator step (NOT run, no manifest apply). Live state after this phase, `ls -la`: dangling `~/repos/.claude/rules/cli.md` and `rules/logging.md` (-> repo `rules/` paths that no longer exist) and `~/.claude/tools.md`; missing `~/repos/.claude/refs/{cli,logging,process-taste,release-rulings}.md` (release-rulings is Phase 1's, also never linked). Pointers in agents/skills read `~/repos/.claude/refs/...` so they dead-end until linked. Danger: the pi `rules` extension `readdirSync`s `rules/` and `readFileSync`s each `.md`, so a dangling symlink throws at pi session start until fixed. Fix: scoped link apply, e.g. `manifest -l 'HOME/repos/.claude/*' -l 'HOME/.claude/*'` (confirm the glob form against `manifest.yml`'s `link:` keys first), then `rm` the three dead symlinks (use `rkvr rmrf`).
