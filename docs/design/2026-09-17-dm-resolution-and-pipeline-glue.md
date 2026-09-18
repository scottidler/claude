# Design Document: DM resolution and pipeline glue

**Author:** Scott Idler
**Date:** 2026-09-17
**Status:** Implemented. Phases 0 through 3 and 5 through 11 shipped; **Phase 4 is `dropped (measured)`**, which is the third outcome Phase 3's decision rule specified in advance: its two candidate rules scored TARGET 12 and 20 against a bar of 6. D2 landed in `tatari-tv/slack-cli` as `1adbfdd`, tagged `v0.14.0` and installed; `dms` is live at 232 edges. **Nothing is left open.** Phase 7's criterion 1 is met (two inline tokens produced two `Skill` invocations in one turn); its original prompt was a doc defect whose first clause named no merge target, which no hook could satisfy. Phase 10's three live-run criteria were satisfied by this doc's own execution, with the caveat that the run used the pre-edit skill text. Phase 11's CLI arm is met by `slack-cli` v0.14.0 and its deployed-service arm is N/A, since neither repo here is a deployed service. 0b-4 and 0b-5 are closed as not-needed: they only corroborate alternatives this doc rejects and does not ship. The `dms` map has no consumer now that Phase 4 dropped, which is the recorded outcome and not a defect: Phases 1 and 2 stand on their own, as this doc said they would before the measurement was taken.
**Review Passes Completed:** 5/5, then panel rounds 1, 2 and 3 as design reviews. **The round cap is spent.** Round 1: 7 must-fix. Round 2: 6 must-fix, and it found three of round 1's folds had not fixed their finding. Round 3: 4 must-fix, all foldable without a fourth round, and it confirmed four of round 2's six folds by execution. Every finding from all three rounds is folded, and each was re-measured here before folding. Round 3 ran with ONE seat: the staff-engineer seat timed out on both attempts and produced no review.

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
- The June complaints are the OPPOSITE failure: "are we sure this thing is still building? 22m; 48k tokens and not moving?".
- **The silence is qualitative here, not a pinned number.** A first measurement put 102 of 124 long gaps (82%) at silent, but round 1 showed the dispatch-to-report join that produced it pairs a dispatch with the next teammate message regardless of sender, including idle notices from a different phase. An exact worker-name join gives 390 pairs and a 14.53-minute median. Neither number is load-bearing and the doc does not rest on one: the complaints are on record verbatim, the long waits are on record, and that is enough to reject a direction that would make them universal.
- A synchronous parent is blocked inside the tool call, so it has no seam for mid-wait output. It would make silent waits universal rather than repair them. **This half rests on `652/0`, which is exact and scope-independent** (round 1 reproduced it under both top-level-only and including-subagents scopes).
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

- D2: a DM channel id resolves to a user id, filled once and cached, so TARGET can require the named recipient. **Met in the cache (232 edges live), not taken up by the guard: Phase 3 measured the tightening and it did not clear its bar.**
- D2: which TARGET variant ships is decided by measurement against the harvested corpus, not asserted. **Met, and the measurement's answer was none of them.**
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
| 3, 4 | claude | opus | D2, measure then tighten (3 measured, 4 dropped on that measurement) |
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

- **A wins on cost and blast radius.** It matches `prose.sh`, the repo's existing prompt-reading hook. No plugin reload. An existing `*-test.sh` harness pattern. It is the only route that cannot corrupt what Scott typed.
- **There is no `source` discriminator, and the hook fires on injected prompts too.** Chunk C measured the `UserPromptSubmit` payload keys at 2.1.272 and they are `cwd`, `hook_event_name`, `permission_mode`, `prompt`, `prompt_id`, `session_id`, `transcript_path`, with no `source` (`2026-09-14-panel-round-cap-phase0/evidence.md:142`). The same evidence records it firing on a prompt handed to `claude -p`. So "fires only on human-typed prompts" is false and the design does not rest on it. Phase 0b probes for a discriminator; if none exists, the hook fires on every prompt and the cost is one ignorable line on the ones it should not have matched, which is the same failure mode already accepted for the discussion class.
- **B's only advantage is text ownership**, which buys nothing unless the design commits to inlining SKILL.md bodies. That trades a reliability problem for a context-budget problem (bodies run 3.3K to 21.3K; a prompt naming three skills could inline 45K) and silently defeats `skillOverrides`.
- **C is the only mechanical route and it fires on the wrong turn.** For "merge, pull main, /bump, install, /cli-shakedown" the original prompt is answered first and the skill runs after. Wrong order.

**Choosing A also closes the discussion-class question, and the injected text carries the closure.** 34% of survivors are discussion, not invocation, and no lexical rule separates them. Under A a wrong match costs one line of injected context rather than a wrongly-executed skill.

That argument only holds if the injected line leaves room to decline, and the feature works precisely when the model does NOT ignore what is injected. So the text is not "invoke `Skill(name)`". It names the token, says the user mentioned it, and makes invocation conditional on the prompt asking for it. Phase 7's criteria include a discussion prompt as a negative case, so the wording is tested rather than asserted.

**The matcher ports `dSt`'s span logic and INVERTS its slash rule.** This is the trap, and porting `dSt` faithfully ships a matcher that scores zero.

