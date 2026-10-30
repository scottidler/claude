# Design Document: the `plan` plugin

**Author:** Scott Idler (drafted with Claude)
**Date:** 2026-10-29
**Status:** In Review
**Review Passes Completed:** 5/5
**Panel rounds:** 2 (synthesis `~/.cache/review-panel/runs/K9rJmiCh/synthesis.md`; round 1: 9 must-fix, 9 cheap-win; round 2: freeze dispute closed, 2 mis-folds and 2 new defects; all folded in below)

## Summary

Collapse the design-doc pipeline (create, review, build, release) into one skills-dir plugin, `plan`, at `HOME/.claude/skills/plan/`. Four skills (`/plan:create`, `/plan:build`, `/plan:review`, `/plan:release`) and four agents (`plan:design-research`, `plan:phase-implementer`, `plan:review-panel`, `plan:release-driver`). New docs land in `docs/plan/`. The new plugin is built and proven live next to the old skills and agents; the old ones are removed in the last phase, after a soak Scott ends.

## Problem Statement

### Background

- The pipeline is spread across 8 personal skills and 4 agents, all in this repo:
  - skills: `create-design-doc`, `how-to-execute-a-plan`, `review-panel`, `architect`, `staff-engineer`, `shipit`, `bump`, `babysit`
  - agents: `design-research`, `phase-implementer`, `review-panel` (+ `review-panel-notes.md`, `review-panel-prompts.md`), `release-driver`
- They call each other by bare name and by absolute path (`agents/review-panel.md:132-133` runs `/home/saidler/.claude/skills/{architect,staff-engineer}/script.sh`).
- Skills-dir plugins already exist here: `rails`, `session`, `pr-guard`. `~/.claude/skills` is a whole-dir symlink into this repo (`manifest.yml:5-6`), so a `plan/.claude-plugin/plugin.json` goes live at the next session start after its commit lands in the working tree, with no manifest run and no `enabledPlugins` entry.
- `pr:watch` (tatari-skills, `pr@tatari-skills` installed) replaces `babysit` (Scott, 2026-10-29).

### Problem

- No single unit owns the pipeline. Renaming one piece means hunting every caller by hand.
- `shipit` and `bump` are two entry points to one release flow with two different routings: `shipit` hands nearly everything to `release-driver` (`skills/shipit/SKILL.md:14-18`, inline only for a "trivial ungated bump" `:72`), while the standing ruling is protected -> release-driver, not protected -> inline `bump release` (`refs/release-rulings.md:10`, `WHOAMI.md:44`).
- "Design doc" undersells what these docs are: a phased build plan that `/how-to-execute-a-plan` consumes.

### Goals

- One plugin `plan` with skills `create`, `build`, `review`, `release` and agents `design-research`, `phase-implementer`, `review-panel`, `release-driver` (Scott, 2026-10-29).
- `architect` and `staff-engineer` fold into `/plan:review` as seats: no arg runs both, `/plan:review architect` or `/plan:review staff-engineer` runs one (Scott, 2026-10-29).
- `/plan:release` unifies `shipit` and `bump`: `bump --gates` picks the path (Scott, 2026-10-29).
- New docs, their `-implementation-notes.md` and `-review-log.md` land in `docs/plan/` (Scott, 2026-10-29).
- Old and new run side by side; old is removed only after the new is proven live (Scott, 2026-10-29).
- `babysit` is removed in favor of `pr:watch` (Scott, 2026-10-29).

### Non-Goals

- **Excluded:** moving existing `docs/design/*` docs. They stay; every reader matches both dirs.
- **Excluded:** publishing `plan` to tatari-skills. It depends on Scott's personal tooling (`otto`, `bump`, `sdv`, gemini and codex CLIs, clyde).
- **Excluded:** pi consuming the `plan` skills. pi keeps reading the old skills by path until Phase 6; `plan/` is excluded from pi's skill loader.
- **Excluded:** chunk G of the setup-audit program (agent house rules, dispatch.md, model defaults, phase return contract). This doc copies the agents as-is; G later works against `plan/agents/*`.
- **Excluded:** behavior changes inside the copied skills and agents beyond renames, paths, the dual-dir doc readers and writers, and the `/plan:release` routing. Same content, new home.
- **Excluded:** `cargo-install`, `sdv-probe`, `rwl-a-plan`, `spec-review`, `thorough-review` move into `plan`. They stay personal skills; `rwl-a-plan` and `thorough-review` get the `docs/plan/` reader fix in Phase 4, and Phase 6 fixes old-name references.

## Proposed Solution

### Overview

Copy, don't move. Phase 1 lands the plugin skeleton together with everything that must hold the moment it goes live (round cap, seat sandbox entries, pi exclusion). Phases 2-4 add the skills and the remaining parallel entries. Phase 5 proves the new path live, including a completed build and both release paths. Scott runs both during a soak and calls the cutover. Phase 6 deletes the old files and the parallel entries that point at them, then proves `/plan:review` again with the old tree gone.

### Architecture

