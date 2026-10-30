## Phase 0: Prove skills-dir loads skills and agents
### Design decisions
- (b) used a scratch settings file passed with `--settings` carrying a PreToolUse capture hook, never the committed `settings.json`; the scratch file and log were removed with `rkvr rmrf`.
- (e) judged by the `reason_type: "rule"` in the permission decision, because auto mode accepts the control call too and a denial cannot be produced under `defaultMode: auto`.
- (h) observed through pi's own `DefaultResourceLoader` against scratch agent dirs holding copies of `HOME/.pi/agent/settings.json` (pi has no list-skills command, and `pi -p` needs a model call).
- (i) driven in an interactive `claude` under tmux with pane capture, so it is verified, not UNVERIFIED.
- (j) `enable` removes the `enabledPlugins` key rather than writing `true`, so Phase 4's enumerator must treat an absent key as enabled.

### Deviations
- None.

### Tradeoffs
- Headless init events and a loader script prove load and registration. They do not prove `${CLAUDE_PLUGIN_ROOT}` expands inside a Bash command the model runs, only in skill and agent body text. Phase 1 can use it in bodies and should keep absolute paths at the head of Bash commands until Phase 5 proves it live.

### Open questions
- None.

## Phase 1: Skeleton, agents, seats, and the live-from-commit guards
### Design decisions
- Agent frontmatter `name:` stays bare (`review-panel`, not `plan:review-panel`) in `HOME/.claude/skills/plan/agents/*.md`: the plugin loader adds the `plan:` namespace itself, same as `tatari-skills/plugins/sre/agents/sre-deep-read-backlog.md`. The "agent names to `plan:*`" rewrite is therefore what the loader does, proven by the init event listing `plan:design-research`, `plan:phase-implementer`, `plan:release-driver`, `plan:review-panel`.
- `plan/agents/review-panel.md`: every Bash head and every file the agent reads is an absolute `/home/saidler/.claude/skills/plan/...` path (seat scripts at Step 3, the staff persona at Step 3.5, `refs/review-panel-prompts.md` at Step 2), per Phase 0 (f): `${CLAUDE_PLUGIN_ROOT}` is unproven inside a Bash command. The first incident-history citation names the absolute `refs/review-panel-notes.md`; the later `(incident: ...)` citations read `refs/review-panel-notes.md`.
- `plan/agents/review-panel.md` Step 1.1 newest-doc scan: `find docs/plan docs/design -name "*.md" ... 2>/dev/null`, so a missing `docs/plan/` in an older repo is silent and the pick spans both dirs (doc location rule).
- `plan/agents/release-driver.md`: description now says it is invoked by `/plan:release` with ENTRY `release` (gated, feature branch) or ENTRY `finish` (gated, PR merged), matching the doc's `/plan:release` branches 2 and 3; "babysit the PR" became "watch the PR" (description and step 4 heading); the `babysit/SKILL.md:80-91` `/loop` citation became `pr:watch`, described as it actually works (a `run_in_background` watcher that exits on the first event, read from `pr@tatari-skills` 0.6.0 `skills/watch/SKILL.md`), not as a `/loop` timer.
- `refs/review-panel-{notes,prompts}.md`: "Companion to `review-panel.md`" now reads `agents/review-panel.md`, since they no longer sit beside it.
- `hooks/panel-round-guard.sh`: the narrowing test is a `case` on `review-panel|plan:review-panel`; the entry log line names the actual `$subagent`. The counter key is untouched, so both names share one `(doc, mode)` entry.
- `.otto.yml` rollback-baseline check pins the full SHA `62dc65f2935efe78308bb87abd0d6eca0a12bb10` (this phase's parent) and prints `git diff --stat` on failure so the offending file is named.
- Bite-proofs, run 2026-10-29:
  - `panel-round-guard-test.sh` with the change: `pass=135 fail=0`. With `panel-round-guard.sh` stashed back to `62dc65f`: `pass=132 fail=3`, failing `plan:review-panel round 4`, `mixed round 4 as plan:review-panel`, `mixed round 4 as review-panel` (the bare name only reached round 3 because the two `plan:` dispatches were never counted). Restored: `pass=135 fail=0`.
  - Appended `bite probe` to `HOME/.claude/skills/shipit/SKILL.md`: `otto lint` rc=1, `The old pipeline files moved off the rollback baseline 62dc65f...` with `HOME/.claude/skills/shipit/SKILL.md | 1 +`. `git checkout --` of that file: rc=0.
  - Created untracked `HOME/.claude/skills/shipit/untracked-probe.md`: `otto lint` rc=1, `Untracked files under the old pipeline's rollback baseline`. `rkvr rmrf` of it: rc=0.
- Success criteria observed:
  - `claude plugin details plan@skills-dir` (fresh process, cwd `/tmp`): `Skills (0)`, `Agents (4)  review-panel, phase-implementer, release-driver, design-research`.
  - Fresh headless init event (`claude -p --output-format stream-json --verbose "reply OK"`, cwd `/tmp`): agents include `plan:design-research`, `plan:phase-implementer`, `plan:release-driver`, `plan:review-panel` beside the 4 bare old agents; `rg -c 'review-panel-notes|review-panel-prompts'` over the whole stream finds nothing; plugin `{"name":"plan","source":"plan@skills-dir","version":"0.1.0"}`.
  - Throwaway launch after the `settings.json` edit: `claude -p "reply OK"` from the scratchpad printed `OK`, rc=0.
  - pi, through its own `DefaultResourceLoader` against copies of the committed and the edited `HOME/.pi/agent/settings.json`: 136 skills each, 0 from `/skills/plan/`. Phase 1 ships no `skills/`, so this shows `agents/`, `refs/` and `seats/` register nothing in pi; the four exclusions' effect on real `skills/*` dirs is Phase 0 (h)'s measurement.

### Deviations
- `review-panel.md:139,151,229` are not rewritten. Each cites a specific existing doc (`docs/design/2026-09-15-intent-guards.md`, `docs/design/2026-09-14-panel-round-cap.md` twice) as incident provenance; those files stay in `docs/design/`, so pointing them at `docs/plan/` would break the citation. Only `:96`, the scan, is a reader the doc location rule governs.
- Five plan files stay out of the `.otto.yml` lint `FILES` list because their copies carry em dashes from the originals: `plan/agents/design-research.md` (14), `plan/agents/phase-implementer.md` (21), `plan/seats/architect/persona.md` (1), `plan/seats/staff-engineer/persona.md` (5), `plan/seats/staff-engineer/notes.md` (4). De-dashing them is a content edit outside the listed rewrites, and the two personas are prompt text piped to gemini and codex. The other ten plan files are in the list.
- `release-driver.md:168` (`review-panel.md:146-151`) is left as-is: it is a sibling reference that still resolves inside `plan/agents/`, and the rewrite list does not name it.

### Tradeoffs
- `cp -p` copies (mode and mtime kept) vs `git mv`: the old files are the rollback baseline and must stay byte-identical; the lint check now enforces that.
- Prose seat paths in `plan/agents/review-panel.md` (Who's on the panel bullets) are absolute rather than tilde, to match the Bash heads and leave no tilde form for the classifier to pattern on.

### Open questions
- Phase 3's criterion `rg -n babysit HOME/.claude/skills/plan` will hit `seats/architect/script.sh:76` and `seats/staff-engineer/script.sh:76` (`# PID handle so a babysitter can follow ...`), a generic word in a comment of scripts the doc says move intact. Either Phase 3 rewrites that comment in the copies or the criterion excludes `seats/`.
- `plan/agents/{design-research,phase-implementer,review-panel}.md` descriptions still name `/create-design-doc`, `/how-to-execute-a-plan`, `/architect`, `/staff-engineer`, since the `plan:*` skills do not exist yet. Phase 6's prose list does not name `plan/agents/*`; these need renaming by Phase 6 at the latest.

## Phase 2: Skills create, build, review
### Design decisions
- `skills/*/SKILL.md` frontmatter `name:` is bare (`create`, `build`, `review`); the loader adds `plan:`, same as Phase 1's agent finding. The init event lists `plan:build`, `plan:create`, `plan:review` and no bare `create`, `build`, `review`.
- `skills/create/SKILL.md`: the dispatch names the agent as `subagent_type: "plan:design-research"`, `Skill(review-panel)` became `Skill(plan:review)`, output is `docs/plan/`. `template.md` and `example.md` are copied byte-for-byte (`cp -p`).
- `skills/build/SKILL.md`: the seven `docs/design` write and read sites became `<doc-dir>`, the directory of the doc the caller passed, defined once in a new "Doc location rule" section before Step 2.5 (notes path, Status `sed`, `git add`, `Design doc:` lines of both commit templates, the finalization notes summary, the status commit). Step 1's `cat docs/<feature>-design.md` became `cat <doc-path>`. The delegated dispatch names `subagent_type: "plan:phase-implementer"`. `/create-design-doc` became `/plan:create` (4 places), the `/bump` integration row became `/plan:release`, and the merge wait names `plan:release-driver` (via `/plan:release`) and `pr:watch` in place of "babysitting".
- `skills/build/SKILL.md` finalization Steps 4-5 still describe the `bump release` / `bump finish` verbs and their ungated/gated behavior. Only the routing nouns were renamed; the release flow itself is Phase 3's `/plan:release`, and rewriting the finalization to call it is a behavior change the doc does not list for Phase 2.
- `skills/review/SKILL.md` is one skill with two paths keyed on the first argument word: `architect` | `staff-engineer` runs that seat script directly, anything else is the panel dispatch (`subagent_type: "plan:review-panel"`). Seat mode merges the two old entries into one flow with a per-seat table (script, persona, reach, announce text, output label, notes file) and per-seat prompts. Every seat script path is the absolute `/home/saidler/.claude/skills/plan/seats/<seat>/script.sh` at the head of the Bash command (Phase 0 (f)).
- The newest-doc `find` in `skills/review/SKILL.md` is `find docs/plan docs/design ... 2>/dev/null`, so a repo without `docs/plan/` is silent.
- The three agent files' `/create-design-doc`, `/how-to-execute-a-plan` renames (Phase 1's open question) are done in the plan copies only: `agents/design-research.md:3,11` -> `/plan:create`; `agents/phase-implementer.md:3,11` -> `/plan:build`; `agents/review-panel.md:3` -> `/plan:create`, `/plan:build`, and "Replaces running `/plan:review architect` then `/plan:review staff-engineer` by hand". The old agents under `HOME/.claude/agents/` and the old skill dirs are untouched; `otto lint`'s rollback-baseline check passed.
- `.otto.yml` lint `FILES` gained `skills/create/SKILL.md`, `skills/create/example.md`, `skills/build/SKILL.md`, `skills/review/SKILL.md`.

### Deviations
- `skills/create/template.md` stays out of lint `FILES`: the copy carries 9 em dashes from the original (lines 25, 26, 52, 53, 64, 77, 83, 110, 116). Same disclosed approach as Phase 1; de-dashing is a content edit outside the listed renames. Together with Phase 1's five files, six plan files are out of the list.
- `skills/review/SKILL.md` is a condensed merge, not a verbatim concatenation of the three sources: the two seat entries share one set of steps, the seat-specific prompt wording for focused prompts and the Mode 2 default prompt is carried as one template with the Staff Engineer differences named in a lead-in, and the original em dashes are replaced with commas and colons. The seat behavior (script-only, no direct CLI, `${TMPDIR:-/tmp}`, probes in Step 4.5, advisory stop) is unchanged.
- `skills/build/SKILL.md` still shows `docs/claude-code-parity-design.md` in the commit-message example and the Example Session (lines 342, 381, 414). They are illustrative sample text from another repo, not sites that read or write this repo's docs; left as copied.

### Tradeoffs
- `<doc-dir>` placeholder with one defining paragraph vs. spelling `docs/plan` or `docs/design` at each site: the placeholder cannot drift to one directory and matches the doc location rule ("derives the directory from the input doc's path"). Cost: the example lines no longer show a literal path.
- One review skill with argument routing vs. three files: the doc's Architecture lists a single `skills/review/SKILL.md`.
- Rename-only `build` finalization vs. calling `/plan:release` there: kept the proven text, left routing to Phase 3 (see Design decisions).

### Success criteria
- `claude plugin details plan@skills-dir` (fresh process, cwd scratchpad): `Skills (3)  build, create, review`, `Agents (4)  review-panel, phase-implementer, release-driver, design-research`. `claude plugin validate --strict` passes.
- `rg -n -e '"(design-research|phase-implementer|review-panel|release-driver)"' -e '/create-design-doc' -e '/how-to-execute-a-plan' -e 'skills/(architect|staff-engineer)/' HOME/.claude/skills/plan/skills` prints nothing (rc=1).
- Every `docs/design` hit in `HOME/.claude/skills/plan/skills`, by line (run as `rg -n -e docs/design ...`; the bare `rg -n docs/design <path>` form printed nothing in this sandbox session even against a file the same pattern matches under `-e` and under `grep`, so the `-e` form was used. Cause not found, recorded rather than guessed):
  - `skills/review/SKILL.md:23`: reader/writer rule text, names `docs/plan/` and `docs/design/` together (derives from caller path, scans both).
  - `skills/review/SKILL.md:27`: the newest-doc `find docs/plan docs/design`, a reader that names both dirs.
  - `skills/review/SKILL.md:373`: error-handling line, names `docs/plan/` and `docs/design/` together.
  - `skills/build/SKILL.md:61`: historical provenance citation (`docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md`, carried from the original line 61).
  - `skills/build/SKILL.md:185`: the Doc location rule, names `docs/plan/` and `docs/design/` and defines `<doc-dir>`.
  - `skills/build/SKILL.md:189`: same rule paragraph, names both dirs.
  - No hit remains in `skills/create/` (its writer is now `docs/plan/`). No write site in `build` hardcodes `docs/design`.
- `otto ci`: exit 0, `All CI checks passed!` (test task includes `claude plugin validate --strict` and the rollback-baseline lint).
- Throwaway launch: `claude -p "reply OK"` from the scratchpad printed `OK`, rc=0. A fresh init event lists `plan:build`, `plan:create`, `plan:review` and the four `plan:*` agents.
- pi, through its own `DefaultResourceLoader` (`SettingsManager.create(dir, dir)`, `reload()`, `getSkills()`) against a copy of the committed `HOME/.pi/agent/settings.json`: 136 skills, 0 from `/skills/plan/`. Control (same copy with the four `plan/skills/*` exclusions removed): 139 skills, 3 from `/skills/plan/` (`build create review`). So the exclusions are what hide the three real skills; `release` has no `SKILL.md` yet, so its entry is untested until Phase 3.

### Open questions
- The seat scripts and refs still name the old skills in comments and prose (`seats/architect/script.sh:7,33`, `seats/staff-engineer/script.sh:7,34,37`, `seats/staff-engineer/notes.md:4,33`, `refs/review-panel-prompts.md:8`: `/architect`, `/staff-engineer`). The doc says seat scripts move intact and Phase 6's prose list does not name them. Rename in Phase 3, 4 or 6, or leave?
- Bare `rg -n docs/design <path>` returned nothing here while `rg -n -e docs/design <path>` and `grep` matched. If the Phase 2 criterion is rerun as written in another session it may print nothing and read as a false PASS; the `-e` form is the reliable one.

## Phase 3: Skill release
### Design decisions
- `skills/release/SKILL.md` runs `bump --gates <REPO>` as Step 1, before any pre-flight that could write, and routes on the single line starting `Gates:` through a four-row table: `none (ungated)` -> Branch 4 check then Branch 1; `<rules> (gated)` -> Branch 2 or 3; `UNKNOWN (...)` -> Branch 5; no `Gates:` line, more than one, a non-zero exit, or other text -> Branch 5. The exit code is named as not the signal (`report_gates`, `scottidler/bump` `src/main.rs`, prints UNKNOWN and returns `Ok`). Line shapes taken from live runs: `bump --gates` on this repo printed `Gates:  none (ungated)`; on `tatari-tv/tatari-skills`, `Gates:  classic_protection, workflows (gated)`; on the remote-less scratch repo, `Gates:  UNKNOWN (could not verify: not a GitHub remote)`, exit 0.
- Branch 1 (ungated) runs inline in the main session, no agent, per the 2026-10-02 (a) ruling; it carries the 2026-10-03 (c) tatari-tv temp-branch + `git merge --ff-only` shape and the 2026-10-05 (d) feature-branch fast-forward, then a bare `bump release` with `run_in_background` after a separate `cd <REPO>` (installed `bump release --help` shows no `[DIR]`), then the live proof (`command -v` + `--version` + acceptance for a CLI, `sdv probe` loop for a service, `/cli-shakedown` by the caller), the `shipit/SKILL.md` contract.
- Branch 4 is checked on every ungated verdict before Branch 1. Its signals are concrete: Scott said this session the change ships as a PR / "on a branch" (2026-10-07 (a)), Scott called the repo protected this session, or the repo's `CLAUDE.md`/`AGENTS.md` says changes land by PR. The ask uses the `rules/interaction.md` shape.
- Branches 2 and 3 dispatch `subagent_type: "plan:release-driver"` with ENTRY `release` / `finish` and the agent's full input list (REPO, LEVEL, MESSAGE, INSTALL, KIND, DEPLOY-URL, ACCEPTANCE; MERGED-PR for finish), read from `plan/agents/release-driver.md`.
- Branch 2 adds two pre-dispatch cases the doc leaves implicit: uncommitted work on the gated default branch -> `git switch -c <slug>` first; local commits on the default branch not on origin -> stop and report (bump's own "stranded" state, never auto-rescued).
- Triggers: the description is the union of the `shipit` and `bump` trigger phrases, plus a one-line routing summary. Refusals, never-bend rules and the `bump` reference are carried from `bump/SKILL.md` and `shipit/SKILL.md`.
- The description is a single-quoted YAML scalar (`it''s` escaped). Unquoted, its `: ` makes the frontmatter invalid strict YAML: pi's loader logged `Nested mappings are not allowed in compact mappings at line 2, column 14` and dropped the skill, so the pi control showed 3 plan skills, not 4. The same warning fires today, with the committed pi settings, for the old `shipit`, `bump` and `babysit` (and, outside this doc, `anthropic-usage-report`, `e2e-v3`, `install-skills`; `cargo-install` fails with `description is required`), so pi loads none of them; the old files are left as-is under the rollback baseline.
- Doc amendment (authorized by the orchestrator, criteria rule): the Phase 3 criterion `rg -n babysit HOME/.claude/skills/plan` became `rg -n -w babysit HOME/.claude/skills/plan`, with a one-line reason under it in the design doc. The bare form hits `babysitter` in a comment at `seats/{architect,staff-engineer}/script.sh:76`, scripts the doc moves intact; the criterion meant the `/babysit` skill reference. This closes Phase 1's open question on that hit.
- `.otto.yml` lint `FILES` gained `HOME/.claude/skills/plan/skills/release/SKILL.md` (no em dashes in it).

### Deviations
- Branch 2's two pre-dispatch cases (switch to a slug branch for uncommitted work on a gated default; stop on stranded local commits) are not spelled out in the doc's five branches. They keep the bump on a feature PR and match `bump release`'s own state table rather than add behavior.
- Branch 4's trigger signals are this skill's concrete reading of "a repo Scott treats as protected"; the ruling names the situation, not how to detect it.

### Tradeoffs
- Gate check first vs `shipit`'s pre-flight first: the doc requires Branch 5 to stop before anything else, and `bump --gates` is read-only, so it runs before the "anything to ship?" check. Cost: a no-op release on an ungated repo still makes one gh call.
- Quoting the description vs rephrasing it to avoid `: `: quoting keeps the trigger phrases verbatim and guards future edits.

### Success criteria
- `claude plugin details plan@skills-dir` (fresh process, cwd scratchpad): `Skills (4)  build, create, release, review`, `Agents (4)  review-panel, phase-implementer, release-driver, design-research`. PASS.
- `/plan:release` headless in a fresh remote-less scratch repo (`git init -b main`, one commit, `git remote -v` empty), run `claude -p "/plan:release" --output-format stream-json --verbose` with cwd in the repo, final skill text: init event lists `plan:release`; tool calls: one Bash, `bump --gates <repo>`; zero `Agent`/`Task` tool_use (and `grep -c '"name":"Agent"'` on the stream is 0); result reports Branch 5 with the raw output including `Gates:  UNKNOWN (could not verify: not a GitHub remote)`; `git rev-list --count HEAD` 1 before and 1 after; `git status --short` empty; branches `main` only. PASS. (A first run, before the description was quoted, behaved the same with two Bash calls, `git rev-parse --show-toplevel` and `bump --gates`.)
- `rg -n -w babysit HOME/.claude/skills/plan` prints nothing, rc=1. PASS.
- `git diff --quiet 62dc65f -- HOME/.claude/skills/shipit HOME/.claude/skills/bump`: rc=0 (old files byte-identical).
- `otto ci`: exit 0, `All CI checks passed!` (rerun after the notes and the quoting fix). Throwaway launch `claude -p "reply OK"` from the scratchpad printed `OK`, rc=0.
- pi, through its own `DefaultResourceLoader` (`SettingsManager.create(dir, dir)`, `reload()`, `getSkills()`) against a copy of the committed `HOME/.pi/agent/settings.json`: 136 skills, 0 from `/skills/plan/`. Control (same copy, the four `plan/skills/*` entries removed): 140 skills, 4 from `/skills/plan/` (`build create release review`). The fourth exclusion is now proven against a real skill.

### Open questions
- The old `shipit`, `bump` and `babysit` descriptions are invalid strict YAML (unquoted `: `), so pi loads none of them today, with no exclusion involved. They are frozen by the rollback baseline and removed in Phase 6, so this is moot for them; `anthropic-usage-report`, `e2e-v3`, `install-skills` and `cargo-install` have the same class of defect outside this doc's scope. Worth a separate fix?
- `plan/skills/build/SKILL.md` finalization still runs raw `bump release` / `bump finish` rather than calling `/plan:release` (Phase 2 decision, unchanged here). Repoint it, and in which phase?

## Phase 4: Remaining parallel entries
### Design decisions
- `hooks/handoff-guard.sh:113`: the exclusion regex is `(^|/)docs/(design|plan)/`; the header comment (`:29`) and the inline comment (`:109-111`) name both dirs. Fixture row 21 in `fixtures/handoff-guard/controls.tsv` is `review docs/plan/2026-10-29-handoff-and-waiting-discipline.md`, a prompt that names a handoff-basename doc under `docs/plan/` and must stay silent. The count assertion, its banner and its failure message in `handoff-guard-test.sh` moved 20 -> 21 in the same commit.
- `hooks/inline/resolve.py`: new `skills_dir_plugin_skill_names(settings, skills_dir)`, the third enumerator, composed in `enumerate_skills`. It globs `*/.claude-plugin/plugin.json` under the skills dir, takes the plugin name from `plugin.json` (dir name as fallback), and emits `<plugin>:<skill>` for each `skills/*/SKILL.md`. It skips only when `enabledPlugins["<name>@skills-dir"] is False`; an absent key is enabled (Phase 0 (j): `enable` removes the key). No bare alias is emitted.
- Tests in `inline/resolve_tests.py` (`SkillsDirPluginSkillNamesTest`): enumerate, skip-on-false, absent-key-enabled, explicit-true-enabled, dir-without-manifest, missing dir, and `enumerate_skills` composition with no bare alias. `LiveStateTest.test_plan_create_resolves_to_exactly_the_namespaced_skill` pins `resolve("plan:create") == ["plan:create"]` against the live tree.
- `AcceptanceCriterionSevenTest` (`kept == 571`) is unchanged and still passes. It guards the matcher's survivor count over frozen fixture tokens, and bare tokens never match a namespaced skill, so adding `plan:*` cannot move it. No live count changed.
- `skills/rwl-a-plan/SKILL.md:94`: `git add <design-doc-path>` with a note that the doc stays where it lives. `skills/thorough-review/SKILL.md:21`: reads prior docs from `docs/plan/` or `docs/design/`; `:22` and `:79`: deliverables go to `docs/plan/` (new docs follow the writer rule).
- `rules/general.md` Documentation: `/plan:create` writes `docs/plan/`, `/create-design-doc` writes `docs/design/` until removal, existing docs stay, readers match both. `README.md` layout table gained a `docs/plan/` row.
- Old pipeline files untouched; the rollback-baseline lint passed in `otto ci`.

### Deviations
- None. (`thorough-review` `:21` is a reader and names both dirs; `:22,:79` are writers and name only `docs/plan/`, which is the "new docs land in `docs/plan/`" rule.)

### Tradeoffs
- Plugin name read from `plugin.json` vs the directory name: the harness keys `enabledPlugins` by the manifest name; the dir name is only a fallback for a manifest without `name`.
- `is False` vs falsy for the skip: a missing or null key must not disable the plugin, per the measured enable behavior.

### Success criteria
- `handoff-guard-test.sh`: `pass=150 fail=0`. `inline/resolve_tests.py`: 29 tests OK. `resolve("plan:create")` against the live tree: `['plan:create']`. PASS.
- Bite-proof: with `:113` reverted to `docs/design/` only, `handoff-guard-test.sh` printed `FAIL  control 21: wanted silence, got {` and `pass=149 fail=1`; restored: `pass=150 fail=0`.
- `otto ci`: exit 0, `All CI checks passed!`.
- Throwaway launch after the `rules/general.md` edit: `claude -p "reply OK"` from a scratch dir printed `OK`, rc=0.
- `rg -n 'pathglob' ~/.gemini/settings.json` names `skills/plan/seats/architect/pathglob.py` on desk and lappy: PENDING OPERATOR STEP (Scott's). Observed on desk after this phase: `~/.gemini/settings.json:22` still reads `python3 -I "$HOME/.claude/skills/architect/pathglob.py"`. Lappy not checked.

### Open questions
- The gemini repoint on desk and lappy is Scott's; Phase 5's `ARCHITECT_PATHGLOB=1` step needs it done first.
