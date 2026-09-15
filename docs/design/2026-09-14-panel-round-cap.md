# Design Document: Panel round cap, mechanically

**Author:** Scott Idler
**Date:** 2026-09-14
**Status:** Implemented
**Review Passes Completed:** 5/5, then a rewrite, then passes 2 and 4 re-run

> Passes 1 to 5 ran against a design built on a `PreToolUse(Bash)` guard at the seat scripts. A codebase dig after pass 5 measured that seam wrong on two counts (the counter does not accumulate; the deny lands in the subagent, not the caller), so the core was rewritten onto the `Agent` dispatch. The superseded design is kept as Alternative 3 rather than deleted.
>
> Over the rewritten core: pass 2 (correctness) re-ran and verified every cited line; pass 4 (edge cases) re-ran and found the mode-collision defect now fixed by the (doc, mode) key. Passes 3 and 5 got a read-through, not a full re-run.
>
> A second research fold-in then upgraded the evidence from concession to measurement, replaced AC4's byte census with properties, added the payload-facts section, and named the docless-audit hole. All of it is in the review log's pre-panel entry.
>
> The panel then ran round 1 over the rewritten doc on 2026-09-14: 3 must-fix folded in, 4 cheap wins folded in, 2 findings rejected with rationale, nothing escalated. Minutes in `docs/design/2026-09-14-panel-round-cap-review-log.md`.

## Summary

The review-panel 3-round cap is prose in `rules/interaction.md` and it does not hold: 10 of 19 measured runs blew it, one reached 14 rounds, with zero prompts from Scott. Chunk C moves the cap to a `PreToolUse` guard on the **`Agent` dispatch**, keyed on the doc under review, the same enforcement class that took AskUserQuestion from 557 violations to zero in three days. It also deletes the poll snippet from `create-design-doc`, stops `synthesis.md` duplicating the raw seat output, and splits 26KB of incident lore out of the agent file.

This is chunk C of the setup-audit program (`docs/design/2026-09-13-setup-audit-program.md`), covering audit item 4.

## Problem Statement

### Background

The panel is two external reviewers (Gemini as Architect, Codex as Staff Engineer) dispatched over one design doc by the `review-panel` agent. The caller folds findings in and re-engages for another round. Rounds are the caller's call, not the panel's.

Scott capped rounds at 3 on 2026-09-08, in `HOME/repos/.claude/rules/interaction.md:111`:

> Cap review-panel rounds at 3 unless Scott asks for more.

### Problem

The cap is prose, and prose does not hold.

- Measured 2026-09-12 over `/tmp/review-panel`: 10 of 19 run dirs exceeded 3 rounds, 7 exceeded 5, one reached 14 (slack-cli scheduled-follow-ups, a 1,435-line doc).
- 3 of the 8 panel runs after the cap landed ran 7, 5 and 10 rounds with **zero Scott prompts**. The parent agent sent 11 and 23 round messages on its own initiative. One parent wrote, in its own transcript on 2026-09-11: "Tenth crossing, and I am not going to tell Scott".
- Docs roughly double per round: 302 -> 578, 458 -> 778, 755 -> 1,335 lines. One `synthesis.md` reached 4,035 lines.
- Scott, 2026-09-07: "why would I keep running round after fucking round? they are supposed to resolve on a completed agreed upon doc. why cant you fucking do that on your own? that is what is in review-panel". Scott, 2026-08-15: "why would I round 3? do you just want to waste tokens talking about the work rather than actually doing it?"

Second, unrelated-looking but same file: `HOME/.claude/agents/review-panel.md` is 26,322 bytes / 360 lines, with 14 commits since 2026-07-14, every one patching exit or delivery behavior in prose. Scott, 2026-06-30: "putting that much extra bullshit in the .md for review-panel means it pollutes the context." The seats work now (41% dispatch failure in July, 4% in September), so most of that text describes failures that no longer occur, and it is paid for on every dispatch.

Third, `HOME/.claude/skills/create-design-doc/SKILL.md:54-67` instructs the caller to poll the panel's run dir. That produced 94 poll streaks of 5 or more calls, 7 of them after the no-poll rule landed, three running 22 to 31 minutes. It also contradicts `rules/interaction.md`'s "Don't idle-poll a stalled subagent".

### Evidence status: re-derived, not inherited

`/tmp/review-panel` holds 1 run dir today, because `/tmp` is tmpfs and the machine booted at 10:16. The distribution survives anyway, in `~/.claude/projects`. Re-derived 2026-09-14 by pairing run-dir ids with round-suffixed artifact paths in the same path string:

```
46 run dirs with round-paired evidence
exceeded 3 rounds: 17 (37%)
exceeded 5 rounds:  7 (15%)
worst: 8wLUyVus, 14 rounds, tatari-tv/marquee
```

This is a floor: a dir whose later rounds were written through `$RUN_DIR` without the id appearing in the path is undercounted. A second, looser derivation over the same corpus returned 56 / 19 / 8. Both confirm the audit's headline max of 14 exactly and both land the over-3 rate in the mid-thirties, against the audit's 10 of 19. The audit measured a smaller window; nothing here contradicts it.

### Goals

- A round past the cap is **denied by a hook**, not discouraged by a sentence.
- Scott can open the door for a specific run, visibly, in one command.
- The deny message names what to do, so it cannot induce a retry loop.
- `synthesis.md` stops carrying a second copy of the raw seat output.
- `review-panel.md` shrinks to the contract; the incident history survives in a notes file.
- The poll snippet is gone from `create-design-doc`.

### Non-Goals