```
HOME/.claude/skills/plan/
  .claude-plugin/plugin.json      name, version, description, author (validate --strict needs author)
  skills/
    create/   SKILL.md template.md example.md         <- create-design-doc
    build/    SKILL.md                                <- how-to-execute-a-plan
    review/   SKILL.md                                <- review-panel skill + architect/staff-engineer entries
    release/  SKILL.md                                <- shipit + bump, merged
  agents/
    design-research.md  phase-implementer.md  review-panel.md  release-driver.md
  refs/
    review-panel-notes.md  review-panel-prompts.md    <- NOT agents/: a frontmatter-less .md there loads as a bogus agent
  seats/
    architect/       script.sh persona.md policy.toml pathglob.py limitations.md   (no SKILL.md)
    staff-engineer/  script.sh persona.md notes.md                                  (no SKILL.md)
```

- **Seats live outside `skills/`.** A `SKILL.md` under `skills/` registers as a `plan:<x>` skill; the seats are scripts the review path calls, not skills.
- **Companions live in `refs/`.** Measured 2026-10-29 with `--plugin-dir`: `agents/review-panel-notes.md` loaded as agent `plan:review-panel-notes`.
- **Seat scripts move intact.** They find `persona.md` and `policy.toml` via `SCRIPT_DIR="$(dirname "$0")"` (`architect/script.sh:62,118,237`, `staff-engineer/script.sh:62,117`). `__pycache__` is not copied. `staff-engineer/notes.md:12` cites the old architect persona path and is rewritten on copy.
- **Paths inside skill and agent bodies are absolute** (`/home/saidler/.claude/skills/plan/...`), matching `review-panel.md` today, unless Phase 0 proves `${CLAUDE_PLUGIN_ROOT}` expands in bodies. Tilde heads were denied as `[Auto-Mode Bypass]` (`agents/review-panel.md`, the Step 3 note).
- **pi:** `HOME/.pi/agent/settings.json` loads `~/.claude/skills` with per-dir `-` exclusions, and pi's loader recurses into any dir without a `SKILL.md` (panel round 1, verified), so it would register `plan/skills/*` as bare `create`, `build`, `review`, `release`. A `-` entry matches only a SKILL.md path or its parent dir exactly, never an ancestor (pi 1.0.4 `matchesAnyExactPattern`, `dist/core/package-manager.js:500-518`, panel round 2), so `-~/.claude/skills/plan` hides nothing. Phase 1 adds one exact entry per plan skill, in the form Phase 0 (h) proves.

### Naming

| Old | New |
|---|---|
| `/create-design-doc` | `/plan:create` |
| `/how-to-execute-a-plan` | `/plan:build` |
| `/review-panel`, `/architect`, `/staff-engineer` | `/plan:review [architect\|staff-engineer]` |
| `/shipit`, `/bump` | `/plan:release` |
| `/babysit` | `/pr:watch` (tatari-skills) |
| agent `design-research` | `plan:design-research` |
| agent `phase-implementer` | `plan:phase-implementer` |
| agent `review-panel` | `plan:review-panel` |
| agent `release-driver` | `plan:release-driver` |
| `docs/design/` | `docs/plan/` (new docs only) |

- Measured 2026-10-29 (`--plugin-dir`, scratch plugin): init event lists `plan:create`, `plan:release`, `plan:review-panel` next to bare `create-design-doc`, `shipit`, `review-panel`. No collision, so side by side works.
- In-plugin dispatch is always namespaced: `subagent_type: "plan:phase-implementer"`, `Skill(plan:review)`. Precedent: `tatari-skills/plugins/sre/skills/clean-backlog/SKILL.md` dispatches `sre:sre-deep-read-backlog`.

### Doc location rule (readers and writers)

- `/plan:create` writes new docs to `docs/plan/`.
- Every other reader and writer (build notes, the Status `sed`, `git add`, review-panel's no-DOC_PATH scan, the seat entries' newest-doc pick) derives the directory from the input doc's path, or scans `docs/plan/` and `docs/design/`. Nothing hardcodes one dir. So a `docs/design/` doc mid-build during the soak keeps its notes beside it.

### `/plan:review` behavior

- No arg: dispatch `plan:review-panel` (both seats in parallel, reconciled synthesis). Same as `Skill(review-panel)` today, counted by `panel-round-guard.sh`.
- `architect` | `staff-engineer`: run that one seat script directly, as `/architect` and `/staff-engineer` do today. Not routed through the agent, not counted by the round cap (unchanged from today). The newest-doc pick scans both dirs.

### `/plan:release` behavior

