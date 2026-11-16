# Handoff: should the personal plan plugin move into tatari-skills?

Branch: main

## Next action

Revisit the 2026-10-29 Non-Goal "Excluded: publishing `plan` to tatari-skills". Scott wants it reopened. For each dependency the old exclusion cited, run its probe below. Classify it as org-available, org-adoptable, or personal-only. Then bring Scott one decision in the house ask shape (`rules/interaction.md`, "Asking Scott a question"). Do not edit either plugin until he picks.

## Read first, in order

1. `docs/design/2026-10-29-plan-plugin.md`: the Non-Goal at the "Excluded: publishing `plan` to tatari-skills" bullet, and the "Publish `plan` to tatari-skills" alternative in Alternatives Considered.
2. `HOME/.claude/skills/plan/`: the live personal plugin. It has skills `create`, `build`, `release`, `review` and agents `design-research`, `phase-implementer`, `release-driver`, `review-panel`, plus `seats/` and `refs/`.
3. `~/repos/tatari-tv/tatari-skills/plugins/plan/`: the org port, landed in https://github.com/tatari-tv/tatari-skills/pull/688 (merged 2026-11-05, commit `56ac3fe9`). Read that commit message: it lists what was stripped (absolute paths, `~/repos/.claude` refs, rkvr, `otto ci`, the release back half).
4. `~/repos/tatari-tv/tatari-skills/docs/handoff/plan-release-pr-watch-gap.md`: open defect in personal `/plan:release` (no `/pr:watch` armed, bump opening PRs). Whichever copy wins inherits it.

## State at handoff (session-scoped facts, re-check)

- Only the personal copy loads. `~/.claude/skills/plan` carries `.claude-plugin/plugin.json`, so it loads as a skills-dir plugin. `plan@tatari-skills` is NOT in `enabledPlugins`.
  - Probe: `rg -n '"plan@' HOME/.claude/settings.json` (expect no hit)
- The two copies have diverged since 2026-11-05. Personal kept `release` + `release-driver`. Org gained llm-backed seats and evals (`1b14bf16`, `831a7a17`).
  - Probe: `git -C ~/repos/tatari-tv/tatari-skills log origin/main --oneline -- plugins/plan`
  - Probe: `git log --oneline -- HOME/.claude/skills/plan`
- The personal copy addresses Scott by name throughout (about 50 hits). Every one must become neutral ("the author") before anything ports.
  - Probe: `rg -c 'Scott' HOME/.claude/skills/plan`

## Scott's position, item by item (verify each, do not take on faith)

| Dependency (from the old Non-Goal) | Scott's claim | Probe |
|---|---|---|
| `otto` | used pervasively at Tatari | `fd -d 2 -H '^\.otto\.yml$' ~/repos/tatari-tv \| wc -l` (67 at writing). Also check who installs it outside Scott. |
| `bump` | could be org | lives at `~/repos/scottidler/bump`, a personal repo. Decide: transfer to tatari-tv, or make `plan:release` work without it. |
| `sdv` | tatari-tv tool | `~/repos/tatari-tv/sdv` exists |
| gemini / codex CLIs | provided by the `llm` plugin | `git -C ~/repos/tatari-tv/tatari-skills ls-tree -r --name-only origin/main plugins/llm` shows `bin/llm-gemini`, `bin/llm-codex`, `skills/codex`. The org `plan` already declares `dependencies: ["llm"]`. |
| `clyde` | tatari-tv tool | `~/repos/tatari-tv/clyde` exists |

Still personal, not raised by Scott (each needs a ruling): `rkvr` (panel run-dir pruning), `~/repos/.claude/rules|refs` reads in `create` step 0, `panel-round-guard.sh` and the other hooks in this repo that key on `plan:review-panel`.

## What landed this session

- `52c03ec` (main, not pushed): closing status block in personal `plan` `create`, `build`, `release`.
  - Each turn that waits on Scott ends with `Doc complete / rp'd / Ready to build`, `Code complete / rp'd / Ready to release`, or `Released / Live / Done`, then a `Your call:` line.
  - "Ready" reports only the agent's own work. A pending approval or decision is `yes` plus `Your call:`, never `no`.
  - Evidence of the need: Scott asked these questions by hand in clyde sessions `fea636e8`, `17ed2cea`, `9f2b0cf6`, `beb7046a`, `ac708dd9`, `d64bd27e`, `0df35021`.
  - Decision C (Scott, this session): the block lives in the personal copy only, for now. If the plugin moves to the org, port it with neutral wording. The new lines still say "Scott".

## Suggested skills

- `session-recall`: the 2026-10-29 plan-plugin session and the #688 port session, for why each cut was made.
- `plan:create`: only if Scott rules to move. The move is a multi-phase, two-repo change, so it gets a design doc.
- `pr:create`: for any tatari-skills change. That repo is PR-gated.
