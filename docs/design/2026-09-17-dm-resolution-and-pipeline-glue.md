# Design Document: DM resolution and pipeline glue

**Author:** Scott Idler
**Date:** 2026-09-17
**Status:** Draft
**Review Passes Completed:** 5/5. Panel review not yet run.

## Summary

Two chunks of the setup-audit program in one doc, at Scott's instruction on 2026-09-17: chunk D2 first, chunk E second. D2 is the cross-repo DM-resolution work transferred out of chunk D, already specified in that doc's Addendum A. E is audit items 7 and 8, the pipeline glue.

Both of E's audit prescriptions name a mechanism that cannot do its stated job, measured. Item 7's inline-`/skill` hook cannot fire a skill. Item 8's "synchronous phase dispatch" would guarantee the failure it is meant to fix. Both are replaced here with mechanisms that exist, and the original prescriptions are recorded as rejected alternatives with their numbers.

## Problem Statement

### Background

- The 2026-09-12 audit produced 22 ranked changes. The program baton is `docs/design/2026-09-13-setup-audit-program.md`; chunks A through D are done.
- Chunk D shipped Phases 0 through 7 and landed on main (`75b0b44..885aafd`). Its Addendum A specified Phases 8, 9 and 10, which cross into `tatari-tv/slack-cli`. On 2026-09-16 those three were transferred out to a new chunk D2 so D could close on what it shipped rather than claim cross-repo work it never did.
- Chunk E is audit items 7 and 8, both in Tier 2 ("stop typing the glue").

### The program rule this doc overrides

- `2026-09-13-setup-audit-program.md:22` says "One chunk per design doc." `:26` says "Do not fold a later chunk's item into an earlier doc."
- Scott overrode both on 2026-09-17: D2 and E in one doc, D2 first. Recorded in Resolved Decisions. The tracker rows get the same note.
- The override is honored as written. It is not silently widened: D2's three phases and E's two items are the whole scope, and no other chunk's items ride along.

### Problem, in three parts

**D2: a DM channel id cannot be resolved to a person.**

- `~/.cache/slack/ids.json` answers "who is `U01E20B6DEZ`" and cannot answer "whose DM is `D01TL0BDQ4T`".
- A post's `channel` field carries the second form (`tatari-tv/slack-cli/src/mcp/request.rs:79`).
- So the shipped TARGET rule's name condition has nothing to compare against for a DM, and it degenerated into "the prompt must carry the raw `D0…` id".
- Chunk D routed around this by adding a second sufficient condition (`posting_intent`), which buys back the denies at the cost of "the right ask to the wrong channel" passing. That cost is still open.

**E item 7: an inline `/skill` token is plain text.**

- A slash at position 0 injects the skill. A `/name` anywhere else does nothing unless the model volunteers `Skill(name)`.
- Measured over 9,899 typed prompts, 2026-06 through 2026-09: 2,004 inline `/token` occurrences match a live skill name, 583 survive positional filtering, across 406 prompts.
- Live cost, Scott's words: "what the fuck does /babysit mean???????????" (08-19), "dont make me have to ask again like that" (08-12).

**E item 8: the release chain and the plan executor both stop short.**

- The post-merge arc ("merged. pull main, finish the bump, install, sdv probe until it lands") is the most repeated imperative in the corpus. Every step has a tool; the chain does not.
- `how-to-execute-a-plan` offers the implementation audit instead of dispatching it (`SKILL.md:456`), and its Step 5 instructs `git push --tags` at `:496` and `:533`, which `git-release-guard.sh:359` denies.
- Phase dispatch ends the parent turn, which reads as stopping.

### Evidence: what the audit prescribed, and what the corpus says

Three prescriptions do not survive first contact. This is the third consecutive chunk where that happened, and it is the same class chunk D named: a stated mechanism that cannot perform its stated job. The question that catches it is "what process, at what moment, runs this, and what can it see?"

**Item 7's hook cannot fire a skill. Measured in the 2.1.274 bundle.**

- Slash expansion is position-0 only: `IM()` reads `if(Hn!==null&&!hn&&Hn.startsWith("/")){ ... processSlashCommand(...) }`. Nothing scans past character 0.
- Expansion runs BEFORE any prompt hook: `IM()` sits between the `query_process_user_input_base_start`/`_end` marks, and the `prompt.submit` chain runs afterward at `query_hooks_start`. A rewritten prompt is committed with no re-expansion.
- `$.command.run` is the only mechanical skill-invocation API and it is refused from `prompt.submit`: "called from a prompt.submit hook, it would wait on the turn this hook is holding". `Ees()` hard-codes that refusal.
- There is no `$.skill.*` API. The full skill namespace is `skill.kind, skill.md, skill.name, skill.prompt, skill.source`.
- **Verdict: no mechanism in 2.1.274 makes an inline `/name` fire the skill on the current turn.**

**Item 8's "synchronous dispatch" would guarantee the failure it is meant to fix.**

- The harness backgrounds Agent dispatches unconditionally, since roughly 2026-06-12. Measured over all 652 `phase-implementer` dispatches ever recorded: zero returned a report inline. Independently re-run in this session, 652 resolved, 0 unresolved.
- `run_in_background` is absent on 1,905 of 1,906 dispatches of every type, not because the model declines to background but because it has no say.
- `name` selects the delivery variant (teams relay vs background task), not synchrony. Both forms end the parent turn at dispatch.
- The June complaints are the OPPOSITE failure: "are we sure this thing is still building? 22m; 48k tokens and not moving?". Measured over 396 dispatch-to-report gaps: median 0.5 min, p90 22.8 min, max 300.9 min. Of the 124 gaps over 10 minutes, **102 (82%) were silent** after the opening status line.
- A synchronous parent is blocked inside the tool call, so it has no seam for mid-wait output. It would make the 82%-silent condition universal.
- **Verdict: the direction inverts. Do not make dispatch synchronous. Make the asynchronous wait legible.**