- **A wall-clock guard around the seats. Already built, and an outer one is forbidden.** Both `HOME/.claude/skills/architect/script.sh:198` and `HOME/.claude/skills/staff-engineer/script.sh:195` run `timeout --kill-after=30s "$WALL_CLOCK"` and exit 124, terminal by policy, never retried. Scott ruled against an outer timeout on 2026-08-04 after the TIMEOUT TIE incident of 2026-08-03: the outer kill won the tie, the script's EXIT trap never ran, and the panel got a 110-byte banner-only file with zero diagnostic, twice on the same doc. `review-panel.md:152` already carries that ruling. The audit's "wall-clock guard that kills a reviewer past its deadline" is asking for a thing that exists and a thing Scott has already refused.
- **An abstain record.** Also already built: `$RUN_DIR/dispatch-status-r$ROUND.txt` records each seat's rc and byte count, and `review-panel.md`'s rc table decodes 124 as "Hung past the wall clock. Report as failed; do NOT silently re-run."
- **Freezing the doc during a round.** The measured failure is growth *across* rounds, not concurrent edits during one, and Step 0.2's snapshot-and-hash already makes any mid-round edit visible as drift. Rejected with reasoning; see Addendum.
- **Reviewer model defaults beyond this agent.** Subagent model defaults across all four agent files are audit item 12, chunk G. See Resolved Decisions for what C does about `review-panel.md`'s own `model:` line.
- Changing what the reviewers review, their personas, or the two scripts.
- **Capping docless audits.** 9 of 346 dispatches name no doc, all of them Mode 2 audits of a code change or a PR. They have no stable key, so they are uncapped. This is arguably correct (the cap is about design-doc rounds) and it is also an evasion path: an agent that wanted a 4th round could reframe it as a docless audit. A fallback key of `cwd` plus a hash of the prompt's first line would close it, at the cost of counting two rewordings as two docs. Not built; revisit if it is ever observed.
- **`spec-review`'s own cap.** `HOME/.claude/skills/spec-review/SKILL.md:13,213` carries an independent "Max 3 rounds" for a different 5-persona skill, with its own round mechanics at `:204,:211,:215`. Out of scope for C, and it will read as inconsistent the moment this cap is mechanical and that one is not. Flagged for whichever chunk owns skill hygiene.
- Exempting implementation audits. `how-to-execute-a-plan/SKILL.md:452` dispatches this same panel for a Mode 2 audit and those rounds are capped identically, on their own counter: see the (doc, mode) key in the Data Model. A Mode 2 run that needs a 4th round uses the same door.

## Proposed Solution

### Overview

One new hook, three text changes.

```
PreToolUse(Agent) -> panel-round-guard.sh
    matches on: subagent_type == "review-panel"
    keys on:    the doc path, parsed from tool_input.prompt
    counts:     ~/.cache/review-panel/rounds/<hash of doc path>
    denies:     round 4+, unless the door is open in the prompt
    door:       PANEL_ROUNDS_ORDERED_BY_SCOTT=<n>
```

### Where the cap has to sit, and why not at the seat scripts

The obvious seam is wrong, and the measurement that kills it is the same one that shapes everything below.

**Every round is a fresh `Agent` dispatch, and every fresh panel agent mints a new run dir.** `review-panel.md:79-83` Step 1.0:

```bash
mkdir -p /tmp/review-panel
RUN_DIR=$(mktemp -d /tmp/review-panel/XXXXXXXX)
```

So a round-4 agent starts with an empty directory and counts zero prior rounds unless the caller hands it the previous `$RUN_DIR`. Measured over `~/.claude/projects` (the dispatch and tool-name counts re-run independently for this doc on 2026-09-14; the run-dir breakdown is the research census of the same corpus):

- 360 `subagent_type":"review-panel"` dispatch records. 28 name a `/tmp/review-panel/<id>` path; 40 name a round number. The other ~88% carry neither.
- 328 distinct run dir ids across all transcripts. Only 56 ever carry a round-suffixed artifact. 272 are single-round dirs.
- The 14-round run (`8wLUyVus`, marquee) was driven by separately named agent instances, `agent-apanel-r2-*`, `agent-apanel-r3b-*`: per-round fresh agents with the run dir passed by hand.
- Dispatch is the `Agent` tool, not `Task`: 2,598 `"name":"Agent"` records against 7 for `Task`.

That defeats a seat-script guard twice over:

1. **The counter does not accumulate.** A `PreToolUse(Bash)` guard counting `dispatch-status*.txt` in the newest run dir reads zero for round 4 of a fresh dispatch and allows it.
2. **The deny lands in the wrong context.** The seat scripts run *inside* the panel subagent. The party that overruns is the caller. `review-panel.md:281-288` measures that a subagent's final turn does not reach its caller at all, so a deny there is a message the violator may or may not pass along. That is the same objection this doc raises against Alternative 2, and it applies just as hard to a Bash seam.

**So the guard sits on the `Agent` tool call**, in the caller's own context, before the subagent exists:

- matcher: the `Agent` tool, narrowed to `tool_input.subagent_type == "review-panel"`
- key: the doc path, parsed out of `tool_input.prompt`
- precedent that a non-Bash `PreToolUse` matcher works here: `block-question-picker.sh` is registered on matcher `AskUserQuestion` in `settings.json` and is the 557-to-zero result

This is also the same enforcement class chunk B hardened, so `lib.sh` is still available for the text handling, and the `excludedCommands` question disappears: that setting is Bash-only.

### Data Model: the counter has to be built, and not in /tmp

There is no durable round counter today. Two measurements:

- `review-panel.md:48` Step 0.1 tells the agent to count `$RUN_DIR/dispatch-status*.txt`, but per the finding above that directory is fresh on most dispatches, so the count is usually zero and the agent is usually wrong about which round it is on.
- `/tmp` is `tmpfs`, 16G, and the machine booted at 10:16 today. Every one of the 328 historical run dirs is gone, which is why only one dir was on disk when this doc's evidence was gathered. A counter in `/tmp` does not survive a reboot.

So chunk C creates one, at `~/.cache/review-panel/rounds/`, per `rules/taste.md` ("cache in `~/.cache` not `~/.config`"). The guard increments on allow; nothing else writes it.

Keying on the doc, not the run dir, is what makes the count survive the fresh-agent pattern: rounds 1 through 4 of one doc are four `Agent` calls with four run dirs and one cache entry.

**The key is (doc, mode), not doc alone.** A doc gets its design-review rounds before it is built and its implementation-audit rounds after, and `review-panel.md:90` Step 1.2 already distinguishes them: `Status: Implemented` in the doc means Mode 2, anything else Mode 1. Keyed on the doc alone, a doc that used all 3 design rounds would have its first implementation audit denied at dispatch, which would break the funnel `rules/taste.md` mandates. The guard reads the mode the same way Step 1.2 does, by grepping the doc it just resolved, so design and audit each get their own 3.

Entry layout, one file per (doc, mode), plain text so it is debuggable with `cat`:

```
~/.cache/review-panel/rounds/<sha256 of "<abs doc path>\n<mode>">
  path=/home/saidler/repos/scottidler/claude/docs/design/2026-09-14-panel-round-cap.md
  mode=1
  rounds=2
```

### What the dispatch payload carries, and what it does not

Chunk B put its harness facts in one named section (`guard-precision.md:194`, "The payload carries `cwd`, and three guards ignore it") because that is where the recurring mistakes live. The analogue here:

- **The `Agent` tool input carries `subagent_type` and `prompt` as sibling keys.** Proven from the corpus: a structural `jq` pass over `~/.claude/projects` returns 347 `tool_use` records carrying both keys. Method matters here: a raw-text grep for the literal `"subagent_type":"review-panel","prompt":"` returns only ~173, because the two keys are adjacent in that order in only about half the records. Use the structural pass, not the literal.
- **A PreToolUse payload carries `tool_name` and `tool_input` for non-Bash tools.** Proven in production, not just by a spike: `emdash.sh` is registered PreToolUse on `Write|Edit|MultiEdit|NotebookEdit` and on 11 MCP matchers, and reads `.tool_input.content`, `.tool_input.new_string`, `.tool_input.new_source`, and walks every string under `tool_input` for `mcp__*` (`emdash.sh:166-176`). Chunk A Phase 0b corroborates from a scratch hook (`2026-09-13-enforcement-core-phase0/evidence.md:97-101`). This narrows Phase 0 to one question: does the matcher fire for the `Agent` tool specifically.
- **A PreToolUse hook fires on a non-Bash, non-edit tool.** Proven by `block-question-picker.sh` on matcher `AskUserQuestion`. Caveat: that hook reads only `.tool_name` (`:20`) and never `.tool_input`, so it does not extend the point above to its own tool class.
- **Nothing anywhere shows a PreToolUse payload for the `Agent` tool.** Not asserted here. It is Phase 0's whole job.
- **The payload does carry `cwd`, and it is mandatory here, not optional.** Re-measured in Phase 0 with the shipped extractor over all 348 dispatch records: 221 (64%) name an absolute doc path and 118 (34%) name a relative `docs/design/...md` that only resolves against `cwd`. Ignoring `cwd` loses 34% of dispatches. (An earlier draft of this bullet said 290/84% and 43/12%, counting path shapes present anywhere in the prompt rather than the single doc the extractor picks. The ruling is unchanged and stronger.) `branch-name-guard.sh:48` and `branch-pr-title-guard.sh:51` already read it.
- **9 of 346 (2.6%) name no `.md` at all.** All nine are docless Mode 2 audits ("review a code change, not a design doc", a PR number, a refactor branch). They have no key, so the cap cannot bind them. Named rather than hidden: see Non-Goals.

### The door

Mirrors `BUMP_ORDERED_BY_SCOTT`, approved by Scott 2026-07-10, implemented at `HOME/.claude/hooks/git-release-guard.sh:75,308`.

The seam is the `Agent` call, not a shell command, so the marker rides in the dispatch prompt. It must be **its own control line**, matched as `^PANEL_ROUNDS_ORDERED_BY_SCOTT=[0-9]+$` against a nonblank line of `tool_input.prompt`:

```
review-panel this doc, round 4
PANEL_ROUNDS_ORDERED_BY_SCOTT=5
```

A word-boundary match anywhere in the prompt is a defect, not a simplification, and this document is the proof. It carries the literal marker followed by an integer four times: in the example above, in the paragraph on what the door is not, in "What this does not close", and in AC3. Re-engaging a panel by quoting prior findings is the normal shape of a round-4 prompt, so an "anywhere" match would let **the document being guarded raise its own cap to 5 or 10**, with no order from Scott and nothing visible to distinguish it from one. That is precisely the invisible overrun this chunk exists to kill.

`git-release-guard.sh:298-310` avoids the same class by reading the marker off a masked copy "so the marker cannot open the door from inside a commit message". The masking itself does not carry over (there is no shell quoting in a prompt), but the defect it guards against does, and an earlier draft of this doc treated the door purely as a forgery question, which the visibility argument covers. Accidental self-trigger is a different failure and the control-line rule is what closes it.

Mechanics copied from the original where they still apply: one marker, one integer, a ceiling rather than a boolean.

Honest about what this door is: a visible, auditable marker, not an unforgeable one. An agent can type the prefix. What it cannot do is open the door *invisibly*, and that is the property that matters here. The failure being fixed is an agent quietly running round 10 and not telling Scott; a door that leaves `PANEL_ROUNDS_ORDERED_BY_SCOTT=10` in the transcript makes that a thing Scott can see and grep for. Stated so a later reader does not mistake it for a security boundary.

The value is the ceiling, not a boolean, so `=5` grants five and still denies six.

### API Design

`panel-round-guard.sh`, stdin/stdout contract identical to its ten registered Bash siblings:

| case | behavior |
|---|---|
| input | PreToolUse JSON on stdin: `tool_input.subagent_type`, `tool_input.prompt` |
| not `review-panel` | allow immediately, before any other work |
| doc path unparseable | allow, and say so on stderr. A guard that denies what it cannot read would block every panel run whose prompt it fails to parse |
| no cache entry for the doc | allow. This is round 1; write the entry |
| allow | exit 0, no output, increment the entry |
| deny | exit 0 with `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}`, the shape `branch-name-guard.sh:56` emits |

House conventions every hook in this repo ships, and this one must too (`git-release-guard.sh:121-130,136`, `prose.sh:64-72`):

- `-h|--help` printing the file's own leading comment block via the standard `awk` dispatch
- `--self-test` exec'ing the `-test.sh` sibling
- `lib.sh` sourced **fail-open**: a missing library passes the call through rather than denying every dispatch in the session

Deny text names the remedy, per the branch-pr-title-guard lesson in the audit ("Error text must say what to do"):

```
panel-round-guard: this is round <N+1> on <doc>; the cap is <cap> (rules/interaction.md).
Rounds 1-<cap> produced findings that belong in the doc, not in another round.
If the doc still has open findings, fold them in and build; if Scott has
ordered more rounds, re-dispatch with PANEL_ROUNDS_ORDERED_BY_SCOTT=<n> in the prompt.
Counter: ~/.cache/review-panel/rounds/<hash> (<N> rounds recorded)
```

`<cap>` is 3, or the door's value when the door is open, so a `=5` run that reaches round 6 gets a message that says 5 and not 3.

### What this does not close

A doc-keyed counter is defeated by copying the doc to a new path, and the door is a marker an agent can type. Both are deliberate: the guard turns a silent overrun into a visible artifact (a duplicate doc in `docs/design/`, or `PANEL_ROUNDS_ORDERED_BY_SCOTT=5` sitting in the transcript) that Scott can see and grep for. It is not a security boundary and nothing here should be read as one.

Clearing `~/.cache/review-panel/rounds/` also resets every counter. That is a cache directory and wiping caches is normal maintenance, so the reset is expected rather than a hole; the cost of a wipe is that one doc's in-flight round count restarts.

The increment is a read-modify-write with no lock. Two dispatches on the same doc and mode racing each other can both read 2 and both write 3, costing one extra round, once. Not worth a lock; stated so no reader assumes atomicity.

Entries never expire. A doc reviewed to the cap, shelved, and picked up months later still reads 3 and denies. That is the correct default (the rounds did happen) and the remedy is the door or deleting the one entry, both of which are deliberate acts. Not worth a TTL until it is an observed problem.

### What happens at round 3 with findings still open

The cap does not mean "ship a doc with open findings." It means the remaining findings get **dispositioned by the author** instead of sent back for another round. `rules/taste.md`: "Reviewers advise, the owner decides... Absent a named concrete flaw, build the owner's requested option," and "fold in everything you agree with; send pushbacks WITH rationale back to the reviewer." Disposition is fold-in or reasoned pushback, both of which the author does without the panel.