- Run `bump --gates` in the target repo and parse the verdict. Five branches:
  1. **Ungated:** commit on main (tatari-tv ungated: temp branch + `git merge --ff-only`, per `release-rulings.md` 2026-10-03 (c)), then `bump release` inline, `run_in_background`. No agent. The main session waits for the completion notification, then proves the new version live: installed binary `--version` plus the acceptance command for a CLI, `sdv probe` for a deployed service (the `shipit/SKILL.md:33` contract).
  2. **Gated, work on a feature branch:** dispatch `plan:release-driver` with ENTRY `release` (`release-driver.md:30` accepts `release` | `finish`). It runs `bump release`, waits for merge, `bump finish`, install, probe.
  3. **Gated, PR already merged:** dispatch `plan:release-driver` with ENTRY `finish`.
  4. **Gate says unprotected on a repo Scott treats as protected:** stop and ask (`release-rulings.md` 2026-10-07 (d)).
  5. **`Gates: UNKNOWN` or unparseable output:** stop before any commit or dispatch and report the raw output. `bump --gates` prints `UNKNOWN` and exits 0 (`bump/src/main.rs:340-346`), so the exit code is not the signal.
- Triggers: union of `shipit` and `bump` descriptions.
- `plan:release-driver` cites `pr:watch` where `release-driver.md:3,172` cites `/babysit` today.

### Implementation Plan

Each phase: one commit on main (this repo takes no PRs), `otto ci` green. From Phase 1 the old files are the rollback baseline: a lint check pins them to a recorded SHA, so fixes during the soak land in `plan/` only. Old and new diverge by design; the old copy stays exactly what it was.

#### Phase 0: Prove skills-dir loads skills and agents
**Model:** sonnet
- Zero repo code. Scratch plugin named `plan` at `~/.claude/skills/plan/` (untracked, never committed, `rkvr rmrf` before Phase 1) with stub `skills/{create,build,review,release}`, `agents/review-panel.md`, `seats/`, `refs/`. The name is `plan` and not `plan-spike` so (i) tests the name that ships.
- Prove and record PASS or FAIL with evidence, in this doc:
  - (a) skills-dir (not `--plugin-dir`) loads `skills/` and `agents/`, named `plan:*`
  - (b) Agent PreToolUse payload carries `subagent_type == "plan:review-panel"` (capture hook)
  - (c) a plugin skill dispatches its own agent by namespaced name
  - (d) `skills/*/SKILL.md` nested in the plugin is not also registered as a bare personal skill
  - (e) `Skill(plan:*)` (the wildcard form Phase 1 ships) matches `Skill(plan:create)` as a permission allow
  - (f) `${CLAUDE_PLUGIN_ROOT}` or `${CLAUDE_SKILL_DIR}` expands in skill and agent bodies
  - (g) `claude plugin validate --strict` accepts `seats/` and `refs/`
  - (h) with four exact entries `-/home/saidler/.claude/skills/plan/skills/{create,build,review,release}` added to a scratch copy of the pi settings, pi registers no `create`, `build`, `review` or `release` skill; with only `-~/.claude/skills/plan`, it registers all four (expected, the ancestor form matches nothing)
  - (i) the built-in `/plan` command does not shadow `/plan:*` in the TUI
  - (j) `claude plugin disable plan@skills-dir` drops the `plan:*` names from the init event and sets `enabledPlugins["plan@skills-dir"] = false`; `enable` restores them (proves the soak rollback and the key `resolve.py` reads)
- If (a) fails: stop. The doc goes back to review with `--plugin-dir` or a local marketplace as the delivery options.
- If (i) fails: stop and bring Scott the rename question; the plugin name is his call.
- If (e) fails: Phase 1 lists each `Skill(plan:<skill>)` explicitly.
- If (h) fails with the four exact entries: stop. pi needs another exclusion mechanism before Phase 1 makes the plugin live.
- **Success criteria:**
  - `claude plugin details plan@skills-dir` shows `Skills (4)` and `Agents (1)`
  - capture-hook log contains `"subagent_type":"plan:review-panel"`
  - all ten items recorded with evidence

##### Phase 0 results

Run 2026-10-29, Claude Code 2.1.314, pi 1.0.4, scratch plugin `plan` at `~/.claude/skills/plan/` (version 0.0.1, since removed with `rkvr rmrf`). Items (a)-(j): all 10 PASS, with caveats noted on (e), (f), (i). No stop branch hit.