**Item 8's "three phase workers sitting idle" is not a stop.**

- In `14db2d24` (09-06) phase 4 was running correctly. The complaint is that named teammates persist in the roster after their phase completes.
- Nothing reaps them. A mechanism exists (`SendMessage` with `{"type":"shutdown_request"}`), used 15 times ever, zero of them on a phase worker against 399 named phase dispatches.
- **Verdict: a missing instruction, not a missing capability.**

### What the corpus adds that the audit missed

- **`bin/release` silently bypasses both PR gates.** It runs `gh pr create --fill` as a subprocess at `:334`, echoed again at `:342`, and its own header at `:29-31` states the reason: "this runs `bump`/`git push` as SUBPROCESSES, so the PreToolUse git-release-guard hook never sees them." `--fill` takes title and body from commit messages, so the body carries no `Release:` line and the title is not branch-derived. The driver does not satisfy Gate D and the title guard; it evades them.
- **`--body-file` denials are the fastest-rising failure class.** The audit reported 6. Measured total is 32, and every one is September: shell construct 13, unreadable path 10, stdin `-` 9.
- **`bump` now carries `release` and `finish` subcommands** duplicating `~/.claude/bin/release`. Two implementations of one flow, and no skill or agent mentions the new ones.
- **`bump` stages everything** (`src/git.rs:47,50` `git add -A`), and `git-release-guard.sh:460` exists solely to compensate.
- **The parent already self-continues.** Three transcripts show a parent acting on a teammate report with no user prompt in between, one of them dispatching the next phase (`15898f96`, 2026-06-27T22:57). The chain is not broken; the instruction to close it is missing.
- **Anthropic already shipped item 7's matcher.** `dSt(text, keyword)` powers the `ultraplan` inline keyword: quote/bracket/angle-span exclusion, apostrophe-vs-quote, path-and-flag neighbors, `filename.ext`. It is hard-coded to `ultraplan`/`ultrareview`/`ultracode` with no config surface, so it cannot be reached, only copied.

### Goals

- D2: a DM channel id resolves to a user id, filled once and cached, so TARGET can require the named recipient.
- D2: which TARGET variant ships is decided by measurement against the harvested corpus, not asserted.
- E7: an inline `/name` becomes an explicit instruction the model acts on, with a false-positive rate that does not make Scott's own prompts fire skills.
- E8: the post-merge arc runs as one chain from one ask.
- E8: a plan executes every phase and dispatches its own implementation audit, with a visible heartbeat during each wait.
- E8: `pr-open` satisfies both PR gates visibly, and `bin/release` stops evading them.

### Non-Goals

- **`rp` as a bare word.** 83 occurrences, no slash, unreachable by a `/token` matcher. It needs a bare-word keyword scanner, which is item 9's WHOAMI vocabulary work. Parked for chunk F, not excluded.
- **Backfilling `dms` from anything**, and the 18 legacy `D…` keys in `users`. Origin known and writer retired. A doc invariant plus a test that the sole writer's key is a user id, nothing more.
- **Group DMs.** `mpim` is already in `CHANNEL_TYPES` and the cache holds 19 resolved `G…` entries. They resolve to names today.
- **Making an inline `/name` mechanically fire a skill.** Proven impossible in 2.1.274. Parked with a revisit condition: a future build exposing the keyword list as config, or a `$.skill.*` API.
- **A `/pipeline` orchestrator with human gates.** The audit floats it as optional. Not requested by Scott, so out.
- **Deduplicating `bump`'s `release`/`finish` subcommands against `bin/release`.** Named here because this doc's work touches both, but it is a `bump` repo change and belongs to whoever owns that repo's next doc.

## Proposed Solution

### Overview

Three independent workstreams, one ship order forced by one cross-repo dependency.

| phase | repo | model | workstream |
|---|---|---|---|
| 0 | claude | opus | all three (0a D2, 0b E7, 0c E8) |
| 1, 2 | **slack-cli** | opus | D2, the fill |
| 3, 4 | claude | opus | D2, measure then tighten |
| 5, 6 | claude | sonnet | E7, matcher and name resolution |
| 7, 8 | claude | opus / sonnet | E7, hook and shim |
| 9 | claude | opus | E8, `pr-open` |
| 10, 11 | claude | opus | E8, execute-a-plan and release-driver |


- **D2** ships `tatari-tv/slack-cli` first, then measures, then tightens the guard in `scottidler/claude`.
- **E7** is a shell hook plus a skill shim, entirely in `scottidler/claude`.
- **E8** is a bash helper plus agent and skill edits, entirely in `scottidler/claude`.

D2 and E do not touch each other's files. E7 and E8 share only `settings.json` hook registration.

### Part 1 (D2): `dms`, then measure, then tighten

Everything here was decided on 2026-09-16 and reviewed by panel round 5. It is not reopened. Two premises drifted and are corrected below.

**The cache gains a `dms: IndexMap<String, String>` map, `D… -> U…`.**

- Not another `D…` key in `users`: `users` is contracted as user-id to display label (`cache.rs:74-84`), both prior additions were new sibling maps, and a `D… -> handle` entry duplicates a name derived from `handles[U]` and diverges on a rename.
- No `CURRENT_SCHEMA` bump. The edge is immutable, so no watermark and no staleness rule. `Merge::Extend` only.
- Fill is eager (`users.conversations` over `im`) with a lazy backstop (one `conversations.info` on a cold miss), Scott's ruling.

