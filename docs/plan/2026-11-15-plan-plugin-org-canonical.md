# Design Document: Make the org plan plugin canonical

**Author:** Scott A. Idler
**Date:** 2026-11-15
**Status:** In Review
**Review Passes Completed:** 5/5 (draft, correctness against live probes, edge cases, clarity and excellence in the round-1 rewrite); panel round 1 folded

## Summary

Two copies of the `plan` plugin exist and have diverged since 2026-11-05: the personal skills-dir copy in this repo (the only one loaded) and the org copy in `tatari-tv/tatari-skills`. This doc makes `plan@tatari-skills` the only copy. It transfers `bump` to tatari-tv, ports `/plan:release` and the closing status block upstream with neutral wording, fixes the `/pr:watch` gap on the way, then switches this repo over and deletes the personal copy.

## Problem Statement

### Background

- 2026-10-29: `docs/design/2026-10-29-plan-plugin.md` built the personal plugin and excluded publishing to tatari-skills because it "depends on Scott's personal tooling (`otto`, `bump`, `sdv`, gemini and codex CLIs, clyde)".
- 2026-11-05: tatari-skills PR https://github.com/tatari-tv/tatari-skills/pull/688 (`56ac3fe9`) landed an org port of create, review and build. It stripped personal coupling and dropped the release back half. Build now ends `Branch ready, PR not opened. Next: /pr:create`.
- Since then:
  - org: `831a7a17` moved the panel onto `bin/plan-panel` with no permission prompts, and `1b14bf16` added an eval for each agent
  - personal: `748ab60`, `b57a463` and `d5a71c5` changed release, the driver and the seat watchdog, and `52c03ec` added the closing status block
- 2026-11-15: Scott reopened the Non-Goal (`docs/handoff/plan-plugin-org-placement.md`). Each dependency was probed:

| Dependency | Probe | Class |
|---|---|---|
| `otto` | `.otto.yml` in 67 tatari-tv repos, 47 workflows call it, and the Backstage scaffolder emits it | org-available |
| `sdv`, `clyde` | `~/repos/tatari-tv/{sdv,clyde}` | org-available |
| gemini / codex | `llm` plugin ships `bin/llm-gemini`, `bin/llm-codex`; org `plan` already declares `dependencies: ["llm"]` | org-available |
| `bump` | remote `scottidler/bump`, public, MIT | org-adoptable |

- Scott picked option A on 2026-11-15: org copy canonical, `bump` transfers to tatari-tv.

### Problem