- (a) PASS. Fresh headless init event (`claude -p --output-format stream-json --verbose "reply OK"`, cwd `/tmp`): `skills` gained `plan:build`, `plan:create`, `plan:release`, `plan:review`; `agents` gained `plan:review-panel`; `plugins` has `{"name":"plan","path":"/home/saidler/.claude/skills/plan","source":"plan@skills-dir","version":"0.0.1"}`. Loaded via skills-dir, no `--plugin-dir`.
- (b) PASS. Scratch settings file passed with `--settings` (PreToolUse, matcher `Agent|Task|Skill`, hook appends stdin to a log) and the prompt "Run the skill plan:review using the Skill tool". The log holds `Agent {"description":"Panel stub check","prompt":"...","subagent_type":"plan:review-panel","run_in_background":false}`; `grep -o '"subagent_type":"[^"]*"'` gives `"subagent_type":"plan:review-panel"`. The Skill call was captured as `{"skill":"plan:review"}`.
- (c) PASS. `skills/review/SKILL.md` said to dispatch `subagent_type "plan:review-panel"`; the dispatch ran and the agent replied `PANEL-OK`.
- (d) PASS. The same init event lists no bare `create`, `build`, `review` or `release` skill. The nested stubs register only as `plan:*` (bare `review-panel`, `create-design-doc`, `create-repo` are other, existing skills).
- (e) PASS. With `{"permissions":{"allow":["Skill(plan:*)"]}}` a `Skill(plan:create)` call logged `"permission_decision":{"decision":"accept","source":"config","reason_type":"rule"}`; the same call with `{}` settings logged `{"decision":"accept","source":"config"}` with no `reason_type:"rule"`. So the wildcard matched as a rule allow. Caveat: `defaultMode` is `auto`, so the control accepts without the rule too; the evidence is the `rule` reason, not a denial.
- (f) PASS. Both vars expand in skill and agent bodies. `/plan:create` body `CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT} SKILL_DIR=${CLAUDE_SKILL_DIR}` returned `CLAUDE_PLUGIN_ROOT=/home/saidler/.claude/skills/plan` and `SKILL_DIR=/home/saidler/.claude/skills/plan/skills/create`. The `review` skill body's `${CLAUDE_PLUGIN_ROOT}` reached the dispatched prompt as `/home/saidler/.claude/skills/plan`, and the agent body's `AGENT_ROOT=${CLAUDE_PLUGIN_ROOT}` came back as `AGENT_ROOT=/home/saidler/.claude/skills/plan`. Caveat: proven in body text only, not inside a Bash command the model runs. Phase 1 can use it in bodies; keep absolute paths at the head of Bash commands until Phase 5 proves otherwise.
- (g) PASS. `claude plugin validate --strict ~/.claude/skills/plan` exits 0 (`Validation passed`) with `seats/architect/script.sh` and `refs/notes.md` present. It also prints directory-profile warnings (README, LICENSE, icon missing) that do not change the result.
- (h) PASS. Scratch pi agent dirs, each a copy of `HOME/.pi/agent/settings.json` plus extra `skills` entries, loaded through pi's own `DefaultResourceLoader` (`SettingsManager.create(dir, dir)`, `reload()`, `getSkills()`):
  - no plan entry: 140 skills, 4 from `/skills/plan/` (`build create release review`)
  - only `-~/.claude/skills/plan`: 140 skills, the same 4 (the ancestor form hides nothing, as expected)
  - four entries `-/home/saidler/.claude/skills/plan/skills/{create,build,review,release}`: 136 skills, 0 from `/skills/plan/`
  Phase 1 ships the four exact absolute entries.
- (i) PASS. Interactive `claude` v2.1.314 under tmux (cwd `/tmp`). Typing `/plan` lists the built-in (`/plan  Enable plan mode or view the current session plan`) and beneath it `/plan:build`, `/plan:create`, `/plan:review`, `/plan:release`. Submitting `/plan:create` ran the plugin skill: the pane showed `CLAUDE_PLUGIN_ROOT=/home/saidler/.claude/skills/plan SKILL_DIR=.../skills/create` and `STUB-create`. No shadowing.
- (j) PASS. `claude plugin disable plan@skills-dir` printed `Successfully disabled plugin: plan` and added `"plan@skills-dir": false` to `enabledPlugins` (written through the `~/.claude/settings.json` symlink into `HOME/.claude/settings.json`; the diff was exactly that one line). A fresh init event then listed no `plan:*` skills, no `plan:*` agents and no `plan` plugin; `claude plugin details plan@skills-dir` still resolved. `claude plugin enable plan@skills-dir` restored all 4 skills and the agent in a fresh init event, and removed the key (diff against the committed file empty) instead of writing `true`. So Phase 4's `resolve.py` treats `enabledPlugins["<name>@skills-dir"] == false` as disabled and an absent key as enabled. `HOME/.claude/settings.json` was reverted with `git checkout`; `git status` is clean for it.
- Success criteria: `claude plugin details plan@skills-dir` showed `Skills (4)  build, create, release, review` and `Agents (1)  review-panel`; the capture log contained `"subagent_type":"plan:review-panel"`; all ten items recorded above.

#### Phase 1: Skeleton, agents, seats, and the live-from-commit guards
**Model:** opus
- `plan/.claude-plugin/plugin.json` shaped like `rails/.claude-plugin/plugin.json` (author included).
- Copy the four agents into `agents/`, the two companions into `refs/`, the seat dirs into `seats/`.
- Rewrite in the copies: agent names to `plan:*`, companion paths to `refs/`, seat paths to `seats/`, `staff-engineer/notes.md:12` persona path, review-panel's doc scan per the doc location rule (`review-panel.md:96,139,151,229`), ENTRY and `/babysit` -> `pr:watch` in `release-driver.md`.
- Everything that must hold the moment the plugin is live, in this same commit:
  - `hooks/panel-round-guard.sh:138`: accept `review-panel` and `plan:review-panel`. Counter key stays `(doc, mode)` (`:235`). Tests in `panel-round-guard-test.sh`: a `plan:review-panel` round-4 deny, and a mixed sequence (3 dispatches alternating names, 4th denied).
  - `settings.json`: new seat paths in `sandbox.excludedCommands` (`:1182-1183`) with both `rails/hooks/index.spec.ts` lists (`SHIPPED_EXCLUDED` and `EXCLUDED`, `:395-405`) updated; `Bash(<seat>:*)` allows (`:232-233`); `Skill(plan:*)` allow; the autoMode allow prose (`:1198`) names the new architect seat path.
  - `HOME/.pi/agent/settings.json`: the four exact plan-skill exclusions Phase 0 (h) proved.