**Correction 1: `cache::upsert` is at `cache.rs:438`, not `:379`.** That citation was wrong when written, in both source documents. `cache.rs` has not changed since `def7d27`. `:379` is `current.users.extend(...)`, a different thing, and an implementer sent there would have edited the wrong function.

**Correction 2: `dms` needs six edit sites, not four.** Addendum A named four. The two `debug!` macros at `:357-365` and `:419-425` are unlisted, and omitting them makes the merge log lie about what merged, which `rules/logging.md` forbids.

| # | site | edit |
|---|---|---|
| 1 | after `cache.rs:117` | `#[serde(default)] pub dms` on `IdCache`, with the immutable-edge doc |
| 2 | after `cache.rs:314` | `dms: Merge` on `struct MergePolicy` |
| 3 | `cache.rs:322,331,337,346` | `dms: Merge::Extend` in all four constants. Omitting any fails to COMPILE, the safe failure |
| 4 | after `cache.rs:397` | the `match policy.dms` arm in the merge body. **The silent failure**: omit it and every write is dropped while every in-memory-patch test passes |
| 5 | `cache.rs:357-365` | `dms={}` in the entry `debug!` |
| 6 | `cache.rs:419-425` | `dms={}` in the exit `debug!` |

**Correction 3: `resolve_dm_user` does not go beside `resolve_self_dm`.**

- `.otto.yml`'s `bloat` task fails any source file over 1500 lines (`-gt`, `exit 1`, and it runs in `ci`'s `before` list so `otto ci` aborts before `check` and `test`).
- `src/command/write.rs` is 1484. `src/command/write/tests.rs` is 1494. Headroom 16 and 6.
- `resolve_self_dm` is 24 lines of body plus a 3-line doc comment, and `rules/logging.md` adds entry and exit logs. Both files trip.
- **New `src/slack/dm.rs` holds `sync_dms` and `resolve_dm_user`.** Single-word filename per `rules/general.md`, zero bloat pressure, both halves together, no decomposition of a file this chunk did not come to change.
- Rejected: `slack/mention.rs` (1198 lines, closest precedent, but it grows the file this chunk would then own) and `slack/cache.rs` (API-free today; putting a `SlackApi` call there introduces a new dependency direction).

**The wiring seam Phase 2 must not skip.** "Runs where the other full syncs run" resolves to `CacheLookup::refresh` (`slack/mention.rs:1060`), reached from `run_refresh` (`command/cache.rs:112`), building a `RefreshSummary` (`mention.rs:162`) and printing a count at `cache.rs:130`. `sync_dms` needs an entry in all three. `CURRENT_SCHEMA`'s single writer is `stamp_schema` (`mention.rs:689`); adding `dms` must not add a second.

**Then the guard.** `resolve_names` gains its `dms` clause in BOTH jq programs (`slack-post-guard.sh:277-325` and the second program at `:311-324`), the `.users` DM branch is removed, and the recipient loop stops being wrapped in `if ! posting_intent` (now at `:705`, drifted from `:685`).

### Part 2 (E7): a `UserPromptSubmit` hook that makes the token an instruction

**The mechanism, stated plainly, because the audit implied injection.** An inline `/name` cannot be made to fire the skill on the current turn in Claude Code 2.1.274. The hook makes it an explicit instruction instead.

Three routes exist. The choice is A.

| | A: `UserPromptSubmit` shell hook | B: rails `prompt.submit` rewrite | C: `turn.complete` + `$.command.run` |
|---|---|---|---|
| fires the skill | no, instructs | no, instructs | yes |
| when | current turn | current turn | a LATER turn |
| cost | one hook, house pattern | plugin reload hazard | needs `$.session.messages()` |
| risk | none to the typed prompt | can corrupt the prompt | wrong order for "merge, /bump, install" |

- **A wins on cost and blast radius.** It matches `prose.sh`, the repo's existing prompt-reading hook. No plugin reload. An existing `*-test.sh` harness pattern. It is the only route that cannot corrupt what Scott typed. Its `source:"user"` discriminator fires it only on human-typed prompts.
- **B's only advantage is text ownership**, which buys nothing unless the design commits to inlining SKILL.md bodies. That trades a reliability problem for a context-budget problem (bodies run 3.3K to 21.3K; a prompt naming three skills could inline 45K) and silently defeats `skillOverrides`.
- **C is the only mechanical route and it fires on the wrong turn.** For "merge, pull main, /bump, install, /cli-shakedown" the original prompt is answered first and the skill runs after. Wrong order.

**Choosing A also closes the discussion-class question.** 34% of survivors are discussion, not invocation, and no lexical rule separates them. Under A a wrong match costs one line of injected context that the model is free to ignore, not a wrongly-executed skill. That is an acceptable failure mode; under B or C it would not be.

**The matcher is `dSt`, ported, not reinvented.** Every exclusion rule the dig derived independently is a subset of it. Port its algorithm, including the rule that is easy to miss: `if(e.startsWith("/")) return []`, so a prompt that already opens with a slash command is not scanned.

**Name resolution drops what must not match.**

- Every `skillOverrides: "off"` entry.
- Bare aliases for plugin-namespaced skills.
- A hard deny list of generic words, taken from the 45 installed names of 8 characters or fewer: `run status config help auto update setup seed pm qa welcome cancel ooo evolve evaluate tutorial unstuck ralph`. Raw inline counts show why: `otto` 551, `config` 322, `publish` 178, `write` 128, `status` 60, `help` 36, `read` 35, `run` 32.