- Two copies that diverge on every edit. Defects get fixed twice or once in the wrong copy.
- The two copies collide on load. `tatari-skills docs/plan/2026-11-03-plan-review-on-llm.md:161-162` measured `plan@skills-dir: ✘ Not loaded ... the name "plan" is already taken by an installed plugin (plan@tatari-skills), which takes precedence`. Installing the org copy today silently drops `/plan:release`.
- Open defect (tatari-skills local branch `plan-release-pr-watch`, `920fcb0b`, `docs/handoff/plan-release-pr-watch-gap.md`): `/plan:release` hands the merge wait to `release-driver` with no `/pr:watch` armed, so CodeRabbit findings sit until someone asks (drata-cli https://github.com/tatari-tv/drata-cli/pull/20). Its second half (bump opening PRs) is closed: bump `0a78a30`, v0.4.8+, and v0.4.10 `bump release --help` says bump never opens a PR.

### Goals

- `plan@tatari-skills` is the one loaded `plan` plugin, with create, review, build and release.
- `bump` lives at `tatari-tv/bump`.
- Org `release` and `release-driver` carry no personal coupling (no "Scott", no `~/repos/.claude`, no `~/HALL-OF-SHAME.md`, no rkvr).
- On a gated release, CI and review threads have one owner (`/pr:watch` or the author), and the merge has one observer (the driver).
- create, build and release end with the closing status block from `52c03ec`, in neutral wording.
- The personal `HOME/.claude/skills/plan` is gone, with no dead config left that names it.

### Non-Goals

- **Excluded:** porting the personal seat scripts and the `watchdog.sh` idle-kill (`d5a71c5`). Org seats run on the llm CLIs. The idle-kill is an llm-plugin change and its own PR.
- **Excluded:** retiring the old personal skills (`/shipit`, `/bump`, `/babysit`, `/create-design-doc`, `/how-to-execute-a-plan`, `/review-panel`, `/architect`, `/staff-engineer`) and the top-level `HOME/.claude/agents/release-driver.md`. That is setup-audit chunk J.
- **Excluded:** changes to the `pr` plugin, `otto`, `sdv` or `clyde`. The release flow below needs none.
- **Parked:** a `bump` pointer plugin (`plugin/` in tatari-tv/bump, pinned from tatari-skills, per tatari-skills `AGENTS.md:42`). Revisit when a second person runs `/plan:release`.
- **Parked:** making `persona_token_var` in bump (`src/github.rs:330-335`) generic. Other users fall back to ambient `gh auth`, which works. Revisit when that fallback fails for someone.

Setup-audit program note: the baton (`docs/design/2026-09-13-setup-audit-program.md`) says not to touch hooks, skills or settings out of chunk order. No chunk is `next`. This move is owner-ordered (Scott, 2026-11-15) and sits outside the program. It touches only the `plan`-specific parts of `settings.json`, `rails/hooks/index.spec.ts`, `.pi/agent/settings.json`, and `panel-round-guard.sh`.

## Proposed Solution

### Overview

Four repos:

`scottidler/bump` (neutral wording) -> GitHub transfer to `tatari-tv/bump` -> `tatari-tv/tatari-skills` (one PR: release port, merge-observer fix, closing blocks, residue, evals) merged and bot-bumped -> `scottidler/claude` (install org, delete personal).

Which steps the order forces:

- **Forced:** the org PR merges before this repo's switch. Installing `plan@tatari-skills` shadows the personal copy (measured), so switching early loses `/plan:release`.
- **Chosen, not forced:** bump's wording and transfer come before the org PR, so the ported preflight and docs name `tatari-tv/bump` from day one, and bump's wording change ships while bump is still ungated.

### Architecture

After the move:

| Piece | Lives in | Notes |
|---|---|---|
| `plan:create`, `plan:review`, `plan:build` | tatari-skills `plugins/plan/skills/` | unchanged except closing blocks |
| `plan:release` (new) | `plugins/plan/skills/release/SKILL.md` | preflight: `bump` on PATH at v0.4.8 or later |
| `plan:release-driver` (new) | `plugins/plan/agents/release-driver.md` | ENTRY `merge` = wait-only merge observer + back half; ENTRY `finish` = back half |
| `/pr:create`, `/pr:watch` | `plugins/pr` | added to plan's `dependencies`; used as shipped |
| `bump` | `tatari-tv/bump` | binary; plugins cannot declare binaries, so `metadata.needs: ["cli"]` plus the preflight |
| Owner standards | `env.PLAN_STANDARDS` in this repo's `settings.json` | `~/repos/.claude/rules/taste.md` |
| Round cap | `plan-panel resolve` (org) + `panel-round-guard.sh` (here) | both stay; agent id stays `plan:review-panel` |

### Release flow after the move (gated repo)

Facts this rests on (tatari-skills origin/main, verified 2026-11-15):

- `watch.py:1240-1241` returns `merged` only if the PR is already MERGED at poll time. `:1329` returns `ready` when the PR is approved, green and clean. `watch/SKILL.md:178` says that on `ready` the watcher reports and stops. It never sees a later human merge.
- `watch_offer.py` `decide_pre_skill` denies `Skill(pr:watch)` while this prompt's `/pr:create` offer is unanswered and `create.offer-watch` is `ask`, which is the default.
- `watch/SKILL.md:31`: in a headless (`sdk-*`) session, `/pr:watch` refuses and arms nothing.

The flow:

1. `plan:build` ends on a feature branch. Its last line becomes `Next: /pr:create, or /plan:release to ship`. Build never invokes release.
2. `/plan:release` checks that `bump --version` is v0.4.8 or later, then runs `bump --gates`.
   - **Ungated verdict, and the author does not treat the repo as protected:** `bump release` inline. No PR, no watcher, no driver.
   - **Gated, or the author treats the repo as protected:** `bump release` on the branch. Then `Skill(pr:create)` with the printed `Release: rides this PR (vX.Y.Z)` line.
3. **CI and review threads:** release never arms `/pr:watch` itself. It defers to `/pr:create`'s offer, so the user's `create.offer-watch` setting decides:
   - `yes`: `/pr:create`'s Stop hook arms the watcher. One watcher, armed once.
   - `ask`: the offer goes to the author. A yes arms the watcher.
   - `no`, a declined offer, or headless: no watcher. The release report says the author owns CI and review threads.
   - PR already open (bump's "open PR exists" path): no `/pr:create`, so no offer. Release prints `/pr:watch <url>` as the next step and does not invoke it, which keeps the author's setting in charge.
4. **Merge observer:** the main session dispatches `plan:release-driver` with ENTRY `merge` in the background, whatever happened in step 3. The driver only polls `gh pr view --json state`. It never fixes CI, never pushes, and never touches threads.
   - `MERGED`: the driver runs the back half (below).
   - `CLOSED`: the driver stops and reports. It runs no `bump finish`.
   - Wait ceiling reached, or a `gh` error persists: the driver stops and reports.
5. **Back half (ENTRY `finish`, or `merge` after MERGED):**
   - Check that the merged PR's `Release: rides this PR (vX.Y.Z)` version equals the version `bump finish` prints. If not, stop before tagging. Another release merged first.
   - `bump finish`, then install.
   - Live proof: `sdv probe` for a deployed service, or the binary's `--version` plus the repo's shakedown (if one exists) for a CLI.
6. **Every non-success exit reports the same fields:** PR URL, pending version, stage reached, whether a watcher is armed, and the resume command. The resume command is `/plan:release` after the merge, which dispatches ENTRY `finish`. That is the existing "the PR merged, finish the bump" arc.

The watcher and the driver run at the same time and never overlap: the watcher owns CI and threads up to `ready`, and the driver owns `MERGED` and after.

### Data Model

Not applicable. The one config value is `env.PLAN_STANDARDS`, a path. `plan-panel:415-423` reads the file and inlines its body as `## OWNER STANDARDS`, so the seats never follow the path themselves.

### API Design

Neutral rename:

| Old | New |
|---|---|
| `PANEL_ROUNDS_ORDERED_BY_SCOTT=<n>` (org `agents/review-panel.md:111`, `skills/review/SKILL.md:100`; `bin/plan-panel` takes `--rounds-ordered` and needs no change) | `PANEL_ROUNDS_ORDERED_BY_OWNER=<n>` |
| bump `Standalone release ordered by Scott: "<words>"` (`src/release/pr.rs:88`, `src/release.rs:1506`) | `Standalone release ordered by the owner: "<words>"` |
| bump `--standalone` help, `STANDALONE_DOOR` text (`src/cli.rs:137-142, 236-242`, `release.rs:77, 627`, `finish.rs:278`), README `:70-74` | "the owner" wording |

`panel-round-guard.sh` accepts both door names after Phase 7. The personal top-level `review-panel` agent still emits `_BY_SCOTT` until chunk J.

### Implementation Plan

#### Phase 0: Prove the switch in an isolated config dir
**Model:** opus
- Zero code. Use a scratch `HOME` and a scratch `CLAUDE_CONFIG_DIR`, both set, because `HOME/.claude/hooks/inline/resolve.py` reads `Path.home()`. Use tatari-skills as the marketplace.
- (a) Does setting `enabledPlugins["plan@tatari-skills"]=true` alone load plan and pull llm and pr? Or is `claude plugin install plan@tatari-skills` needed?
- (b) The init event's `agents` list holds `plan:review-panel`. A copy of `panel-round-guard.sh`, registered in the scratch settings, fires on a dispatch to it.
- (c) `inline-skill-tokens.py` resolves `/plan:create` from the scratch install.
- (d) An eval `scaffold.sh` can put stub `gh` and `bump` on PATH for a Bash-tool agent.
- (e) Rollback: with plan installed, add a skills-dir `plan` too. Then remove the org entry from `enabledPlugins`, run `claude plugin uninstall plan@tatari-skills`, and check whether the skills-dir `plan` loads.
- Fallbacks:
  - (a) needs install: Phase 7 adds `claude plugin install plan@tatari-skills`.
  - (b) or (c) fails: stop and bring the failing probe to the author before Phase 3. Both hooks depend on these ids.
  - (d) fails: Phase 6's evals drop the stub cases and test only the no-input stop.
  - (e) needs more than uninstall: the Rollback Plan names the extra step.
- **Success criteria:**
  - Each of (a)-(e) has an `Observed:` line in the implementation notes.
  - `claude plugin list` in the scratch dir shows `plan@tatari-skills`, `llm@tatari-skills` and `pr@tatari-skills` enabled.

#### Phase 1: Neutral wording in bump
**Model:** sonnet
- Repo: `scottidler/bump`. It is ungated today, so release it with its own `bump release`.
- Replace the "Scott" strings in `src/cli.rs`, `src/release.rs`, `src/release/pr.rs`, `src/release/finish.rs`, `src/release/standalone.rs`, their tests, and `README.md:70-74` with "the owner".
- `rg -n -i 'ordered by' HOME/.claude/hooks` in this repo printed nothing on 2026-11-15, so no guard matches the printed line.
- **Success criteria:**
  - `rg -c 'Scott' src README.md | wc -l` prints `0`. Observed on main: `9` (8 source files with 36 lines in all, plus README).
  - `otto ci` exits 0.
  - `bump release --help | rg -c Scott | wc -l` prints `0` once the new bump is installed. Observed on main (v0.4.10): `1` (`rg -c` itself prints `4`).

#### Phase 2: Transfer bump (agent runs it; Scott accepts one email)
**Model:** sonnet
- A direct transfer is impossible: `orgs/tatari-tv/members/scottidler` returns 404, and GitHub requires the transferring account to be able to create repos in the target org. `escote-tatari` is a member (204), and `members_can_create_public_repositories` is `true`.
- Two-hop GitHub transfer, which keeps commits, tags, releases with binaries, and the redirects:
  1. As home: `GH_PERSONA=home gh api -X POST repos/scottidler/bump/transfer -f new_owner=escote-tatari`. A user-to-user transfer waits for the recipient. Scott accepts the email as `escote-tatari`.
  2. Confirm `GH_PERSONA=work gh api repos/escote-tatari/bump --jq .full_name` prints `escote-tatari/bump`.
  3. As work: `GH_PERSONA=work gh api -X POST repos/escote-tatari/bump/transfer -f new_owner=tatari-tv`.
- The repo stays public. The MIT LICENSE and the Cargo `authors` stay as-is.
- Agent follow-up:
  - Move the local clone `~/repos/scottidler/bump` -> `~/repos/tatari-tv/bump`.
  - Run `git remote set-url origin git@github.com:tatari-tv/bump`.
  - Update the bump row in dotfiles `docs/new-machine-bootstrap.md` from `scottidler/bump` to `tatari-tv/bump`.
  - Update the comment cites in `HOME/.claude/hooks/git-release-guard.sh`, `intent-guard.sh` and `intent-guard-test.sh:634`.
- After the transfer, tatari-tv org rulesets apply, so bump's own later releases are gated.
- **Success criteria:**
  - `GH_PERSONA=work gh api repos/tatari-tv/bump --jq .full_name` prints `tatari-tv/bump`. Observed on main: `gh: Not Found (HTTP 404)`.
  - `bump --gates ~/repos/tatari-tv/bump` prints a `Gates:` line ending in `(gated)`.
  - `rg -n 'scottidler/bump' -g '*.sh' HOME/.claude/hooks | wc -l` prints `0`.
    - Observed on main: `4`, in `git-release-guard.sh`, `intent-guard.sh` and `intent-guard-test.sh`.
    - `fixtures/inline-token/fixtures.json` is recorded prompt corpus and stays.

#### Phase 3: Port release and release-driver to tatari-skills
**Model:** opus
- Branch `plan-release-port`, cut from local `plan-release-pr-watch` (`920fcb0b`). Its handoff commit rides, and Phase 4 deletes the file, so nothing is left orphaned.
- Add `plugins/plan/skills/release/SKILL.md` and `plugins/plan/agents/release-driver.md`, ported from the personal copies.
- Strip:
  - `~/HALL-OF-SHAME.md` and `release-rulings.md` refs
  - the stale `[DIR]` caveat (`release/SKILL.md:107-109`, `release-driver.md:68-71`; v0.4.10 ships `[DIR]`)
  - the Branch 1 commit-on-main hook workaround
  - `/cli-shakedown` and `/rust-cli-coder`
  - sandbox, allow-rule and classifier prose
  - `intent-guard.sh` and `systemctl --user`
  - every "Scott"
- Add `allowed-tools` with `Bash(bump:*)`.
- Add a fail-closed preflight: `bump` must be on PATH at v0.4.8 or later. Otherwise stop and name `tatari-tv/bump` as the install source.
- Branch 4 stays an author override of an ungated verdict ("the author treats this repo as protected"). It is not decided by `bump --gates`.
- **Success criteria:**
  - `bin/skillzy validate` exits 0.
  - `prek run no-em-dashes --all-files` exits 0.
  - `git grep -n -i -e scott -e HALL-OF-SHAME -e '~/repos/.claude' -- plugins/plan/skills/release plugins/plan/agents/release-driver.md` exits 1 with no output.

#### Phase 4: Merge observer and watcher handoff
**Model:** opus
- `release/SKILL.md` gated branch: implement steps 3-6 of the release flow above.
  - Defer to `/pr:create`'s offer, and never invoke `/pr:watch` directly.
  - Print `/pr:watch <url>` on the existing-PR path.
  - Dispatch the driver with ENTRY `merge` in every case.
  - Emit the non-success report fields.
- `release-driver.md`:
  - ENTRY `merge` loses its CI-fix loop (personal `:163-171`) and becomes poll-only: MERGED -> back half, CLOSED -> stop, ceiling or persistent error -> stop.
  - The back half gains the Release-line version check before `bump finish`.
- Delete `docs/handoff/plan-release-pr-watch-gap.md`.
- **Success criteria:**
  - The Phase 6 eval cases pass, and the negative control fails. Both ENTRY `merge` cases also grade `not_contains` on `git commit` and `git push`, which proves the poll-only loop.
    - `release-driver-merge-closed-stops`
    - `release-driver-merge-merged-finishes`
    - `release-driver-finish-version-mismatch-stops`

#### Phase 5: Closing status blocks
**Model:** sonnet
- Port the `52c03ec` closing block to create, build and release in neutral wording: "the author", and `Your call:` stays.
- Skill-lint caps a skill body at 500 lines. Org `build/SKILL.md` is 488 lines on main, so build's block goes in the existing `build/orchestrating.md`. `SKILL.md` gets a one-line pointer as its last step. The block also folds in the org's five-line report, with the last line `Next: /pr:create, or /plan:release to ship`.
- **Success criteria:**
  - `rg -c 'Your call:' plugins/plan/skills/create/SKILL.md plugins/plan/skills/build/orchestrating.md plugins/plan/skills/release/SKILL.md` prints a count of at least 1 for each of the three files.
  - `bin/skillzy validate` exits 0.

#### Phase 6: Residue, manifest, evals
**Model:** sonnet
- Rename `PANEL_ROUNDS_ORDERED_BY_SCOTT` -> `PANEL_ROUNDS_ORDERED_BY_OWNER` in org `agents/review-panel.md` and `skills/review/SKILL.md`.
- `plugin.json`:
  - Add `pr` to `dependencies`.
  - Change the description to name release.
  - Leave the version alone, because the bot owns it.
  - Mirror the description into `marketplace.json`.
  - These edits turn `bot-files-check` red until AI Foundry approves the PR's last commit.
- **Dependency announcement:** an existing install that gains a dependency fails to load until the user re-runs `claude plugin install plan@tatari-skills` (tatari-skills `AGENTS.md`). The PR body and the plugin README carry that command, and the PR author posts it to plan users before the merge.
- Evals under `plugins/plan/evals/`, each tagged `tags: [agent:release-driver]`, with stub `gh` and `bump` on PATH via `scaffold.sh`:
  - `release-driver-merge-closed-stops`: `gh pr view` reports CLOSED. Pass when the trace has no `bump finish` and the report names the resume command.
  - `release-driver-merge-merged-finishes`: `gh pr view` reports MERGED, and the Release line matches. Pass when the trace has exactly one `bump finish`.
  - `release-driver-finish-version-mismatch-stops`: the Release line says v1.2.3, and the stub `bump finish` reports v1.2.4. Pass when the trace has no tag push.
  - Negative control under `evals-controls/`: the closed-stops prompt with a MERGED stub, which must fail the "no `bump finish`" grader.
  - Eval procedure: CONTRIBUTING.md:365-366. Run on a copy with `del(.dependencies)`, under `env -i` with a clean HOME.
- **Success criteria:**
  - `git grep -n -i -e scott -e 'HALL-OF-SHAME' -e '~/repos/.claude' -- plugins/plan ':!plugins/plan/.claude-plugin'` exits 1 with no output.
  - `bin/skillzy validate --only agent-evals` exits 0.
  - The local eval run scores all three cases passed and the control failed.

Phases 3-6 ship as one tatari-skills PR through `/pr:create`. It merges, and the bot bumps the version.

#### Phase 7: Switch this repo (after the tatari-skills merge)
**Model:** sonnet
- Gate: the plan version the bot bumped holds the release skill once installed. Run `claude plugin install plan@tatari-skills`, which also pulls the new `pr` dependency. Then `ls ~/.claude/plugins/cache/tatari-skills/plan/*/skills/release/SKILL.md` lists a file for the new version. Until this command runs, the personal copy keeps loading.
- One commit in `scottidler/claude`:
  - `settings.json` `enabledPlugins`: add `plan@tatari-skills: true` and `llm@tatari-skills: true`. `pr@tatari-skills` is already there (`:1098`).
  - `settings.json` `env`: set `PLAN_STANDARDS` to the absolute path of `~/repos/.claude/rules/taste.md`.
  - Run `git rm -r HOME/.claude/skills/plan`.
  - `settings.json` dead entries:
    - Drop the seat-script allow (`:235-236`) and the `sandbox.excludedCommands` seat entries (`:1200-1201`).
    - At `:1216`, remove only the clause naming `~/.claude/skills/plan/seats`. The same line clears the personal `/architect`, `/review-panel` and `~/.claude/skills/architect/script.sh`, which stay until chunk J.
  - Update `HOME/.claude/skills/rails/hooks/index.spec.ts` `SHIPPED_EXCLUDED` (`:399-406`) in the same commit.
  - Drop `HOME/.pi/agent/settings.json:63-66`.
  - `panel-round-guard.sh`:
    - Accept `PANEL_ROUNDS_ORDERED_BY_(SCOTT|OWNER)`, with a fixture for each name. Break the regex once to prove the new fixture fails.
    - Refresh its comments to cite this doc.
  - Delete `docs/handoff/plan-plugin-org-placement.md`, because the work item is closed.
- Auto mode has denied phase workers that edit this repo's hooks and settings (`[Self-Modification]`, setup-audit log 2026-09-26). If that recurs, the worker writes a patch and Scott applies it.
- **Success criteria:**
  - `bash HOME/.claude/hooks/panel-round-guard-test.sh` exits 0, including both door fixtures.
  - The rails spec passes.
  - AC1 and AC2 pass.

## Acceptance Criteria

Each criterion says when it can first pass.

- [ ] AC1 (post-switch): `claude plugin list 2>&1 | rg -A3 'plan@'` shows `plan@tatari-skills` enabled and no `plan@skills-dir`.
  - Observed on main: `❯ plan@skills-dir` / `Version: 0.1.0`, and no `plan@tatari-skills`.
- [ ] AC2 (post-switch): run from this repo root:
  - `test ! -e HOME/.claude/skills/plan` exits 0
  - `rg -n 'skills/plan' HOME/.claude/settings.json HOME/.pi | wc -l` prints `0`
  - Observed on main: `test` exits `1`, and the count is `9`.
- [ ] AC3 (post-merge): `git -C ~/repos/tatari-tv/tatari-skills ls-tree -r --name-only origin/main plugins/plan | rg -c 'skills/release/SKILL.md|agents/release-driver.md'` prints `2`.
  - Observed on main: no output, exit 1.
- [ ] AC4 (post-merge): `git -C ~/repos/tatari-tv/tatari-skills grep -n -i -e scott -e 'HALL-OF-SHAME' -e '~/repos/.claude' origin/main -- plugins/plan ':!plugins/plan/.claude-plugin'` exits 1 with no output. Exit 128 means git failed, which is not a pass.
  - Observed on main: 2 lines (the two `PANEL_ROUNDS_ORDERED_BY_SCOTT` lines).
- [ ] AC5 (post-switch, end to end): bump's first release after the switch runs through `/plan:release` from the org copy on gated `tatari-tv/bump`. Then `git -C ~/repos/tatari-tv/bump describe --tags --abbrev=0` equals the version in that PR's `Release: rides this PR (vX.Y.Z)` line, and `bump --version` prints it.
  - Observed on main: cannot run. `tatari-tv/bump` does not exist yet (`gh: Not Found (HTTP 404)`), and the org copy has no release skill.

## Resolved Decisions

- 2026-11-15, Scott: option A. The org copy becomes canonical, and `bump` transfers to tatari-tv.
- 2026-11-15, Scott: the agent runs the bump transfer, the history transfers with it, and the repo stays public. Method: the two-hop GitHub transfer via `escote-tatari` (Scott picked A over a mirror push, which loses releases and redirects).
- 2026-11-15, author, after panel round 1 (M1-M3): **the driver keeps ENTRY `merge` as a wait-only merge observer, and release never invokes `/pr:watch` itself.**
  - `/pr:watch` exits at `ready` and never sees a later merge.
  - An explicit arm is denied under the default `ask`.
  - Headless sessions arm nothing.
  - The driver's poll-only loop fixes nothing, so CI and threads keep one owner.
  - This reverses the draft's "ENTRY `finish` only" decision.
- 2026-11-15, author: **`PLAN_STANDARDS` = `taste.md`.** `plan-panel` inlines one file. `taste.md` is what the personal seats filtered against (personal `review-panel.md:320`). `process-taste.md` and `design-exemplars.md` already reach the author through the CLAUDE.md "Read when" routing.
- 2026-11-15, author: **add `pr` to plan's `dependencies`, and announce the reinstall.** Release calls `/pr:create`, so a missing `pr` must fail at install, not mid-release. The cost is a one-time `claude plugin install plan@tatari-skills` for existing users (Phase 6 announcement).
- 2026-11-15, author: **keep the `plan:review-panel` arm in `panel-round-guard.sh`.** It counts per (doc, mode), and `plan-panel resolve` counts per run dir, so the two measure different things.
- 2026-11-15, author: **live proof in the org copy is "`sdv probe` for a deployed service, or the binary's version plus the repo's shakedown (if one exists) for a CLI".** `/cli-shakedown` is personal.
- 2026-11-15, author (panel D1): **the back half checks the Release-line version before tagging.** `bump finish` tags whatever version is on the default tip, so a second release that merges first would otherwise be tagged under the wrong PR.

## Alternatives Considered

### B: Org canonical, release stays personal
- **Description:** port only the closing block. Keep `release` and `release-driver` in a small personal plugin with a different name.
- **Why not chosen:** Scott picked A.

### C: Status quo
- **Why not chosen:** every fix lands twice, and the pr-watch defect is fixed in one copy only.

### Rename the personal plugin (`scott-plan`) so both load
- **Description:** the 11-03 measurement shows a differently named skills-dir plugin loads alongside `plan@tatari-skills`. This would remove the forced order and give a rollback independent of uninstall.
- **Why not chosen:** it keeps the fork, which is the problem. A transitional rename means two sets of `plan`-like skills during the move and a second rename to undo. The order constraint is satisfied by sequencing Phase 7 after the merge.

### Release arms `/pr:watch` explicitly (draft design)
- **Why not chosen:** `decide_pre_skill` denies it under the default `ask`, and an armed watcher still exits at `ready` before the merge (panel round 1, M1/M2).

### Extend `/pr:watch` with a release mode that waits for the merge
- **Why not chosen:** it changes the `pr` plugin's "stop at ready" contract for one caller, and it needs no new capability the driver lacks.

### Composed standards file for `PLAN_STANDARDS`
- **Description:** a generated file concatenating `taste.md`, `process-taste.md` and `design-exemplars.md`.
- **Why not chosen:** a second copy of three living docs drifts the moment one is edited.

## Technical Considerations

### Dependencies
- Blast radius, in ship order:
  1. `scottidler/bump` (Phase 1)
  2. GitHub transfer (Phase 2)
  3. dotfiles bootstrap doc (Phase 2)
  4. `tatari-tv/tatari-skills`, one PR (Phases 3-6)
  5. `scottidler/claude` (Phase 2 comment cites, Phase 7)
- plan -> `llm`, `pr` plugins. Release -> the `bump` binary (preflight), `gh`, and `sdv` when deployed.
- Every existing `plan@tatari-skills` user must reinstall once after the merge (Phase 6 announcement).

### Security
- The transfer keeps bump public. The repo holds no secrets. `persona_token_var` names env-var keys, not values.
- AI Foundry approval gates the tatari-skills `plugin.json` and `marketplace.json` edits (CONTRIBUTING:208-213).

### Testing Strategy
- Phase 0 proves the load switch and the rollback before any code moves.
- skill-lint, `no-em-dashes`, the closure check and `agent-evals` on the tatari-skills PR.
- Three hermetic release-driver evals with positive and negative graders, plus a control that must fail.
- `panel-round-guard-test.sh` with both door names, and a deliberate break to prove the fixture bites.
- AC5 runs one gated release end to end on bump itself.

### Rollback Plan
- Phase 7 is one commit. Rollback:
  - `git revert` that commit.
  - `claude plugin uninstall plan@tatari-skills`, plus any extra step Phase 0 (e) observed.
  - The personal copy loads again at the next session.
- `~/.claude/skills` is a whole-dir symlink (`manifest.yml:5`), so the switch and its revert are live at the next session with no manifest apply.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Installing the org copy before its PR merges drops `/plan:release` (measured collision) | Med | High | Phase 7's gate checks the installed cache for `skills/release/SKILL.md` |
| The new `pr` dependency breaks existing plan installs until reinstall | High | Med | Phase 6 announcement with the exact command, before the merge |
| `enabledPlugins` alone does not install plan or llm | Med | Med | Phase 0 (a), with an explicit `claude plugin install` fallback |
| An old `bump` on PATH (opens PRs, no `[DIR]`) | Med | Med | the preflight requires v0.4.8 or later |
| Two release PRs merge out of order, and the wrong version is tagged | Low | High | Release-line version check before `bump finish` |
| tatari-tv rulesets gate bump's own releases | High | Low | expected. AC5 uses it as the end-to-end test |
| AI Foundry approval is voided by a later push | Med | Low | request approval only after the final commit |
| Auto mode denies the Phase 7 worker editing settings or hooks | Med | Low | the worker writes a patch, Scott applies it |

## Open Questions

None.

## Review Log

- Round 1 (2026-11-15), synthesis `~/.cache/review-panel/runs/CdD4Th1K/synthesis.md`:
  - must-fix 7, cheap-win 9, defer 1
  - All folded: M1-M3 (merge observer redesign), M4 (install gate + reinstall announcement), M5 (`:1216` clause only), C1-C8 (criteria), D1 (Release-line check), D2 (min bump version), D3 (Branch 4 stays an author override), and the rename alternative recorded.
  - The author re-verified M1 and M2 against tatari-skills origin/main: `watch.py:1240,1329`, `watch/SKILL.md:31,178`, `watch_offer.py` `decide_pre_skill`.
  - No pushbacks.

## References
- `docs/handoff/plan-plugin-org-placement.md`
- `docs/design/2026-10-29-plan-plugin.md` (Non-Goals, "Publish `plan` to tatari-skills")
- tatari-skills https://github.com/tatari-tv/tatari-skills/pull/688, `56ac3fe9`, `docs/plan/2026-11-03-plan-review-on-llm.md`
- tatari-skills local branch `plan-release-pr-watch` (`920fcb0b`), `docs/handoff/plan-release-pr-watch-gap.md`
- drata-cli https://github.com/tatari-tv/drata-cli/pull/20
- bump `0a78a30` (stop opening PRs)