- `.otto.yml` test task: `claude plugin validate --strict HOME/.claude/skills/plan`; plan files in the lint `FILES` list.
- `.otto.yml` lint, rollback-baseline check: `git diff --quiet <literal SHA of this phase's parent> -- <8 old skill dirs, 6 old agent files>` and `git ls-files --others --exclude-standard -- <same paths>` prints nothing. Removed in Phase 6.
- **Success criteria:**
  - `claude plugin details plan@skills-dir` shows `Agents (4)`, and the init event lists no `plan:review-panel-notes` or `plan:review-panel-prompts`
  - `panel-round-guard-test.sh` ends `fail=0` with the new-name deny and the mixed-name case; reverting the `:138` change makes both fail
  - appending a line to `HOME/.claude/skills/shipit/SKILL.md`, or creating an untracked file under it, makes `otto lint` fail; reverting passes

#### Phase 2: Skills create, build, review
**Model:** sonnet
- `skills/create/` from `create-design-doc/` (+ `template.md`, `example.md`): `design-research` -> `plan:design-research`, `Skill(review-panel)` -> `Skill(plan:review)`, output `docs/plan/`.
- `skills/build/` from `how-to-execute-a-plan/`: `phase-implementer` -> `plan:phase-implementer`, `/create-design-doc` -> `/plan:create`, `Skill(review-panel)` -> `Skill(plan:review)`, `/bump` and `release-driver` -> `/plan:release` and `plan:release-driver`, `babysit` -> `pr:watch`. All seven `docs/design` write sites (`:185,286,289,296,311,465,511`: notes path, Status `sed`, `git add`, commit message) and the readers follow the doc location rule.
- `skills/review/` from `review-panel/SKILL.md` plus the `architect` and `staff-engineer` SKILL.md entry text, with the seat argument per "`/plan:review` behavior"; the newest-doc `find` (`architect/SKILL.md:49`, `staff-engineer/SKILL.md:59`) scans both dirs.
- **Success criteria:**
  - `claude plugin details plan@skills-dir` shows `Skills (3)`
  - `rg -n -e '"(design-research|phase-implementer|review-panel|release-driver)"' -e '/create-design-doc' -e '/how-to-execute-a-plan' -e 'skills/(architect|staff-engineer)/' HOME/.claude/skills/plan/skills` prints nothing
  - every `docs/design` hit in `HOME/.claude/skills/plan/skills` (`rg -n docs/design`) is either a write site or reader listed above that also names `docs/plan` or derives from the input path, or a historical provenance citation (e.g. the `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md` citation carried from `how-to-execute-a-plan/SKILL.md:61`), listed by line in the implementation notes

#### Phase 3: Skill release
**Model:** opus
- `skills/release/SKILL.md` per "`/plan:release` behavior", from `shipit` and `bump`. Routing follows the ruling, not `shipit`'s current hand-everything-to-the-agent shape.
- **Success criteria:**
  - `claude plugin details plan@skills-dir` shows `Skills (4)`
  - `/plan:release` in a scratch git repo with no GitHub remote stops at branch 5 (`Gates: UNKNOWN`) with no new commit (`git rev-list --count HEAD` unchanged) and no agent dispatch
    - Observed on main (2026-10-29), `bump --gates <remote-less scratch repo>`: `Gates:  UNKNOWN (could not verify: not a GitHub remote)`
  - `rg -n -w babysit HOME/.claude/skills/plan` prints nothing
    - Amended in Phase 3: `-w` added. The criterion targets the `/babysit` skill reference; the bare substring also hit "babysitter" in a comment at `seats/{architect,staff-engineer}/script.sh:76`, scripts this doc moves intact.