**The `review-panel` shim.** `Skill(review-panel)` returns `Unknown skill` today because review-panel is an agent. A one-file `SKILL.md` dispatches the agent, modeled on `shipit/SKILL.md`. To avoid two signals for one meaning, the shim REPLACES the agent reference in `create-design-doc/SKILL.md:47` rather than sitting beside it.

### Part 3 (E8): make the wait legible, chain the release, satisfy the gates

**`how-to-execute-a-plan` stops offering the audit and dispatches it.**

- The dispatching turn exists and is proven: the main thread is woken by the final phase's teammate-message, carries tool-use capability, and fires without a user prompt. Three transcripts show it, one of them dispatching the next phase.
- `:456` ("Then **wait for the user**. They may run it, skip it, or defer it") is deleted. The audit is dispatched, not offered.
- Each wake emits a one-line beat: phase, elapsed, what it waits on. That converts a silent 22-minute gap into a heartbeat using the mechanism that already exists. This is the half that keeps the fix from recreating the June failure.
- After accepting a phase report the orchestrator sends `{"type":"shutdown_request"}` to that worker. One line, and it closes the "three workers sitting idle" complaint.
- Step 5's `git push && git push --tags` at `:496` and `:533` is replaced with the `rules/git.md` sequence. The skill stops instructing a step its own hook denies.

**A `Stop` hook backstop, only if Phase 0 says prose is insufficient again.** Prose saturation is already present: four "DO NOT STOP" statements at `:275-280` and `:363-364`, and the failure persists. `prose.sh` is the shipped proof that a Stop hook can block a premature end (`:98` emits `{decision:"block",reason:$r}`; the harness caps consecutive blocks at 8 so a hook bug cannot wedge a session). A sibling hook scanning for "dispatched phase-implementer, never dispatched review-panel after the last one" fits the existing shape exactly: same payload, same transcript read, same block verb.

**`release-driver` gains the back half of the chain.** It stops today at "tag verified, install reported the new version" (`:96-102`). It gains `sdv probe` until live for a deployed service, or installed-binary version plus acceptance commands for a CLI, then the shakedown. It also gains an entry path for "the PR already merged, finish the bump", which its step 2 has no route for today.

**`pr-open` satisfies both gates visibly.**

- Branch from `git branch --show-current`. Title de-slugged from the branch as `type(scope): <those same words>`, so `slug(title minus type/scope) == branch` by construction.
- Release intent is an explicit argument, never defaulted and never guessed. `Release: rides this PR (vX.Y.Z)` only after confirming a version line changes vs base, else Gate D `:566` denies the claim.
- Body written to a literal readable path under `$TMPDIR`, passed as `--body-file <literal path>`. Never a process substitution, never `-`, never an unexpanded `$VAR`. Those three are the 32 September denials.
- **It does not hide `gh` behind a subprocess.** `bin/release:334` does, and that is the bug, not the pattern. `pr-open` emits the command where the hook can see and approve it.

## Data Model

**`IdCache` gains one field.** `dms: IndexMap<String, String>`, `#[serde(default)]`, `D…` to `U…`. No watermark, no schema bump, `Merge::Extend` in every policy constant.

```rust
match policy.dms {
    // Extend in EVERY policy: the D-to-U edge is immutable, so there is no
    // listing whose absence should remove an entry. `Replace` has no meaning
    // here and no constant sets it.
    Merge::Extend | Merge::Replace => current.dms.extend(patch.dms.clone()),
}
```

`Merge` is a two-variant enum, so the `match` forces a `Replace` arm to exist. Collapse both with the reason stated, or make `Replace` `unreachable!` with the same comment. Do not let `Replace` silently do a wholesale replace: no constant sets it today, and a future sibling sync would inherit a behavior this design rejected.

**Stale doc comment fixed in the same commit.** `cache.rs:350-354` already omits `subteams` and `profiles`, both of which have policy halves. Adding `dms` makes it wronger.

**No other persisted shape changes.** E7's hook and E8's helper hold no state.

## Implementation Plan

Twelve phases. Phase 0 is three independent zero-code spikes and its answers can change Phases 6 through 11.

### Phase 0: prove the three environmental assumptions
**Model:** opus
**Repo:** `scottidler/claude`

- **0a (D2).** Reproduce the criterion 3c baseline from the harvested harness. `slackrecall.py` on disk carries `WINDOW = 12`; `rowsFinal.json` was produced at `WINDOW = 3`. Set it to 3 and confirm the split. The harness reads the LIVE `~/.claude/projects` tree, so a re-run yields more than 216 rows: `rowsFinal.json` is pinned as the denominator.
- **0b (E7).** Six probes: a `UserPromptSubmit` hook's `additionalContext` reaches the model; what `source` a normal typed prompt carries; whether it fires for prompts that start with `/`; that a `prompt.submit` hook returning text beginning with `/` is NOT expanded; that `$.command.run` is refused from `prompt.submit` and succeeds from `turn.complete`; whether a `skillOverrides: "off"` skill is still resolvable.
- **0c (E8).** Six cells over `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` x `name` x `run_in_background`, using the scratch-hook method from `2026-09-14-panel-round-cap-phase0/evidence.md:6-8`. Also capture whether the PreToolUse `Agent` payload carries `tool_input.name`: a guard on the named form is impossible if it does not.
- **Success criteria:** every answer is an observed log line or tool result pasted into `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md`, never an inference from the bundle; 0a reproduces 26 denies splitting 9 TARGET / 17 artifacts; 0c states whether any cell yields a synchronous dispatch.
- **Gate:** if no 0c cell is synchronous, Phases 9 and 10 build the legible-wait design and the synchronous option is closed in writing. If one is, the doc is amended before Phase 9 starts.

