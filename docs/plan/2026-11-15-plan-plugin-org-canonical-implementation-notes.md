# Implementation notes: Make the org plan plugin canonical

Design doc: `docs/plan/2026-11-15-plan-plugin-org-canonical.md`

## Phase 0: Prove the switch in an isolated config dir

Zero code, no commit. Claude Code 2.1.325. In the commands below,
`$P` = `/media/saidler/4tb/claude-tmp/claude-1000/-home-saidler-repos-scottidler-claude/2b95322b-5443-4dc4-ac66-b61060934cd6/scratchpad/phase0`.
Canonical scratch: `HOME=$P/homegh2 CLAUDE_CONFIG_DIR=$P/homegh2/.claude`, marketplace
`tatari-tv/tatari-skills` from GitHub at `df92743d` (origin/main on 2026-11-15).

### Observed

- **(a) enabledPlugins alone vs install. Verdict: install needed. Fallback applies; Phase 7 already runs it.**
  - enabledPlugins only, GitHub marketplace (`$P/homegh`), `{"plan@tatari-skills":true,"pr@tatari-skills":true}`:
    - `claude plugin list` before any session: `No plugins installed. Use claude plugin install to install a plugin.`
    - Session 1 init (`claude -p --output-format stream-json --verbose --max-turns 1 "reply with the single word ok"`, filtered to plan/llm/tatari): `{"plugins":[],"agents":[],"skills":[]}`. Session start installs the enabled plugins in the background; that session loads none of them.
    - `claude plugin list` after: `plan@tatari-skills Status: ✘ failed to load Error: Dependency "llm@tatari-skills" is not installed`. enabledPlugins does NOT pull dependencies.
    - Added `llm@tatari-skills: true`. Session 2 init: `{"plugins":["pr@tatari-skills 0.6.22"]}`. Session 3 init: same, plus `"plugin_errors":[{"plugin":"plan@tatari-skills","type":"dependency-unsatisfied",...}]`, while `installed_plugins.json` already listed llm (installed 06:30:42, during session 2). Session 4 init: `{"plugin_errors":null,"plugins":["plan@tatari-skills","pr@tatari-skills","llm@tatari-skills"]}`.
  - Install path, fresh scratch (`$P/homegh2`):
    - `claude plugin install plan@tatari-skills` -> `✔ Successfully installed plugin: plan@tatari-skills (scope: user) (+ 1 dependency: llm)`. It wrote `enabledPlugins` `{"plan@tatari-skills":true,"llm@tatari-skills":true}`.
    - First session after install, init: `{"plugin_errors":null,"plugins":["plan@tatari-skills 0.1.2","llm@tatari-skills 0.3.0","pr@tatari-skills 0.6.22"],"agents":["llm:fable-reviewer","llm:opus-reviewer","plan:design-research","plan:phase-implementer","plan:review-panel"],"skills":["plan:build","plan:create","plan:review","llm:claude-advisor","llm:codex","llm:gemini","llm:model-selector","llm:session-launcher"]}`
  - Directory-source marketplace (`$P/home`, local snapshot): same llm dependency failure with enabledPlugins only.
- **(b) `plan:review-panel` id and `panel-round-guard.sh`. Verdict: PASS.**
  - Setup: `HOME/.claude/hooks/panel-round-guard.sh` and `lib.sh` copied to `$P/homegh2/.claude/hooks/`, registered as `PreToolUse` matcher `Agent` via a wrapper that sets `PANEL_ROUND_GUARD_DEBUG=1`. Scratch counter `$P/homegh2/.cache/review-panel/rounds/<key>` seeded with `rounds=3` for `$P/work/docs/plan/2026-11-15-probe.md` (Status: In Review).
  - Command: `cd $P/work && claude -p --output-format stream-json --verbose --max-turns 3 --allowedTools Agent < b-prompt.txt`. The prompt asks for one Agent call with `subagent_type "plan:review-panel"` and prompt lines `DOC_PATH: docs/plan/2026-11-15-probe.md` / `OPEN: hook probe item`.
  - Init `agents`, filtered: `["plan:review-panel"]`
  - tool_use: `{"name":"Agent","input":{"subagent_type":"plan:review-panel","description":"probe","prompt":"DOC_PATH: docs/plan/2026-11-15-probe.md\nOPEN: hook probe item"}}`
  - tool_result: `PreToolUse:Agent hook error: panel-round-guard: this is round 4 on $P/work/docs/plan/2026-11-15-probe.md; the cap is 3 (rules/interaction.md). ... Counter: ~/.cache/review-panel/rounds/87b3ae52... (3 rounds recorded)`
  - Debug log: `entry: subagent=plan:review-panel ...` / `doc=... mode=1 rounds=3 this_round=4 cap=3` / `reason gate: round 4, 1 OPEN/DISPUTE line(s)` / `deny: round 4 exceeds cap 3`
  - Identical on both the directory marketplace (`$P/home`) and the GitHub marketplace (`$P/homegh2`).