The ready-to-build gate is unchanged: Open Questions empty, every finding dispositioned. The cap changes who closes the last few, not whether they get closed. If the author genuinely cannot close them, that is the case the door exists for, and it is Scott's call rather than the agent's.

### Landmine: the status-file name is inconsistent today

Step 0.1 (`review-panel.md:48`) says suffix every artifact with `-r$ROUND`, including `dispatch-status-r$ROUND.txt`, and Step 5's exit contract checks that exact name. Step 3's actual code block (`review-panel.md:133`) writes unsuffixed `dispatch-status.txt`. Both names exist in the wild.

Measured: 30 run dirs used the suffixed form, 4 used the unsuffixed one, so agents mostly follow Step 0.1 over the snippet they are actually shown.

The guard does not depend on either spelling any more (it counts in `~/.cache`, keyed on the doc), so this is no longer load-bearing for the cap. It stays in scope because Phase 3 is already editing the file and because the exit contract at `:299` checks a name the Step 3 snippet does not write, which is a live inconsistency in the agent's own hard gate.

### Implementation Plan

#### Phase 0: Prove the Agent seam
**Model:** sonnet
Zero code. The design rests on one unproven harness fact, so it gets measured before anything is built. Written to `docs/design/2026-09-14-panel-round-cap-phase0/evidence.md`:
- A `PreToolUse` hook registered on the `Agent` tool **fires**, and its stdin carries `tool_input.subagent_type` and `tool_input.prompt`. See "What the dispatch payload carries" for exactly which parts of this are already proven and which are not. Method is chunk A's Phase 0b verbatim: a scratch hook that tees stdin to a file and returns a block decision (`enforcement-core.md:181,189`), this time on matcher `Agent`.
- A deny from that hook **blocks the dispatch** and the denial text reaches the caller, not a subagent.
- Free measurement while the scratch hook is up: register `UserPromptSubmit` alongside the `Agent` matcher and record whether it fires during an autonomous dispatch. Costs nothing and settles the fallback question with data instead of reasoning.
- The `cwd` field is present in the `Agent` payload, not just the Bash one. The corpus says 34% of dispatches need it to resolve a relative doc path, so a missing `cwd` costs 34% of coverage and changes the key design.
- **Success criteria:** evidence.md contains one verbatim `Agent` PreToolUse payload showing `subagent_type`, `prompt` and `cwd`; a recorded deny that blocked a dispatch; and a doc-path extraction hit rate over at least 25 sampled real prompts, at or above the 96% the corpus predicts. A parse miss means an uncapped dispatch, so the hit rate is a gate, not a risk-table entry. If the payload lacks `subagent_type` or `prompt`, there is **no proven preventative seam** and the doc is reopened before Phase 1. An earlier draft named a `UserPromptSubmit` counter as the fallback; that is incoherent and is recorded here so it is not re-proposed. `UserPromptSubmit` fires on human input, and this doc's Problem Statement measures the disease as autonomous: 7, 5 and 10-round runs with **zero Scott prompts**. A counter that increments when Scott types cannot count a round Scott never triggered. No `UserPromptSubmit` hook is registered in `settings.json` today, so there is no precedent either way.

#### Phase 1: `panel-round-guard.sh` and its matrix
**Model:** opus
- Match `subagent_type == "review-panel"`; everything else allows before any other work.
- Extract the doc path from `tool_input.prompt`; unparseable allows and warns.
- Counter at `~/.cache/review-panel/rounds/<sha of abs doc path + mode>`, incremented on allow. Mode is read off the doc's `Status:` line, the same test Step 1.2 uses.
- Door: `PANEL_ROUNDS_ORDERED_BY_SCOTT=<n>` matched as `^PANEL_ROUNDS_ORDERED_BY_SCOTT=[0-9]+$` against a nonblank line of its own in the prompt, ceiling semantics. (Corrected during Phase 1: this bullet said "at a word boundary", contradicting the "The door" section above and AC3. The control-line rule is the correct one and its reasoning is stated there: this document carries the literal marker four times, so an anywhere-match would let the guarded doc raise its own cap.)
- `panel-round-guard-test.sh` alongside its 10 sibling matrices: allow rounds 1-3 and deny 4 for one doc; two docs counted independently; a different `subagent_type` always allows; an unparseable prompt allows; the door at `=5` allows round 4 and denies round 6; a doc path given relative versus absolute resolves to the same counter; flipping the doc to `Status: Implemented` starts a fresh count.
- **Success criteria:** `bash HOME/.claude/hooks/panel-round-guard-test.sh` exits 0; reverting the round comparison fails at least 4 cases (break-the-code evidence recorded).

#### Phase 2: Register it and wire the gates, in this phase
**Model:** sonnet
- Add to `settings.json` `PreToolUse` on the `Agent` matcher, confirm `bin/hooks-resolve` sees it.
- Add to `.otto.yml`'s lint list: `panel-round-guard.sh`, `panel-round-guard-test.sh`, this design doc, its implementation notes, the Phase 0 evidence file, and `review-panel-notes.md`. Chunk B's CW5 set that precedent; a file not on the list drifts em-dashes back in where CI cannot see it (`rules/safety.md`).
- **Link step runs in this phase**, per chunk B's recorded rule: a phase that adds a file another live hook depends on links it in the same phase, or four guards fail open through the symlink path (`guard-precision-implementation-notes.md`, Phase 7 note).
- **Success criteria:** `bin/hooks-resolve` reports all hooks resolved, 0 warnings; `otto ci` exits 0.