### Phase 1: `slack-cli` gains `dms` on the cache
**Model:** opus
**Repo:** `tatari-tv/slack-cli`

- The six edit sites in the table above, in one commit. Sites 1 through 3 fail to compile if wrong; site 4 fails silently.
- Fix the stale `cache.rs:350-354` doc comment in the same commit.
- Add the `users` doc invariant and a test that the sole writer's key is a user id, so a `D…` key cannot return unnoticed.
- **Success criteria:** a `dms` write SURVIVES `upsert`, written to fail against a build without the merge arm and PROVEN to fail against it; an existing `ids.json` loads with `dms` empty and no error; `otto ci` green including `bloat`.

### Phase 2: `slack-cli` fills `dms`, eagerly and on a miss
**Model:** opus
**Repo:** `tatari-tv/slack-cli`

- New `src/slack/dm.rs`: `sync_dms` (one `users.conversations` over `im`) and `resolve_dm_user(api, cache_path, dm_id) -> Result<Option<String>>`.
- **Register the module.** `src/slack.rs:10-20` declares submodules alphabetically; `pub mod dm;` goes between `decode` (`:14`) and `follow_ups` (`:15`). A new file nobody declares compiles to nothing, and `taste.md` names registration as the most-skipped step in an implementation audit.
- Wire `sync_dms` into `CacheLookup::refresh` (`mention.rs:1060`), `RefreshSummary` (`mention.rs:162`) and the count string (`command/cache.rs:130`). All three.
- `channel_display_name` (`read.rs:525-533`) stops discarding `ch.user`: fill `dms` from the response it already fetches when `is_im` is set.
- `CHANNEL_TYPES` (`read.rs:48`) does not change, and `read/tests.rs:772` stays true.
- Function-level debug logging per `rules/logging.md`: entry with the dm id, exit with hit | miss | not-an-im.
- **Success criteria:** a cold `D…` costs exactly one `conversations_info` and a warm one costs zero, asserted on a fake API's call count; a non-`im` channel writes nothing; an `im` whose `user` is absent writes nothing rather than an empty string; `sync_dms` over N ims yields N entries and leaves `channels` unchanged; no source file exceeds 1500 lines.

### Phase 3: measure the TARGET variants
**Model:** opus
**Repo:** `scottidler/claude`

- Prerequisite: Phase 2 merged, bumped, tagged and **installed**. The guard reads a cache only the installed binary writes.
- Replay the pinned 216-row corpus against three variants: the shipped rule (`variantA.sh`, confirmed functionally identical to the guard on disk), name-mandatory for non-exempt DMs only, and name-mandatory for every non-exempt recipient (`variantB.sh` is the starting point, its loop already unwrapped at `:621-630`).
- The first-cut guard survives in no file, so the "79 denies in 216" number cannot be re-derived and is not restated as a live measurement.
- **Decision rule, all three outcomes specified:** the variant that ships is the strictest whose deny count does not exceed 9, artifacts excluded.
  - Both clear -> all-recipients ships, the weak condition disappears.
  - Only DM-only clears -> DM-only ships, the weak condition survives for channels alone, and the measurement is recorded here as the reason.
  - **Neither clears** -> nothing ships in Phase 4 and the shipped rule stands. That is a null result, not a failure: it says `dms` did not buy back enough, and it is recorded here with the counts rather than worked around. Phases 1 and 2 still stand on their own (the cache answers a question it could not answer before) and Phase 4 closes as `dropped (measured)`.
- **Success criteria:** three deny counts in a table in this doc; every deny the selected variant introduces is read individually and named; the 2026-07-10 shakedown posts, the `**MCP write test**` marker and the duplicate-body case still deny in the selected variant.

### Phase 4: TARGET requires the named recipient
**Model:** opus
**Repo:** `scottidler/claude`

- `resolve_names` gains its `dms` clause in BOTH jq programs; the `.users` DM branch is removed. `U…` resolution is unaffected: it runs through `$uits` over `.handles` at `:294`, a separate branch.
- The recipient loop stops being wrapped in `if ! posting_intent` (`:705`). Phase 3's result decides whether the weak condition remains as a per-recipient fallback for channels or disappears.
- Cold-miss backstop: a `D…` absent from `dms` is resolved through the installed `slack` client before authorization, with a timeout, and a failure DENIES, consistent with this guard's existing missing-cache behavior.
- The 3-turn window is unchanged.
- **Success criteria:** a post to a peer's DM whose prompt names the person by handle, display name, real name or first name allows; the same post naming nobody denies, and the deny text names the person rather than the `D…` id; the replay's deny count matches Phase 3's measurement for the selected variant; the cold-miss path is exercised against a `D…` deliberately removed from `dms`.

### Phase 5: the inline-token matcher, standalone
**Model:** sonnet
**Repo:** `scottidler/claude`

- Port `dSt`'s exclusion algorithm, including `startsWith("/") -> no scan`. No wiring to anything.
- Fixtures are committed and pinned: `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/inline-token/fixtures.json`, 2,004 records, 1,421 labeled false positives and 583 survivors. Do NOT regenerate them: the generator reads the live session tree and the counts move.
- **Success criteria:** 0 of the 1,421 known false positives match; at least 95% of the 583 survivors match; `the three standard endpoints (/status, /deployed, /version)` and `a "name()/help arm,"` both produce zero matches.