- **(c) `inline-skill-tokens.py` resolves `/plan:create`. Verdict: PASS.**
  - Command: `HOME=$P/homegh2 INLINE_SKILL_TOKENS_LOG=$P/inline.log`, then `echo '{"hook_event_name":"UserPromptSubmit","prompt":"next, run /plan:create on the auth idea"}' | python3 -I HOME/.claude/hooks/inline-skill-tokens.py`
  - Output, exit 0: `{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": "inline-skill-tokens hook: the user's prompt contains these inline tokens, quoted verbatim from it: /plan:create. Each one names an installed skill. ..."}}`
  - Log: `INJECT	count=1	next, run /plan:create on the auth idea	plan:create`
  - `resolvable_skills()` read `SETTINGS_PATH=$P/homegh2/.claude/settings.json` and returned `['llm:claude-advisor', 'llm:codex', 'llm:gemini', 'llm:model-selector', 'llm:session-launcher', 'plan:build', 'plan:create', 'plan:review']`
  - Negative control, `HOME=$P/homeempty`: no output, log `BAIL	no-live-skill	...	plan:create`
- **(d) Eval `scaffold.sh` puts stub `gh` and `bump` on PATH for a Bash-tool agent. Verdict: FAIL under `claude plugin eval` on this host (AppArmor). The stub mechanism passes in a plain session.**
  - Throwaway plugin `$P/evalprobe`, case `evals/stub-path`, `allowed_tools: [Bash]`, shaped after `plugins/llm/evals/opus-reviewer-finds-bug/scaffold.sh`. `scaffold.sh` writes `bin/gh` (prints `STUB_GH $1 $2 state=CLOSED`), `bin/bump` (prints `STUB_BUMP version=0.4.10`), and `.claude/settings.json` `{"env":{"PATH":"$PWD/bin:$PATH"}}`.
  - Command: `claude plugin eval $P/evalprobe --trust-plugin --scaffold --ablation none --runs 1 --no-publish --max-cost-usd 1 --allow-tools Bash --keep-temp`
  - Output, three runs (inside and outside the outer sandbox, then with `sandbox.network.allowAllUnixSockets: true` added to the scaffold settings): score 0, both graders `pattern not found in trace`. Bash tool_result each time: `Exit code 1 apply-seccomp: write /proc/self/setgroups (nested userns is capability-restricted; caller must provide CAP_SYS_ADMIN): Permission denied`. The agent's command never ran.
  - Root cause: `/etc/apparmor.d/bwrap-userns-restrict` (package `apparmor`) stacks every child of `/usr/bin/bwrap` with `profile unpriv_bwrap`, which carries `audit deny capability`. Reproduced without Claude: `/usr/bin/bwrap --unshare-user --ro-bind / / --dev /dev --proc /proc sh -c 'unshare -U sh -c "echo deny > /proc/self/setgroups"'` -> `cannot create /proc/self/setgroups: Permission denied`. Outside bwrap, `unshare -U -r unshare -U -r true` succeeds. The eval's Bash sandbox has no off flag, so no Bash-tool eval runs on this host. No tatari-skills eval uses Bash today: `rg -l 'allowed_tools:.*Bash' plugins/*/evals*/` prints nothing.
  - Plain session: ran the same `scaffold.sh` in `$P/dwork1`, then `claude -p --allowedTools Bash < prompt.md` there. Output: `$P/dwork1/bin/gh`, `$P/dwork1/bin/bump`, `STUB_GH pr view state=CLOSED`, `STUB_BUMP version=0.4.10`.
  - UNVERIFIED: whether the eval child honors the scaffold dir's `.claude/settings.json` `env`. Bash never started there. The eval init `cwd` was the scaffold dir (`.../home/cwd`).