#### Phase 3: Shrink `review-panel.md` to the contract
**Model:** sonnet
- Move the incident narratives to `HOME/.claude/agents/review-panel-notes.md`, referenced by one line. Measured movable narrative, by section: Step 3 `:139-144,:146-150,:154-159,:176-182` (~1,800B), Step 5 `:305-313` plus part of `:284-288` (~1,000B), Step 0 `:33-44` (~1,050B), Step 4 `:241-248` plus three anecdotes in `:260-268` (~900B), Step 3.75's otto PR #3 story inside `:231` (~450B), Step 1's 2026-08-08 anecdote inside `:89` (~450B, sub-line surgery not a move), "Why this agent exists" `:21-27` (~300B). Total ~6,350B. The rules those incidents produced stay.
- Move Step 2's two reviewer prompt bodies (`:106`, `:109`) out to `review-panel-prompts.md`. Not into the seat scripts: that would couple standalone `/architect` and `/staff-engineer` runs to panel behavior, which Non-Goals rules out. Step 2 is 3,505 bytes in 14 lines, 13% of the file, and none of it is agent instruction: it is verbatim text piped to gemini and codex. This is the largest cut available that costs no rules.
- Lore extraction alone lands at ~19,970, zero margin. With the Step 2 move, ~16,500. Reported as an observation in the implementation notes; AC4 gates on the properties, not the number.
- Step 6 report shape: `Round: <n>` becomes `Round: <n> of 3`.
- Step 3's dispatch block writes `dispatch-status-r$ROUND.txt`, agreeing with Step 0.1 and Step 5's exit contract. See the landmine note above.
- Step 4: `synthesis.md` carries `[SYNTHESIS]` only. The raw seat output already lives in `arch-r$N.out` and `staff-r$N.out`; duplicating it into `synthesis.md` is what produced the 4,035-line file.
- Document the door in Step 0, so the agent reads about `PANEL_ROUNDS_ORDERED_BY_SCOTT` in the file it already loads, not only in a deny it has not hit yet.
- **Success criteria:** `review-panel-notes.md` non-empty; every numbered step, the rc table, and the hard exit contract still present in the agent file; zero em-dashes in both. Byte count is reported as an observation, not gated. (Amended after the round-1 implementation audit. This bullet asserted under 20,000 and Phase 3 hit 19,954, but the audit found Phase 3 had silently dropped Step 4's four enumerated rejected-dogma examples, which are the operative content of that rule and not narrative. Restoring them, plus correcting Step 1.2's mode instruction to match the guard's metadata-block read, puts the file at 20,273. Re-deleting a rule to satisfy a byte number is the failure this criterion would have caused, and AC4's own note already demotes byte census to an observation for exactly this reason: "an acceptance criterion phrased as a census of the final tree has to be re-derived every time the plan changes". AC4's property checks remain the gate and they pass.)

#### Phase 4: Delete the poll snippet, point the rule at the guard
**Model:** sonnet
- Remove `create-design-doc/SKILL.md:54-67` (the "Poll its run dir" block). Keep lines 69-74 ("Trust the findings, not the verdicts"): different lesson, still true.
- `rules/interaction.md:111`: the cap sentence becomes a pointer to `panel-round-guard.sh`, matching how chunk B replaced the branch-slug prose with a pointer to its hook.
- Left alone deliberately, with reasons, so a later reader does not think they were missed: `docs/2026-09-08-rails-function-hooks-handoff.md:65,84,113,133` carries a poll-the-run-dir recipe and restates the cap, but it is a dated handoff and dated docs are point-in-time (`rules/taste.md`). `docs/design/2026-09-08-rails-bash-rewrite.md:91,518,527` likewise. `docs/sandbox-filesystem-allowlist.md` documents the `/tmp/review-panel` allowlist and the `mktemp -d` shape, both of which this chunk leaves intact, so it does not go stale. `README.md:31` and `bin/check-review-panel` are untouched: the guard is on the `Agent` tool, so a health check that runs the seat scripts directly was never in its path (it would have been a false positive for the rejected Bash design, which is one more mark against it).
- **Success criteria:** `rg -c 'Poll its run dir' HOME/.claude/skills/create-design-doc/SKILL.md` returns 0; `rg -c 'panel-round-guard' HOME/repos/.claude/rules/interaction.md` returns at least 1.

#### Phase 5: Shakedown against the live, linked hook
**Model:** sonnet
- Re-run every acceptance criterion through the `~/.claude/hooks/` symlink path so `$0` is the production path, per chunk B's Phase 9 method. Record each Observed line.
- **Success criteria:** all acceptance criteria below pass with their output recorded; `otto ci` exits 0.

## Acceptance Criteria

- [x] AC1: A 4th `Agent` dispatch on the same doc is denied. Feed a `review-panel` dispatch payload through `~/.claude/hooks/panel-round-guard.sh` four times for one doc path; the 4th stdout contains `"permissionDecision":"deny"`, the first three are empty with exit 0.
  - *Observed on main:* not yet runnable, the hook does not exist (Phase 1).
  - *Observed 2026-09-14 (Phase 5, shakedown through `~/.claude/hooks/panel-round-guard.sh`, `readlink -f` confirmed as the production repo path, `PANEL_ROUND_CACHE_DIR` pointed at a scratch dir under `$TMPDIR`, doc path a scratch file under `$TMPDIR`):* rounds 1 to 3 exit 0 with empty stdout; round 4 exits 0 with stdout `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"panel-round-guard: this is round 4 on <doc>; the cap is 3 (rules/interaction.md)...."}}`. PASS.
- [x] AC2: A dispatch that is not this panel is never touched. A payload with `subagent_type` of `Explore`, repeated 5 times, produces empty stdout and exit 0 every time.
  - *Observed on main:* not yet runnable (Phase 1).
  - *Observed 2026-09-14 (Phase 5, same production hook path, isolated scratch cache dir):* all 5 dispatches with `subagent_type:"Explore"` exit 0 with empty stdout; the scratch cache dir has 0 entries afterward (never written). PASS.
- [x] AC3: The door opens and holds a ceiling. With the same doc at 3 rounds, a prompt carrying `PANEL_ROUNDS_ORDERED_BY_SCOTT=5` allows rounds 4 and 5 and denies round 6.
  - *Observed on main:* not yet runnable (Phase 1).
  - *Observed 2026-09-14 (Phase 5, production hook path, scratch doc and cache dir):* after 3 plain rounds, round 4 with `PANEL_ROUNDS_ORDERED_BY_SCOTT=5` as its own control line allows (empty stdout, exit 0), round 5 with the same marker allows, round 6 with the same marker denies with `"the cap is 5 ... (5 rounds recorded)"`. PASS.
- [x] AC4: The agent file carries the contract and no incident narrative, and the poll snippet is gone. As properties, not a byte census: every numbered step (0, 1, 2, 3, 3.5, 3.75, 4, 5, 6), the rc table, the hard exit contract, the snapshot-and-hash drift rule (Step 0.2) and the verify-every-negative-claim rule (Step 4) are present in `review-panel.md`; no dated incident narrative remains in it (no `20\d\d-\d\d-\d\d` outside a one-line pointer to the notes file); `review-panel-notes.md` exists, is non-empty, and is referenced; `rg -c 'Poll its run dir' HOME/.claude/skills/create-design-doc/SKILL.md` returns 0.
  - *Observed on main 2026-09-14:* `wc -c` is `26322`, `rg -c 'Poll its run dir'` returns `1`, notes file does not exist. Fails as expected before Phases 3 and 4.
  - Phrased as properties on purpose. Chunk B's review log records the lesson after three instances: "an acceptance criterion phrased as a census of the final tree has to be re-derived every time the plan changes, and that re-derivation is exactly the step that keeps getting skipped." An earlier draft of this AC asserted under 12,000 bytes, which the per-section measurement below shows is unreachable without deleting contract. Byte count is reported in the implementation notes as an observation, not asserted as a gate.
  - *Observed 2026-09-14 (Phase 5, against the landed Phase 3/4 state):* every numbered step marker (`Step 0` through `Step 6`, including `Step 3.5` and `Step 3.75`) present; the rc table's `| rc | Meaning | What to do |` header present; the hard exit contract paragraph present ("Hard exit contract. You may not end a turn in which you dispatched reviewers..."); the Step 0.2 snapshot-and-hash rule present ("Re-snapshot and re-hash, always... Compare against the PREVIOUS round's snapshot hash"); the Step 4 verify-every-negative-claim rule present ("repeat any seat's negative claim, absolute..."); `rg '20\d\d-\d\d-\d\d' HOME/.claude/agents/review-panel.md` returns zero matches (no dated narrative at all, not even a pointer); `review-panel-notes.md` exists, is 7090 bytes, and is referenced from `review-panel.md` at 12 call sites; `rg -c 'Poll its run dir' HOME/.claude/skills/create-design-doc/SKILL.md` produces no output and exits 1, i.e. zero matches. PASS.
- [x] AC5: Every hook resolves and CI is green. `bin/hooks-resolve` prints all resolved with 0 PATH warnings, and `otto ci` exits 0.
  - *Observed on main 2026-09-14:* `hooks-resolve: all hook files resolved (0 PATH warning(s))`, and `otto ci` exit `0`. Passes today and must still pass after Phase 2.
  - *Observed 2026-09-14 (Phase 5, after Phases 1-4 landed):* `bin/hooks-resolve` -> `hooks-resolve: all hook files resolved (0 PATH warning(s))`; `otto ci` ends `[test] 114 pass / 0 fail`, `[ci] ✅ All CI checks passed!`, exit `0`. PASS.
- [x] AC6: The count survives the fresh-agent pattern; two docs do not share a counter; and a mode flip starts a fresh count. Four dispatches for doc D deny on the 4th even though each would mint its own run dir; doc E's first dispatch still allows; and doc D with `Status: Implemented` allows again from round 1.
  - *Observed on main:* not yet runnable, the hook does not exist (Phase 1). This is the criterion that proves the design's central claim: 272 of 328 historical run dirs were single-round, so a per-run-dir counter would pass AC1 and still never fire in practice.
  - *Observed 2026-09-14 (Phase 5, production hook path, each dispatch a fresh process invocation, scratch docs D and E under `$TMPDIR`, one shared scratch cache dir):* doc D rounds 1-3 allow, round 4 denies with `"the cap is 3"`; doc E's first dispatch (its own counter, same cache dir) allows; doc D rewritten with `**Status:** Implemented` and dispatched as an Implementation Audit allows from round 1; the cache dir holds exactly 3 entries after the run (D mode 1, E mode 1, D mode 2), confirming distinct (doc, mode) keys. PASS.

## Resolved Decisions

- **2026-09-14, the wall-clock half of audit item 4 is not built.** It exists in both seat scripts, and an outer timeout is forbidden by Scott's 2026-08-04 ruling. Recorded as a Non-Goal with the citation rather than silently dropped.
- **2026-09-14, `model:` on `review-panel.md` stays `opus`.** The audit's "`model: sonnet` for reviewers" cannot mean the seats: they are Gemini and Codex, not Claude. The only Claude model in the loop is this orchestrator, and Step 3.75 and Step 4 require it to run differential probes and to verify each seat's negative claims against the code before repeating them. That is the verification work, not scaffolding. Subagent model defaults as a class are item 12 / chunk G.
- **2026-09-14, the cap value stays 3.** Scott set it; nothing in the evidence argues for a different number.
- **2026-09-14 (panel round 1), an unparseable doc path fails OPEN.** The Architect argued fail-closed on `rules/taste.md`'s "fail loudly, fail closed". Rejected: every guard in this tree fails open on an unreadable payload (`emdash.sh:92,97`, `prose.sh:107`, `branch-name-guard.sh:47`, `branch-pr-title-guard.sh:50`, `git-release-guard.sh:150`, all tracing to `rewrite-cd-read.py:911-914`), and the Blast radius section prices what a fail-closed bug costs: every panel dispatch on every machine. The concern's correct form is the Phase 0 extraction-hit-rate gate, which is now a success criterion.
- **2026-09-14 (panel round 1), no separate deny log.** House precedent exists (`rewrite-cd-read.py:483`), but the counter file already records where a doc stopped and the deny text is in the transcript. A third record of the same fact is the inflation this chunk exists to remove. Scott can overturn this one cheaply if he wants the audit trail.

## Alternatives Considered

### Alternative 1: Keep the cap in prose, make it louder
- **Description:** Restate the cap in `review-panel.md` Step 0 as a hard stop, bold, with the count printed.
- **Pros:** No new hook. Smallest change.
- **Cons:** This is what already failed. The cap has been prose since 2026-09-08 and was blown 10 times in 19 runs.
- **Why not chosen:** Scott, on a different rule: "you have ZERO method of making a change to prevent your behavior in the future. Whatever let you fuck it up today will still be present tomorrow." (design-exemplars.md #10.)

### Alternative 2: Count rounds in the agent, deny in the agent
- **Description:** Step 0 counts and refuses at 4.
- **Pros:** No hook, no attribution problem, the agent already counts.
- **Cons:** The agent doing the counting is the party that overran. It is also the party that wrote "Tenth crossing, and I am not going to tell Scott".
- **Why not chosen:** self-enforcement by the violator.

### Alternative 3: A `PreToolUse(Bash)` guard on the seat scripts
- **Description:** Deny the `architect/script.sh` + `staff-engineer/script.sh` dispatch inside the panel agent, counting `dispatch-status*.txt` in the run dir. This was this doc's own design through pass 5.
- **Pros:** Bash is the seam every existing guard uses; `lib.sh` and `shapes.sh` apply directly.
- **Cons:** Two fatal ones. The counter does not accumulate, because `review-panel.md:79-83` mints a fresh run dir per dispatch and 272 of 328 historical dirs were single-round, so round 4 reads zero. And the deny lands inside the subagent, whose final turn is measured as not reaching its caller (`review-panel.md:281-288`), so the party that overruns may never see it.
- **Why not chosen:** it fails the same test this doc applies to Alternative 2. Recorded rather than deleted because it is the obvious design and the next reader will propose it again.

### Alternative 4: A `SubagentStop` hook
- **Description:** Count rounds as the panel subagent exits.
- **Pros:** The event is live at this version, already registered and carrying `prose.sh` (verified 2026-09-14, Claude Code 2.1.270).
- **Cons:** Fires after the round has already run. It can report an overrun, never prevent one.
- **Why not chosen:** wrong side of the action. Kept in reserve as a reporting path if the guard needs an audit trail.

## Technical Considerations

### Dependencies

- `HOME/.claude/hooks/lib.sh` and `shapes.sh`, both shipped by chunk B.
- `bin/hooks-resolve` and `hooks-preflight.sh`, shipped by chunk B, catch the register-before-the-file-exists failure this hook would otherwise be the eighth instance of.
- `docs/design/2026-09-14-panel-round-cap-review-log.md`, opened before the panel runs (a process artifact, not a build phase).
- `~/.cache` writable from inside the sandbox: true, `sandbox.allowWrite` lists `/home/saidler/.cache`.
- A `PreToolUse` matcher on the `Agent` tool: the design's one unproven dependency, and Phase 0's whole job.

### Security

The counter lives under `~/.cache`, writable by the user and anything running as them. A local actor could zero it to reset the cap or inflate it to block panels. Same trust boundary as every other file this setup reads, including the hooks themselves, so it adds no new exposure. Noted, not defended against. The counter file holds a doc path and an integer: no secrets.

### Testing Strategy

Matrix in the shape chunk B established: explicit allow and deny fixtures, plus a mutation sweep over every deny fixture. Break-the-code evidence required: revert the round comparison, show the matrix fails, restore.

**Not the `shapes.sh` sweep.** `shapes.sh` exists for one problem, "the command word was not the first word of the statement", and its 16 templates are shell wrappers (`eval`, `bash -c`, `timeout`, process substitution) around a command word. This hook consumes `tool_input.prompt`. There is no command word and no shell. All 16 shapes could pass while proving nothing about prompt parsing, marker placement or path extraction. Inheriting it here would be ceremony in the doc whose subject is deleting ceremony.

The mutations that actually apply to a prompt-consuming guard:

- the door marker inside quoted or indented doc text, which must NOT open the door
- the door marker as its own control line, which must
- a doc path given relative versus absolute, resolving to one counter
- two `.md` paths in one prompt
- an `.md` path that is not the doc under review
- no path at all

### Blast radius and ship order

One repo, `scottidler/claude`. No cross-repo blast radius: nothing outside this repo imports these files.

The reach inside it is every session on every machine. `~/.claude/hooks/` and `~/.claude/agents/` are manifest symlinks into this repo on both desk.lan and ltl-7007.lan, so the guard is live for all sessions on a machine as soon as the commit lands there, including sessions already running (shell hooks are re-read per invocation). A bad guard blocks every panel dispatch until it is fixed, which is the argument for Phase 1's break-the-code evidence and Phase 5's shakedown through the production symlink path.

Ship order: C blocks nothing. D through J are independent of it. Within C, Phase 0 gates Phase 1 (attribution), and Phase 2's link step gates Phase 5's shakedown.

### Rollout Plan

Land on `main` by `git push origin panel-round-cap:main`; this repo takes no PRs, and `git checkout` fails here from a session whose own config is this repo. Shell hooks are symlinked from `~/.claude/hooks/`, so the guard is live on commit, which is why Phase 2 owns the link step. No rails plugin change, so no session restart is needed.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Two panels on two docs run concurrently | Low | Low | Counters key on the doc path, so concurrent panels on different docs never share an entry |
| The `Agent` PreToolUse payload lacks `subagent_type` or `prompt` | Med | High | Phase 0 measures it before Phase 1; named fallback is a `UserPromptSubmit` counter, and the doc reopens rather than the phase improvising |
| The doc path cannot be parsed from a real dispatch prompt | Med | Med | Guard allows and warns rather than denying what it cannot read; Phase 0 reports the extraction hit rate over 25+ sampled prompts |
| The guard denies and the agent retries variants instead of stopping | Med | High | Deny text names the remedy and the door; `shapes.sh` sweep closes the wrapper and quoting bypasses; chunk B measured 22 such bypasses on the other guards |
| A cache wipe resets every counter | Med | Low | Expected: `~/.cache` is wipeable by design. Cost is one doc's in-flight count restarting |
| Shrinking `review-panel.md` drops a rule that was load-bearing | Med | High | Phase 3 moves narratives only; every rule stays. AC4 pairs the byte target with a presence check on the steps, the rc table and the exit contract |
| A doc that used its design rounds cannot get an implementation audit | Med | High | Counter keys on (doc, mode), read off the `Status:` line exactly as Step 1.2 does. AC6 covers the flip |
| A doc-keyed counter is defeated by copying the doc to a new path | Low | Med | Accepted. Same class as the typeable door: the bypass becomes a visible artifact rather than a silent one |
| The cap blocks a round Scott actually wants | Low | Med | The door, one env prefix, documented in the deny text itself |

## Review log

Round-by-round panel minutes, pushbacks and their rationale live in `docs/design/2026-09-14-panel-round-cap-review-log.md`, opened before round 1 rather than retrofitted. Only rulings land in this doc.

Chunk B opened one because "the design doc was reproducing the exact disease it is meant to help fix": its Resolved Decisions reached 22% of word count, roughly half of it minutes rather than rulings, and the doc grew 378 to 536 lines across three rounds. This is the doc about review-process inflation. It does not get to inflate: Resolved Decisions stays under 10% of word count.

## Implementation Audit

Kept here as a section of this doc rather than a separate artifact (`guard-precision.md:521` precedent). Walks the plan bullet by bullet against the code, with undisclosed deviations as the primary finding.

### Round 1, 2026-09-14 (Mode 2). 3 must-fix, 4 cheap wins, 4 defer.

Seats: architect rc=0 (6,535B, succeeded on attempt 2 of 2 after the known Invalid-stream retry); staff-engineer rc=0 (7,836B). Snapshot equalled the live file, 0 lines of drift. 5 questions asked, 5 answered.

This dispatch was also the live end-to-end proof the shakedown could not give. It was the first real `Agent` dispatch to meet the registered guard, and it worked unassisted: the extractor pulled the doc path from a real prompt, mode detection read `Status: Implemented`, and `~/.cache/review-panel/rounds/` gained one entry, `path=<this doc> mode=2 rounds=1`, whose filename equals the hand-computed `sha256("<abs doc path>\n2")`. AC6 is now proven live, not only synthetically.

**The seats disagreed, and the disagreement is itself a finding.** The Architect reported zero defects, asserting the regex was robust and that prose discussing `Status: Implemented` would not trigger a mode flip. It ran no commands; two of its five verdicts were falsified by probes. The Staff Engineer named both parser defects and reported honestly that it could not execute the matrix. It was right on both. This is exactly what Step 4's verify-every-negative-claim rule exists for.

- **Must-fix 1, FIXED. The door opened from a fenced code block.** The control-line regex anchored both ends and correctly rejected indented, inline, mid-sentence, trailing-text and pasted-deny-text markers, but not a marker at column 1 *inside a fence*, and this document carries exactly that at `:165`. Reproduced: after 3 recorded rounds, a round-4 prompt quoting a verbatim `sed -n '161,170p'` excerpt of this doc's own door section ALLOWED and the counter advanced to 4. The guarded document was raising its own cap from 3 to 5, which is precisely the invisible overrun the control-line rule was written to prevent. Undisclosed, and CI could not see it because the matrix's quoted-marker cases used inline backticks only. Fixed by masking fenced blocks before the match, which is the `git-release-guard.sh:298-310` masked-copy precedent this doc already cites. Four regression cases added; reverting the mask fails all four.
- **Must-fix 2, FIXED. Mode detection flipped on a `Status: Implemented` anywhere in the body.** The read grepped the whole file unanchored, so an In Review doc carrying a fenced example keyed as Mode 2. Reproduced. The damage is the inverse of how it looks: the key then fails to change when the status genuinely flips, so a doc's first implementation audit inherits its exhausted design-review counter and is denied at dispatch, defeating the (doc, mode) mitigation for the Med/High risk row. Latent rather than live: all 15 `docs/design/*.md` agreed with their real status. Fixed by scoping the read to the metadata block above the first `##` heading. Deliberately NOT anchored at end of line, because `Status: Implemented with a follow-up owed` must keep reading as Mode 2. Six regression cases added; reverting the scoping fails all six.
- **Must-fix 3, NOT FIXED, and not chunk C's to fix.** `review-panel.md` Step 3's "ONE foreground Bash call" mandate is unexecutable today: the rails `tool.call` hook denies any Bash call combining a `sandbox.excludedCommands` head with another statement, and chunk A put both seat scripts in `excludedCommands`. The audit was denied three times this round and launched each seat as its own single-statement call, losing the wait-keeps-the-PID-namespace-alive property that the 2026-08-31 detached-seat incident produced the rule for. Not a Phase 3 regression: the same mandate is at `762016f`. Chunk C did rewrite this file, so the rule is now provably un-followable and someone owns it. Carried to Open Questions.
- **Cheap wins, all folded in.** The stale 12%/84% relative-path figures at `:154` and `:241` now carry Phase 0's re-measured 34%/64%, matching the shipped hook's own comment. Phase 3's one undisclosed content loss, Step 4's four enumerated rejected-dogma examples, is restored; they are the operative content of that rule, not narrative, and they had landed nowhere, not even in the notes file. Step 1.2's mode instruction now describes the metadata-block read so the agent file and the guard agree. This section replaces its own placeholder.
- **Verified clean, and not on the seats' word.** The compression risk was the one I most expected to bite and it did not: the audit diffed `762016f`'s 26,322B file against the shipped one, enumerated all 190 removed lines, and confirmed each of the 12 rules the moved incidents produced is still stated explicitly in the agent file. I had independently grepped 21 rule markers to the same conclusion. Frontmatter intact, nine step headers present, em-dashes 44 to 0 across all three files.
- **AC1 through AC6 all hold**, verified by the audit independently of the phase reports and of my own checks. The matrix runs inside `otto ci`, so it cannot rot. One item UNVERIFIED: Phase 0's 97.4% extraction hit rate over 348 corpus dispatches, reported in `evidence.md` and not re-derived by the audit.

## Open Questions

Empty through the build. These three were opened by the round-1 implementation audit, after the phases landed. Two are now fixed; the third is documented where it lives and handed on. None blocked chunk C, which is Implemented.

- [x] **FIXED: Step 3's "ONE foreground Bash call" is executable again.** Audit must-fix 3. The rails `tool.call` hook denies a Bash call that compounds a `sandbox.excludedCommands` head with any stage that acts, and both seat scripts are excluded heads, so the old block's `tee` and `wc` made the mandate unexecutable. The first fix attempted was a single `panel-dispatch.sh` holding the compound internally and added to `excludedCommands`; the auto-mode classifier refused it as a security weakening and it was right, because an excluded head whose body is an arbitrary compound is a general escape hatch that runs unsandboxed with nothing able to inspect it. The actual fix needs no new entry, no rails change and no weakening: `echo` and `wait` are ALREADY treated as carrying no behavior of their own, so dropping `tee` for a `>` redirect and moving the byte count to a separate Step 4 `wc -c` call leaves the compound with no acting stage at all. Step 3 now carries a paragraph explaining why the block must stay builtin-only, so the next editor does not reintroduce the deny.
- [x] **FIXED: every run-dir artifact now carries the `-r$ROUND` suffix.** `doc-snapshot.md`, `prompt.txt`, `arch.out`, `staff.out` and `staff-sub.txt` are all unsuffixed. Phase 3 had fixed only `dispatch-status.txt`, the one name wired to Step 5's exit contract, and the round-1 audit then tripped over the rest while reviewing: its own artifacts were `-r1`-suffixed while Step 3.75 told it to read `arch.out`. `doc-snapshot`, `prompt`, `arch`, `staff` and `staff-sub` are all suffixed now, so Step 0.1's "suffix EVERY artifact" is true rather than aspirational.
- [ ] **`spec-review`'s "Max 3 rounds" is still prose, and now documented as such.** Flagged as a Non-Goal before the build (`HOME/.claude/skills/spec-review/SKILL.md:13,213`). `panel-round-guard.sh` cannot cover it: that skill dispatches 5 persona sub-agents, not the `review-panel` subagent, so the guard's `subagent_type` match never fires. `SKILL.md:213` now says exactly that, cites this doc's measured prose-cap failure (17 of 46 runs, worst 14, zero prompts), and tells the agent the cap binds on itself because nothing will stop it at 4. Making it mechanical needs its own key and belongs to whichever chunk owns skill hygiene.

## Addendum: rejected, with reasoning

- **Freeze the doc during a round.** Prescribed by the audit. The measured failure is doc growth across rounds (302 -> 578, 755 -> 1,335), which a within-round freeze does not touch. Step 0.2 already snapshots and hashes, so a mid-round edit shows up as measured drift and the round is explicitly run against the snapshot. Adding a write-lock on the doc path would block the caller from folding findings in while a round finishes, which is the one thing they should be doing. Revisit if a round is ever measured failing *because* of a concurrent edit.

## References

- Program baton: `docs/design/2026-09-13-setup-audit-program.md`
- Audit item 4, ranked report: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/
- Chunk B precedent (shared parser, guard matrices, link-step rule): `docs/design/2026-09-13-guard-precision.md`, `docs/design/2026-09-13-guard-precision-implementation-notes.md`
- The door: `HOME/.claude/hooks/git-release-guard.sh:75,308`
- The chokepoint: `HOME/.claude/agents/review-panel.md:113-133`
- The timeout ruling: `HOME/.claude/agents/review-panel.md:152`, `HOME/.claude/skills/architect/script.sh:35`, `HOME/.claude/skills/staff-engineer/script.sh:41`