### Phase 6: name resolution
**Model:** sonnet
**Repo:** `scottidler/claude`

- Enumerate live skills; drop `skillOverrides: "off"`; drop bare aliases for plugin skills; enforce the generic-word deny list.
- **Success criteria:** `/babysit` resolves to exactly one skill; `/run` and `/status` resolve to nothing; a skill flipped `"off"` never resolves, proven by flipping one on and off.

### Phase 7: wire the hook
**Model:** opus
**Repo:** `scottidler/claude`

- The `UserPromptSubmit` hook, registered in `settings.json`, with its `*-test.sh` beside it in the shape the other 20 guards use.
- One line in `interaction.md` naming the hook, per the enforcement-before-prose rule.
- **Success criteria:** a live session where `merge, pull main, /bump, install, /cli-shakedown` produces both skill invocations with no second prompt; a live session where `is chunk E ready to build, or do I need to /create-design-doc on it first?` invokes nothing; a prompt already opening with a slash command is left alone; `hooks-preflight.sh` reports the new hook resolving.

### Phase 8: the `review-panel` shim
**Model:** sonnet
**Repo:** `scottidler/claude`

- One `SKILL.md` dispatching the agent, modeled on `shipit/SKILL.md`. It REPLACES the agent reference in `create-design-doc/SKILL.md:47`.
- **Success criteria:** `Skill(review-panel)` no longer returns `Unknown skill`; a dispatch through the shim increments `panel-round-guard.sh`'s counter (its `subagent_type == "review-panel"` match fires); a 4th round through the shim is denied.

### Phase 9: `pr-open`
**Model:** opus
**Repo:** `scottidler/claude`

- `HOME/.claude/bin/pr-open`, symlinked per the `manifest.yml:68` precedent, shaped on `bin/release`.
- Branch-derived title, explicit `--release` argument, literal `--body-file` path under `$TMPDIR`.
- `bin/release` stops using `--fill` and calls `pr-open`, so the gates see the command instead of being bypassed. **Two sites, not one:** the live call at `:334` and the dry-run echo at `:342`. Fixing only the first leaves the dry-run lying about what the driver does.
- **Success criteria:** `pr-open` on a branch with a version delta emits a command the title guard and Gate D both allow, proven by running it against the live hooks; the same on a branch with no version delta and `--release rides` is DENIED by Gate D `:566`; `rg -n 'gh pr create --fill' HOME/.claude/bin/release` returns zero lines.

### Phase 10: `how-to-execute-a-plan` runs the plan
**Model:** opus
**Repo:** `scottidler/claude`

- Delete `:456`. Dispatch the audit instead of offering it.
- Per-wake heartbeat: phase, elapsed, what it waits on.
- `shutdown_request` to each phase worker after its report is accepted.
- Step 5's `git push --tags` at `:496` and `:533` replaced with the `rules/git.md` sequence, routed through `pr-open` where a PR is involved. Both sites: fixing only the live one leaves the summary box lying.
- **Success criteria:** `rg -n 'push --tags' HOME/.claude/skills/how-to-execute-a-plan/SKILL.md` returns nothing; the audit-offering sentence is gone; a multi-phase run dispatches review-panel with no user prompt between the last phase and the dispatch.

### Phase 11: `release-driver` owns the back half
**Model:** opus
**Repo:** `scottidler/claude`

- The chain extends past tag verification: install -> `sdv probe` until live (deployed) or installed-binary version plus acceptance commands (CLI) -> shakedown.
- An entry path for "the PR already merged, finish the bump", which step 2 lacks today.
- Route the post-merge arc there from the `bump`, `shipit` and `babysit` trigger descriptions.
- **Success criteria:** a deployed-service release probes until the new version is live and reports the probe output; a CLI release reports the installed binary's version; `release-driver.md` names `pr-open` rather than a raw `gh pr create`.

## Blast radius and ship order

- **Two repos.** `tatari-tv/slack-cli` (Phases 1 and 2) and `scottidler/claude` (everything else).
- **The order is forced for D2 only.** slack-cli ships the fill first; the guard tightens last, because it cannot read a field the client does not write and must not tighten before the cache can answer.
- **Phase 3 waits for an INSTALLED binary, not a merged PR.** A merged-but-uninstalled slack-cli leaves `dms` empty, and tightening against an empty map denies every name-only DM post.
- **`tatari-tv/slack-cli` is gated on BOTH gates, checked live 2026-09-17.** Classic protection present (`required_approving_review_count: 1`, `require_code_owner_reviews: true`), and org ruleset `126206` carries `deletion`, `non_fast_forward` and a `workflows` rule. `enforce_admins: false` bypasses only the classic half. PR flow only: `bump --no-tag` on the branch, release-intent line in the body, `bump --tag-only` on main after merge, push the tag by name.
- **`slack-cli` is release-managed.** `Cargo.toml:3` carries `version = "0.13.1"`, so Gate D applies to its PR.
- **E7 and E8 are single-repo and independent of D2.** They can land in any order relative to it. They share only `settings.json`.
- **`scottidler/claude` takes no PRs.** Both gates were checked live for chunk D and were clear; re-check before pushing, and land with `git push origin <branch>:main`, which never touches the working tree (the chunk A hazard).

### Operator steps, called out because a phase agent will not do them

- **Install `slack` after Phase 2 merges.** Merge, bump, tag, `cargo install`, verify `slack --version`. Phase 3 cannot start before this.
- **Restart the session after any hook or plugin change lands**, if Phase 0b's answer requires it. Function-hook plugins load once at session start; the chunk A hazard stands for every phase touching rails.
- **Run `/plugin-types` once** in an interactive session if Phase 0b needs generated types. It is not scriptable from a subagent.