- **(e) Rollback. Verdict: PASS. Uninstall is enough; no extra step.**
  - Plan installed in `$P/homegh2`, then `HOME/.claude/skills/plan` copied to `$P/homegh2/.claude/skills/plan`. `claude plugin list`: `plan@tatari-skills Status: ✔ enabled`, and `plan@skills-dir: ✘ Not loaded`, with the harness reason that the name "plan" is already taken by the installed `plan@tatari-skills`, which takes precedence.
  - Removed `plan@tatari-skills` from `enabledPlugins`. `claude plugin list`: `plan@tatari-skills Status: ✘ disabled`, `plan@skills-dir Version: 0.1.0 Status: ✔ loaded`. Dropping the entry alone already lets the skills-dir copy load.
  - `claude plugin uninstall plan@tatari-skills` -> `✔ Successfully uninstalled plugin: plan (scope: user)` / `1 auto-installed dependency no longer needed: llm. Run claude plugin prune to remove.`
  - Next session init: `{"plugin_errors":null,"plugins":["llm@tatari-skills 0.3.0","pr@tatari-skills 0.6.22","plan@skills-dir 0.1.0"],"agents":["plan:design-research","plan:phase-implementer","plan:release-driver","plan:review-panel"],"skills":["plan:build","plan:create","plan:release","plan:review"]}`
- **`claude plugin list` in the scratch dir** (`$P/homegh2`, after `claude plugin install plan@tatari-skills`; "Synced from claude.ai" block omitted):

  ```
  Installed plugins:

    ❯ llm@tatari-skills
      Version: 0.3.0
      Scope: user
      Status: ✔ enabled

    ❯ plan@tatari-skills
      Version: 0.1.2
      Scope: user
      Status: ✔ enabled

    ❯ pr@tatari-skills
      Version: 0.6.22
      Scope: user
      Status: ✔ enabled
  ```

### Design decisions
- Marketplace source is GitHub `tatari-tv/tatari-skills` at origin/main `df92743d` (`$P/homegh2`). Why: it matches live `known_marketplaces.json` (`source: github`), which caches plugins under `plugins/cache/`, and `inline/resolve.py` reads only that cached `installPath`. The first pass used a directory source (`git clone --no-hardlinks` of the local clone at `df92743d`, `$P/home`) because the scratch HOME had no git credential helper. A directory source reads plugins in place and records an `installPath` under `plugins/cache/` that never exists, so (c) could not be tested on it.
- GitHub clone auth in the scratch HOME: a `$HOME/.gitconfig` holding only the `credential "https://github.com"` helper lines from the live `~/.gitconfig` (`!/usr/bin/gh auth git-credential`, which uses the ambient `GH_TOKEN`). No `GIT_CONFIG_*` injection, no key handling, no secret written.
- `CLAUDE_CONFIG_DIR=$HOME/.claude` in the canonical scratch. `inline/resolve.py` reads `Path.home()/.claude/{settings.json,plugins/installed_plugins.json}` and ignores `CLAUDE_CONFIG_DIR`; the live layout has the two equal.
- Model auth: only `~/.claude/.credentials.json` copied into each scratch config dir. No `ANTHROPIC_API_KEY` is set. The access token had about 4 hours left, so no refresh ran. Fingerprints of the live and scratch token pairs matched after every session (`21e725c458c4` for all), so the live login was not rotated.
- (b) seeds the round counter at 3 instead of running three panel rounds. A round-4 deny is the cheapest observable and never dispatches a panel.

### Deviations
- (d) ran through a throwaway plugin `$P/evalprobe`, not a plan eval case in tatari-skills, because Phase 0 writes no code there. Same mechanism, scratch location.
- `pr@tatari-skills` was enabled explicitly in every scratch. Plan's `plugin.json` declares only `dependencies: ["llm"]` today; `pr` becomes a dependency in Phase 6. Live settings already enable `pr`.

### Tradeoffs
- GitHub-sourced scratch over the local-clone directory source: GitHub matches the live cache layout `resolve.py` depends on. The directory run stays as a second data point for (a) and (b).
- Plain-session proof of the stub PATH mechanism over fixing the host for an eval-run proof: editing `/etc/apparmor.d` is a system change, not this phase's call.

### Open questions
- (d) blocks Phase 6's stub evals and Phase 4's success criteria on this host. The doc's fallback (drop the stub cases, test only the no-input stop) also drops the evidence Phase 4 uses to prove the poll-only loop. Options: take the fallback | run the evals on a host whose AppArmor allows nested userns under bwrap | change `/etc/apparmor.d/bwrap-userns-restrict` on this host.
- After Phase 7, `git revert` also drops `llm@tatari-skills` from `enabledPlugins`. llm stays installed but disabled; `claude plugin prune` removes it. Optional, not needed for the personal copy to load.
- The enabledPlugins-only path took four session starts to converge in (a). The session-3 dependency error, while `installed_plugins.json` already listed llm, was not root-caused: Phase 7 runs `claude plugin install` and does not depend on that path.