#### Phase 4: Remaining parallel entries
**Model:** sonnet
- `hooks/handoff-guard.sh:113`: exclude `docs/plan/` too; a fixture row in `fixtures/handoff-guard/controls.tsv` and the count assertion in `handoff-guard-test.sh:228-232` moved from 20 to 21 in the same commit.
- `hooks/inline/resolve.py`: third enumerator for skills-dir plugin skills (`skills/*/.claude-plugin/plugin.json` + `skills/*/SKILL.md` -> `<plugin>:<skill>`, skip `enabledPlugins["<name>@skills-dir"] == false`, the key Phase 0 (j) measured), tests in `inline/resolve_tests.py`.
- `skills/rwl-a-plan/SKILL.md:94` and `skills/thorough-review/SKILL.md:21,22,79`: readers and writers follow the doc location rule.
- `rules/general.md` Documentation: `/plan:create` writes `docs/plan/`; `/create-design-doc` writes `docs/design/` until removal. `README.md:33` layout table gains a `docs/plan/` row.
- Operator step, Scott, on desk and lappy: repoint `~/.gemini/settings.json:22` from `skills/architect/pathglob.py` to `skills/plan/seats/architect/pathglob.py`. Both copies are identical (the rollback-baseline check holds the old one), so old `/architect` runs are unaffected, and every soak review exercises the final hook path.
- **Success criteria:**
  - `handoff-guard-test.sh` and `resolve_tests.py` pass; `resolve("plan:create")` returns `["plan:create"]` against the live tree
  - `rg -n 'pathglob' ~/.gemini/settings.json` names `skills/plan/seats/architect/pathglob.py` on desk and lappy
  - `otto ci` exits 0

#### Phase 5: Live acceptance
**Model:** opus
- Fresh session per step, results recorded in `docs/design/2026-10-29-plan-plugin-implementation-notes.md` (this doc predates `docs/plan/`, so its notes sit beside it):
  - `/plan:create` on a toy feature in a scratch repo: doc lands in `docs/plan/`, `plan:design-research` dispatched
  - `/plan:review` on that doc: both seats run from `seats/`, rc files `rc=0`, no classifier denial, `ARCHITECT_PATHGLOB=1` run uses the repointed hook
  - `/plan:review architect`: one seat, direct
  - 4th `plan:review-panel` dispatch on the same doc: denied by the guard
  - `/plan:build` on a one-phase toy doc in `docs/plan/`: `plan:phase-implementer` commits, notes land beside the doc, `otto ci` green
  - `/plan:release`, ungated: the next ungated release Scott calls, through to installed version or probe
  - `/plan:release`, gated: the next gated release Scott calls, through `plan:release-driver` to `bump finish` and probe
- **Success criteria:** AC4 and AC5 pass.

#### Soak (Scott, not a phase)
- Use `/plan:*` for day-to-day work. Old skills stay loaded. Scott calls the cutover, and only after AC4 and AC5 pass.

#### Phase 6: Remove the old
**Model:** sonnet
- Gate: AC4 and AC5 recorded PASS in the implementation notes.
- Delete via `rkvr rmrf`: `skills/{create-design-doc,how-to-execute-a-plan,review-panel,architect,staff-engineer,shipit,bump,babysit}`, `agents/{design-research,phase-implementer,release-driver,review-panel,review-panel-notes,review-panel-prompts}.md`.
- Drop the old entries Phase 1 paralleled: `panel-round-guard.sh` bare name, old seat paths in `settings.json` and both `index.spec.ts` lists, old `Skill(...)` allows, autoMode prose. `HOME/.claude/settings.json.bak` is tracked and carries the old seat paths: delete it or update it, after reading what it backs up.
- Drop the rollback-baseline check from `.otto.yml`, and the four plan-skill pi exclusions only if pi is then pointed at the plan skills (otherwise they stay).
- Tests that read the live skill tree or the bare names:
  - `inline/resolve_tests.py` `AcceptanceCriterionSevenTest` (`kept == 571`): freeze the enumeration with a recorded `skills=` set; fixtures untouched
  - `inline/resolve_tests.py:187` `LiveStateTest` `resolve("babysit")`: retarget to a surviving skill
  - `inline-skill-tokens-test.sh` (`:98,104,111,114,116,132-137,185,203`): swap `/bump`, `/create-design-doc`, `/how-to-execute-a-plan`, `/babysit:bogus` for surviving names
  - `panel-round-guard-test.sh:47,141,170`: bare `review-panel` literals -> `plan:review-panel`
- `.otto.yml` lint `FILES`: drop the old paths. `bin/check-review-panel:22-23,76,128-132`: new seat paths.
- Prose that names the old: `HOME/.claude/CLAUDE.md`, `WHOAMI.md` (vocabulary: rp, panel, shipit, bump, plus `:44`), `refs/release-rulings.md`, `refs/process-taste.md`, `rules/{general,pr,rust,interaction}.md`, `routed/voice.md`, `hooks/codex-stdin-guard.sh:48` (deny prose), `skills/{rwl-a-plan,spec-review,thorough-review}/SKILL.md`, `HOME/.pi/agent/AGENTS.md`, `HOME/.pi/agent/prompts/{shipit,review-panel,how-to-execute-a-plan,babysit,create-design-doc}.md`. `rules/general.md` drops the `docs/design` line.
- Setup-audit baton: chunk G's targets become `plan/agents/*`.
- Recovery after removal: `git revert` of this single commit, plus the gemini repoint back.
- **Success criteria:** AC6 passes.

## Acceptance Criteria

- [ ] AC1: `claude plugin details plan@skills-dir` shows `Skills (4)` and `Agents (4)`.
  - Observed on main (2026-10-29): `Plugin "plan@skills-dir" not found.`