## Requirement traceability

| requirement | asked by |
|---|---|
| D2 and E in one doc, D2 first | Scott, 2026-09-17, this session |
| DM/group-DM/channel not in cache is looked up, found, cached | Scott, 2026-09-16, quoted in Addendum A |
| eager sync plus lazy backstop | Scott's ruling, 2026-09-16 |
| `dms` as a new map, no schema bump, Extend only | panel round 5, both seats, 2026-09-16 |
| inline `/skill` tokens fire | audit item 7 |
| `review-panel` shim | audit item 7 |
| one release chain, `pr-open`, execute-a-plan self-audit | audit item 8 |
| do NOT make dispatch synchronous | this doc's measurement, 2026-09-17 |
| `resolve_dm_user` outside `write.rs` | this doc's bloat measurement, 2026-09-17 |

## Technical Considerations

### Dependencies

- Phase 1 and 2: no new crates. Everything needed exists (`conversations_info` at `api.rs:682`, `Channel.is_im`/`.user` at `api.rs:264-279`, `upsert` at `cache.rs:438`).
- Phases 5 through 10: bash plus `jq`, already required by `hooks-preflight.sh`. No new dependencies.
- Phase 3 and the harness: `python3`, already used by every prior chunk's measurement.

### Performance

- The guard's Bash-hook budget is 250 ms per chunk, measured in chunk D. The gated shape costs 27 ms. Phase 4's cold-miss backstop adds one subprocess call ONLY on a `D…` absent from `dms`, which the eager sync makes rare.
- The `UserPromptSubmit` hook runs once per typed prompt, not per tool call. It reads no transcript.

### Security

- No secret handling changes. The slack token path is untouched; `conversations.info` on an `im` needs nothing the token does not already hold, confirmed live.
- `pr-open` narrows an existing hole rather than opening one: `bin/release:334` currently evades two authorization gates by subprocessing `gh`.
- The `UserPromptSubmit` hook reads the typed prompt and writes only `additionalContext`. It cannot deny, and it cannot alter what Scott typed.

### Testing Strategy

- Phase 1's merge-arm test is written to FAIL against a build without the arm, and proven to fail. That is the one test in this doc that catches a silent failure.
- Phase 5's matcher is tested against the 1,421 classified false positives and 583 survivors from this dig, not against invented fixtures.
- Phase 9's `pr-open` is tested against the LIVE hooks, both the allow and the deny direction.
- Guard changes re-run `slack-post-guard-test.sh` to its current baseline before and after.

### Rollout Plan

- slack-cli: PR flow, own it to green, work every CodeRabbit thread, then install.
- `scottidler/claude`: land on main per the chunk A hazard, then verify through the live symlink path, not the repo copy.

## Acceptance Criteria

Every criterion names a literal command. Each was executed against current `main` on 2026-09-17 and its output recorded beneath it, per the ready-to-build gate. A criterion that cannot run until a phase ships says so and names the phase.

- [ ] **1. The cache answers the DM question.** `jq -r 'has("dms")' ~/.cache/slack/ids.json` returns `true` and `jq -r '.dms|length'` returns a count greater than zero.
  - `Observed on main: false`. Correctly failing: `dms` does not exist yet. Ships in Phase 2, and the count requires the INSTALLED binary, not a merged PR.

- [ ] **2. `slack-cli` stays under the bloat gate.** `otto ci` exits 0 in `tatari-tv/slack-cli`, including the `bloat` task.
  - `Observed on main: All files within 1500 line limit`. **Passes today, and that is the point: the margin is the risk.** `src/command/write/tests.rs` 1494, `src/command/write.rs` 1484, headroom 6 and 16. This criterion bites only after Phase 2 adds code, which is why `resolve_dm_user` goes in a new file.

- [ ] **3. The selected TARGET variant does not deny more than the shipped rule.** The Phase 3 replay against the pinned 216-row corpus returns a deny count no greater than 9, artifacts excluded, with all three variants' counts in this doc.
  - Cannot run until Phase 3. The denominator is pinned now: `phase0/replay/rowsFinal.json`, md5 `5ade36f7fead9c5973b2398a2cbe6473`, 216 rows, 26 denies splitting 9 TARGET / 17 artifacts. Verified on harvest.

- [ ] **4. The plan executor stops instructing a denied command.** `rg -n 'push --tags' HOME/.claude/skills/how-to-execute-a-plan/SKILL.md` returns zero lines.
  - `Observed on main:` two lines, `496:git push && git push --tags` and `533:│  5. git push && git push --tags     [if approved]│`. Correctly failing. Ships in Phase 10.

- [ ] **5. The release driver stops evading the PR gates.** `rg -n 'gh pr create --fill' HOME/.claude/bin/release` returns zero lines.
  - `Observed on main:` two lines, `:334` (the live call) and `:342` (the dry-run echo). Correctly failing. Ships in Phase 9.

- [ ] **6. The new hook resolves.** `hooks-preflight.sh` exits 0 with the `UserPromptSubmit` hook registered.
  - `Observed on main:` `rg -n 'UserPromptSubmit' HOME/.claude/settings.json` exits 1, zero matches. No such hook exists today; the preflight cannot report on it. Ships in Phase 7.

- [ ] **7. The matcher separates the classes.** Against `phase0/inline-token/fixtures.json`, zero of the 1,421 `label != "survivor"` records match, and at least 554 of the 583 `label == "survivor"` records match (95%).
  - `Observed on main:` fixtures materialized and verified, `total 2004 survivors 583 false-positives 1421`, class split `code-span 832, path-glued 544, url 36, path-continues 8, filename-ext 1`. No matcher exists yet. Ships in Phase 5.