## Phase 1: Neutral wording in bump

Commit: `scottidler/bump` `941e0f1` (local on main, unpushed, unreleased).

### Design decisions
- Mechanical "Scott" -> "the owner" across `src/` and `README.md`; sentence-initial doc-comment hits become "The owner" (`src/cli.rs`, `src/release.rs`, `src/release/pr.rs`, `src/release/standalone.rs`, `src/release/tests/standalone.rs`), so comments stay grammatical.
- The printed and PR-quoted audit line is `Standalone release ordered by the owner: "<words>"` (`src/release.rs` print site, `src/release/pr.rs` format), matching the API Design table.
- The `--standalone` help, `STANDALONE_DOOR`, the `finish.rs` refusal and the README read "the owner's words" / "the owner already ordered".
- Gap-fill (orchestrator call): the placeholder `<his exact words>` also named one person, so it became `<the owner's exact words>` in `src/release.rs` (`STANDALONE_DOOR`, the `--standalone needs the owner's words` bail), `src/release/finish.rs` (the no-untagged-version refusal), and the `src/release/tests/finish.rs` assertion. The `src/cli.rs` parse-test input `"his exact words"` moved with it. `rg -n -i '\bhis\b|\bhim\b' src README.md` prints nothing.

### Deviations
- None.

### Tradeoffs
- sed over every hit, then a line-by-line diff review, vs. hand-editing: every hit was a possessive or "Scott already" and mapped one to one.

### Open questions
- None.

### Environment note
- `otto ci` fails 4 path-canonicalization tests (`git::tests::worktree_for_branch_finds_sibling_worktree_and_none_otherwise`, 3 `release::tests::finish::*`) when `TMPDIR` is the sandbox default `/tmp/claude-1000`, a symlink. With `TMPDIR` at a symlink-free path, `otto ci` exits 0. Unrelated to this phase.

Observed: `rg -c 'Scott' src README.md | wc -l` -> `0`; `otto ci` (real TMPDIR) -> exit 0; `./target/debug/bump release --help | rg -c Scott | wc -l` -> `0` (debug-build proxy; the installed-binary check waits on the release).

## Orchestrator: Phase 0 (d) fallback applied to Phases 4 and 6