- [ ] AC2: during the soak, a headless init event (`claude -p --output-format stream-json --verbose "reply OK"`) lists all 8 `plan:*` names AND the 8 old skills and 4 old agents.
  - Observed on main: `{"agents":["design-research","phase-implementer","release-driver","review-panel"],"skills":["architect","babysit","bump","create-design-doc","how-to-execute-a-plan","review-panel","shipit","staff-engineer"]}`, no `plan:*`.
- [ ] AC3: `bash HOME/.claude/hooks/panel-round-guard-test.sh` ends `fail=0` and contains a `plan:review-panel` round-4 deny case and a mixed-name case.
  - Observed on main: `pass=125 fail=0`; no `plan:review-panel` case.
- [ ] AC4: a live `/plan:review` writes both seat rc files with `rc=0` from `HOME/.claude/skills/plan/seats/`, and a live `/plan:build` on a one-phase `docs/plan/` doc produces one commit plus a `-implementation-notes.md` beside that doc.
  - Cannot run on main: depends on Phases 1-4.
- [ ] AC5: one ungated and one gated `/plan:release` each end with the new version installed or probed live (binary `--version` or `sdv probe` shows the tag `bump` cut).
  - Cannot run on main: depends on Phase 3 and on releases Scott calls.
- [ ] AC6: after Phase 6, none of the 8 old skill dirs or 4 old agent files exist under `HOME/.claude/`; `git grep -l -E 'skills/(architect|staff-engineer)/|Skill\((shipit|bump|babysit|review-panel|create-design-doc|how-to-execute-a-plan)\)' -- ':!docs' ':!HOME/.claude/hooks/fixtures'` prints nothing (`git grep`, not `rg`: `rg` skips the hidden `.claude/` dirs; fixtures are frozen data); `otto ci` exits 0; and with the old tree gone, in fresh sessions: `/plan:review` still writes both rc files `rc=0`, `/plan:build` on a one-phase toy `docs/plan/` doc still produces one commit plus notes beside the doc, and `/plan:release` in the remote-less scratch repo still stops at branch 5 with no new commit and no dispatch.
  - Observed on main (`5d4a84a`, clean tree, 2026-10-29): all 12 present; `git grep` lists 11 files (`agents/review-panel.md`, `settings.json`, `settings.json.bak`, 6 old skill files, `rails/hooks/index.spec.ts`, `bin/check-review-panel`); `otto ci` exits 0 (`All CI checks passed!`).

## Resolved Decisions

- 2026-10-29, Scott: plugin named `plan`, lives in `scottidler/claude`, skills `create | build | review | release`, docs in `docs/plan/`.
- 2026-10-29, Scott: `architect` and `staff-engineer` fold into `plan` as seats of `/plan:review`.
- 2026-10-29, Scott: `release-driver` joins `plan` behind `/plan:release`, which unifies `shipit` and `bump`.
- 2026-10-29, Scott: `babysit` goes away for `pr:watch`.
- 2026-10-29, Scott: build and prove the new before removing the old; side by side meanwhile.
- 2026-10-29, author: single-seat `/plan:review <seat>` calls the seat script directly, uncapped, as `/architect` does today. Routing it through the agent would need a one-seat mode in `review-panel.md`, which is a behavior change outside scope.
- 2026-10-29, author: `AcceptanceCriterionSevenTest` freezes a recorded skill set at removal rather than re-baselining 571; the test guards the matcher, not the live skill list.
- 2026-10-29, author: `rules/general.md` names both dirs during the soak and only `docs/plan/` after removal, so the rule always matches what the loaded skills do.
- 2026-10-29, panel round 1 (staff, verified by the panel agent): the round-cap guard, seat sandbox entries and pi exclusion move to Phase 1, because the plugin is live from Phase 1's commit and `panel-round-guard.sh:138` passes any other `subagent_type`.
- 2026-10-29, panel round 1: the rollback-baseline check stays a lint `git diff` against a literal SHA plus an untracked-file check. The architect's "breaks on rebase" objection does not apply (main-only, no rebases), and its pre-commit alternative sees only staged changes.
- 2026-10-29, panel round 1: the gemini pathglob repoint moves from Phase 6 to Phase 4, so the soak exercises the final hook path while both copies exist.
- 2026-10-29, panel round 1: Phase 6 is gated on a completed live build and both release paths (AC4, AC5).
- 2026-10-29, panel round 2: both seats accept the rollback-baseline pushback (architect: "no concrete command sequence that defeats this check under these repo constraints"; staff ran it, exit 0 on baseline, 1 on a committed change). Dispute closed.
- 2026-10-29, panel round 2 (staff, verified against pi 1.0.4 source): the pi exclusion is four exact plan-skill entries, not the plugin dir; Phase 0 (h) gains a FAIL branch.
- 2026-10-29, panel round 2: AC6 re-proves build and release with the old tree gone, not only review. Release uses the Phase 3 remote-less stop, since a live release after removal would gate Phase 6 on one Scott calls.
- 2026-10-29, panel round 2: Phase 0 stubs all four skills, so (h) can pass; the Phase 2 `docs/design` criterion exempts historical citations.