- [ ] **8. The guard's own suite does not regress.** `bash HOME/.claude/hooks/slack-post-guard-test.sh` reports zero failures and no fewer than 129 passes.
  - `Observed on main: pass=129 fail=0`. This is the baseline Phase 4 must not break, and the count floor rises with the fixtures Phase 4 adds.

## Resolved Decisions

- **2026-09-17 (Scott): D2 and E ship in one design doc, D2 first.** Overrides the program's one-chunk-per-doc rule at `:22` and the no-folding rule at `:26`. The override is recorded here and in the tracker; it is not treated as a precedent for later chunks.
- **2026-09-17: the audit's item 7 mechanism is rejected on measurement.** A `prompt.submit` hook cannot fire a skill; expansion is position-0 and runs first. Mechanism A ships and the platform limit is stated in the doc rather than implied away.
- **2026-09-17: the audit's item 8 direction is inverted on measurement.** Synchronous dispatch would make the 82%-silent condition universal. The wait becomes legible instead.
- **2026-09-17: a wrong inline-token match is acceptable**, because mechanism A's failure mode is one line of ignorable context. The 34% discussion class is therefore not a blocker and needs no lexical suppressor.
- **2026-09-17: `resolve_dm_user` goes in a new `src/slack/dm.rs`**, not beside `resolve_self_dm`. `write.rs` has 16 lines of headroom against a hard `bloat` gate.
- **2026-09-17: `rowsFinal.json` is the pinned Phase 3 denominator**, harvested off tmpfs into this doc's phase0 directory. The harness reads the live projects tree, so a re-walk would move the denominator.
- **2026-09-17: the `review-panel` shim replaces the agent reference** in `create-design-doc`, rather than sitting beside it, so two signals do not encode one meaning.
- **2026-09-16 and earlier:** every Addendum A decision stands unchanged. The fill is eager with a lazy backstop; `dms` is a new map; no `CURRENT_SCHEMA` bump; no watermark, Extend only; `CHANNEL_TYPES` unchanged; the 18 legacy keys are left alone.

## Alternatives Considered

### Alternative 1: the audit's `prompt.submit` injection hook (item 7 as prescribed)
- **Why not:** it cannot work. `$.command.run` is refused from `prompt.submit`; a rewritten prompt beginning with `/` is not re-expanded; there is no `$.skill.*` API.

### Alternative 2: rails `prompt.submit` inlining SKILL.md bodies
- **Why not:** trades reliability for context budget (up to 45K on a three-skill prompt), produces no `Skill(name)` record, and silently defeats `skillOverrides`.

### Alternative 3: `turn.complete` plus `$.command.run` (the only mechanical route)
- **Why not:** fires on a later turn, so the skill runs after the prompt is answered. Wrong order for the imperative chains this item exists to fix. Parked with a revisit condition: it becomes correct if the chain ever needs to run AFTER the turn rather than within it.

### Alternative 4: synchronous phase dispatch (item 8 as prescribed)
- **Why not:** a blocked parent has no seam for mid-wait output, so it guarantees the measured 82%-silent failure. Also not demonstrably available: zero of 652 dispatches were synchronous.

### Alternative 5: `resolve_dm_user` beside `resolve_self_dm` (Addendum A as written)
- **Why not:** `write.rs` 1484/1500 and `write/tests.rs` 1494/1500. Both trip `bloat`, and `otto ci` aborts before `check` and `test`.

### Alternative 6: a lexical suppressor for the discussion class
- **Why not:** unnecessary under mechanism A, whose wrong-match cost is one ignorable line. Would be required under B or C.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The `dms` merge arm is omitted and every write is silently dropped | Med | High | Phase 1's survives-upsert test, written to fail against a build without the arm and PROVEN to fail |
| Phase 4 tightens against an empty `dms` and denies every DM post | Med | High | Phase 3 gates on an INSTALLED binary, not a merged PR; the cold-miss backstop covers the residue |
| Phase 0c finds no synchronous cell and Phase 10 has no mechanism | Med | Med | The legible-wait design needs no synchrony; the Stop-hook backstop is the fallback and `prose.sh` proves the seam |
| The inline-token hook fires on discussion and wastes a turn | High | Low | Mechanism A's output is ignorable context; measured at 34% of survivors and accepted in writing |
| `pr-open` satisfies the gates in test and drifts later | Low | Med | Phase 9 tests against the LIVE hooks in both directions, allow and deny |
| The harvested harness is edited and the denominator moves | Low | Med | `rowsFinal.json` is pinned and committed; Phase 0a records its md5 |

## Open Questions

None.

## References

- Program baton: `docs/design/2026-09-13-setup-audit-program.md`
- Chunk D and Addendum A (D2's prior spec): `docs/design/2026-09-15-intent-guards.md`
- D2's client-repo working copy: `tatari-tv/slack-cli/docs/2026-09-16-dm-resolution-handoff.md`
- Audit, ranked: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/ (items 7, 8)
- Audit, raw findings: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-audit-findings-2026-09-12/
- Harvested Phase 3 harness: `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/replay/`
- Chunk A (hook/plugin load hazard): `docs/design/2026-09-13-enforcement-core.md`
- Chunk B (guard parser precision): `docs/design/2026-09-13-guard-precision.md`
- Chunk C (panel round cap, Agent PreToolUse seam): `docs/design/2026-09-14-panel-round-cap.md`