### Design decisions
- Phase 0 (d) failed on this host (AppArmor `bwrap-userns-restrict` denies the eval sandbox's nested userns, so Bash never starts under `claude plugin eval`). `rg -n -i 'plugin eval|evals' .github/workflows` in tatari-skills prints nothing, so CI runs no evals either. The doc's own fallback applies: Phase 6 drops the stub `gh`/`bump` cases and keeps an eval for the no-input stop only.

### Deviations
- Phase 4's success criterion named the three stub eval cases, which the doc's Phase 0 (d) fallback removes. Substitute proof of the poll-only loop: the ENTRY `merge` section of `plugins/plan/agents/release-driver.md` contains no `git commit`, `git push` or CI-fix step, checked by a grep recorded in the Phase 4 notes. The back-half Release-line check is proven by reading the prompt, not by an eval. The stub `scaffold.sh` cases can return when evals run on a host that permits nested userns under bwrap.

### Tradeoffs
- Keep the stub evals committed but unrunnable vs. drop them: dropped, because an eval nobody can run is a criterion with no observed output.

### Open questions
- None.

## Phase 3: Port release and release-driver to tatari-skills

Commit: tatari-skills `392408e0` on `plan-release-port` (from `b1665649`, unpushed). Observed: `bin/skillzy validate` exit 0; `prek run --all-files` exit 0 (26 hooks passed); `prek run no-em-dashes --all-files` exit 0; the Phase 3 `git grep` exit 1, no output.

### Design decisions
- Frontmatter: skill keeps the personal `name`/`description`/`argument-hint` and adds `allowed-tools: [Bash(bump:*)]`; the description also names the `bump` dependency and install source. Agent keeps `tools: Bash, Read, Grep, Glob` and `model: opus`, matching org `review-panel.md`.
- Preflight is a new Step 0.5 in `release/SKILL.md`: `bump --version` must print `bump vX.Y.Z` at v0.4.8 or later; missing, older, or unparseable stops and names `tatari-tv/bump` with `cargo install --git https://github.com/tatari-tv/bump`.
- With the `[DIR]` caveat gone, every verb call is `bump release|finish ... <REPO>` (Branch 1 step 3, Branch 2 step 2, driver "What the two verbs do"); the `cd <REPO>` + `pwd` dance is removed.
- The allow-rule prose is replaced by one neutral line pointing at the skill's own `allowed-tools` grant (`Bash(bump:*)` matches only a command starting with `bump`), so the "run it bare" rule keeps its reason.
- `/cli-shakedown` becomes "the repo's shakedown, if it documents one" (skill Branch 1 step 5 and Branch 2 relay; driver step 6 and return value), per the Resolved Decision on live proof. `/rust-cli-coder` becomes "a Rust project whose `build.rs` runs `build_version::emit()`".
- Branch 4 is headed "a repo the author treats as protected" and says outright that it is the author's override, not a `bump --gates` verdict. The `rules/interaction.md` ask shape became an inline neutral shape.
- Standalone door wording follows bump `941e0f1`: `ordered by the owner`, `<the owner's exact words>`. In the driver the order must come from the invoking prompt, since the agent cannot see the session.
- Also stripped: release-ruling date cites (2026-10-02 (a), 2026-10-03 (c), 2026-10-05 (d), 2026-10-07 (a)/(d)), `HALL-OF-SHAME §VIII`, the `review-panel.md:146-151` sandbox carve-out, the word "real" in "real changed files" / "real product-code failure".

### Deviations
- The personal skill's closing status block (`52c03ec`) was left out: Phase 5 ports it in neutral wording.
- ENTRY `merge` keeps its CI-fix loop and ENTRY `release` stays, as ported; Phase 4 rewrites them.
- `plugins/plan/README.md` skill table not updated: `bin/skillzy validate` does not require it, and the orchestrator asked for only what validation requires.
- The no-input-stop eval (`plugins/plan/evals/release-driver-merge-no-pr-stops`) moved from Phase 6 to Phase 3, because `skillzy-agent-evals` requires an eval case for each new agent (Scott chose this, 2026-11-15). It uses no stub `gh` or `bump` (Phase 0 (d)); its graders are delegation, a missing-PR stop, and no `bump release|finish` command in the trace. Not run locally (Bash-free, but evals were not part of this phase's criteria); no control yet.

### Tradeoffs
- `cargo install --git` as the named install command vs naming the repo only: the bump README documents only `cargo install --path .`, and a concrete command beats a bare repo name for someone hitting the preflight. It depends on Phase 2 having made `tatari-tv/bump` exist.

### Open questions
- `bin/skillzy validate` step `agent-evals` fails: `plan/release-driver: agent is missing an eval case`. CONTRIBUTING.md "Adding a New Agent" says a new agent must ship with a case, not a `schemas/agent-evals.json` entry, and the orchestrator ruled evals out of Phase 3. Writing `plugins/plan/evals/release-driver-merge-no-pr-stops/{case.yaml,prompt.md}` was denied by the auto-mode classifier; only its `scaffold.sh` landed (untracked). Options: pull the Phase 6 no-input-stop eval into Phase 3 | a temporary grandfather entry that Phase 6 removes | commit red and let Phase 6 turn it green. Resolved: Scott picked the first (see Deviations).

## Phase 4: Merge observer and watcher handoff

Commit: tatari-skills `7985dd05` on `plan-release-port` (from `392408e0`, unpushed). Observed: `bin/skillzy validate` exit 0; `prek run --all-files` exit 0; the ENTRY `merge` section grep hits one line, a prohibition; `rg -n 'pr:watch'` on the skill shows the printed `Next: /pr:watch <url>` hint and no `Skill(pr:watch)`; `Release: rides` sits in the back half's step 1, before `bump finish` (step 2); `git ls-files docs/handoff/plan-release-pr-watch-gap.md` prints nothing.

### Design decisions
- Skill Branch 2 grows to six steps (`plugins/plan/skills/release/SKILL.md`): step 4 defers to `/pr:create`'s watcher offer and records WATCHER (`armed` | `not armed`), step 5 dispatches the driver with `run_in_background: true` and ENTRY `merge` in every gated case, step 6 ends the turn with a waiting report. A new "Reporting a non-success exit" section carries the five fields (PR, pending version, stage reached, watcher, resume).
- The existing-PR hint is a ` ```text ` fence holding `Next: /pr:watch <url>`. A bare fence counts as shell to `check-claude-plugin-closure` (`closure.py` `_EXECUTABLE_FENCE_LANGS` includes `''`), which flagged `pr:watch` as a cross-plugin script reference.
- The driver passes WATCHER through only to echo it in its non-success report; it changes nothing the driver does.
- ENTRY `merge` is its own `##` section: a first `gh pr view --json state,body` read (MERGED goes straight to the back half, CLOSED stops, OPEN takes EXPECTED-VERSION from the Release line), then one `run_in_background` loop on `gh pr view --json state --jq .state` that exits on MERGED, CLOSED, the ceiling, or five consecutive `gh` errors.
- The wait ceiling is a driver input, WAIT-CEILING, default 86400 seconds (24 hours), polled once a minute. A stop at the ceiling is cheap: the resume command `/plan:release` after the merge dispatches ENTRY `finish`.
- Release-line check (`release-driver.md` Back half step 1): the merged PR body's `Release: rides this PR (vX.Y.Z)` against the version in `bump finish -n <REPO>`'s `[dry-run] fetched origin/<default>: <sha> carries vX.Y.Z` line (`finish_dry_run` in bump `src/release/finish.rs`, present since v0.4.0, so inside the v0.4.8 preflight). Mismatch stops before `bump finish` runs. The dry run tags, pushes, and installs nothing.
- ENTRY `release` removed from the driver, with its steps 2 (commit the code change) and 3 (`bump release`). The skill runs `bump release` inline in the main session on both branches and never dispatched ENTRY `release`, and the doc's Architecture table lists only ENTRY `merge` and `finish`. ENTRY is now required; any other value stops. This also takes every `git commit` instruction out of the driver.
- The CI-fix loop, the `gh pr checks --watch --fail-fast` wait, and the "review required" admin-merge paragraph are gone. Hard boundaries now forbid commit, push, editing a file, re-running a check, touching threads, and merge or admin-merge.

### Deviations
- Success criterion: the three stub eval cases are replaced by the orchestrator's grep substitute (Phase 0 (d) fallback, see the Orchestrator section). The existing `release-driver-merge-no-pr-stops` eval still validates; its graders were not touched (the driver still says the PR url is required).
- Same effect, correct seam: the doc says the driver compares against "the version `bump finish` prints". `bump finish` prints its version only as it tags, so the check reads the `bump finish -n` dry run instead, which prints the version before anything moves.
- ENTRY `release` removed (Design decisions), which the doc does not name; it was the only way the driver could commit or run `bump release`, both of which the flow keeps in the main session.

### Tradeoffs
- `bump finish -n` then `bump finish` vs. parsing the version after the real run: the dry run stops before a tag exists. A merge landing in the seconds between the two calls is not caught; the doc's race is a release merging during the hours-long wait, which the check covers.
- A 24-hour default ceiling vs. waiting indefinitely: a background subagent that never ends hides a stuck release, and the resume path makes a stop cheap.
- `text` fence vs. inline code for the existing-PR hint: the fence keeps the hint a distinct printable line; inline code would also pass the closure check.

### Open questions
- Is 24 hours the right default WAIT-CEILING for the merge wait, or should it be longer for repos where review takes days?

## Phase 5: Closing status blocks

Commit: tatari-skills on `plan-release-port` (from `7985dd05`, unpushed); SHA in the phase report. Observed: `rg -c 'Your call:'` prints create 5, build/orchestrating 3, release 2; `bin/skillzy validate` exit 0; `prek run --all-files` exit 0; `wc -l` shows build 474, create 308, release 338, review 374; `git grep -n -i -e scott -e "rp'd" -- plugins/plan/skills` exits 0 with one hit, `review/SKILL.md:100` (`PANEL_ROUNDS_ORDERED_BY_SCOTT`, a Phase 6 rename).

### Design decisions
- Build's block lives in a new "The closing block" section of `plugins/plan/skills/build/orchestrating.md`, which now says it applies to both modes (its header said Delegated only). `build/SKILL.md` step 3 keeps its box diagram and replaces the five-line report with a one-line pointer, which took the file from 488 to 474 lines.
- Build's block folds the five-line end report: `Branch ready, PR not opened.`, `Branch:`, `Code complete:`, `Audited:`, `Left undone:`, then `Your call:` and `Next: /pr:create, or /plan:release to ship`. The personal block's `Ready to release` line is dropped because build never releases.
- Create's `rp'd:` line is renamed `Reviewed:` and build's is `Audited:` (the shorthand is personal).
- Release's block adds no report fields: it states it closes the turn, and that the non-success fields and Branch 2 step 6's waiting report ride above it.
- The three blocks use a ` ```text ` fence. A bare fence counts as shell to `check-claude-plugin-closure`, which flagged `pr:create` in build's block as a cross-plugin reference.

### Deviations
- Personal build's checkpoint-message sentence was not ported: the org build has no approval checkpoint, since it never pushes or releases.
- Success criterion `git grep ... -e scott` exits 0, not 1: `plugins/plan/skills/review/SKILL.md:100` still carries `PANEL_ROUNDS_ORDERED_BY_SCOTT`. Phase 6 renames it; Phase 5 touches none of that file. Zero hits in the three files this phase edited.

### Tradeoffs
- Folding into the existing `orchestrating.md` vs. trimming `SKILL.md` to fit: the doc named `orchestrating.md`.

### Open questions
- None.

## Phase 6: Residue, manifest, evals
### Design decisions
- Control is `evals-controls/release-driver-merge-no-pr-stops/cases/no-delegation`: the prompt forbids delegating, so the `delegated-to-release-driver` `tool_used` grader must fail. Graders copied from the case. Chosen because the case allows no Bash, so a "make it run a bump verb" control cannot be produced deterministically.
- The control case omits the `tags:` line so only the positive case carries `agent:release-driver`; the control runs from its own plugin copy.
- `bin/plan-panel` takes `--rounds-ordered N` and has no `SCOTT` string; confirmed, no change.
- plugin.json description now ends "open it with /pr:create, or ship it with /plan:release"; version untouched; same text in `marketplace.json`.
### Deviations
- Edited the Phase 3 case `release-driver-merge-no-pr-stops/case.yaml`: dropped the `(?i)` prefix from the `names-the-missing-pr` pattern. The first local run failed that grader on a correct "the PR url is missing" report; the eval regex engine does not take the inline flag. "PR", "missing" and "required" appear lowercase or caps as written, so case-insensitivity was not needed. The control carries the same fix.
- The stub `gh`/`bump` cases (merge-closed, merged-finishes, version-mismatch) and their control were not written, per the Phase 0 (d) fallback. The criterion "all three cases pass" is replaced by the single existing case.
- The control fails `names-the-missing-pr` as well as `delegated-to-release-driver` (the directly answered reply words it differently). CONTROL.md names the delegation grader as the one that must fail.
### Tradeoffs
- Negative control that forbids delegation vs one that supplies a PR url: the latter needs Bash and gh in the eval, which cannot run on this host.
### Open questions
- The positive case ran under `claude plugin eval` with no Bash start failure, because the agent stopped on the missing PR before running anything. The Phase 0 (d) blocker was not exercised, so any case that must run a command is still UNVERIFIED.
- The dependency announcement was not posted anywhere; the README carries the command `claude plugin install plan@tatari-skills`. The PR author posts it before the merge.
- `bot-files-check` did not appear in the local `prek run --all-files` output (every listed hook passed); expect it red in CI until AI Foundry approves the last commit.

## Implementation audit (panel round 2, Mode 2, Scott-ordered round override)

Synthesis: `~/.cache/review-panel/runs/CdD4Th1K/synthesis.md`, round 2 section. Counts: must-fix 2, cheap-win 4, defer 1. Questions 3/3 answered. Fold commit: tatari-skills `plan-release-port` `96243f16`.

### Design decisions
- M1 folded: `release/SKILL.md` Branch 2 now runs `cd <REPO>` before step 1, because `/pr:create` and `gh pr view <branch>` act on the cwd. `release-driver.md` back-half verification calls take `git -C <REPO>`; the tag check uses `rev-parse vX.Y.Z^{commit}` instead of `git describe`.
- M2 folded: `bump finish -n` takes the same `--install`/`--no-install` flag as the real run, because `finish.rs` checks the install setting before the dry-run branch.
- C1 folded: a non-zero `bump finish -n` exit is a refusal even when the `carries vX.Y.Z` line printed.
- C2 folded: the preflight accepts `bump vX.Y.Z-N-g<sha>` (a build between tags) and compares on `vX.Y.Z`.

### Deviations
- C3 (undisclosed until now): Phase 3's branch was cut from `b1665649`, the orchestrator's rebase of `920fcb0b` onto origin/main `df92743d`. The local branch was 36 commits behind and lacked the `agent-evals` validate step.

### Tradeoffs
- One fold commit on top of the phase commits vs. rewriting them: the fold is reviewable on its own, and the PR squash-merges anyway.

### Open questions
- D1 (deferred, inherited from the personal copy): Branch 4's "ship as a PR on an ungated repo" cannot run, because bump refuses on a non-default branch (`release.rs`). The port did not introduce it; left for a follow-up.
- C4 is sequencing and already in the plan: Phase 1's own `bump release` must run before the Phase 2 transfer, or bump's release goes down the gated path.

## Phase 2: Transfer bump

### Design decisions
- Two hops ran as planned: `scottidler/bump` -> `escote-tatari/bump` (accepted by email, 2026-11-16T18:21:51Z), then `escote-tatari/bump` -> `tatari-tv/bump` (immediate). Repo stays public.
- The clone moved to `~/repos/tatari-tv/bump` with `origin` = `git@github.com:tatari-tv/bump`. The `scottidler/bump` cites in `git-release-guard.sh`, `intent-guard.sh` and `intent-guard-test.sh` now read `tatari-tv/bump`, and ride the Phase 7 commit. The dotfiles `docs/new-machine-bootstrap.md` row is committed in dotfiles.
- `hooks/fixtures/inline-token/fixtures.json` still names `~/repos/scottidler/bump`: those are recorded transcript contexts, not live references, so they stay.

### Deviations
- None.

### Tradeoffs
- None.

### Open questions
- None.

Observed: right after hop 2, `bump --gates ~/repos/tatari-tv/bump` printed `Gates:  none (ungated)`. Cause: org ruleset 126206 ("Require Actions Workflows") targets repos whose custom property is `managed=true`, and a transferred repo arrives `managed=false`. Running `github-setup.py ensure bump` set `managed=true` and the default protection. After that, `bump --gates` printed `Gates:  classic_protection, workflows (gated)`.

## PR review fixes (tatari-tv/tatari-skills#759)

### Design decisions
- CodeRabbit raised five findings; four were fixed in `7a3190f7` and one follow-up in `e405876f`:
  - Release Branch 4 now stops before any change. This closes the audit's D1: `bump release` refuses an ungated repo off the default branch, so that verdict has no PR path.
  - The Branch 1 preflight also checks `origin/<default>..HEAD`. When all checks are empty it runs `bump release -n`, and it continues only on `pending version vX.Y.Z`. A clean feature branch skips the empty commit.
  - The Branch 1 switch and fast-forward use `git -C <REPO>`.
  - The build handoff lets a deploy-only criterion stay UNVERIFIED, listed in `Left undone`.
- Declined: binding `bump finish` to the dry-run version. That needs a new bump flag; step 3's verification still catches a mismatch after the tag.

### Deviations
- Branch 4's behavior changed from "go to Branch 2" to "stop and report", because Branch 2 cannot run on an ungated repo.

### Tradeoffs
- None.

### Open questions
- A `bump finish --expect vX.Y.Z` flag would close the declined race.
- `pr` plugin `watch.py` exits `ci-failed` on any failing required check, including `bot-files-check`, which is an approval gate. The watcher dies on every PR that touches bot-managed files until approval lands.

Shipped in: tatari-tv/tatari-skills#759, merge `bee4dd5e`.

## Phase 7: Switch this repo
### Design decisions
- `PLAN_STANDARDS` written as the absolute `/home/saidler/repos/.claude/rules/taste.md` in `settings.json` env, matching how other entries in the file write absolute home paths.
- `panel-round-guard.sh` accepts `PANEL_ROUNDS_ORDERED_BY_(SCOTT|OWNER)`; the deny text now names `_OWNER`, the org spelling.
- Test fixtures: a full OWNER ceiling group (rounds 1-3 plain, 4-5 with marker allowed, 6 denied at cap 5) and an OWNER open-reason fixture, beside the existing SCOTT ones.
- Mutation proof: regex narrowed to `BY_(SCOTT)`; the run reported `pass=154 fail=4` (owner door round 4, round 5, round 6 cap text, and owner door counts as a reason). Regex restored; suite back to `pass=158 fail=0`.
- Dead plan-seat entries removed from `settings.json` allow and `sandbox.excludedCommands`, from the architect pathglob clause, from the rails spec `SHIPPED_EXCLUDED` and from the `EXCLUDED` fixture list (it carried the same two stale entries), and the four `skills/plan/skills/*` lines from `.pi/agent/settings.json`.
### Deviations
- Also removed the two plan-seat entries from the rails spec `EXCLUDED` fixture, not only `SHIPPED_EXCLUDED`: same dead strings, and AC2-style greps stay clean.
- The `_SCOTT` spelling stays accepted per the doc ("accept both"), so old prompts still open the door.
### Tradeoffs
- Kept `_SCOTT` accepted vs. a hard cutover: org copy now emits `_OWNER`, but in-flight prompts and the existing fixtures use `_SCOTT`.
### Open questions
- None.