## Alternatives Considered

### Move instead of copy
- **Description:** `git mv` everything in one phase and fix callers.
- **Pros:** no duplicate files, no drift window.
- **Cons:** the pipeline is down until the new one works; a skills-dir loading surprise breaks every design doc in flight.
- **Why not chosen:** Scott asked for side by side.

### Publish `plan` to tatari-skills
- **Description:** in-tree plugin under `tatari-skills/plugins/plan/`.
- **Pros:** marketplace delivery, bot versioning.
- **Cons:** depends on Scott's personal CLIs; `spec:design-doc` already exists there; `build` and `release` are not pillar verbs.
- **Why not chosen:** Scott chose `scottidler/claude`.

### Seats as their own skills (`/plan:architect`, `/plan:staff-engineer`)
- **Pros:** no argument parsing.
- **Cons:** nouns as skill names break noun:verb; two more entries for one action.
- **Why not chosen:** folded into `/plan:review` (Scott, 2026-10-29).

### Pre-commit hook as the rollback-baseline guard (architect, round 1)
- **Description:** `git diff --cached | grep <old paths>` in a pre-commit hook.
- **Why not chosen:** sees only staged changes, skipped by `--no-verify`, and adds a second mechanism next to `otto lint`.

## Technical Considerations

### Dependencies
- Claude Code skills-dir plugin loading (Phase 0 proves `skills/` and `agents/`).
- `bump` with `release`, `finish`, `--gates` (`bump --help`, 2026-10-29).
- `pr:watch` from `pr@tatari-skills`.
- gemini and codex CLIs behind the seat scripts (unchanged).

### Security
- The autoMode allow prose (`settings.json:1198`) grants the architect seat its pathglob hook by path. The new path needs the same grant, no wider: same `policy.toml`, same read-only allowlist.
- No secrets touched.

### Testing Strategy
- Mechanical: `claude plugin validate --strict` in `otto test`; `panel-round-guard-test.sh` new-name and mixed-name cases, proven to bite by reverting `:138`; the rollback-baseline check proven to bite in Phase 1; `resolve_tests.py` for the new enumerator; Phase 3's UNKNOWN stop in a scratch repo.
- Live: Phase 5, fresh sessions, results recorded; AC6's post-removal `/plan:review`.

### Rollout Plan
- Precondition for Phase 1: `otto ci` exits 0 on main with a clean tree. Met 2026-10-29 at `5d4a84a`, after the pending edits to `settings.json`, `WHOAMI.md`, `rules/general.md`, `rules/pr.md` and `HOME/.pi/agent/settings.json` landed as their own commits.
- Phases 0-5 land on main one commit each. The plugin is live on desk at the next session start; lappy at `git pull`.
- Soak until Scott calls it, after AC4 and AC5. Phase 6 removes the old.
- Rollback during the soak: `claude plugin disable plan@skills-dir` (proven in Phase 0 (j)). Old skills are untouched.

### Blast radius
- Single repo (`scottidler/claude`), plus the unmanaged `~/.gemini/settings.json` on desk and lappy (operator step, Phase 4).
- No other repo changes. tatari-skills untouched.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| skills-dir does not load `skills/` or `agents/` | Med | High | Phase 0 proves it with zero repo code; stop on FAIL |
| Old copy changes during the soak, so rollback is not to a known state | Med | Med | Phase 1 lint check pins old files to a literal SHA and rejects untracked additions; fixes land in `plan/` only |
| Phase 0 spike dir `plan/` left behind and committed by Phase 1 | Low | Med | Phase 0 removes it with `rkvr rmrf`; Phase 1 starts from `git status` showing no `skills/plan/` |
| Round cap open for `plan:review-panel` | Low | High | Guard change ships in the same commit that makes the agent live (Phase 1), with tests proven to bite |
| pi registers `plan/skills/*` as bare names | High without fix | Med | pi exclusion in Phase 1; Phase 0 (h) proves both sides |
| Classifier denies the new seat path | Med | Med | autoMode prose updated Phase 1; proven live Phase 5 |
| `/plan:release` acts on an UNKNOWN gate | Low | High | Branch 5 stops before any commit; Phase 3 test in a remote-less scratch repo |
| Old-name tests break at removal | High | Low | Phase 6 lists every live-tree and bare-name test and fixes them in the same commit |
| `pr:watch` drafts human-review replies for Scott to pick, where `babysit` posted | Low | Low | Accepted with the swap (Scott, 2026-10-29); `rules/pr.md` updated Phase 6 |

## Open Questions

- [ ] none

## References
- `docs/design/2026-09-13-setup-audit-program.md` (chunk G overlap)
- `docs/design/2026-09-14-panel-round-cap.md` (the guard)
- `refs/release-rulings.md`
- `tatari-skills/plugins/sre/skills/clean-backlog/SKILL.md` (namespaced agent dispatch precedent)
- Panel round 1 synthesis: `~/.cache/review-panel/runs/K9rJmiCh/synthesis.md`
