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

## Phase 7: JQL line (fix 13c)
### Design decisions
- New "JQL Searches (Atlassian MCP)" section in `HOME/repos/.claude/refs/jira.md`: `fields` and `maxResults` (at most 25) always, recommended `fields` of summary/status/assignee/updated, `responseContentFormat: "markdown"`, `nextPageToken` for paging, `searchResultMode: "count"` only for counts (the doc's fix 13c) because the default field set includes `description`.
- Parameter names taken from the live `mcp__atlassian__searchJiraIssuesUsingJql` schema, checked via ToolSearch in-session by the orchestrator on 2026-10-09 (required `cloudId`, `jql`; optional `fields`, `maxResults`, `nextPageToken`, `responseContentFormat`, `searchResultMode`).
- The tool's `maxResults` description reads "Max (50-100)" but the schema has `maximum: 100` and no minimum. The doc's <= 25 stands because the schema permits it. If the server rejects values under 50 at call time, this line needs revisiting.
### Deviations
- None.
### Tradeoffs
- A five-bullet section vs a fuller parameter table: the fix is a tool-budget guard, so only the parameters that move result size are listed.
### Open questions
- Does the Atlassian server enforce the "50-100" in the description at call time? Not exercised in this phase (no live JQL call made).

## Phase 7 addendum (orchestrator, 2026-10-09)

### Open questions
- Closed: the Phase 7 open question (does the server enforce the "Max (50-100)" description text). A live read-only call, `searchJiraIssuesUsingJql` with `jql: "project = AIF ORDER BY updated DESC"`, `fields: ["summary","status","assignee","updated"]`, `maxResults: 5`, `responseContentFormat: "markdown"`, returned exactly 5 issues, only the four requested fields, plus `nextPageToken` and `isLast: false`. Values under 50 are accepted; the at-most-25 line stands.

## Phase 8: Title-guard fixture (fix 11)
### Design decisions
- One fixture added to the "slash branches" block of `HOME/.claude/hooks/branch-pr-title-guard-test.sh`: branch `chore/retire-general-plugin`, title `chore(marketplace): retire general plugin`, asserts the deny reason contains `git branch -m chore-retire-general-plugin`. Guard untouched (rename text already shipped in `0907a90`).
- Bite proof in a scratch copy of the whole hooks dir (the guard sources `lib.sh`, so a lone copy allows everything): replacing the guard's `git branch -m $bslug` with `git branch -m x-$bslug` made the new fixture FAIL (`reason lacks "git branch -m chore-retire-general-plugin"`), pass=49 fail=2; the other failure is the existing `fix-markdown-dark-mode` slug fixture. The real hook: pass=51 fail=0.
### Deviations
- None.
### Tradeoffs
- Full-slug assertion on a second chore-prefixed branch vs relying on the generic `git branch -m` substring fixtures: the substring never pinned the computed slug, which is the model-facing instruction.
### Open questions
- None.

## Phase 9: bump honors a directory (scottidler/bump)
### Design decisions
- `ReleaseArgs.dir` / `FinishArgs.dir`, `Option<PathBuf>` positional `[DIR]` -- bump `src/cli.rs` -- the top-level `DIRECTORIES` positional is untouched; `bump release /path` stays a bare simple command.
- `resolve_verb_dir(Option<&Path>)` -- bump `src/main.rs` -- one pure resolver for both verbs: explicit dir (made absolute against cwd), else cwd; logs explicit and resolved at DEBUG. `dispatch_command` calls it per verb; `dispatch_release`/`dispatch_finish` already took `&Path`, so they are unchanged.
- Tests: one per verb parses `bump <verb> -n /some/repo` and asserts the resolved dir, plus a default/relative test. Bite proven: forcing the resolver to ignore the explicit dir failed all three.
- README usage lines gain `[DIR]`; clap help picks it up from the arg.
### Deviations
- None to the spec. Branch `release-verbs-take-dir`, one commit (eba0468) in the bump repo; no push/tag/release (the doc's "lands with `bump release`" is the parent's finalization).
### Tradeoffs
- Unit tests on the resolver plus clap parse vs a subprocess end-to-end test -- the end-to-end run was done by hand against the built binary from outside any repo; a subprocess test would need a fixture with a fetchable origin.
### Open questions
- `bump release -n <repo>` from outside the repo could not print a dry-run plan here: the repo was on its feature branch, and the verb refuses off-default ("runs on the default branch 'main', but you are on 'release-verbs-take-dir'"), which names the repo's branch and so proves the dir was honored. The plan print for release is only reachable on main with something to release; confirm the refusal is acceptable evidence until the branch merges. `finish -n` printed the full dry-run plan, rc=0.

## Phase 10: Not-a-repo gate (fix 4)
### Design decisions
- `not_a_repo_gate` -- `HOME/.claude/hooks/git-release-guard.sh` -- called first in `check_stmt`, before the tag gates, for any statement whose command word is `git` or `bump`. Judges the directory the statement runs in: `resolve_stmt_tree`'s `cd_at` directory, then git's global `-C`/`--git-dir` or bump's directory positionals resolved against it; `git -C <dir> rev-parse --git-dir` failing -> deny.
- git's global options are parsed by POSITION (only before the subcommand), not by `dash_c_tree`'s directory-exists heuristic: `git commit -C <commit>` and `git switch -C <branch>` put theirs after the verb, and a branch named like a directory would fool the existence test. Fixture `git commit -C $REPO` from /tmp denies.
- bump: `release`/`finish` [DIR] and the legacy top-level `DIRECTORIES` (which is what `bump --gates <dir>` uses) are resolved the same way; every directory named is checked, not just the first; none named means the statement's directory. Value-taking flags (`--message`, `--install`, `--standalone`, `--ci-timeout`, greedy `--skip-member`) are skipped so their values are never read as directories. This is the design-gap call the parent asked for: resolve, don't deny.
- Stands down (allows) whenever the hook cannot know the directory: an unexpanded `$VAR`/backtick/substitution or `~` path, a `cd` it cannot follow (`resolve_stmt_tree` now records `stmt_cd_unknown` for `cd -`, `cd "$X"`, or a non-directory target), a `-C` target that does not exist (git refuses that loudly itself), or a leading `GIT_DIR=`/`GIT_WORK_TREE=` assignment. If `cmdword_is` matched but no token reads as the verb, the statement's own directory is judged with no exemption (fail closed).
- Tests: 85 new cases in `git-release-guard-test.sh` (16 denies, 18 shape-swept denies x2 via `runcwdwrapped` from `shapes.sh`, 33 allows). Self-test 289/0 before -> 374/0 after. Bite: the new test file against `git show dc91785:HOME/.claude/hooks/git-release-guard.sh` (scratch dir with `lib.sh` and `shapes.sh` beside it) -> pass=322 fail=52; all 52 failures are the new denies ("want deny got allow"), including `bump finish` and `git status` at `/tmp`; every allow held on the old hook too.
### Deviations
- Baseline: the criterion says `HEAD~1`. The bite ran before this commit existed, when `HEAD~1` was `3240e91` (unrelated); it used `dc91785`, the commit before this phase, explicitly. After this commit `HEAD~1` resolves to the same `dc91785`.
- Deny text splits by tool (same effect, truer hint): git -> "'<dir>' is not a git repository. 'cd <repo>' in its own call, or 'git -C <repo> ...'."; bump -> "... or 'bump <verb> <repo>'." with the actual verb filled in when it is `release`/`finish`. The doc's single text tells a `git status` caller to run `bump <verb> <repo>`, which is the wrong tool. Single quotes instead of the doc's backticks, matching every other deny in the file.
- Exemptions added beyond the doc's list, each legal outside a repo: `git version`, `git -v`/`-h`/`--help`/`--exec-path`/`--html-path`/`--man-path`/`--info-path`, `--help` anywhere after a git verb, bare `git`, `git diff --no-index`, the `git rev-parse` repo probes (`--is-inside-work-tree`, `--is-inside-git-dir`, `--git-dir`; denying the probe whose answer IS "not a repo" would break every script that asks), and bump `-h`/`--help`/`-V`/`--version`.
- `git ls-remote <url>`: "url" is read as any operand carrying `:` or starting `/`, `./`, `../`; a bare word is a remote name and is still denied outside a repo.
### Tradeoffs
- Allow on an unresolvable directory vs deny: the verdict names one directory, and a guess would deny legitimate `cd "$REPO" && git ...` chains from a non-repo session; git and bump still fail loudly on their own if the guess would have been right.
- Position-based global-option parse vs reusing `dash_c_tree` verbatim: the precedent cannot tell `git commit -C <sha>` from `git -C <dir>` when a directory of that name exists; the position can.
### Open questions
- `HOME/.claude/bin/pr-open` cites `git-release-guard.sh:563` and `:566` for Gate D in a comment and two `die` texts; those line numbers were already stale before this phase and moved further with it. Not touched here (out of phase scope); a later phase or a pointer-by-name fix should own it.

## Phase 11: Sandbox-off deny (fix 3)
### Design decisions
- `sandboxoff_deny` -- `HOME/.claude/hooks/intent-guard.sh` (beside the `sandbox_off` read) -- one deny text for all three heads, carrying the doc's API text with the actual verb filled in (`git push`, `ssh`, `bump release`; `bump` alone when no verb token is found). The parenthetical `(from a subagent: \`bump <verb> <repo>\`)` stays literal: interpolating the git/ssh verb into it would read `bump git push <repo>`.
- GIT-NET: the flag now denies inside the `GITNET_VERBS` case, after the HTTPS-URL override deny and before the shape rule; the shape rule lost its `sandbox_off -eq 0` guard (with the flag set it can no longer be reached). SSH-SHAPE: same, the flag denies first, the substitution/redirect shape checks run unguarded. bump: new per-statement check, `cmdword_is bump` with the flag set, any bump invocation (including `bump --gates`), since `bump *` is in excludedCommands.
- Fixtures: the old "same shapes are fine with the sandbox off" section is now "SANDBOX-OFF: excluded heads deny with the flag set". The three old `runsb allow` fixtures flip to deny (`cd ... && git push origin x`, the piped push, `git -C ... push ... | tail -2`), as does the SSH-SHAPE `runsb allow "ssh ripr.lan 'echo $(hostname)'"`. Added: the eight denies the criterion names plus `bump finish <dir>`, allows for `ls`, `git status`, and quoted prose, and a `runsbsays` helper asserting the reason text on three payloads.
- Self-test: before pass=599 fail=0, after pass=614 fail=0. Bite: the new test file beside the 49985c0 hook (scratch copy of the whole hooks dir) -> pass=598 fail=16; all 16 failures are the new sandbox-off denies/reason checks ("want deny got allow"), including the three flipped fixtures and the flipped ssh fixture.
- Prose: `release-driver.md` (the "What the two verbs do" paragraph and the three `bump release`/`bump finish` command lines in the loop), `rules/git.md`, `skills/bump/SKILL.md` (contract block plus synopsis), `skills/shipit/SKILL.md`, `skills/how-to-execute-a-plan/SKILL.md` now prescribe `bump release <repo>` / `bump finish <repo>`. Each states that the positional ships in the bump release carrying scottidler/bump commit eba0468 (installed bump v0.4.2 has no `[DIR]`, checked with `bump release --help`), and gives the interim: `cd <repo>` in its own call, then the bare verb, until `--help` shows `[DIR]`. No version number predicted. `refs/release-rulings.md` and `skills/babysit/SKILL.md` prescribe no cd shape; untouched.
### Deviations
- Fixture line numbers: the doc cites `intent-guard-test.sh:675-677,697`; at 49985c0 the three allow fixtures were at `:672-674` and the ssh one at `:695` (`:675-677` held the comment and the two override denies, which stay deny). Same fixtures by content.
- The PUBLIC-REPO section's `runsb_pending` variable (the piped push used to assert the refspec walk ignores a redirect) is gone: with the flag set the payload now denies on SANDBOX-OFF before the walk, and sandboxed it denies on GIT-NET, so no payload carries a pipe into the walk. The unpiped redirect fixtures (`2>&1`, `> /dev/null`) still carry that assertion. Comment updated to say so.
- Prose scope beyond the two files the doc names: the bump, shipit, and how-to-execute-a-plan skills carried the same separate-cd prescription, updated consistently (parent asked for this sweep).
### Tradeoffs
- Deny every bump with the flag vs only `release`/`finish`: `bump *` is excluded as a whole, so no bump form needs the flag; a narrower check would leave `bump --no-tag` and `bump --gates` as bypass routes for nothing.
- Interim fallback in the prose vs prescribing only `<repo>`: the installed bump rejects the positional today, so prose with no fallback would send every agent into an "unexpected argument" refusal until the release lands.
### Open questions
- Ship order: the doc says bump ships Phase 9 before Phase 11 lands. Phase 11 is committed while eba0468 is unreleased and uninstalled, so this hook (live on commit) denies the sandbox-off escape while release-driver run from outside the repo has no `bump release <repo>` yet. The parent should land the bump release before this commit reaches main, or accept the interim cd shape.