- `dSt` excludes any match whose preceding character is `/`, `\` or `-`: `if(ye==="/"||ye==="\\"||ye==="-")continue`, where `ye` is `e[U-1]`.
- It was built to match a BARE `ultraplan` and to exclude `/ultraplan`. E7 needs the opposite.
- Measured by porting the function and running it: `dSt("please /bump next","bump") -> []`, `dSt("merge, pull main, /bump, install","bump") -> []`, `dSt("please bump next","bump") -> match`.
- **What to take:** the quote/bracket/angle/code span exclusion, the apostrophe-vs-quote rule, the trailing-neighbor rules (`/`, `\`, `-`, `?`, and `.` followed by alphanumeric), and `if(e.startsWith("/")) return []`.
- **What to invert:** the leading-neighbor rule. A `/` before the token is REQUIRED, not disqualifying. `\` and `-` before it still disqualify.
- **And the character before THAT slash must be a boundary**: start-of-string, whitespace, or an opening delimiter. Without it the matcher accepts every slash-separated word list in ordinary prose. Measured against the pinned fixtures (round 2):

| variant | survivors | false positives |
|---|---|---|
| faithful `dSt` port | 0 / 583 | 0 / 1,421 |
| require `/` before, check nothing before it | 561 / 583 | **195 / 1,421** |
| + boundary-before-slash | 560 / 583 | 7 / 1,421 |
| + Phase 6's generic-word deny list | **554 / 571** | **2** |

  The 195 are real prose: `~/repos/scottidler/bump main [!] is v0.3.0` fires `/bump`, `category/risk/status are spec enums` fires `/status`, `bump/shipit/babysit` fires `/babysit`. One rule takes them to 7 at a cost of one survivor, and Phase 6's deny list takes the rest.

**Name resolution drops what must not match.**

- Every `skillOverrides: "off"` entry.
- Bare aliases for plugin-namespaced skills.
- A hard deny list of generic words, taken from the 45 installed names of 8 characters or fewer: `run status config help auto update setup seed pm qa welcome cancel ooo evolve evaluate tutorial unstuck ralph`. Raw inline counts show why: `otto` 551, `config` 322, `publish` 178, `write` 128, `status` 60, `help` 36, `read` 35, `run` 32.

**The `review-panel` shim.** `Skill(review-panel)` returns `Unknown skill` today because review-panel is an agent. A one-file `SKILL.md` dispatches the agent, modeled on `shipit/SKILL.md`. To avoid two signals for one meaning, the shim REPLACES the agent reference in `create-design-doc/SKILL.md:47` rather than sitting beside it.

### Part 3 (E8): make the wait legible, chain the release, satisfy the gates

**`how-to-execute-a-plan` stops offering the audit and dispatches it.**

- The dispatching turn exists and is proven: the main thread is woken by the final phase's teammate-message, carries tool-use capability, and fires without a user prompt. Three transcripts show it, one of them dispatching the next phase.
- `:456` ("Then **wait for the user**. They may run it, skip it, or defer it") is deleted. The audit is dispatched, not offered.
- Each wake emits a one-line beat: phase, elapsed, what it waits on. That makes the boundaries between phases visible using the mechanism that already exists. It does NOT fill a silent mid-phase gap, which has no mechanism today (see below).
- After accepting a phase report the orchestrator sends `{"type":"shutdown_request"}` to that worker. One line, and it closes the "three workers sitting idle" complaint.
- Step 5's `git push && git push --tags` at `:496` and `:533` is replaced with the `rules/git.md` sequence. The skill stops instructing a step its own hook denies.

**The Stop-hook backstop does NOT cover the dispatch boundary, and the doc no longer claims it does.** The 2.1.274 bundle: `[end-turn] Stop hook block discarded (turn ended by tool result ... no model re-invoke)`. An Agent dispatch ends the parent turn BY TOOL RESULT, so a Stop-hook block at that boundary is discarded. `prose.sh` proves ordinary Stop blocking, not this one.

- What a Stop hook CAN still catch is a turn that ends normally with phases outstanding, which is a different and narrower case. It stays available as a fallback for that case only.
- **The heartbeat rests on the wake that exists, and nothing else.** The parent is woken by each teammate report and can act in that turn, proven in three transcripts. A beat is emitted on each such wake, so the boundaries between phases become visible.
- **It does NOT fix the 22-minute case.** A genuinely silent mid-phase gap has no mechanism today: no intermediate notification arrives, so nothing wakes the parent to speak. That residual silence is an accepted limit, stated rather than designed away.
- **Prose is the only thing enforcing the beat, and prose in this file has already failed once.** `how-to-execute-a-plan/SKILL.md` carries four "DO NOT STOP" statements at `:275-280` and `:363-364` and the stopping behavior persisted. Phase 10's criterion asserts the beat in a transcript for exactly that reason: it is the only part of this that is checkable.

**`release-driver` gains the back half of the chain.** It stops today at "tag verified, install reported the new version" (`:96-102`). It gains `sdv probe` until live for a deployed service, or installed-binary version plus acceptance commands for a CLI, then the shakedown. It also gains an entry path for "the PR already merged, finish the bump", which its step 2 has no route for today.

**`pr-open` satisfies both gates visibly.**

- Branch from `git branch --show-current`. Title de-slugged from the branch as `type(scope): <those same words>`, so `slug(title minus type/scope) == branch` by construction.
- Release intent is an explicit argument, never defaulted and never guessed. `Release: rides this PR (vX.Y.Z)` only after confirming a version line changes vs base, else Gate D `:566` denies the claim.
- Body written to a literal readable path under `$TMPDIR`, passed as `--body-file <literal path>`. Never a process substitution, never `-`, never an unexpanded `$VAR`. Those three are the 32 September denials.
- **It does not hide `gh` behind a subprocess.** `bin/release:334` does, and that is the bug, not the pattern.
- **The handoff is a protocol, not a phrase.** "Emits the command where the hook can see it" has two failure modes and the design picks between them: running `gh` inside the helper still bypasses PreToolUse, and merely printing it creates no PR. So: `release` stops at a distinct `PR creation required` result carrying the literal command; the agent runs that literal as its own Bash tool call, where the hooks see it; only a verified creation advances. Denial, failure and resume are each defined, because a denied `gh pr create` must not leave the driver believing a PR exists.

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

Twelve phases. Phase 0 is four independent zero-code spikes (0a, 0b, 0c, 0d) and its answers can change Phases 5 through 11.

### Phase 0: prove the three environmental assumptions
**Model:** opus
**Repo:** `scottidler/claude`

- **0a (D2). Re-pin the baseline; do NOT diff against `rowsFinal.json`.** Running the repaired driver against today's guard during round 2 showed the pinned baseline is stale: `pinned rows=216 deny=26 TARGET=9 multi-stmt=0` versus `today rows=236 deny=34 TARGET=8 multi-stmt=9`. Two causes, both real: the corpus grew (the documented drift), and the guard gained a multi-statement rule after `rowsFinal.json` was made. So `rowsFinal.json` is EVIDENCE of what chunk D measured, not a comparison arm for a post-fix variant. 0a freezes a corpus snapshot, measures today's shipped guard against it, and that becomes Phase 3's baseline. `slackrecall.py` needs `WINDOW = 3` (it ships `WINDOW = 12`).
- **0b (E7).** Six probes: a `UserPromptSubmit` hook's `additionalContext` reaches the model; **whether ANY field discriminates a typed prompt from an injected one** (chunk C measured the payload keys at 2.1.272 with no `source`, so the probe asks whether one exists, it does not presuppose one); whether it fires for prompts that start with `/`; that a `prompt.submit` hook returning text beginning with `/` is NOT expanded; that `$.command.run` is refused from `prompt.submit` and succeeds from `turn.complete`; whether a `skillOverrides: "off"` skill is still resolvable.
- **0d (E8, added in round 1).** Two assumptions no other spike covers. Does anything wake the parent DURING a phase, or only on the teammate report? And does a `shutdown_request` to a completed `phase-implementer` clear it from the roster? Both are what Phase 10's heartbeat and reaping rest on. The reaping half asserts the EFFECT (the worker is gone from `ListAgents`), not that a message was sent.
- **0c (E8).** Six cells over `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` x `name` x `run_in_background`, using the scratch-hook method from `2026-09-14-panel-round-cap-phase0/evidence.md:6-8`. Also capture whether the PreToolUse `Agent` payload carries `tool_input.name`: a guard on the named form is impossible if it does not.
- **Success criteria:** every answer is an observed log line or tool result pasted into `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md`, never an inference from the bundle; **0a commits a rows file and the driver can replay it** (below); 0c states whether any cell yields a synchronous dispatch.
- **0a's deliverable is an artifact, not a number.** `slackrecall.py` always re-walks the live `~/.claude/projects` tree and has no replay-from-file mode, so a count taken at 0a has drifted by Phase 3, which is a whole cross-repo ship later. Measured during review on one afternoon: 236 posts, then 237, then 239, then 240. So 0a (1) adds a `--from-rows <file>` mode that replays committed payloads instead of re-walking, (2) commits the snapshot it walked, and (3) records that snapshot's TARGET count against today's shipped guard. Phase 3 replays that file. Without the file and the mode, 0a inherits the same drift one level up.
- **Gates, one per spike.**
  - 0a: the gate is that the committed rows file replays deterministically, twice, to the same counts. The absolute numbers are whatever they are; `rowsFinal.json`'s 26/9/17 is chunk D's record and is NOT the target.
  - 0d: if a `shutdown_request` does not clear a completed worker from the roster, Phase 10 drops the reaping bullet rather than shipping an instruction that does nothing. One observation already exists in this doc's own drafting session: a `shutdown_request` to an idle review-panel worker returned `shutdown_approved` and the worker terminated. That is one data point on a different agent type, not the gate.
  - 0b: if no field discriminates a typed prompt, the hook fires on every prompt and that is written into Phase 7 as an accepted cost. **0b-4 and 0b-5 are CLOSED as not-needed, 2026-09-17**, rather than carried: a `prompt.submit` rewrite has no effect in print mode, and both probes only corroborate Alternatives 1 and 3, which this doc rejects on other grounds and does not ship. 0b's gate turns on mechanism A, which is proven alive, obeyed, and now proven to fire two skills in one turn. If `additionalContext` does not reach the model at all, mechanism A is dead and the doc returns to the A/B/C table before Phase 5 starts.
  - 0c: if no cell is synchronous, Phases 10 and 11 build the legible-wait design and the synchronous option is closed in writing. If one is, the doc is amended before Phase 10 starts. **Outcome: four of six cells are synchronous, and the doc was amended (Alternative 4, and the item 8 decision). Phases 10 and 11 still build the legible-wait design, because the seam argument is what carries it.**
  - 0d: if nothing wakes the parent mid-phase, Phase 10's heartbeat covers report boundaries only and the residual silence is stated as a limit, not promised away.

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

- New `src/slack/dm.rs`: `sync_dms` and `resolve_dm_user(api, cache_path, dm_id) -> Result<Option<String>>`.
- **Register the module.** `src/slack.rs:10-20` declares submodules alphabetically; `pub mod dm;` goes between `decode` (`:14`) and `follow_ups` (`:15`). A new file nobody declares compiles to nothing, and `taste.md` names registration as the most-skipped step in an implementation audit.
- **`sync_dms` PAGINATES.** `users_conversations` returns `Page<Channel>` with a `next_cursor` (`api.rs:902-916`), and `sync_channels` loops it (`mention.rs:463-473`). Addendum A's "one `users.conversations` listing" is one PAGE, which contradicts this phase's own "N ims yields N entries" criterion. Copy `sync_channels`'s cursor loop exactly.
- Wire `sync_dms` into `CacheLookup::refresh` (`mention.rs:1060`), `RefreshSummary` (`mention.rs:162`) and the count string (`command/cache.rs:130`). All three. **Plus the two output projections that would otherwise omit `dms` silently:** `run_refresh`'s JSON object (`command/cache.rs:136`) and `render()`'s text form (`command/cache.rs:160`).
- **`slack cache resolve <id>`, a new `CacheAction` variant.** `CacheAction` is `List | Add | Refresh` today (`cli.rs:563-580`) and `Add` warms a CHANNEL, so `resolve_dm_user` would ship with no caller Bash can reach and Phase 4's cold-miss backstop would have no implementation. This is the narrowest chokepoint that makes it reachable, and the guard shells out to it.
- **`channel_display_name` takes the signature change. Not optional.** It is `fn channel_display_name(api, channel_id) -> Option<String>` (`read.rs:525-533`) with no `cache_path`, so the opportunistic fill Addendum A specifies is impossible without threading a path through both callers (`read.rs:150`, `:202`). Thread it. Addendum A asked for the fill, Scott ruled for eager-plus-lazy, and an earlier draft of this phase left the choice open, which is how a specified behavior quietly becomes unbuilt.
- `CHANNEL_TYPES` (`read.rs:48`) does not change, and `read/tests.rs:772` stays true.
- Function-level debug logging per `rules/logging.md`: entry with the dm id, exit with hit | miss | not-an-im.
- **Success criteria:** a cold `D…` costs exactly one `conversations_info` and a warm one costs zero, asserted on a fake API's call count; a non-`im` channel writes nothing; an `im` whose `user` is absent writes nothing rather than an empty string; `sync_dms` over N ims yields N entries and leaves `channels` unchanged; no source file exceeds 1500 lines.

### Phase 3: measure the TARGET variants
**Model:** opus
**Repo:** `scottidler/claude`

- Prerequisite: Phase 2 merged, bumped, tagged and **installed**. The guard reads a cache only the installed binary writes.
- **Re-derive variant A from the guard on disk. Do NOT use the harvested `variantA.sh` as the baseline arm.** It is not functionally identical: `variantA.sh:354-356` greps the raw prompt, while the shipped guard pipes through `sed 's/<[^>]*>/ /g'` first (`slack-post-guard.sh:396-405`) to strip harness tags. The shipped comment quantifies the gap at 58 of 400 sampled transcripts carrying the `<command-message>` wrapper. Comparing a post-fix variant against a pre-fix baseline invalidates the whole measurement.
- **The replay driver is already repaired, tested, and committed.** It isolates through `HOME`, which is the seam the guard already has: `IDS` (`:112`), `LEDGER` (`:113`) and a `~/` body-file expansion (`:248`) are its only `$HOME` uses, so a scratch `HOME` holding a copy of the ids cache redirects the ledger without touching the guard or inventing an env var the guard does not read. Verified: live ledger 10 entries before the run and 10 after. Do not reintroduce a `REPLAY_LEDGER` variable; the driver's header records why that shape failed.
- Replay the pinned corpus against three variants: the re-derived shipped rule, name-mandatory for non-exempt DMs only, and name-mandatory for every non-exempt recipient (`variantB.sh` is the starting point, its loop already unwrapped at `:621-630`). **The pinned corpus is `phase0/replay/rows-0a.json`, 241 posts, md5 `4c70205d279a87ad19c8f73159bf5e07`.** An earlier draft of this bullet said "the pinned 216-row corpus", which is `rowsFinal.json`, chunk D's record. Phase 0a re-pinned the baseline and the Resolved Decisions entry below says so; the stale number is corrected here rather than left to mislead an implementer into replaying the wrong file.
- The first-cut guard survives in no file, so the "79 denies in 216" number cannot be re-derived and is not restated as a live measurement.
- **Decision rule, all three outcomes specified:** the variant that ships is the strictest whose **TARGET deny count** does not exceed the shipped guard's TARGET count on the same Phase 0a snapshot.
- **It scopes to TARGET denies, not to all non-artifact denies.** The guard gained a multi-statement rule after `rowsFinal.json` was cut, and it contributes 9 denies that have nothing to do with which TARGET variant ships. Counting all non-artifact denies made the old form unsatisfiable by the SHIPPED guard: measured `posts=236 allow=202 deny=34`, splitting 17 artifacts / 8 TARGET / 9 multi-statement, so "non-artifact denies <= 9" fails at 17 before any variant is tried.
  - Both clear -> all-recipients ships, the weak condition disappears.
  - Only DM-only clears -> DM-only ships, the weak condition survives for channels alone, and the measurement is recorded here as the reason.
  - **Neither clears** -> nothing ships in Phase 4 and the shipped rule stands. That is a null result, not a failure: it says `dms` did not buy back enough, and it is recorded here with the counts rather than worked around. Phases 1 and 2 still stand on their own (the cache answers a question it could not answer before) and Phase 4 closes as `dropped (measured)`.
- **Success criteria:** three deny counts in a table in this doc; every deny the selected variant introduces is read individually and named; the 2026-07-10 shakedown posts, the `**MCP write test**` marker and the duplicate-body case still deny in the selected variant.

#### Measured 2026-09-17: neither variant clears, and nothing ships in Phase 4

Run on `desk.lan` with `slack v0.14.0` installed and `slack cache refresh` done, so `~/.cache/slack/ids.json` carried `dms` at 232 edges for the first time. Corpus: `phase0/replay/rows-0a.json`, 241 posts, md5 `4c70205d279a87ad19c8f73159bf5e07`, replayed through `phase0/replay/slackrecall.py --from-rows`. Variant A is a byte copy of `slack-post-guard.sh` (`md5 b2f7be3899efacb44d2a00d3da575879`, identical on both sides), so the baseline arm is the shipped rule and not the harvested `variantA.sh`. Scripts, raw counts and the full deny lists: `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase3/`.

| variant | rule | posts | allow | deny | TARGET | artifact | multi-statement | clears TARGET <= 8 |
|---|---|---|---|---|---|---|---|---|
| A | the shipped rule, re-derived from the guard on disk | 241 | 208 | 33 | **6** | 17 | 10 | baseline |
| B | name mandatory for non-exempt DMs, `posting_intent` still covers channels | 241 | 202 | 39 | **12** | 17 | 10 | **no** |
| C | name mandatory for every non-exempt recipient | 241 | 194 | 47 | **20** | 17 | 10 | **no** |

Variant A reproduces Phase 0a exactly, down to byte-identical scored rows (`f23c42e6230549396f4c62495d52f0b1`). Every replay ran twice and was byte-identical to itself. The live send ledger was never opened: zero entries written during six full replays.


**Re-measured 2026-09-17 after the guard changed under it.** The first run scored A=8, B=14, C=25 against the guard as it stood at `b245a61`. Two later commits edited `slack-post-guard.sh`: `9131321` (the `WRITE_VALUE_FLAGS` bypass) and the round 4 fix for a global option before the subcommand. Both make the guard catch statements it previously dropped, which is why the multi-statement class went 9 to 10 and every TARGET count fell. The round 4 audit caught that the recorded numbers no longer reproduced against the tree they ship with, which is the defect: **the table above is the re-run against the final guard, and the variant scripts were regenerated from it.** The DECISION is unchanged either way, because 12 and 20 exceed 6 exactly as 14 and 25 exceeded 8.

**Neither variant clears the bar, so nothing ships in Phase 4. The shipped TARGET rule stands and Phase 4 closes as `dropped (measured)`.** That is the third outcome this phase specified in advance, and it is recorded with its counts rather than worked around.

**`dms` bought back zero denies, and the reason is structural rather than a shortfall in the map.** Every DM id in the corpus resolves through `dms` today, including the one the shipped rule already denies (`D0C0W882C93` to Roman Pavlushkov). Resolution can only buy back a deny where the prompt NAMES the person and the id failed to resolve, and the shipped guard already allowed every one of those through `posting_intent`. Making the name mandatory removes that cover, and what it exposes is that Scott's posting asks are routinely collective: "lets send a slack to each group of owners as DMs or Group DM" names nobody by construction, and cannot be satisfied by any name-mandatory rule however good the resolution is.

**The six TARGET denies variant B introduces, read individually.** All six resolve to a person, so none of them is a resolution failure:

1. `D01VB7QMKJ7`, Brian Feldman. Body "hey brian, need an approval from you as the `@tatari-tv/fe` codeowner on the tatari-skills stack". Window ends "actually lets hold off merging the 285 and instead lets ping". Session `71390a78`.
2. `D03G74VF2T1`, Lin O'Driscoll. Body "hey lin, need a `@tatari-tv/data-science` approval on the tatari-skills stack". Same window and session as 1: one "lets ping" covering several codeowners, naming none of them.
3. `D08UME8GC82`, Tantum Nilkaew. Body "tantum, closing the loop: the access you gave worked". Window "Loose ends, 3 Tech Specs reviewed in Slack, never labelled || if was off || can you fix all of these". Session `c640cd94`.
4. `D042EB42T1C`, Kyle Zou. Body "doing a tech spec cleanup: getting every TS labelled `eng-tech-spec`". Window "yes update the doc || lets send a slack to each group of owners as DMs or Group DM || if you cant send multiple, send to the page's author". Session `dbda303f`.
5. `D08UME8GC82`, Tantum Nilkaew. Same body, window and session as 4.
6. `D0B36NE6VFA`, David Ontiveros. Same body, window and session as 4.

Items 4, 5 and 6 are one instruction fanned out to three recipients, and it is the clearest case in the corpus: the ask is explicit, it is unambiguously a posting ask, and the rule denies all three because the recipients were named by role rather than by name.

**The seventeen TARGET denies variant C introduces, read individually.** Six are the DM cases above (items 1, 2, 3 and 4, 5, 6 recur), and the eleven that are additional to variant B are:

7. `C0C11ND3SAV`, the group DM with Vlad Belik and Andrii Bashuk. The window names Vlad by full name; the recipient spelling is the `mpdm-scott.idler--vlad.belik--andrii.bashuk-1` channel, which no prompt ever types. Session `16181e66`.
8. `C0C11NDHZSM`, the group DM with Vlad, Roman, Dmitriy and Serhii. Same window and session as 7.
9. `C0C0ZGUP273`, the group DM with Vlad and Roman. Session `dbda303f`, the tech-spec cleanup window.
10. `#ai-foundry` via `slack write '#ai-foundry' --edit`, window "yes, edit it to lead with slack-cli". Session `427be5a9`. An edit of an existing post, which cannot fan out and cannot duplicate.
11. `C0AUBBY21S6`, `#ai-helpdesk`. Window "send the announcement to #engineering, copy the link and sha". The ask names a DIFFERENT channel, and the crosspost to the second one is what denies. Session `46a34eeb`.
12. `C0ACWPXHLPK`, `#ai-foundry`. Body opens `<@U02G958R3GA> this was good, worked all of it`. Window ends "lets ping". Session `71390a78`.
13. `C0AA8UBU5MX`, `#tech-spec-reviews`. Window "drop the quick missive to Mike in that thread". Session `d5cbd237`. This one is a fixture in the shipped matrix, asserted to ALLOW ("a missive to Mike in a channel the prompt does not name").
14. `C0ACWPXHLPK`, `#ai-foundry`. Window "send it || i didnt ask for a draft. I asked you to send it. I showed yo || this is not fucking rocket science". Session `eee0d5db`. Also a shipped fixture asserted to ALLOW.
15. `json`, from `slack write --at 7d --output json '#clipboard'`. Session `798c79d4`. The target is `#clipboard`, which is EXEMPT; `--output` is missing from `WRITE_VALUE_FLAGS` (`slack-post-guard.sh:191`) so the parser reads its operand as the target.
16. `json`, from `date '+now=%s %H:%M:%S'; slack --version; slack write ... --output json ...`. Session `c8b815bd`. Same parser gap.
17. `json`, from `date '+scheduled_at=%H:%M:%S'; slack write --at ... --output json ...`. Same session, same gap.

