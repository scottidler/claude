# Design Document: Handoff ownership and waiting discipline

**Author:** Scott Idler
**Date:** 2026-09-18
**Status:** Approved, building (Open Questions closed by Scott 2026-09-20, Addendum A)
**Review Passes Completed:** 5/5, then panel round 1 (one seat: staff rc=124) and panel round 2 (both seats rc=0), both fully folded. Round 2 was 8 must-fix / 7 cheap wins, every one re-verified against the code before folding. Two of the three rounds under the cap are spent.
**Chunk:** F2 of the setup-audit program (`docs/design/2026-09-13-setup-audit-program.md`), audit items 10 and 11

## Summary

Finish owning the `handoff` skill (it still carries two third-party defaults that break it), give the resume side a mechanism instead of prose, and close the three foreground-sleep bypasses the harness's own block leaves open.

Item 11 has seven prescriptions. This doc builds four of them (the sleep-bypass rule, the waiting line in `release-driver.md`, the ToolSearch section, the silent-turn env knobs) and drops three with the measurement or citation that killed each. Two of the four are already shipped natively by Claude Code 2.1.276 and reduce to reusing what is there rather than building it.

## Problem Statement

### Background

- The 2026-09-12 audit ranked 22 changes. F2 is items 10 and 11.
- Chunks C, D, E and F1 all found the same class of defect: the audit's prescribed *mechanism* cannot do its stated job. F2 hits it again, inverted. Here two mechanisms are **already done** by the harness and a third is **forbidden by our own skill**.
- Claude Code version under test: **2.1.276**, BUILD_TIME `2026-09-18T00:40:43Z`, GIT_SHA `bc0a4292`.

### Problem

**Item 10, handoff.** Chunk A replaced the mattpocock symlink with a local skill (`5faca7d`) and gave it a resume mode. It did not touch two properties inherited verbatim from the upstream file:

- `disable-model-invocation: true` (`HOME/.claude/skills/handoff/SKILL.md:5`), byte-identical to `mattpocock/skills/skills/productivity/handoff/SKILL.md:4`.
- "Save it to the session scratchpad or the OS temp directory, not the workspace" (`SKILL.md:44`), a reword of upstream's `:8` "Save to the temporary directory of the user's OS - not the current workspace."

Neither was decided. Chunk A's commit message and `docs/design/2026-09-13-enforcement-core.md` say nothing about either. They are third-party defaults that survived a rewrite, and they are what the audit's item 10 is actually about.

What they cost, re-measured over 5,337 transcripts / 1,468,690 records / 2026-06-09..2026-09-18:

- **6 hard errors on the strict basis**, all identical: `Skill handoff cannot be used with Skill tool due to disable-model-invocation`. Dates 06-27, 07-01, 07-10, 07-30, and **09-18 (x2, while this doc was being written)**. Strict means `tool_result` blocks only. A broader scan over all record types returns 9, but that basis now sweeps in this doc's own text quoting the error, so 6 is the number. An earlier draft said 9 including three on 09-12; round 1 could not reproduce those and they are withdrawn. A 7th followed when AC1's baseline probe was run in this session. The load-bearing part is unchanged by the correction: a by-skill counter over the strict set returns `handoff` and **nothing else in the entire corpus**.
- **118 inline misses** in 102 sessions (prose `/handoff`, no command block). The audit said 50.
- **95 sessions open by pasting a handoff path** by hand (66 in the audit's window, of 3,139 main-thread sessions), rising: Jun 10, Jul 39, Aug 17, **Sep 29**.
- **265 in-window resumption gaps over 6 hours** in 215 sessions. Confirms the audit's 275.
- Usage is **flat across the chunk-A rewrite**: slash by month 11 / 23 / 8 / 16. The rewrite fixed the receiving prose and nothing else.

There is no resume trigger, and no rule anywhere mentions handoff (`rg 'handoff' HOME/repos/.claude/rules/` is empty).

**Item 11, waiting.** The harness already denies foreground sleep. It has since **2026-06-22T06:15:29Z**, three months before the audit's window closed, so the audit measured a period in which its own prescription was already live. The deny text already names Monitor and `run_in_background` verbatim.

The deny is `Bash.create().validateInput` -> `VDs(command)`, which splits statements with tree-sitter, tests **statement 0 only** against `/^sleep\s+(\d+(?:\.\d*)?)\s*$/`, and denies when the value is `>= 25` (`var Dpn = 25`). Three bypass classes are live, each probed this session:

| Bypass | Probe | Result |
|---|---|---|
| B1 position | `echo A; sleep 26; echo B` | ALLOWED |
| B2 sub-threshold chaining | `sleep 24; sleep 24` | ALLOWED |
| B3 loop-wrapping | `for i in 1 2 3; do sleep 30; done` | **ALLOWED, ran 90s** |
| B3 loop-wrapping | `until [ -f X ]; do sleep 5; done` | ALLOWED |
| control | `sleep 25; echo done`, `sleep 30`, `sleep 60`, `sleep 900; echo "15m elapsed"` | DENIED |
| control | `sleep 24` | ALLOWED |

B2 is the one the deny message itself names and does not enforce: "Do not chain shorter sleeps to work around this block."

B3 is the one that matters. A polling agent does not write `sleep 900` at the top of a command, it writes a loop. Measured: **488 polling-loop sleeps** (`until`/`while` + sleep), 294 on the main thread across 89 sessions, **486 of them ran**, 33 over 10 minutes, **15.9 hours of wall clock burned**. Median 11.0s, p90 402.4s, max 65.8m.

And the native block is not durable. Its gate is `function BL(){return I("tengu_amber_sentinel",!1)}`, a **remotely controlled statsig flag defaulting to false**. The same flag gates `Monitor.isEnabled()`. If Anthropic flips it, the block and the recommended alternative both vanish in the same instant.

### Goals

- Handoff: stop throwing `disable-model-invocation`, write to a path that survives the session, and carry the parts of Scott's shape that are missing (commits, PR URL, read-first paths).
- Handoff: a mechanism on the resume side, not a rule asking the model to remember.
- Sleep: cover the three bypass classes the native deny misses, in a way that never contradicts the deny it complements.
- Record every prescription this chunk does NOT build, with the measurement or citation that decided it. Nothing is silently dropped.

### Non-Goals

Each one is excluded for a named reason, not parked.

- **A `pr-babysitter` agent.** Excluded on our own scar tissue. `babysit/SKILL.md:31-32` forbids it in those words: "in the foreground. No background fleet, no per-PR agents, no cache, no sentinels, no scheduled ticks." `:134` forbids cadence. `:26-27` names the incident: "a sweep once spent 21 background sessions on PRs the user never asked about." `release-driver.md:3` already owns the async wait-for-merge gap, and `general:babysit-prs` is a third surface that already exists. Measurement agrees: main-thread PR polling fell **106 -> 249 -> 125 -> 30** Jun to Sep, a 76% drop Jul to Sep, as babysit adoption rose. Revisit condition: Scott overrules, in which case the same chunk must amend `babysit/SKILL.md:31-32` and `:134` or the setup contradicts itself.
- **Owning or replacing `resume-session`.** The baton at `docs/design/2026-09-13-setup-audit-program.md:60` says owning the resume side means bringing that external skill in-house. It is wrong. `HOME/.claude/skills/resume-session` symlinks to `Q00/ouroboros/skills/resume-session`, which is Ouroboros MCP session recovery (`ooo resume-session`, EventStore reads, `ouroboros run workflow --orchestrator --resume <session_id>`). Zero overlap with handoff docs. This doc corrects the baton.
- **In-repo ntfy on a silent turn.** Not buildable here, and not worth building anywhere on the measurement. See "ntfy is not buildable in this repo" below.
- **Rewriting `grill-me/SKILL.md:7`.** That file is a symlink into `mattpocock/skills`, a third-party repo. The fix is a manifest line, not an edit there.
- **A blanket waiting line in `phase-implementer.md`.** It has no polling surface: it implements one phase to completion and returns (`:9-13`, `:24-40`). Item 11 names a file with nothing to discipline.

## Proposed Solution

### Overview

Eight phases, one repo, one branch. Phase 0 is a zero-code spike. Phases 1 and 2 are the deterministic prerequisites the hook phases depend on; Phases 5, 6 and 7 are independent of the hook phases and are ordered last only because they are the smallest, not because anything blocks them.

| Phase | What | Always-on cost |
|---|---|---|
| 0 | Harness spike, zero code | 0 |
| 1 | Manifest repair: link `grilling`, drop the stale `handoff` entry | 0 |
| 2 | Handoff frontmatter, path, and shape | +~100 B (`WHOAMI.md`) |
| 3 | `handoff-guard.sh` grounding hook | 0 |
| 4 | Sleep-loop rule in `intent-guard.sh` | 0 |
| 5 | `silent_turn_reminder` env knobs | 0 |
| 6 | ToolSearch section in `general.md` | +~250 B |
| 7 | Waiting discipline in `release-driver.md`, with carve-outs | 0 |

### Item 10 is two inherited defaults, not two reversals

This matters for how it gets built. Reversing a decision needs Scott's ruling and an addendum capturing the road not taken. Correcting an inherited default does not.

Evidence that both are inherited, not decided:

- Upstream `mattpocock/skills/skills/productivity/handoff/SKILL.md:4` is `disable-model-invocation: true`. Ours is `:5`, same value.
- Upstream `:8`: "Save to the temporary directory of the user's OS - not the current workspace." Ours `:44`: "Save it to the session scratchpad or the OS temp directory, not the workspace, unless the user says otherwise."
- Chunk A's commit `5faca7d` message covers resume mode, blocker re-testing and write-mode probes. It does not mention either property.
- `docs/design/2026-09-13-enforcement-core.md` mentions handoff twice, both incidental (`:300` an `rm` rewrite test target, `:316` a guard false positive).

So: `disable-model-invocation` comes out, and the save path becomes a fixed repo path. The upstream reason for a temp path is that mattpocock's skill is write-only and has no receiver; a doc nobody is told to read is litter in a workspace. Ours has a receiver as of chunk A and is about to get a grounding hook, which inverts the argument: 95 sessions already open by pasting a handoff path, and a scratchpad path dies with the session.

**Path:** `docs/handoff/<branch>.md` in the repo being worked. Keyed on branch because that is what the resume side can compute without being told.

### The resume side is a grounding hook, not a trigger

Chunk E proved there is no `$.skill.*` API and no way to make a hook fire a skill (baton `:63`). A `UserPromptSubmit` hook can only inject `additionalContext`. So the artifact is named `handoff-guard.sh` and described as a grounding hook, the same shape F1 shipped as `session-recall-guard.sh`. Calling it a trigger would make its acceptance criterion unsatisfiable.

Two fires, both cheap and both mechanical:

1. **The prompt asks to resume from a handoff.** Not "contains a path matching `*handoff*.md`": this document's own filename matches that glob, so the naive predicate injects "invoke the handoff skill in resume mode" into any prompt that names this design doc. `session-recall-guard.sh:121` already separates a request from an incidental reference and that discrimination is carried forward here rather than re-derived.
2. **A handoff exists and is newer than the last commit.** `docs/handoff/<branch>.md` mtime vs `git log -1 --format=%ct`. Inject: read it first.

Fire 2 is why this is a hook and not the `interaction.md` line item 10 asks for. A hook can `stat` the file and compare; prose can only ask the model to remember to. That is "enforcement before prose" (baton `:23`) applied properly, and it costs **0 always-on bytes** instead of ~250.

### The sleep rule goes in `intent-guard.sh`, and it covers only what the harness misses

Three independent reasons it is needed at all, given the native deny exists:

1. The loop form is the form that occurs. 488 measured loop-sleeps, 486 ran, none were ever going to hit a statement-0 regex.
2. B2 is unenforced and the harness admits it in its own deny text.
3. `tengu_amber_sentinel` defaults to false and is remotely controlled. Our half is the durable half.

Why a rule inside `intent-guard.sh` rather than a new hook:

- The file's header states the policy (`:4-8`): one hook, several rules, because each hook pays a process spawn on **every** Bash call against a tree already at ~510 ms per call. A new hook costs that forever to catch a rare pattern; a new rule costs nothing.
- The parsing this needs exists only there: `stmts` over a `mask_heredoc | mask_comment` copy, `cmdword_is`, and the wrapper-mutation sweep. A naive regex on the raw command is exactly the false-positive class `lib.sh` exists to kill.
- `.otto.yml` wires `*-test.sh` by glob (`intent-guard-test.sh:4`), so fixtures ride for free. A new hook file would need an edit to the lint task's explicit FILES array.
- Registration cost: **zero** settings edits. `intent-guard.sh` is already 11th in the `PreToolUse(Bash)` chain.

**The rule, stated so it can be tested:**

**What the population actually looks like.** 800 loop+sleep Bash calls classified in round 1: `while true` / `while :` = **11**, for-loops = **483**, terminating `while`/`until` = **306**. And **367 of the 800 already set `run_in_background`**, which the rule allows unconditionally, so the addressable population is well under half the headline. The for-loop is the dominant form and the rule has to catch it or it catches nothing.

- **T1, the summed total: 25 seconds, denying at `>=` not `>`.** The native check is `if(g<Dpn)return null` with `var Dpn=25`, so it fires at 25 and bare `sleep 25` is denied, which the probe table confirms. An earlier draft said "exceeds 25", which let `echo A; sleep 25` through and defeated the stated match-`Dpn` rationale. Summed across statements (kills B1 and B2), multiplied by the loop bound where the bound is statically computable.
- **A statically computable bound is not only a literal word list.** It is: a literal list (`for i in 1 2 3`), a brace range (`for i in {1..30}`), and `seq` with literal arguments (`for i in $(seq 1 30)`). That last one is the measured dominant form, `for i in $(seq 1 30); do sleep 60; done`, and an earlier draft of this rule let it through by treating every command substitution as opaque. It is arithmetic, not a hard edge.
- **T2, the per-iteration cap, is withdrawn (panel round 2).** It priced the wrong quantity. Monitor's own description mandates the interval it would have denied: "Poll intervals: 30s+ for remote APIs (rate limits), 0.5-1s for local checks", and the `gh pr checks` example ten lines above that line sleeps 30 per iteration. T2 at 25 denied the harness's documented remote-poll pacing, denied this doc's own allow-control, and left total duration unpriced: `for i in {1..60}; do sleep 0.5; done` (30s, bounded) denied while `until ...; do sleep 0.5; done` (unbounded) allowed. The rule rewarded the less-bounded shape. One quantity is priced now, total foreground wait, and per-iteration interval is not the guard's business. Measured per-iteration sleeps are kept as the record of what T2 would have hit: median 20.0s, p90 45.0s, max 603.0s, 205 of 755 over 25s.
- DENY an unbounded loop that contains a sleep and contains no `break` token anywhere in its body (`while true; do sleep N; done`). Only 11 of 800, kept because it is the unambiguous case. The `break` carve-out is syntactic, not reachability: `while true; do true && break; sleep 1; done` and the `|| break` form that never terminates flatten to the identical `stmts` stream (`while true|do true|break|sleep 1|done`, probe re-run this round), so the operators that decide reachability are gone by the time the guard sees the command. A guard that denied every `while true` with a sleep would deny Monitor's own `gh pr checks` example, which is exactly that shape plus a break. Failing open on `break`-bearing unbounded loops is a stated, narrow exception to fail-closed, taken because the alternative contradicts the harness.
- ALLOW a `while`/`until` whose condition can terminate, at any interval. That is verbatim what the native deny message tells the model to write and what Monitor's own documented example uses (`until grep -q "Ready in" dev.log; do sleep 0.5; done`).
- ALLOW unconditionally when `run_in_background` is set, matching the native predicate exactly (`&& !n.run_in_background`), so the guard never contradicts the harness.
- Deny text reuses the harness's wording so the two read as one voice.

**What the existing parser can and cannot do, probed rather than asserted.** Round 1 verified command *recognition* and this doc then generalized that into bound computation, which round 2 rejected. Both halves re-run this round against `lib.sh` in the worktree:

- **Recognized, no `lib.sh` change needed:** `stmts` is NUL-separated, `cmdword_is sleep` returns true on `do sleep 30`, `cmdword_is true` on `while true`, `cmdword_is grep` on `until grep -q x f`. The ALLOW side's condition verb is decidable on the flat stream.
- **NOT available on the flat stream:** the bound and the sleep never share a statement, and a `seq` bound is detached from its loop entirely. `for i in $(seq 1 30); do sleep 60; done` yields `for i in $()` | `do sleep 60` | `done` | `seq 1 30`: the substitution is masked in place and re-emitted breadth-first at the end. Reachability is gone too (the `&& break` / `|| break` pair above). `stmts` is stateless per statement apart from `cwd_accumulates`, so nothing carries a loop context across the boundary.
- **So Phase 4 adds one thing:** a loop-span match over the masked raw command (`for <var> in <bound>; do <body> done`, and the `while`/`until` forms), which yields the bound text and the body text as one span. `stmts` and `cmdword_is` are then run *inside* the span to find and sum the sleeps. The bound is parsed from the span's own text, not from the flattened stream, which is what makes `$(seq 1 30)` computable. No `lib.sh` change; the new code is a rule-local span scan.
- **Unsupported loop syntax fails closed.** `for ((i=0; i<30; i++)); do sleep 1; done` flattens to `for` | `i=0` | `i<30` | `i++` | `do sleep 1` | `done`: it is neither one of the three bound forms nor an opaque-bound `for ... in`. It denies as an uncomputable bound rather than falling through to ALLOW.

**Known hard edge, narrowed.** A loop whose bound is genuinely opaque (`for f in $(cat list); do sleep 30; done`, a `$VAR` bound, a glob, a C-style `for`) cannot have its total computed. Same class as the variable-verb limit chunk B handed on. The rule fails closed on those, and on unbounded loops with no `break` in the body, and says so in the deny text rather than claiming a total it cannot compute. `seq` with literal arguments is explicitly NOT in this class. The one place this rule fails open is the `break`-bearing unbounded loop, for the reason stated above; the false-positive size of the opaque-bound class is **`[UNQUANTIFIED]`**, since sizing it needs a corpus re-measurement that round 2's scope forbade.

### Four of item 11's prescriptions are already shipped or not actionable

**"Pointing at Monitor and run_in_background": already shipped, verbatim.** The native message names both. Zero work beyond copying the sentence into our deny.

**"One status line per wake": already shipped natively.** `silent_turn_reminder` is a native attachment: `nJn = 5` turns of no user-visible output, `oJn = 3` max reminders per stretch, text `rJn` = "The user hasn't heard from you in a while..." It is fully env-tunable with zero code: `CLAUDE_CODE_SILENT_TURN_REMINDER`, `CLAUDE_CODE_SILENT_TURN_REMINDER_TURNS`, `CLAUDE_CODE_SILENT_TURN_REMINDER_TEXT`. This becomes a `settings.json` `env` change, conditional on Phase 0 proving the model-capability gate is satisfied for `opus[1m]`. It counts **turns, not minutes**, which the criterion must state.

**"The same line in babysit, release-driver, phase-implementer": 1 of 3, with a mandatory carve-out.**

- `release-driver.md` is the genuine target. Three poll sites, all vague, none naming a mechanism: `:156` (`Poll: gh pr checks`), `:167` ("Pace your polling so you're not spinning every few seconds"), `:186` ("Poll on a sane pace (roughly every 30s), not a spin").
- `babysit/SKILL.md:80-91` already solves it with `/loop` (CodeRabbit `/loop 2m`, CI `/loop 10m`). A second mechanism there is duplication. Cross-reference only.
- `phase-implementer.md` has no polling surface. Non-Goal, above.
- **The carve-out is not optional.** `review-panel.md:147` and `:151` forbid `run_in_background` for a measured reason: "`wait` is what keeps the namespace alive," a detached child loses the sandbox namespace. A blanket "use run_in_background" line contradicts chunk C's shipped design. The new line names that exception explicitly, and `review-panel.md:147,151` must be byte-identical after this chunk.

**"Teammate prompt templates load SendMessage once": the prescription is misaimed, the overhead it names is measured.** No "teammate prompt template" artifact exists in this repo; `SendMessage` appears only as prose in `review-panel.md:310-340`, `review-panel-notes.md:119-120`, `how-to-execute-a-plan/SKILL.md:90`, and a `settings.json:409` permissions entry. But the measurement is strong: `select:SendMessage` is issued as a standalone ToolSearch **362 times across 174 sessions**, and **173 of those 174 sessions then call it**. A 99.4% hit rate means the search is pure overhead, and it is rising (Jun 92, Jul 80, Aug 66, **Sep 125**). Editing a template that does not exist saves nothing. The only fix that would is un-deferring the tool, and **there is no user-settable way to do that for a built-in**. The deferral predicate is `vY(e)`: `if(e.alwaysLoad===!0)return!1; if(z(e))return!1; ... return e.shouldDefer===!0`. Both doors are shut:

- `alwaysLoad` is a tool-definition property whose only externally-writable form is the MCP `_meta` key `anthropic/alwaysLoad`. MCP tools only. `SendMessage` is a built-in.
- `z(e)`'s allowlist reads the statsig `tengu_non_deferrable_builtins` and served client data. Neither is reachable from `settings.json`. `nonDeferrableBuiltins`, `toolSearch` and `alwaysLoadTools` return zero hits in the binary.

The only lever is `ENABLE_TOOL_SEARCH`, already `"true"` in `settings.json` env. Setting it falsy un-defers **everything** and surrenders the context saving across every deferred tool, to kill 362 searches. No per-tool granularity exists in this version.

**So this is dropped as a build item and carried as one line of prose in Phase 6:** fold `SendMessage` into an existing `select:` call rather than issuing it standalone. That is a prose mitigation for a capability gap, and the doc says so rather than dressing it as enforcement.

### ntfy is not buildable in this repo, and the measurement says do not build it elsewhere either

Two independent reasons, either one sufficient.

**No hook event fires on elapsed time.** All 33 events in 2.1.276, extracted from the binary's `Bf` and `Lie` arrays (two identical copies, hook dispatcher and settings schema):

```
PreToolUse, PostToolUse, PostToolUseFailure, PostToolBatch, Notification,
UserPromptSubmit, UserPromptExpansion, SessionStart, SessionEnd, Stop,
StopFailure, SubagentStart, SubagentStop, PreCompact, PostCompact,
PreModelSwitch, PostModelSwitch, PermissionRequest, PermissionDenied, Setup,
TeammateIdle, TaskCreated, TaskCompleted, Elicitation, ElicitationResult,
ConfigChange, WorktreeCreate, WorktreeRemove, InstructionsLoaded, CwdChanged,
FileChanged, DirectoryAdded, MessageDisplay
```

Every one is edge-triggered by a discrete action. Three specific dead ends:

- `Notification` + `idle_prompt` is the wrong direction. The notifier is `class BZ`, arming method `#a()`, whose first statement is `if(h)return;` where `h = isLoading`. It arms only after `lastQueryCompletionTime` is set, meaning after the turn ENDS. Its message is literally "Claude is waiting for your input."
- `PostToolUse` is structurally blind to the case. Chunk E measured the silent window as a parent blocked inside an `Agent` call (baton `:63-64`: 102 of 124 gaps over 10 minutes were silent). During that window no tool resolves in the parent, so no `PostToolUse` fires.
- `Monitor` and `run_in_background` + `TaskCompleted` are model-driven or completion-driven, never wall-clock.

**The event is rare.** Over 13,651 main-thread turns in 3,139 sessions: median 18.4s, p90 77.3s, p99 239.0s. **25 turns over 10 minutes (0.18%)**, and 10 of those 25 contain an internal inactivity gap over 10 minutes with no tool call either, meaning an abandoned session rather than silent work. **15 genuine silent working turns in 101 days**, one per 6.7 days, and 5 of the 15 were opened by a skill-body injection rather than Scott typing.

The only working shape is an out-of-process systemd user timer over `~/.claude/projects/*/*.jsonl` mtimes, in `scottidler/dotfiles` beside `swap-watch.sh` (the one existing ntfy sender: `HOME/.local/bin/swap-watch.sh:4-5,55`). Different repo, different apply. Tracked as an operator step, not a phase. **Open question OQ1.**

### The ToolSearch rule is right, but the audit's reason for it is wrong

The audit: "12 of 18 failed searches dropped the prefix." Re-measured over 1,764 ToolSearch results: **19 zero-match failures (1.1%)**, and the cause split is 6 dropped the `mcp__server__` prefix, 6 used a full `mcp__` name for a tool that does not exist, 5 used a bare built-in that is simply not deferred, 2 were keyword queries. **Prefix-dropping is 6 of 19 (32%), not 12 of 18 (67%).** A prefix-only rule leaves 13 of 19 standing.

So the section states all three facts, not one:

- `select:` takes **exact** tool names, comma-separated. A bare query is a fuzzy search (`tool_search_tool_bm25`), a different code path from `select:` (`tool_search_tool_regex`).
- An MCP tool's exact name is `mcp__server__tool`.
- Names come from the deferred-tool list in the session's own system reminder, never from memory. This is the 6 + 5 = 11 of 19 the prefix rule would miss.

Grounded in the harness's own prompts, which use exactly this form in three places: memory tools (`load them with ToolSearch("select:${X}")`), the artifact tool (`query select:${Uh}`), and EndConversation (`Load the full guidance via ToolSearch("select:<name>")`).

Goes in `general.md`. **Not** a `rules/tools.md`: `~/.claude/tools.md` already exists and is Scott's custom-CLI inventory, and a name collision on two unrelated things is the exact cognitive dissonance `general.md` forbids.

**Handed on, out of chunk:** `select:mcp__atlassian__searchConfluenceUsingCql` failed while `select:mcp__claude_ai_Atlassian__...` succeeded. Two Atlassian servers were registered and the model picked the dead one. That is MCP hygiene, audit item 17, not F2.

### `/grilling` is confirmed dangling and confirmed harmless

- `grill-me/SKILL.md:7` is `` Run a `/grilling` session. `` Confirmed at that exact line. The skill is a symlink into `mattpocock/skills`.
- No `grilling` skill exists anywhere. `fd -i grilling` returns nothing.
- Impact re-measured: 24 prompts containing `/grill*` in 15 sessions, of which 4 slash invocations at position 0 and **6 skill-body loads**. The audit said 10 invocations. On all 6, **the model improvised and no error occurred**: 06-30 opened "Alright. Grilling mode. I'm not here to help you build it, I'm here to try to kill it before you spend two weeks on it."

So the fix ships because a dangling pointer is wrong, not because it costs anything. The doc says so rather than inheriting the audit's impact claim.

## Implementation Plan

#### Phase 0: harness spike, zero code
**Model:** opus
- Register a temporary `PreToolUse(Bash)` hook that denies unconditionally, run `sleep 26`, record whether the hook reason or the native `Blocked:` text comes back.
- Set `CLAUDE_CODE_SILENT_TURN_REMINDER_TURNS=2` in `settings.json` `env`, start a fresh session, grep its JSONL for `"type":"silent_turn_reminder"`.
- **Success criteria:**
  - Hook-vs-`validateInput` ordering is recorded in this doc as an observed fact, not an assumption.
  - The `silent_turn_reminder` attachment appears within 2 silent turns, or it does not and **Phase 5 is dropped with the measurement recorded**.
- **Result, 2026-09-20 (Claude Code 2.1.278), detail in the implementation notes:**
  - **Ordering: `validateInput` runs BEFORE the `PreToolUse` hook chain.** A scratch-project hook denying unconditionally returned its marker for `echo hi` and did NOT run for `sleep 26`, which came back with the native `Blocked: standalone sleep 26` text. So this rule's entire domain is what the native check lets through: B1, B2 and B3. T1's `>=` boundary is load-bearing for summed and multiplied totals, and moot for the bare statement-0 sleep the harness already refuses.
  - **`silent_turn_reminder`: inconclusive headless, Phase 5 NOT dropped.** The gate chain resolves in our favor (`Ee` is the main-session flag, `ute()` is focus mode, the env var short-circuits the capability lookup, and `Bash` is absent from the five-tool visible set `rjo`), but attachments are injected into the request rather than echoed to stdout and a `-p` run leaves no transcript to inspect. One interactive session decides it; until then Phase 5 is open, not dropped.

#### Phase 1: manifest repair
**Model:** sonnet
- Add `skills/productivity/grilling: ~/.claude/skills/grilling` to `manifest.yml`.
- Delete the stale `handoff` entry at `manifest.yml:13`, which would otherwise clobber the local skill Phase 2 edits.
- Scoped apply only. `rules/interaction.md:125-126` forbids an unscoped full apply.
- **Success criteria:**
  - `~/.claude/skills/grilling/SKILL.md` resolves after the scoped apply.
  - `~/.claude/skills/handoff/SKILL.md` is still a local regular file, not a symlink.
  - `git -C ~/repos/mattpocock/skills status --porcelain` is empty: the third-party repo is untouched.

#### Phase 2: handoff frontmatter, path, and shape
**Model:** sonnet
- Delete `disable-model-invocation: true` from `SKILL.md:5`.
- Replace the scratchpad/temp instruction at `:44` with the fixed path `docs/handoff/<branch>.md`.
- Add the three missing shape elements to write mode: commits, PR URL, read-first paths.
- Update the `handoff` entry in `WHOAMI.md`'s Vocabulary section, which currently claims the trigger is all that is owed.
- **Success criteria:**
  - `rg 'disable-model-invocation' HOME/.claude/skills/handoff/` returns nothing.
  - `rg -i 'scratchpad|OS temp|not the workspace' HOME/.claude/skills/handoff/` returns nothing. (F1's scar tissue: a reversed instruction survives in every place the file repeats it. Round 1 reversed one, round 2 found four survivors, round 3 found two more.)
  - Write mode names commits, PR URL and read-first paths.
  - The `handoff` entry in `WHOAMI.md`'s Vocabulary section no longer claims the resume trigger is all that is owed, and `WHOAMI.md`'s byte count is recorded before and after so AC5's 400-byte ceiling is measured rather than assumed.

#### Phase 3: `handoff-guard.sh` grounding hook
**Model:** opus
- **Depends on Phase 2.** The hook's whole output is "invoke the handoff skill in resume mode." Until `disable-model-invocation` is gone, that instruction is unfollowable and the hook would manufacture the exact error it is meant to prevent.
- New `UserPromptSubmit` hook, third in the chain after `inline-skill-tokens.py` and `session-recall-guard.sh`.
- Fire 1: the prompt **asks to resume from a handoff**, per `:116`. Not the bare glob: `*handoff*.md` matches this design doc's own filename, so "review docs/design/2026-09-18-handoff-and-waiting-discipline.md" would inject "invoke the handoff skill in resume mode". The predicate carries `session-recall-guard.sh:121`'s request-vs-reference discrimination, and the fixture set includes review requests, quoted examples, and prompts naming several paths.
- Fire 2: `docs/handoff/<branch>.md` exists and its mtime is newer than `git log -1 --format=%ct`.
- Silent, exit 0, no output, in three cases: cwd is not a git repo, HEAD is detached (no branch name to key on), or the repo has no commits (`git log -1` fails). Fire 1 still works in all three, since it reads only the prompt.
- `handoff-guard-test.sh` alongside it, picked up by the `*-test.sh` glob.
- **Deploy it, in this phase.** Hooks are not manifest-managed, so committing the file changes nothing: create the symlink `~/.claude/hooks/handoff-guard.sh -> <repo>/HOME/.claude/hooks/handoff-guard.sh`, and add the hook to the `UserPromptSubmit` array in `settings.json` (write it with the Write tool; that path is denied to Bash in the sandbox).
- **Success criteria:**
  - Set equality against a committed id list of corpus prompts: the hook fires on exactly the handoff-path openers in the list and on none of the 20 committed non-handoff controls. (F1's AC2 lesson: a regex selecting zero records "fires on every record it selects", so coverage percentages prove nothing.)
  - Both mtime directions asserted with fixtures: newer than HEAD fires, older is silent.
  - At least three fixtures fail against a deliberately broken predicate. Break the code to prove the test bites.
  - **Deployment asserted, not assumed.** `readlink ~/.claude/hooks/handoff-guard.sh` resolves into this repo, AND the hook's command string appears in `settings.json`'s `UserPromptSubmit` array (which held exactly two entries before this phase). `hooks-preflight.sh` cannot carry this: it exits 0 unconditionally and warns only through `additionalContext`, and linked does not mean registered.

#### Phase 4: sleep-loop rule in `intent-guard.sh`
**Model:** opus
- New rule implementing the DENY/ALLOW shape above, reusing `stmts`, `cmdword_is` and the heredoc mask, plus the rule-local loop-span scan the parser section specifies.
- **Wire `run_in_background` end to end.** `grep -n run_in_background intent-guard.sh lib.sh intent-guard-test.sh` returns **zero hits in all three** (re-run this round). The unconditional ALLOW and the allow-control both depend on the field, so the hook must read `tool_input.run_in_background` and `run()` at `intent-guard-test.sh:19`, which builds `tool_input:{command:$c}` only, must be able to supply it. Wiring is a step, not an assumption.
- Correct the stale RULES block at `intent-guard.sh:22-25`, which names GH-WRITE and DELETE-OUT while the file implements six (INGEST, POST, PUBLIC-REPO and LN are the four it omits, per the rule names asserted in `intent-guard-test.sh`).
- **Success criteria:**
  - All three bypass classes deny: `echo A; sleep 26` (B1), `sleep 24; sleep 24` (B2), and for B3 the three bound forms plus the unbounded case: `for i in 1 2 3; do sleep 30; done`, `for i in {1..30}; do sleep 60; done`, **`for i in $(seq 1 30); do sleep 60; done`** (the measured dominant form, 483 of 800), and `while true; do sleep 30; done`.
  - **Wrapper sweep, with the loop exclusion stated.** B1 and B2 ride all 18 `runwrapped` spellings. Loop fixtures ride **14 of 18**: `for` is a reserved word, so `timeout 5 %s`, `nohup %s`, `\%s` and `"%s"` produce strings bash cannot parse, verified by `bash -n` over `wrap_shapes` (`total=18 invalid=4`). Asserting deny on an unparseable string tests nothing, so the matrix skips those four for compound-command fixtures rather than passing vacuously.
  - **Cardinality is proven, not assumed.** Paired fixtures per bound form where the multiplication alone decides, since every earlier fixture carried a per-iteration sleep already over the old T2 and so passed against an implementation that computed no bound at all: `for i in $(seq 1 30); do sleep 0.5; done` (15s) ALLOWS and `for i in $(seq 1 60); do sleep 0.5; done` (30s) DENIES; the same pair in literal-list and brace-range form. A build that skips the bound fails the allow half or the deny half.
  - **Sleeps sum inside one iteration too.** `for i in 1 2 3; do sleep 4; sleep 5; done` totals 27 and denies, so B2 cannot be rebuilt inside a loop body.
  - **Uncomputable bounds fail closed:** `for f in *.txt; do sleep 30; done`, `for f in $(cat list); do sleep 30; done` and `for ((i=0; i<30; i++)); do sleep 1; done` all deny.
  - **The `break` carve-out is asserted in both directions:** `while true; do sleep 30; done` denies, `while true; do check && break; sleep 30; done` allows.
  - At least five allow-controls hold, drawn from the harness's own recommended patterns so the guard never contradicts the deny it complements: `until grep -q "Ready in" dev.log; do sleep 0.5; done`; the `gh pr checks` loop from Monitor's description, whose `sleep 30` is now allowed because the loop terminates and no per-iteration cap exists; bare `sleep 24`; any command with `run_in_background` set; and a heredoc whose BODY contains the word `sleep` (chunk D's heredoc false-positive class).
  - `intent-guard-test.sh` fixture count rises and `fail=0`.

#### Phase 5: `silent_turn_reminder` env knobs, no code
**Model:** sonnet
- Conditional on Phase 0's second criterion passing.
- Add `CLAUDE_CODE_SILENT_TURN_REMINDER_TURNS` to `settings.json` `env`, with the chosen value justified against the native default of 5.
- **Success criteria:**
  - A fresh session's transcript shows the attachment at the configured turn count, not the default.

#### Phase 6: ToolSearch section in `general.md`
**Model:** sonnet
- The three-fact section above, citing the harness's own usage so a future reader can re-verify.
- Plus one line: fold a known-needed tool like `SendMessage` into an existing `select:` call rather than issuing it standalone. Prose mitigation for a capability gap, labelled as such.
- **Success criteria:**
  - The section states all three facts (exact names, `mcp__server__tool` form, names come from the session's deferred list), not the prefix alone.
  - The `SendMessage` line is present and is marked as guidance, not enforcement.
  - Byte delta recorded in this doc against the measured prefix.
- **Result, 2026-09-20:** `HOME/repos/.claude/rules/general.md` new `## ToolSearch` section states all three facts and closes with a `SendMessage` line explicitly labelled "Guidance", not enforcement. `wc -c`: 5,285 -> 5,649, **+364 bytes**. Combined with Phase 2's +138, the chunk is **+502 against the 400-byte ceiling, 102 bytes over**; see AC5 below for the full accounting and the tradeoff between the citation's re-verifiability and the byte budget.

#### Phase 7: waiting discipline in `release-driver.md`
**Model:** sonnet
- Replace the vague pacing at `:167` and `:186` with **`run_in_background` plus a terminating `until` loop** named explicitly. Not `Monitor`: `release-driver.md:4` is `tools: Bash, Read, Grep, Glob`, so that agent cannot call it, and naming a tool it does not have is an instruction it cannot follow.
- Add the `review-panel.md` carve-out by name to the new line.
- Cross-reference `/loop` in `babysit/SKILL.md:80-91` rather than adding a second mechanism there.
- **Success criteria:**
  - `release-driver.md:167` and `:186` name `run_in_background`, and name no tool absent from that agent's `tools:` line.
  - `review-panel.md:147` and `:151` are byte-identical after the phase.
  - `phase-implementer.md` is unchanged.

## Acceptance Criteria

Every criterion's literal command was run against current `main` before this doc was called ready, and what it returned is recorded under it.

- [ ] **AC1.** Invoking `Skill(handoff)` returns the skill body, not `cannot be used with Skill tool due to disable-model-invocation`.
  - *Observed on main (2026-09-18):* FAILS as designed. The literal invocation returned `Skill handoff cannot be used with Skill tool due to disable-model-invocation. Ask the user to run /handoff themselves`. That is the 7th recorded occurrence on the strict basis and the third today.
- [ ] **AC2.** `handoff-guard.sh` fires on exactly the committed handoff-opener id list and on zero of the 20 committed controls, asserted as set equality, not a coverage percentage.
  - *Observed on main:* not runnable. The hook does not exist until Phase 3, and the id list is committed by Phase 3. Named here rather than assumed.
- [ ] **AC3.** All three sleep bypass classes deny (18 wrapper spellings for the simple-command fixtures, the 14 parseable ones for the loop fixtures), both halves of each cardinality pair behave (30 x 0.5 allows, 60 x 0.5 denies), all five allow-controls pass, and `bash HOME/.claude/hooks/intent-guard-test.sh` ends `fail=0` with a fixture count above today's.
  - *Observed on main (2026-09-18):* `pass=187 fail=0`. So the phase must raise 187, and `fail=0` alone proves nothing.
- [ ] **AC4.** `git -C ~/repos/mattpocock/skills status --porcelain` and `git -C ~/repos/Q00/ouroboros status --porcelain` are both empty.
  - *Observed on main (2026-09-18):* both empty. This is a hold-the-line criterion, so it must still be empty after Phase 1 and Phase 7.
- [ ] **AC5.** The always-on prefix grows by no more than 400 bytes over its pre-F2 value, on the rules-plus-memory-files basis stated below.
  - *Observed on main (2026-09-18):* 64,166 bytes (51,485 in 14 rules + 12,681 in four memory files). Ceiling for this chunk: 64,566.
  - *Observed after Phase 2 + Phase 6 (2026-09-20):* Phase 2's `WHOAMI.md` +138 (2,887 -> 3,025, per the Phase 2 commit `24a9403`). Phase 6's `general.md` +364 (5,285 -> 5,649, `wc -c` before/after the ToolSearch section edit). Combined **+502**, which is **over the 400 ceiling by 102 bytes** (64,668 against the 64,566 cap). Recorded here rather than papered over: fitting the three required ToolSearch facts plus a re-verifiable citation to the harness's own `select:` usage (memory tools, artifact tool, `EndConversation`) into fewer bytes was tried through several compressions (649 -> 490 -> 402 -> 379 -> 364); 364 is what a future reader can still verify against. Phases 1, 3, 4, 5 and 7 are asserted to add zero (Phase 4's confirmed above at AC3; Phase 4 touches no always-on file). Whether the 102-byte overage is acceptable, or the ToolSearch section should drop its citation to close the gap, is Scott's call, not the phase implementer's.
- [ ] **AC6, both directions.** `rg -i 'scratchpad|OS temp|not the workspace' HOME/.claude/skills/handoff/` returns nothing, over the whole skill directory rather than the one line Phase 2 edits, AND `rg -F 'docs/handoff/' HOME/.claude/skills/handoff/` returns at least one hit. The negative alone is satisfied by deleting the save instruction entirely. Baseline re-run this round: the negative currently hits `SKILL.md:44`, so it starts red and can go green only by a rewrite.
  - *Observed on main (2026-09-18):* returns `SKILL.md:44`. This is the criterion the Risks table's mitigation column points at, so it is numbered here rather than living only inside a phase.

## Blast radius and ship order

- **One repo**, `scottidler/claude`. No cross-repo write.
- `~/.claude/skills`, `~/.claude/agents` and `~/.claude/output-styles` are **directory** symlinks into this repo (`manifest.yml:5-7`), so a skill or agent edit, and a NEW skill or agent file, go live on commit with no apply step.
- **`~/.claude/hooks` is NOT one of them.** `grep -n hooks manifest.yml` returns nothing: hooks are not manifest-managed at all. `~/.claude/hooks` is a plain directory holding one symlink per hook file, created outside any managed path. So **an existing hook's edits go live on commit, but a NEW hook file does not exist to the harness until two separate steps run**: a symlink is created in `~/.claude/hooks/`, and the hook is registered in `settings.json`. Only Phase 3 adds a new hook file, and both steps belong to it. Chunk B learned this exact lesson once already (baton `:100`: four ported guards failed open through the symlink path until a later phase named it).
- `manifest.yml` changes need a scoped apply.
- **Ship order forced, twice:**
  - Phase 1 before Phase 2, or the manifest apply clobbers the local handoff skill Phase 2 just edited. `manifest.yml:13` still links `mattpocock/skills`' `skills/productivity/handoff` over `~/.claude/skills/handoff`, which is now a local file.
  - Phase 2 before Phase 3, or the hook instructs the model to invoke a skill that throws.
- `mattpocock/skills` and `Q00/ouroboros` are read-only reach, asserted by AC4.
- `scottidler/dotfiles` is reached only if OQ1 resolves in favor of the ntfy watcher, which is a separate repo, separate apply, and not a phase here.

### Always-on prefix, and a correction to F1's figure

Two different bases were in use, and both numbers are right on their own basis:

- **Rules only:** 13 always-on rules totaled 50,738 bytes when F1 measured (`docs/design/2026-09-17-session-recall.md:190`). With `recall.md` (747) now landed, 14 rules total **51,485**.
- **Rules plus the four memory files:** `HOME/.claude/CLAUDE.md` 5,707 + `WHOAMI.md` 2,887 + `tools.md` 3,349 + `HOME/repos/CLAUDE.md` 738 + 51,485 = **64,166**.

**This doc uses the 64,166 basis** because that is what actually enters the context window: a byte of `WHOAMI.md` costs the same as a byte of `taste.md`. F1's 50,738 is not wrong, it is rules-only and predates `recall.md`. The reconciliation closes to the byte with no residual: 50,738 + 747 (`recall.md`) + 12,681 (four memory files) = 64,166. No path-scoped file is double-counted in either figure.

**One correction F1 owes, recorded here.** `docs/design/2026-09-17-session-recall.md` and the baton's F1 log entry both say F1 was "+1,200 bytes of always-on with no offset." On F1's own rules-only basis the addition was `recall.md` at **747**. On the full basis it was **+2,539**, because the WHOAMI Vocabulary block took that file from 1,095 to 2,887 (`git show 7bcba8c~1:HOME/.claude/WHOAMI.md | wc -c` -> 1,095; current -> 2,887). WHOAMI is always-on and sits outside F1's stated basis, so F1 under-reported its own delta by roughly half.

F2's projected delta: **+~350 bytes**, from two phases, not one.

- **Phase 6, ~250 B** in `general.md`: the ToolSearch section plus the `SendMessage` line.
- **Phase 2, ~100 B** in `WHOAMI.md`: rewriting the handoff Vocabulary entry. `WHOAMI.md` is 2,887 of the counted 64,166, so this is not free. Round 1 caught this doc faulting F1 for under-reporting exactly this file and then omitting it from its own projection. AC5's ceiling is set at 400 to cover both.
- Phases 1, 3, 4, 5 and 7 add zero. Phase 3's hook carries the handoff instruction through `additionalContext` instead of the ~250-byte `interaction.md` line item 10 asked for, so the resume side costs nothing.

Against F1's actual +2,539 on this basis.

**One offset candidate, flagged not planned.** `rules/interaction.md:128-134`, "Don't idle-poll a stalled subagent", 387 bytes. Once Phase 4's rule is mechanical and Phase 7's line is in `release-driver.md`, the FIRST sentence is duplicated by enforcement. The SECOND sentence is about per-phase check-ins during an approved plan, which no hook covers and no phase here touches. This is a claim to verify in review, not a planned deletion: F1's round 1 overturned exactly this kind of deletion claim, and rounds 1 through 3 then spent most of their findings chasing the reversal through six surviving sites. If taken, it is a sentence-level edit with the second sentence preserved verbatim.

## Resolved Decisions

- **2026-09-18. `disable-model-invocation` and the temp path are inherited, not decided.** Both are byte-equivalent to `mattpocock/skills/.../handoff/SKILL.md:4,8`. Chunk A's `5faca7d` and `docs/design/2026-09-13-enforcement-core.md` are silent on both. So Phase 2 corrects a third-party default rather than reversing a Scott ruling, and needs no addendum.
- **2026-09-18. `pr-babysitter` is a RECOMMENDED Non-Goal, awaiting Scott.** Grounds: `babysit/SKILL.md:31-32`, `:134`, `:26-27`, `release-driver.md:3`, and a 76% Jul-to-Sep fall in main-thread polling. Recorded as the author's recommendation, not a closed decision: it drops something the audit prescribed, so it is Scott's to confirm or overrule.
- **2026-09-18. The baton's `:60` note about `resume-session` is wrong** and gets corrected in this chunk.
- **2026-09-18. "Teammate prompt templates load SendMessage once" is dropped**, not deferred. The overhead is measured and unarguable (362 solo searches, 99.4% hit rate), but `alwaysLoad` is MCP-server-scoped and `SendMessage` is built-in. There is nothing to build. Revisit condition: Anthropic exposes a per-tool deferral setting.
- **2026-09-18 (panel round 1, one seat). Four must-fix and three cheap wins folded, all verified before folding.** The load-bearing one: Phase 4's rule as drafted denied the rare shape and missed the measured one. Of 800 loop+sleep calls, `while true` is 11 and for-loops are 483, and the dominant `for i in $(seq 1 30); do sleep 60; done` satisfied neither DENY clause. `seq` with literal arguments is arithmetic, not an opaque bound, so it moved out of "known hard edge" and into the rule. A second threshold (T2, per-iteration) was added because "a small per-iteration sleep" was untestable.
- **2026-09-18. Round 1 was a one-seat round, not a panel.** Architect rc=0; staff-engineer rc=124, both 10m attempts spent. A sandbox network denial to the Gemini API host killed architect attempt 1 and codex's alongside it; the allowlist fix rescued architect only. Per `review-panel.md:197` a timeout is reported as failed, never counted as a review. So this doc has had **one** cross-model seat, and that gap is stated rather than papered over.
- **2026-09-18 (panel round 2). `Dpn = 25` is now verified at the symbol level**, closing round 1's UNVERIFIED: `var Dpn=25` and `if(g<Dpn)return null` read directly from the 2.1.276 binary, along with `n[0]` as the only element tested, which confirms statement-0-only.
- **2026-09-20 (panel round 2, fold completed). All 8 must-fix and all 7 cheap wins are folded**, each re-verified here before folding rather than taken from the synthesis. The first fold pass on 09-18 took M1, M2, M6, M7, M8's primary site and C5, then stopped; this pass took the rest.
  - **T2 is withdrawn, which is the load-bearing change (M5 plus the ruled asymmetry).** A per-iteration cap priced the wrong quantity: Monitor's own description says "Poll intervals: 30s+ for remote APIs (rate limits), 0.5-1s for local checks" and its `gh pr checks` example sleeps 30, so T2 at 25 denied both the harness's instruction and this doc's own allow-control, while a bounded `for i in {1..60}; do sleep 0.5; done` (30s) was denied and an unbounded `until` loop at the same interval was allowed. One quantity is priced now: total foreground wait. OQ2 collapses from two thresholds to one.
  - **`:148`'s "the parser needs no `lib.sh` change, verified" is replaced with a probe (M4).** Re-run against `lib.sh`: `for i in $(seq 1 30); do sleep 60; done` flattens to `for i in $()` | `do sleep 60` | `done` | `seq 1 30`, and `while true; do true && break; sleep 1; done` and its `|| break` twin flatten identically. Bound-to-sleep association and exit reachability are both absent from the flat stream. Phase 4 now specifies a rule-local loop-span scan and the doc no longer claims the flat stream is enough.
  - **The unbounded-loop DENY gained a `break` carve-out, failing open on one narrow class, stated.** Denying every `while true` carrying a sleep would deny Monitor's own documented `gh pr checks` pattern, and reachability is not computable, so the carve-out is syntactic presence of `break`.
  - **Three criteria that could pass against an absent implementation are now two-sided** (M3, C7, and the wrapper sweep): paired cardinality fixtures where the multiplication alone decides (30 x 0.5 allows, 60 x 0.5 denies), AC6 paired with a positive `docs/handoff/` assertion, and the loop fixtures restricted to the 14 of 18 wrapper spellings a reserved word can ride (`bash -n` over `wrap_shapes`: `total=18 invalid=4`).
  - **Two wiring and citation defects (C3, C6).** `grep -n run_in_background intent-guard.sh lib.sh intent-guard-test.sh` returns zero hits in all three, so Phase 4 carries the plumbing as a step. `release-driver.md:4` is `tools: Bash, Read, Grep, Glob`, so Phase 7 names `run_in_background` rather than `Monitor`, which that agent cannot call.
  - **M8's survivor.** Round 2 fixed the fire-1 predicate at `:116` and left `:260` still reading "prompt contains a path matching `*handoff*.md`". That is the F1 class this doc quotes against itself, caught on its own doc, one round later. Both sites now agree.
- **2026-09-18. Item 11's seven prescriptions, dispositioned.** Built: the sleep-bypass rule (1), the `release-driver.md` line (2, one of the three named files), the ToolSearch section (4), the `silent_turn_reminder` knobs (6). Dropped: `pr-babysitter` (3), SendMessage templates (5), ntfy (7). Nothing is carried forward unresolved.

## Alternatives Considered

### Alternative 1: a standalone `sleep-guard.sh` hook
- **Why not:** one more process spawn on every Bash call, forever, against a tree already at ~510 ms per call, to catch a rare pattern. `intent-guard.sh:4-8` states the one-hook-many-rules policy for exactly this reason, and the heredoc/wrapper parsing the rule needs exists only there.

### Alternative 2: build item 11's sleep deny as prescribed, ignoring the native one
- **Why not:** the native deny has been live since 2026-06-22 and its text already names Monitor and `run_in_background`. Two independent denies with different wording read as two competing instructions. Ours covers only the three bypasses and reuses the native wording.

### Alternative 3: an `interaction.md` line for the handoff resume side
- **Why not:** prose can only ask the model to remember to compare mtimes. A hook can `stat`. Same outcome, 250 fewer always-on bytes, and it is actually enforced.

### Alternative 4: a prefix-only ToolSearch rule, as the audit prescribed
- **Why not:** measured, prefix-dropping is 6 of 19 failures. The rule would leave 13 of 19 standing.

## Technical Considerations

### Dependencies
- Claude Code 2.1.276. Two findings depend on statsig flags outside our control: `tengu_amber_sentinel` (gates both the native sleep deny and `Monitor`) and `tengu_hushed_lark` (gates `silent_turn_reminder`). Both are recorded as observed-on state, not guarantees.

### Performance
- Phase 4 adds one rule to an already-spawned hook: no new process per Bash call.
- Phase 3 adds a third `UserPromptSubmit` hook: one spawn per human prompt, the same cost F1 accepted for `session-recall-guard.sh`.

### Security
- The handoff path moves into the repo, so handoff docs become commit candidates. `SKILL.md:51` already carries a redaction instruction; Phase 2 keeps it and the path change makes it load-bearing rather than advisory.

### Testing Strategy
- Every hook phase ships a `*-test.sh` picked up by the `.otto.yml` glob, with break-the-code evidence.
- Phase 4's denies are asserted through `runwrapped`'s wrapper spellings, per chunk B's rule that a parser change needs a shape-mutation sweep and not only the pre-existing matrix: all 18 for the simple-command fixtures, 14 for the loop fixtures (the four spellings a reserved word cannot ride, measured with `bash -n`).

### Rollout Plan
- Branch, one commit per phase, `otto ci` green per phase. Symlinked artifacts go live on commit; `manifest.yml` needs the scoped apply in Phase 1.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Phase 4's rule false-positives on a legitimate wait loop | Med | High | Five allow-controls drawn from the harness's own recommended patterns, plus the heredoc-body control; T2 withdrawn, so a polite 30s remote poll is no longer denied |
| The opaque-bound fail-closed class denies more than it should | Med | Med | Size is `[UNQUANTIFIED]`, deliberately: it needs a corpus re-measurement. Phase 4 lands the deny text naming the shape, and the class is re-measured before any widening |
| `tengu_amber_sentinel` flips off, taking Monitor with it | Low | Med | Our rule is the durable half; its deny text names `run_in_background`, which is not flag-gated |
| Phase 2's reversed instruction survives somewhere in the file | Med | Med | AC6's `rg` assertion over the whole skill directory, not the one line |
| Phase 1's apply clobbers the local handoff skill | Med | High | Ship order: Phase 1 deletes the stale manifest entry before Phase 2 edits the file; AC asserts it is still a regular file |
| Handoff docs in the repo leak secrets | Low | High | `SKILL.md:51` redaction instruction retained and promoted |

## Open Questions

- [x] **OQ1. ntfy.** Does Scott want the out-of-process dotfiles watcher at all, given 15 genuine silent turns in 101 days and no in-repo mechanism? Default: no. **Closed 2026-09-20, Addendum A.1: no.**
- [x] **OQ2. One sleep threshold, T1.** Round 2 withdrew T2 (`:142`), so the only number left is T1, the total foreground wait summed across statements and multiplied by a computable loop bound. Recommended **25s**, matching the native `Dpn = 25` so the two guards agree at the boundary and the deny can speak with one number. Scott's call is the value alone. **Closed 2026-09-20, Addendum A.2: 25s.**
- [x] **OQ3. `grilling` model-invocability.** Linking it makes it model-invocable, unlike `grill-me`, since upstream has no `disable-model-invocation`. Accept, or add a local override? **Closed 2026-09-20, Addendum A.3: accept, no override.**

## Addendum A: Scott's rulings, 2026-09-20

All three open questions closed on Scott's call, each taking the author's recommendation. Recorded per decision with the grounds it rests on and what reversing it costs, so a reversal is an edit with a known blast radius rather than a re-derivation.

- **A.1. No ntfy watcher.** Item 11's seventh prescription is dropped, not deferred. Grounds: 15 genuine silent turns in 101 days, and `silent_turn_reminder` (Phase 5) already covers the in-repo case with zero code. The watcher would live in `scottidler/dotfiles`, a second repo and a second apply, for a rate under one event a week.
  - **To reverse:** a new phase in a later chunk, in the dotfiles repo, not an edit here. Nothing in Phases 0-7 depends on this. Revisit condition: the silent-turn rate rises above the `silent_turn_reminder` attachment's reach, measured, not felt.
- **A.2. T1 = 25 seconds.** The single threshold, summed across statements and multiplied by a statically computable loop bound, denying at `>=` not `>`. Grounds: the native deny is `var Dpn=25` with `if(g<Dpn)return null`, so 25 is where the harness already fires, and a different number would make the two guards disagree at the boundary for no gain.
  - **To reverse:** one constant in the Phase 4 rule plus the fixture arithmetic that straddles it. The cardinality pairs are written as 15s allow / 30s deny, so any T1 in `(15, 30]` keeps them valid; a value outside that range needs the pairs re-chosen. AC3 and `:140` both name the number.
- **A.3. `grilling` ships model-invocable, no local override.** Phase 1 links the upstream skill as-is. Grounds: upstream carries no `disable-model-invocation`, the defect being fixed is that `grill-me/SKILL.md:7` invokes a skill that is not installed (10 user hits), and a local override would re-introduce the exact property Phase 2 is removing from `handoff` for being an unexamined third-party default.
  - **To reverse:** a local `disable-model-invocation: true` in a copy of the skill, which turns a manifest link into a maintained fork. Revisit condition: the model invokes `grilling` unasked and that is measured as noise, not anticipated as a risk.

## Handed on, out of chunk

- **Two Atlassian MCP servers, one dead.** `select:mcp__atlassian__searchConfluenceUsingCql` failed while `select:mcp__claude_ai_Atlassian__...` succeeded, in the same corpus. That is 6 of the 19 ToolSearch failures and no rule can fix it. Audit item 17, MCP hygiene.
- **The uncommitted `intent-guard.sh` PUBLIC-REPO range fix** sitting on branch `session-recall` (20 lines, fresh-branch push walked from the root and denied `scottidler/second-brain` over a 5.5 MB icon already on `origin/main`). It has no test fixture. Chunk D territory, not F2's.
- **`bump` carries `release` and `finish` subcommands** duplicating `~/.claude/bin/release`, carried forward from chunk E's log and still unassigned.

## References

- Baton: `docs/design/2026-09-13-setup-audit-program.md`
- Dense audit report: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/
- F1: `docs/design/2026-09-17-session-recall.md`
- Chunk A (handoff skill origin): `docs/design/2026-09-13-enforcement-core.md`, commit `5faca7d`
- Upstream handoff: `~/repos/mattpocock/skills/skills/productivity/handoff/SKILL.md`
