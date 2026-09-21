# Handoff: chunk F2, handoff ownership and waiting discipline

**Branch:** `worktree-f2-handoff`, in the worktree `/home/saidler/repos/scottidler/claude/.claude/worktrees/f2-handoff`
**HEAD:** `edafdcd`
**Design doc:** `docs/design/2026-09-18-handoff-and-waiting-discipline.md` (Status: Approved, building)

## Next action

Implement **Phase 4**, the sleep-loop rule in `HOME/.claude/hooks/intent-guard.sh`, to the
spec at the doc's `:136-155` (rule) and `:280-295` (phase steps and criteria). Then Phase 6,
then Phase 7. Nothing blocks any of the three.

## Why this worktree exists

`~/.claude/skills`, `~/.claude/agents`, `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, every
`~/.claude/hooks/*.sh` and every `~/repos/.claude/rules/*.md` are symlinks into the MAIN checkout
`/home/saidler/repos/scottidler/claude`. Editing `HOME/.claude/**` there changes the live config of
every running Claude session mid-turn, and a `git checkout` there swaps it wholesale. This branch is
therefore built in a worktree, where the same files are inert. Do not "simplify" by moving back.

## State: phases 0-3 done, 4/6/7 open, 5 parked

| Phase | State | Commit |
|---|---|---|
| 0 harness spike | done | `a9bbdc9` |
| 1 manifest repair | done | `d66e2b2` |
| 2 handoff skill + WHOAMI | done | `24a9403` |
| 3 `handoff-guard.sh` | done | `edafdcd` |
| 4 sleep rule in `intent-guard.sh` | **NOT STARTED** | |
| 5 `silent_turn_reminder` env | parked on Scott's interactive probe | |
| 6 ToolSearch section in `general.md` | **NOT STARTED** | |
| 7 waiting discipline in `release-driver.md` | **NOT STARTED** | |

`a9bbdc9` also carries the full panel-round-2 fold (8 must-fix, 7 cheap wins) and **Addendum A**,
Scott's rulings: no ntfy watcher, **T1 = 25s**, `grilling` ships model-invocable.

## Read first, in this order

1. `docs/design/2026-09-18-handoff-and-waiting-discipline.md` sections "The sleep rule goes in
   `intent-guard.sh`" and "Phase 4". The rule changed materially in round 2: **T2 is withdrawn.**
2. `docs/design/2026-09-18-handoff-and-waiting-discipline-implementation-notes.md`, Phase 0. It
   records that `validateInput` runs BEFORE the PreToolUse chain, which bounds what Phase 4 can see.
3. `HOME/.claude/hooks/handoff-guard.sh` as the shape to copy for hook prose and CLI surface.
4. `/tmp/review-panel/f2handoff/synthesis.md` only if you need a finding's original wording.

## What Phase 4 must do, condensed

- One threshold, **T1 = 25s**, denying at `>=` (native `Dpn = 25`, `if(g<Dpn)return null`).
  Summed across statements, multiplied by a statically computable loop bound.
- Three bound forms: literal list, brace range, `seq` with literal arguments. Everything else
  (glob, `$(cat ...)`, `$VAR`, C-style `for ((...))`) fails closed.
- Unbounded loops deny **unless a `break` token appears in the body**. Reachability is not
  computable and denying the class would deny Monitor's own `gh pr checks` example.
- Terminating `while`/`until` loops allow at **any** interval. No per-iteration cap exists.
- `run_in_background` allows unconditionally, and **must be wired**: it has zero hits today in
  `intent-guard.sh`, `lib.sh` and `intent-guard-test.sh`. The hook has to read
  `tool_input.run_in_background` and `run()` at `intent-guard-test.sh:19` has to supply it.
- The parser needs a **rule-local loop-span scan** over the masked raw command. Do not try to do
  this on the `stmts` stream: probes in the implementation notes show the bound and the sleep land
  in different statements, `$(seq 1 30)` is re-emitted detached, and `&& break` / `|| break`
  flatten identically.
- Fixtures: cardinality pairs where multiplication alone decides (30 x 0.5 allows, 60 x 0.5
  denies) per bound form; intra-iteration summing; the `break` carve-out both directions; loop
  fixtures ride **14 of 18** `runwrapped` spellings (`for` is a reserved word, verified
  `total=18 invalid=4`).
- Also correct the stale RULES block at `intent-guard.sh:22-25`.

## Blockers, each with its probe

- **None blocking phases 4, 6, 7.** Verified: `otto ci` is green on `edafdcd`
  (`cd <worktree> && otto ci`, last run all matrices `fail=0`).
- **Phase 5 is waiting on one interactive measurement**, not on code. Probe: set
  `CLAUDE_CODE_SILENT_TURN_REMINDER_TURNS=2` in `settings.json` `env`, start a fresh interactive
  session, let two turns pass with tool calls and no prose, then
  `grep -c silent_turn_reminder ~/.claude/projects/**/<session-id>.jsonl`. Scott is running it.
  Headless `-p` cannot answer it: attachments go into the request, not stdout, and a `-p` run
  leaves no transcript. Do NOT record a headless negative as "Phase 5 dropped".

## Deployment, deliberately not done

Two steps stay for the MAIN checkout after this branch lands, because from a worktree they would
point the live setup at a temporary path:

- `ln -s <main-checkout>/HOME/.claude/hooks/handoff-guard.sh ~/.claude/hooks/handoff-guard.sh`
  (hooks are NOT manifest-managed; `grep -n hooks manifest.yml` is empty).
- `manifest` scoped apply for the `grilling` link. Unscoped apply is forbidden
  (`rules/interaction.md:125-126`).

`settings.json` registration for the hook IS committed (third `UserPromptSubmit` entry).

## Time-sensitive and session-scoped

- The panel round counter is keyed on `sha256(doc_path + mode)` (`panel-round-guard.sh:222`). The
  doc moved into the worktree, so the guard reads **0 rounds** for the new path although two are
  spent. Do not let that authorize a third round by accident.
- Today's fold of round 2 is **unreviewed**. Recommended next review is one mode-2 Implementation
  Audit over the finished branch, not another mode-1 round.
- The MAIN checkout is on branch `session-recall` with 5 unpushed commits and 4 uncommitted files
  (`intent-guard.sh` PUBLIC-REPO range fix, `conductor` removal in `settings.json`, `~/.pi` links
  in `manifest.yml`, baton edits). The `intent-guard.sh` change there will conflict with Phase 4's
  edits to the same file. It is chunk D territory, not F2's.
- `origin/main` is `763cb07`; the main checkout's local `main` ref is 78 behind it.

## Suggested skills

- `/how-to-execute-a-plan` if you want the phased machinery, though phases 4, 6 and 7 are small
  enough to implement directly, which is how 0-3 were done.
- `/review-panel` in mode 2 once 4, 6 and 7 are in.
- `/otto` for the CI contract.

## Do not

- Do not re-derive the corpus measurements. `docs/design/2026-09-18-handoff-and-waiting-discipline-phase3/`
  holds `fires.tsv` (85 human fires), `counts.json` (denominators plus sha) and the 20 controls.
- Do not reinstate T2 or a per-iteration cap. It was withdrawn on measurement, recorded at `:142`.
- Do not write a second handoff. Update this file.