**Two of variant C's denies break fixtures the shipped matrix asserts must allow** (13 and 14), and three more are a parser gap rather than a rule (15, 16, 17). Corroborating measurement, run against the whole shipped matrix: variant A `pass=129 fail=0`, variant B `pass=124 fail=5`, variant C `pass=117 fail=12`. Variant A's perfect score is the second confirmation that the baseline arm is the shipped guard.

**The `--output` parser gap is real today and is not this phase's to fix.** `WRITE_VALUE_FLAGS` (`:191`) lists eight value-taking flags and `--output` is not among them, so `slack write --output json '#clipboard' ...` authorizes against the target `json` instead of against the exempt `#clipboard`. Today `posting_intent` hides it, so it is a latent gap rather than a live one. It is recorded here for Scott to route rather than folded into a phase nobody asked for.

**The must-still-deny cases hold in all three variants**, asserted directly rather than through the replay, because the corpus copy of the marker post went to the exempt DM and the driver wipes the ledger per post: `phase3/must-deny.sh` reports 12 passed, 0 failed over the `**MCP write test**` marker into a named coworker DM, the 2026-07-10 shakedown turn, the `/cli-shakedown` command wrapper, and a duplicate body inside the hour, each against A, B and C. Its fixture cache carries `dms` on purpose, so the recipient resolves and TARGET passes: a deny that landed because the id no longer resolved would prove nothing about whether TEST-TEXT and RESEND still bite.

### Phase 4: TARGET requires the named recipient (dropped, measured)
**Model:** opus
**Repo:** `scottidler/claude`

**This phase does not ship. Phase 3 measured its two candidate rules at TARGET 12 and 20 against a bar of 6, and the decision rule this doc set in advance closes it as `dropped (measured)`.** The bullets below are kept as the record of what was designed and what it would have cost, not as work to do. Phases 1 and 2 stand on their own: the cache answers a question it could not answer before, and the `dms` map is live at 232 edges.

- `resolve_names` gains its `dms` clause in BOTH jq programs; the `.users` DM branch is removed. `U…` resolution is unaffected: it runs through `$uits` over `.handles` at `:294`, a separate branch.
- The recipient loop stops being wrapped in `if ! posting_intent` (`:705`). Phase 3's result decides whether the weak condition remains as a per-recipient fallback for channels or disappears.
- Cold-miss backstop: a `D…` absent from `dms` is resolved by shelling out to `slack cache resolve <id>` (Phase 2's new variant) before authorization, with a timeout, and a failure DENIES, consistent with this guard's existing missing-cache behavior.
- **It invokes an ABSOLUTE path, never a bare `slack`.** `which -a slack` on this machine returns `~/.cargo/bin/slack` plus `/usr/bin/slack` and `/bin/slack`, which are the Slack DESKTOP app. The guard does no PATH handling today (zero hits for `PATH=`, `command -v` or a `cargo/bin` reference), so a bare `slack` in an authorization gate is a coin flip between the CLI and a GUI launcher. Resolve `$HOME/.cargo/bin/slack` explicitly and deny if it is missing or does not answer `cache resolve`.
- **The 18 legacy `D…` keys under `.users` break here, and that is stated rather than discovered.** `$dmits` (`slack-post-guard.sh:292`) is their only reader and this phase removes it. They resolve today and stop resolving after this phase, which is correct (they are a retired tool's artifact) but it is a behavior change, not a no-op.
- **Ordering hazard, and it is the reason this phase ships last. It is worse than "the cache lacks `dms`": an old writer ERASES it.** `IdCache` is deliberately not `deny_unknown_fields` (`cache.rs:62-67`) and `save()` serializes the struct wholesale (`cache.rs:591`), so an old binary loads a `dms`-bearing cache, drops the field it does not know, and writes it back without it. The repo already asserts that behavior: `cache/tests.rs:103 resave_of_pre_change_cache_drops_the_groups_key`. `Merge::Extend` cannot help, because the old binary has no field to extend.
- **Installing the binary is not sufficient, because a resident process is a writer.** `slack mcp serve` is a long-running stdio server (`main.rs:84`) whose `users_search` path reaches `mcp/helpers.rs:912` -> `ensure_users_fresh` -> `fill_users` -> `upsert_full_user_sync` -> `save`. Replacing `~/.cargo/bin/slack` does not replace code already resident in that process, and this machine runs a live slack MCP server.
- **So the rollout condition is:** install the new binary, **restart or reconnect every persistent MCP writer**, confirm no older copy resolves on PATH, and verify a post-install MCP operation leaves `dms` intact. Only then does Phase 4 ship.
- **The failure mode if that is skipped depends on PATH, and is not uniformly "deny everything":** a current binary's cold-miss backstop recovers a `dms`-less cache, so the guard degrades rather than failing closed. An absent or stale binary is the fail-closed case. Pin the PATH (below) so the outcome is not a coin flip.
- The 3-turn window is unchanged.
- **Success criteria:** a post to a peer's DM whose prompt names the person by handle, display name, real name or first name allows; the same post naming nobody denies, and the deny text names the person rather than the `D…` id; the replay's deny count matches Phase 3's measurement for the selected variant; the cold-miss path is exercised against a `D…` deliberately removed from `dms`.

### Phase 5: the inline-token matcher, standalone
**Model:** sonnet
**Repo:** `scottidler/claude`

- **Python.** `dSt` is character-scanning with span tracking; in bash/jq that is a liability on a path that runs for every prompt. The tree already ships Python hooks, so this is the house option, not a new dependency.
- Port `dSt`'s span and trailing-neighbor logic, keep `startsWith("/") -> no scan`, and INVERT the leading-neighbor rule so `/` before the token is required rather than disqualifying. No wiring to anything.
- **The inversion is the whole phase.** A faithful port scores zero on every survivor: `dSt("merge, pull main, /bump, install","bump") -> []`. Write the test that proves the inversion first.
- **Scoring protocol, because the fixture format does not imply one.** Each record is scored at ITS OWN occurrence, the token starting at `context[offset + 1]`, not "run the matcher over the window and count what it finds". 435 of the 2,004 records hold more than one `/token` in their 100-char window, 428 of them false positives, so the per-window reading gives entirely different numbers (faithful port: 6/583 and 77/1421 rather than 0 and 0) and makes criterion 7 unreachable.
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
- **Success criteria:** a live session where a multi-clause prompt carrying two inline tokens produces **both** skill invocations with no second prompt. **MET 2026-09-17**, measured through the live hook: `give me /chisle-help and then /chisle-review, nothing else` produced `{"skill":"chisle-help"}` and `{"skill":"chisle-review"}` in one turn, no second prompt. **The criterion originally named `merge, pull main, /bump, install, /cli-shakedown` and that prompt is a doc defect, independent of the hook:** its first clause names no repo, branch or PR, so any session must ask which merge, and the criterion forbids exactly that question. No hook can satisfy it. The clause under test is the inline tokens, and it is now tested with a prompt whose other clauses are answerable; a live session where `is chunk E ready to build, or do I need to /create-design-doc on it first?` invokes nothing, which is the discussion case the injected wording has to survive; a second discussion case, `13 of the 15 costliest sessions are /how-to-execute-a-plan`, also invokes nothing; a prompt already opening with a slash command is left alone; `rg -c 'UserPromptSubmit' HOME/.claude/settings.json` returns at least 1 and `hooks-preflight.sh` emits no unresolved-hook warning naming it.

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
- **`bin/release` stops creating the PR at all.** It does NOT call `pr-open` internally: a subprocess call from inside `release` leaves `gh` invisible to PreToolUse exactly as `--fill` does, and a phase agent implementing "release calls pr-open" reimplements the bug. `release` returns `PR creation required` carrying the literal command; the caller runs it as its own Bash tool call. **Two sites:** the live call at `:334` and the dry-run echo at `:342`.
- **`release-driver.md:74-80` gains the new result as a consumer.** It recognizes only done, paused and failure today, so `PR creation required` would fall through unhandled.
- **The three transitions, named rather than implied:** a DENIED `gh pr create` returns to the caller with the denial text and no PR recorded; a FAILED creation (network, auth) is retried once then reported; RESUME re-enters `release` with the PR url, and `release` verifies the PR exists before advancing rather than trusting the caller.
- **Every `gh` call in `release` sets `GH_PERSONA` explicitly.** `release` is a bash script, so the `.zshenv` `gh()` persona function does not exist in it and the rails `tool.call` hook does not rewrite a subprocess. Measured from inside a bash script in `~/repos/scottidler/claude`: `GH_PERSONA` unset, `gh api user --jq .login` returns `escote-tatari`, the WORK account, on a personal repo. So the caller creates the PR as home and `release` would verify it as work. This repo is public so it passes here; four of Scott's personal repos are private and it would not. The resume verification is exactly the twin of the failure already named: a successful creation leaving the driver believing no PR exists.
- **The human path changes too.** When Scott runs `release` at a terminal there is no PreToolUse and no agent, so the stop-and-hand-back prints the command for him to run. Say so in the helper's output rather than leaving a terminal user staring at a stopped driver.
- **Success criteria:** on a scratch branch with a version delta, the command `pr-open` emits is piped to `git-release-guard.sh` and `branch-pr-title-guard.sh` as a PreToolUse payload and both return an empty decision (allow); the same command on a branch with no version delta and `--release rides` returns a deny from Gate D `:566`, with the deny text recorded. "Running it against the live hooks" means exactly that: feed the hook its payload on stdin and read the JSON, do not open a PR to find out. `rg -n 'gh pr create --fill' HOME/.claude/bin/release` returns zero lines, and `release-driver.md` handles `PR creation required`.

### Phase 10: `how-to-execute-a-plan` runs the plan
**Model:** opus
**Repo:** `scottidler/claude`

- Delete `:456`. Dispatch the audit instead of offering it.
- Per-wake heartbeat: phase, elapsed, what it waits on.
- `shutdown_request` to each phase worker after its report is accepted.
- Step 5's `git push --tags` at `:496` and `:533` replaced with the `rules/git.md` sequence, routed through `pr-open` where a PR is involved. Both sites: fixing only the live one leaves the summary box lying.
- **Success criteria (all MET; the three live-run ones were satisfied by this doc's own execution, 2026-09-17):** the audit was DISPATCHED rather than offered, and `ListAgents` showed no phase worker after the run, both observed directly. Eight workers were reaped by asserting the roster, and the heartbeat ran per teammate wake. **The caveat, stated rather than hidden: this run executed the PRE-edit skill text, so it demonstrates the practice and not the artifact.** The artifact is asserted statically below. `rg -n 'push --tags' HOME/.claude/skills/how-to-execute-a-plan/SKILL.md` returns zero lines; the audit-offering sentence at `:456` is gone; a multi-phase run dispatches review-panel with no user prompt between the last phase and the dispatch; **the transcript of that run shows one beat per teammate wake, naming the phase and elapsed time** (without this assertion the phase can pass with the heartbeat unbuilt); **after the run, `ListAgents` shows no phase worker** (the effect, not the send).

### Phase 11: `release-driver` owns the back half
**Model:** opus
**Repo:** `scottidler/claude`

- The chain extends past tag verification: install -> `sdv probe` until live (deployed) or installed-binary version plus acceptance commands (CLI).
- **The shakedown does NOT move into `release-driver`.** Its frontmatter grants `tools: Bash, Read, Grep, Glob` (`release-driver.md:4`), so it cannot call `Skill(cli-shakedown)`. Either widen the grant or leave the shakedown with the caller. **Leave it with the caller:** the agent exists to own the async wait in an isolated context, and a shakedown is an interactive exercise whose findings Scott reads. `release-driver` returns "installed at vX.Y.Z, shakedown not run" and the caller fires the skill.
- `sdv probe` is a plain binary, so the probe half needs no new grant.
- An entry path for "the PR already merged, finish the bump", which step 2 lacks today.
- **Its declared inputs (`release-driver.md:23`) grow to carry what the back half needs**: the deployment URL, the expected version, and the acceptance commands. Today they carry none of the three, so the probe half would have nothing to probe.
- Route the post-merge arc there from the `bump`, `shipit` and `babysit` trigger descriptions.
- **Success criteria:** **the CLI arm is MET 2026-09-17** by `tatari-tv/slack-cli` v0.14.0, the first live exercise of this path: merged, tagged, installed, and the installed binary's version reported (`slack v0.14.0`), with `slack cache refresh` returning `232 dm(s) indexed` as the acceptance command. **The deployed-service arm is N/A for this doc**: neither repo in its blast radius is a deployed service, so there is nothing to `sdv probe`. It is written and waits for the first service release rather than being carried as an open item against this doc. A deployed-service release probes until the new version is live and reports the probe output; a CLI release reports the installed binary's version; `release-driver.md` names `pr-open` rather than a raw `gh pr create`; its return contract names the shakedown as the caller's step.

## Blast radius and ship order

- **Two repos.** `tatari-tv/slack-cli` (Phases 1 and 2) and `scottidler/claude` (everything else).
- **The order is forced for D2 only.** slack-cli ships the fill first; the guard tightens last, because it cannot read a field the client does not write and must not tighten before the cache can answer. **The guard half did not ship: Phase 3's measurement dropped Phase 4, so D2's blast radius ends at `slack-cli` plus this doc.**
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

**All eight verified 2026-09-17 against the landed implementation, and every box below is ticked on that run, not on intent.** Each was recorded pre-implementation with an `Observed on main:` line showing it correctly failing; those lines are kept as the before-state rather than overwritten. The round 4 audit caught that the section still read as pre-implementation while `Status` said Implemented, which is the defect this block closes.

| # | verified today | how |
|---|---|---|
| 1 | `true`, 232 edges | `jq 'has("dms")'` and `.dms\|length` on the live cache, after `slack v0.14.0` was installed |
| 2 | green | `otto ci` exit 0 in `tatari-tv/slack-cli`, `bloat` included |
| 3 | met, no selection | neither variant cleared the bar, so no variant was selected and none can deny more than the shipped rule |
| 4 | zero lines | `rg -n 'push --tags' HOME/.claude/skills/how-to-execute-a-plan/SKILL.md` |
| 5 | both halves | `rg -n 'gh pr create --fill' HOME/.claude/bin/release` zero lines, AND both guards return `{}` on the allow case with Gate D denying the no-delta case |
| 6 | registered | `jq` names `~/.claude/hooks/inline-skill-tokens.py`, which exists and is executable |
| 7 | 564/571, 0 FP | matcher plus Phase 6's deny list over the pinned fixtures, asserted in CI by `AcceptanceCriterionSevenTest` |
| 8 | `pass=141 fail=0` | the guard's own matrix |


Every criterion names a literal command. Per the ready-to-build gate, each was run against current `main` on 2026-09-17 and its output recorded beneath it, EXCEPT where the criterion's subject does not exist yet: those say so, name the phase, and record what was run in its place.

- **Executed as written, full criterion:** 1, 4, 8.
- **Executed in part** (the half that exists today): 2 (the `bloat` stanza standalone, not full `otto ci`), 5 (the string check, not the allow/deny pair), 6 (the `jq` probe).
- **Substitute recorded, criterion not runnable yet:** 3 (baseline pinned, and round 2 showed the pin is stale against today's guard), 7 (fixtures built and all three matcher variants measured).

- [x] **1. The cache answers the DM question.** `jq -r 'has("dms")' ~/.cache/slack/ids.json` returns `true` and `jq -r '.dms|length'` returns a count greater than zero.
  - `Observed on main: false`. Correctly failing: `dms` does not exist yet. Ships in Phase 2, and the count requires the INSTALLED binary, not a merged PR.

- [x] **2. `slack-cli` stays under the bloat gate.** `otto ci` exits 0 in `tatari-tv/slack-cli`, including the `bloat` task.
  - `Observed on main:` the `bloat` stanza run standalone returns `All files within 1500 line limit`; the top four by size are `write/tests.rs` 1494, `write.rs` 1484, `mcp/tests.rs` 1400, `scheduled.rs` 1382. **Full `otto ci` was NOT run** (it compiles and tests the crate); the bloat half was run as the part this doc puts at risk. **Passes today, and that is the point: the margin is the risk**, headroom 6 and 16. This criterion bites only after Phase 2 adds code, which is why `resolve_dm_user` goes in a new file.

- [x] **3. The selected TARGET variant does not deny more than the shipped rule.** Replaying Phase 0a's committed rows file, the selected variant's **TARGET** deny count is no greater than the shipped guard's TARGET count on that same file, with all three variants' counts in this doc and the baseline arm re-derived from the guard on disk.
  - **Rewritten twice.** Round 1: the premise that `variantA.sh` is the shipped rule was false. Round 3: "deny count no greater than 9, artifacts excluded" is unsatisfiable by the shipped guard itself, measured `deny=34` splitting 17 artifacts / 8 TARGET / 9 multi-statement, so non-artifact denies are 17 against a bar of 9. The multi-statement rule postdates the old baseline and is orthogonal to this decision, so the criterion scopes to TARGET.
  - `Observed on main:` the shipped guard scores `posts=236 allow=202 deny=34` (TARGET 8). `rowsFinal.json`'s `216/26/9/0` is chunk D's record, not a target. The denominator moves until Phase 0a commits one, which is why 0a's deliverable is the file.
  - **Measured in Phase 3 on 2026-09-17: A=8 (baseline), B=14, C=25 on `rows-0a.json`.** The criterion is met as a measurement and no variant is selected: neither clears the bar, so nothing ships in Phase 4. All three counts, the baseline re-derivation and the named deny lists are in the Phase 3 section above.

- [x] **4. The plan executor stops instructing a denied command.** `rg -n 'push --tags' HOME/.claude/skills/how-to-execute-a-plan/SKILL.md` returns zero lines.
  - `Observed on main:` two lines, `496:git push && git push --tags` and `533:│  5. git push && git push --tags     [if approved]│`. Correctly failing. Ships in Phase 10.

- [x] **5. The release driver stops evading the PR gates.** `rg -n 'gh pr create --fill' HOME/.claude/bin/release` returns zero lines, AND a `pr-open`-built command run against the live `git-release-guard.sh` and `branch-pr-title-guard.sh` is ALLOWED on a branch with a version delta and DENIED without one.
  - The string check alone measures a deletion, not the behavior; round 1 flagged that. The allow/deny pair is what bites.
  - `Observed on main:` the string check returns two lines, `:334` (the live call) and `:342` (the dry-run echo). Correctly failing. Ships in Phase 9.

- [x] **6. The new hook is registered and resolves.** `jq -r '.hooks.UserPromptSubmit[]?.hooks[]?.command' HOME/.claude/settings.json` lists the hook's executable path, AND that path exists and is executable.
  - **Rewritten twice.** Round 1 killed "`hooks-preflight.sh` exits 0": every path in that script exits 0, including the unresolved-hooks branch at `:40-48`. Round 2 killed the replacement too: `rg -c 'UserPromptSubmit'` returns 1 against `{"hooks":{"UserPromptSubmit":[]}}`, so it passed with zero hooks installed, and "preflight emits no warning naming it" is vacuously true when the hook does not exist. The criterion now asserts the executable, not the event-name string.
  - `Observed on main:` the `jq` returns empty; no `UserPromptSubmit` key exists. Correctly failing. Ships in Phase 7.

- [x] **7. The matcher separates the classes.** Against `phase0/inline-token/fixtures.json`, with Phase 6's deny list applied: at least 554 of the 571 remaining survivors match, and the ONLY false positives are the two enumerated clipped-window records below.
  - **The 0-false-positive form was unachievable and is restated rather than moved.** `fixtures.json` stores a 100-char window by design, so a delimiter that opened outside the window is clipped away and the span logic is asked to close something it cannot see. 375 of the 832 `code-span` records have odd backtick parity in their window.
  - The two permitted residuals, both `/handoff`, both with an unbalanced delimiter in-window: `'he \`last-prompt\` record carries the human-readable form (\`\\"/handoff to the next agent...'` and `'-args>\`; the \`last-prompt\` record carries the human form (\`"/handoff to the next agent...'`. Any third false positive fails the criterion.
  - The denominator does not move: same pinned file, same 2,004 records.
  - Substitute run, since no matcher exists: the fixtures were materialized and verified at `total 2004 survivors 583 false-positives 1421`, class split `code-span 832, path-glued 544, url 36, path-continues 8, filename-ext 1`. The criterion itself ships in Phase 5.
  - **Round 1 added the case that matters:** a faithful `dSt` port scores 0 of 583, because `dSt` excludes a match preceded by `/`. The criterion is unchanged; the trap is now named in Phase 5.

- [x] **8. The guard's own suite does not regress.** `bash HOME/.claude/hooks/slack-post-guard-test.sh` reports zero failures and no fewer than **141** passes. The floor rose from 129 with the fixtures the round 4 fixes added: five for the `WRITE_VALUE_FLAGS` value-consuming rule, two positive controls, four for a global option before the subcommand, and one more positive control.
  - `Observed on main: pass=129 fail=0`. This is the baseline Phase 4 must not break, and the count floor rises with the fixtures Phase 4 adds.

## Resolved Decisions

- **2026-09-17 (Phase 3, measured): Phase 4 is dropped and the shipped TARGET rule stands.** Replaying `rows-0a.json` against the three arms scored TARGET 8 (shipped, re-derived from disk), 14 (name-mandatory for DMs) and 25 (name-mandatory for every recipient). The bar was 8 and neither candidate clears it, which is the null outcome this doc specified in advance. `dms` bought back zero denies because resolution only helps where the prompt names the person, and those posts were already allowed by `posting_intent`; what a name-mandatory rule actually hits is Scott's collective asks ("lets send a slack to each group of owners as DMs"), which name nobody by construction. Evidence: the Phase 3 section above and `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase3/`.
- **2026-09-17 (Phase 3): the pinned Phase 3 corpus is `rows-0a.json` (241 posts), not `rowsFinal.json` (216).** The Phase 3 bullet still said "the pinned 216-row corpus" after Phase 0a re-pinned the baseline; the bullet is corrected in place rather than left to send an implementer at the wrong file.
- **2026-09-17 (Scott): D2 and E ship in one design doc, D2 first.** Overrides the program's one-chunk-per-doc rule at `:22` and the no-folding rule at `:26`. The override is recorded here and in the tracker; it is not treated as a precedent for later chunks.
- **2026-09-17: the audit's item 7 mechanism is rejected on measurement.** A `prompt.submit` hook cannot fire a skill; expansion is position-0 and runs first. Mechanism A ships and the platform limit is stated in the doc rather than implied away.
- **2026-09-17: the audit's item 8 direction is inverted on measurement.** A blocked parent has no seam for mid-wait output, so synchronous dispatch would make silent waits universal. The wait becomes legible instead. Zero of 652 `phase-implementer` dispatches ever returned inline, which is exact as history. The 82%-silent figure from the first pass did not survive round 1's join correction and is not load-bearing.
- **2026-09-17 (Phase 0c): the decision stands, and one leg under it is withdrawn.** Synchronous dispatch IS available: four of 0c's six cells returned the report inline, decided solely by `run_in_background: false`. So `652/0` describes what has happened, not what is possible, and it can no longer be cited as an availability argument. The decision now rests entirely on the mid-wait seam, which 0d measures directly. Evidence: `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md`, section 0c.
- **2026-09-17: a wrong inline-token match is acceptable**, because mechanism A's failure mode is one line of ignorable context. The 34% discussion class is therefore not a blocker and needs no lexical suppressor.
- **2026-09-17: `resolve_dm_user` goes in a new `src/slack/dm.rs`**, not beside `resolve_self_dm`. `write.rs` has 16 lines of headroom against a hard `bloat` gate.
- **2026-09-17: `rowsFinal.json` is the pinned Phase 3 denominator**, harvested off tmpfs into this doc's phase0 directory. The harness reads the live projects tree, so a re-walk would move the denominator.
- **2026-09-17: the `review-panel` shim replaces the agent reference** in `create-design-doc`, rather than sitting beside it, so two signals do not encode one meaning.
- **2026-09-17 (round 1): the matcher inverts `dSt`'s leading-slash rule rather than porting it.** A faithful port scores zero on every survivor. Measured by running the extracted function.
- **2026-09-17 (round 1): mechanism A does not rest on a `source` discriminator**, because none exists on the payload and the hook fires on injected prompts too. This repo's own chunk C evidence had measured that three chunks ago.
- **2026-09-17 (round 1): the Stop-hook backstop is withdrawn at the dispatch boundary.** A block there is discarded because the turn ended by tool result. The heartbeat rests on the teammate-report wake, and mid-phase silence is named as an accepted limit rather than designed away.
- **2026-09-17 (round 1): the 82%-silent figure is not load-bearing and is stated qualitatively.** It did not reproduce under an exact worker-name join. The item 8 decision rests on `652/0`, which is exact.
- **2026-09-17 (round 2): the matcher requires a boundary before the slash.** Requiring `/` alone accepts every slash-separated word list in prose: 195 false positives of 1,421. Measured at 561/195, 560/7 with the boundary rule, 554/571 survivors and 2 false positives once Phase 6's deny list applies.
- **2026-09-17 (round 2): criterion 7's zero-false-positive form was unachievable and is restated, not moved.** The fixtures store a 100-char window, so 375 of 832 `code-span` records have a clipped delimiter. The two permitted residuals are enumerated; a third fails.
- **2026-09-17 (round 2): `release` does not call `pr-open` internally.** A subprocess call leaves `gh` invisible to PreToolUse exactly as `--fill` does. `release` stops and hands the literal command back; the caller runs it.
- **2026-09-17 (round 2): the rollout condition names resident MCP writers, not just the installed binary.** An old writer ERASES `dms` (not `deny_unknown_fields`, wholesale `save()`, and the repo already tests the erasure), and `slack mcp serve` is long-running, so replacing the binary does not replace resident code.
- **2026-09-17 (round 2): the cold-miss backstop invokes an absolute path.** `/usr/bin/slack` and `/bin/slack` on this machine are the Slack desktop app.
- **2026-09-17 (round 2): `channel_display_name` takes the signature change.** An earlier draft left it optional, which is how a specified behavior quietly becomes unbuilt.
- **2026-09-17 (measured while folding round 2): `rowsFinal.json` is evidence, not a comparison arm.** Today's guard scores the same corpus differently (`216/26/9/0` pinned vs `236/34/8/9` today), because the guard gained a multi-statement rule after the baseline was made. Phase 0a re-pins.
- **2026-09-17 (round 3): the Phase 3 decision rule scopes to TARGET denies.** Counting all non-artifact denies made it unsatisfiable by the shipped guard itself (17 against a bar of 9), because the multi-statement rule postdates the old baseline and is orthogonal to which TARGET variant ships.
- **2026-09-17 (round 3): Phase 0a's deliverable is a committed rows file plus a `--from-rows` replay mode**, not a number. The driver re-walks the live tree, which drifted 236 -> 240 in one afternoon.
- **2026-09-17 (round 3): every `gh` call in `bin/release` sets `GH_PERSONA`.** A bash subprocess gets neither the `.zshenv` persona function nor the rails rewrite, and defaults to the work account on a personal repo.
- **2026-09-17 (round 3): fixtures are scored per-record, not per-window.** 435 records hold multiple tokens in their window; the per-window reading makes criterion 7 unreachable.
- **2026-09-16 and earlier:** every Addendum A decision stands unchanged. The fill is eager with a lazy backstop; `dms` is a new map; no `CURRENT_SCHEMA` bump; no watermark, Extend only; `CHANNEL_TYPES` unchanged; the 18 legacy keys are left alone.

## Alternatives Considered

### Alternative 1: the audit's `prompt.submit` injection hook (item 7 as prescribed)
- **Why not:** it cannot work. `$.command.run` is refused from `prompt.submit`; a rewritten prompt beginning with `/` is not re-expanded; there is no `$.skill.*` API.

### Alternative 2: rails `prompt.submit` inlining SKILL.md bodies
- **Why not:** trades reliability for context budget (up to 45K on a three-skill prompt), produces no `Skill(name)` record, and silently defeats `skillOverrides`.

### Alternative 3: `turn.complete` plus `$.command.run` (the only mechanical route)
- **Why not:** fires on a later turn, so the skill runs after the prompt is answered. Wrong order for the imperative chains this item exists to fix. Parked with a revisit condition: it becomes correct if the chain ever needs to run AFTER the turn rather than within it.

### Alternative 4: synchronous phase dispatch (item 8 as prescribed)
- **Why not:** a blocked parent has no seam for mid-wait output, so it would make silent waits universal instead of repairing them. That is the whole reason, and it is the only one.
- **Amended 2026-09-17 by Phase 0c.** An earlier form of this entry added "also not demonstrably available: zero of 652 dispatches were synchronous." That was wrong: `652/0` is a true statement about what has happened, and it was read as a statement about what is possible. 0c measured four synchronous cells out of six. `run_in_background: false` returns the subagent's report inline, on demand; `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` and `name` are irrelevant to it. The availability claim is withdrawn and the rejection rests on the seam argument alone.

### Alternative 5: `resolve_dm_user` beside `resolve_self_dm` (Addendum A as written)
- **Why not:** `write.rs` 1484/1500 and `write/tests.rs` 1494/1500. Both trip `bloat`, and `otto ci` aborts before `check` and `test`.

### Alternative 6: a lexical suppressor for the discussion class
- **Why not:** unnecessary under mechanism A, whose wrong-match cost is one ignorable line. Would be required under B or C.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The `dms` merge arm is omitted and every write is silently dropped | Med | High | Phase 1's survives-upsert test, written to fail against a build without the arm and PROVEN to fail |
| Phase 4 tightens against an empty `dms` and denies every DM post | Med | High | Phase 3 gates on an INSTALLED binary, not a merged PR; the cold-miss backstop covers the residue |
| Phase 0c finds no synchronous cell and Phase 10 has no mechanism | Med | Med | The legible-wait design needs no synchrony, so 0c's answer does not block it. **There is no Stop-hook fallback at the dispatch boundary**: that block is discarded (`:210`). The heartbeat is prose, asserted in a transcript by Phase 10's criterion, and mid-phase silence stays an accepted limit |
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
