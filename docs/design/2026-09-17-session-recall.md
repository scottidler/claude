# Design Document: Session recall

**Author:** Scott Idler
**Date:** 2026-09-17
**Status:** Draft
**Review Passes Completed:** 5/5, then panel rounds 1, 2 and 3 folded (7, 6 and 9 must-fix, every one verified against the corpus or the code before folding). Round 2 sustained round 1's pushback on the result; round 3 sustained the result again and overturned the reason a second time. **All three rounds are spent: 7, 6 and 9 must-fix, every one folded. A fourth needs Scott's `PANEL_ROUNDS_ORDERED_BY_SCOTT=4`.**

## Summary

Chunk F1 of the setup-audit program, audit item 9. 73 sessions open by asking Claude to go find a previous session, and nothing in the setup encodes that. This builds the retrieval path (a `session-recall` skill over clyde's MCP surface), a narrow `UserPromptSubmit` hook that points at it when the prompt names a session, an always-on `rules/recall.md`, and a vocabulary section in WHOAMI.

The audit's prescribed hook trigger is not built. Measured, it fires on 38.2% of typed prompts. The trigger here fires on 0.41%: 46 of 11,225 human prompts, and zero across all 6,820 non-human records. Those are the design-time figures; Phase 2's frozen snapshot re-measures the shipped hook at **48 fires and zero non-human fires**, both differences accounted for in AC2.

## Problem Statement

### Background

- The 2026-09-12 audit ranked 22 changes to this setup. Item 9 is "session recall", called out as the largest uncovered standing order.
- Chunks A, B, C, D, D2 and E are done. F was split into F1 and F2 on 2026-09-17; this is F1.
- `vault-recall` already exists and does the same job for the Obsidian vault. It is the pattern to copy, not a design to invent.

### Problem

- 73 sessions open with a request to go find a previous session. The audit's wider predicate counts 108; re-measured, 73 as the very first prompt is confirmed, and 108 is predicate width rather than an error.
- Zero encoding anywhere. `clyde --help` was run in 24 of 245 home sessions, which is the model rediscovering the tool surface from scratch.
- Read-target-first is the #1 correction class at 162 instances, still rising (24.3 per 1000 in September) despite `taste.md` and the 2026-09-08 confirm-target rule both already saying it in prose.
- Prose is not carrying this. That is the program's whole thesis: hooks fix behavior, rule text does not.

### Goals

- A named retrieval path the model reaches for without being told, mirroring `vault-recall`.
- A prompt-time nudge narrow enough to be defensible against the always-on budget.
- The clyde tool surface written down once, correctly, so the model stops guessing parameter names.

### Non-Goals

- **The audit's prescribed hook trigger** ("a URL, a path, or how do I"). Excluded on measurement: 38.2% of typed prompts. See Alternative 1.
- **The word "yesterday" as a trigger.** Excluded on measurement: 14 of its fires are diff text, and it names no target, so its injected line is the uncorroborated shape that 0b-3a recorded being refused.
- **Predicate (c)**, a path or URL with no action verb. Excluded: 5.32% for no gain over (d), and "no action verb" is a negative lexical test over a ~60-word verb list, the same shape `inline-skill-tokens` already rejected as its Alternative 6.
- **Teaching `inline-skill-tokens.py` bare-word tokens.** `HOME/.claude/hooks/inline/tests.py:57-63` parks this case and points at "chunk F's WHOAMI vocabulary work" using `bump` as its example. The audit asked for a WHOAMI section, not a hook change. Parked, revisit condition: the vocabulary section ships and bare-word misses are then measured above the rate that justified the slash-token hook.
- Anything in F2 (items 10 and 11): the handoff skill, resume trigger, sleep deny, `pr-babysitter`.
- Chunk H's always-on trim. This chunk stays inside the budget rather than fixing it.

## Proposed Solution

### Overview

Four artifacts, in dependency order:

1. `session-recall` skill: the retrieval path. Everything else points at it.
2. `session-recall-guard.sh`: `UserPromptSubmit` hook, trigger (d), pointing at 1.
3. `rules/recall.md`: always-on prose for what the hook's predicate cannot see. **Deletes nothing**: see the verdict table.
4. WHOAMI vocabulary section.

### Architecture

```
UserPromptSubmit
  -> session-recall-guard.sh          5 bails, 2 triggers, 0.41% of prompts
     -> additionalContext             quotes the trigger verbatim, two branches
        -> Skill(session-recall)      the skill owns ToolSearch and the clyde call
rules/recall.md (always-on)           covers the prompts the hook's predicate misses
WHOAMI vocabulary                     glossary, no enforcement seam
```

### The trigger, measured

**Denominator: 11,225 human prompts.** Four non-human buckets are counted separately, because their false-fire rate is what decides the predicate:

| bucket | records | fires, pre-fix |
|---|---|---|
| **human** | **11,225** | **47** (46 non-meta) |
| `<...>`-tagged (task notifications, agent messages) | 2,607 | 21 |
| `Another Claude session sent a message:` wrapper | 2,351 | 9 |
| `Review this change for security` harness | 1,862 | 0 |
| `Caveat:` | 0 | 0 |

**Round 1 caught this doc making the research brief's error mirrored, and the correction is folded here.** The brief absorbed the harness class *into* its denominator, inflating the rate and hiding false fires inside it. This doc excised two classes *from* the denominator without adding a bail for them, which made their false fires invisible instead. Both are the same mistake about what a denominator is for.

- The earlier 13,567 figure was **17% inflated**: 2,351 of those records are agent deliveries that begin with the literal `Another Claude session sent a message:` and then continue into a tag. A `startswith("<")` test misses every one, because the harness prepends that sentence before the tag.
- `<...>`-tagged prompts demonstrably reach `UserPromptSubmit`: the live hook's own log at `~/.cache/claude/inline-skill-tokens.log` carries `<task-notification>` and agent-message entries.
- The earlier "0 false fires" was true only of the security-review bucket. Measured across all non-human buckets it was **30**.

### The predicate

Five bails, then two triggers. Bails run first and short-circuit.

**Bails:**

1. Prompt begins with `<`.
2. Prompt begins with `Another Claude session sent a message:`.
3. Prompt contains a fenced code block (` ``` `).
4. Prompt names `clyde`. **29 fires** (round 2's count, not pass 4's 34) where naming the tool makes the **hook injection** redundant. It does not make the *skill* redundant: round 2 read all 29 and found 13 reaching MCP tools, 10 the CLI, and 6 neither, with every one of the 6 accounted for (four had no unmet retrieval need, one was interrupted, one hit an expired login and used clyde on retry). No case of the model ignoring an eligible ask, so the theory survives.
5. Prompt opens agent-shaped: `You are `, `Summarize this Claude Code`, `Review this change for security`, `Analyze the following`.

**Triggers, either one. Case folding is stated per arm, because Phase 2 found it unstated and it moves the count by one record:** the id arm is matched **case-sensitively**, since its character class is literally `[0-9a-f]` and folding it would widen the class; the phrase arm is matched **case-insensitively**, since its members are prose fragments and a sentence-initial `Previous session` or a shouted `THE PREVIOUS SESSION` is the same ask as a lower-case one. Phase 0's spike (`2026-09-17-session-recall-phase0/spike-hook.sh`) used `grep -oiP` on the phrase arm, so the case-insensitive form is the only one the injection probe ever tested. This is the same omission round 2 fixed on the id arm (the prose form scores 50 rather than 46), left unfixed on the phrase arm until Phase 2 measured it.

- **Id arm**, and this is the literal regex because round 2 caught the prose form scoring differently:

  ```
  (?<![/\w\-"'])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![/\w\-"'])
  ```

  The lookarounds exclude `/`, any word character (so adjacent hex and underscores), `-`, `"` and `'`. Pass 1 described this as "not adjacent to `/`, `"` or `'`", which omits `\w` and `-` and **scores 50 rather than 46**. An implementer working from the prose would fail this doc's own Phase 2 criterion. The test separates a session id from a string literal (`const SID_SHARED: &str = "9d4c1f28-..."`) and from `image-cache/<uuid>/1.png`. A naive match scores 849; this scores 154.
- **Phrase arm**, enumerated in full because Phase 0 exists to decide it and an unenumerated list is unreproducible:
  - `previous|last|prior|earlier` followed by `session|conversation|chat`
  - `the session where`
  - `that doc|design|spec we wrote|made|did`
  - **"yesterday" is NOT in the list.** 14 of its fires are diff text and it names no target.

**Result: 46 fires on 11,225 human prompts (0.41%), and 0 across all 6,820 non-human records.** Design-time figures, on round 3's 18,048-record extraction. Phase 2's frozen snapshot re-measures the shipped hook at 48 and 0; AC2 pins that figure and reconciles both differences.

### The corpus has a provenance flag, and this doc was not using it

Round 2's correction, and it is a methodology fix rather than a predicate fix. The doc says "no provenance field, so opener-matching is the only lever". **That is true of the live `UserPromptSubmit` payload and false of the corpus replay**: transcript records carry `isMeta` and `isSidechain`, and this doc's measurements ignored them.

- 2,052 records in the human bucket carry `isMeta`, including 1,187 `Base directory for this skill:` preambles, 505 `[Request interrupted...]` records, 2 summarizer prompts and 1 compaction continuation.
- **One of the 47 is one of them**, a `/doctor` expansion. True non-meta human fires: **46**.
- Phase 2's replay buckets on `isMeta` rather than on prefix guessing. The prefix bails stay, because the live hook has no flag to read; the replay does, and a measurement that guesses when it could read is the thing `taste.md` forbids.
- **The fence bail's stated purpose was also wrong.** Its 12 suppressed records are 9 skill preambles, 2 summarizer prompts and 1 compaction continuation, all machine records, not humans pasting code. The clause stays because dropping it moves the number, but it earns its place by suppressing machine records, not by the reason pass 4 gave.

### Why bails 1 and 2 replace the opener list as the sound answer

Bails 1 and 2 are prefix tests on how the harness delivers a record, not guesses about what a machine prompt looks like. They take all 30 false fires to 0 and leave human fires unchanged. Round 2 printed and read all 30 suppressed records: task notifications, bash stdout and agent deliveries, **zero genuine recall asks**, so the bails cost no recall.

**The zero on the security-review bucket is held jointly, and pass 4 credited it wrongly.** Of the 12 security-review records that pass the trigger, the fence clause alone leaves 11, while `>3 lines starting +`, bail 5, and bail 4 each independently leave 0. Bail 4 zeroes it because **all 12 are security reviews of the clyde repo and therefore contain the word `clyde`**. So that zero rests on an opener literal this doc calls incomplete plus the coincidence that Scott develops clyde. Neither is a property of the predicate, and the doc says so rather than banking it.

### Pushback recorded: the code-ish bail is one clause, not four

Round 1's architect seat held that fence-only leaves 24 security-review candidates where the 4-part bail leaves 0, and that `>3 lines starting +` is therefore load-bearing. **Measured, that is not so**, and the reason is ordering: bail 5 removes the entire security-review bucket before any code-ish test runs. With bails 1, 2, 4 and 5 in place, fence-only, fence-plus-diff-lines, and the full 4-part form all score **46 non-meta human / 0 false**, identically. The Rust literals `const ` and `&str` are dead weight, and so is the diff-line count.

Dropping code-ish **entirely** is the one variant that does move: **49 non-meta human fires**, so the fence clause suppresses 12 records carrying a fenced block and a UUID. Those 12 are **9 skill preambles, 2 summarizer prompts and 1 compaction continuation**, all machine records, not humans pasting code. The clause stays because dropping it moves the number, and its warrant is machine-record suppression. It stays as one clause.

### The two arms are not equivalent, and Phase 0 decides the phrase arm

The 46 split: **the id arm** 35 alone, **the phrase arm** 8 alone, 3 carrying both. The id arm is **82.6%** of the value (38 of 46).

- **The id arm is resolvable.** The prompt names an id the hook quotes back verbatim, so the injected line is corroborated by the prompt's own text. That satisfies the anti-injection requirement by construction.
- **The phrase arm is not.** "the session where we..." names no id. The hook can quote the matched phrase but cannot name a target, so the injected line is closer to an instruction the prompt does not support.

`docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md:167-173` (0b-3a) recorded the model refusing exactly that shape: *"Flagging per prompt-injection policy rather than acting on it."*

**If Phase 0 shows the phrase arm refused, the hook ships as the id arm alone at 38 of 11,225 (0.34%) and that is a pass, not a failure.** The phrase arm's job moves to `rules/recall.md`, which is always-on prose and cannot be read as injection.

### Implementation contract for the hook

Copied from `inline-skill-tokens.py`, which is the only `UserPromptSubmit` hook in the tree and already solved this problem:

- Registered at `HOME/.claude/settings.json` on matcher `*`.
- Emits exit 0 plus JSON on stdout: `hookSpecificOutput.hookEventName` = `"UserPromptSubmit"`, `hookSpecificOutput.additionalContext` = the string (`inline-skill-tokens.py:183-192`). Not exit-code signalling, not bare stdout. **It cannot deny**, and this hook does not try to.
- **The trigger is interpolated verbatim**, never replaced by a count or a paraphrase (`:66-85`).
- **Two branches with an explicit decline branch.** `inline-skill-tokens` carries one because 34% of its matched tokens are discussion rather than invocation.
- **No provenance.** The payload is seven keys (`cwd`, `hook_event_name`, `permission_mode`, `prompt`, `prompt_id`, `session_id`, `transcript_path`), measured at 2.1.274 and again at 2.1.272. The hook cannot tell a typed prompt from a harness-submitted one, so the decline branch is load-bearing rather than polite.

### Emitted text

> session-recall hook: this prompt names a prior session, quoted verbatim from it: {quoted}.
>
> Decide from the prompt's own wording:
> - asking about that session's content (what was decided, what was built, where a file went) -> resolve it with `Skill(session-recall)` before answering, and cite `path:line`.
> - naming it in passing (a statistic, an aside, a session you are already reading) -> resolve nothing. This line is context, not an order.

**The emitted text names the skill, not the clyde tools.** Two reasons, both from pass 3. The clyde MCP tools are deferred, so a raw `mcp__clyde__session_grep` in the injected line is a name the session cannot call until something runs `ToolSearch`; the skill already owns that step. And naming the tools in both the hook and the skill is the derived-field problem from `taste.md`: two copies of one fact that drift. The skill is the single source.

### The clyde surface, written down once

The skill states these exactly. Every one of these is a name the model has guessed wrong:

| tool | required | optional | CLI |
|---|---|---|---|
| `mcp__clyde__sessions_search` | `query` | `limit`, `include_archived`, `sort` | `clyde session search` |
| `mcp__clyde__sessions_ls` | | `repo`, `since`, `tag`, `model`, `limit`, `include_archived` | `clyde session ls` |
| `mcp__clyde__session_open` | `id` | | `clyde session resume` |
| `mcp__clyde__session_grep` | `id`, `query` | `context_lines`, `limit` | none |
| `mcp__clyde__session_read` | `id` | `offset`, `limit` | none |
| `mcp__clyde__session_efficiency` | `id` | | `clyde efficiency session` |

Traps, all stated in the skill:

- Plural split is inconsistent and load-bearing: `sessions_search` | `sessions_ls` are plural, `session_open` | `session_grep` | `session_read` | `session_efficiency` are singular.
- `context_lines`, not `context` or `-C`. `include_archived`, not `archived`. `since`, with no `until`.
- `id` takes a unique prefix, not only a full UUID.
- `session_grep.query` is a plain case-insensitive substring. `sessions_search.query` is FTS. Same field name, different language.

### `rules/recall.md`

- Frontmatter: `---` at line 1, `alwaysApply: true` at line 2, `---` at line 3. That is the only key. **`.otto.yml:112-116` fails CI unless every `rules/*.md` except `voice.md` has `---` as its literal first line**, so a criterion demanding `alwaysApply: true` AT line 1 cannot coexist with a green `otto ci`. Round 3 caught exactly that contradiction between this doc's AC4 and AC5.
- **Budget target: <= 1,200 bytes**, the `otto.md` size class (1,085). Current always-on total is 43,706 across 11 files; effective prefix is 50,738 once `voice.md` (2,815, no frontmatter, loaded anyway) and `safety.md` (4,217, glob `**/*`) are counted.
- Carries what the hook's predicate cannot see: a recall ask with no id and no trigger phrase, and the tool-surface pointer.
- **Deletes nothing.** Enforcement-before-prose is satisfied vacuously here, as it was in chunk D: no existing clause is subsumed by this hook.

**There is no swap. This chunk is +1,200 bytes of always-on with no offset, and that is the accounting.** Pass 1 claimed one deletable clause and round 1 overturned it. Every clause in the neighbourhood stays:

| clause | verdict |
|---|---|
| `interaction.md:28-29` read the actual thing first | **STAYS.** Round 1 overturned this doc's own pass-1 verdict by reading the domains: that clause governs repos, files and configs; this hook governs prior sessions. Disjoint |
| `interaction.md:30-31` name the exact artifact before starting | STAYS, fires at action time on a target the model chose |
| `interaction.md:32` list candidates and ask which | STAYS, disambiguation, orthogonal |
| `taste.md:142-144` no guesses, search/read/run first | STAYS, covers questions with no named target |
| `marquee.md:6` marquee URL goes to `marquee read` | STAYS, same class, already tool-specific |

### WHOAMI vocabulary

- `HOME/.claude/WHOAMI.md`, symlinked (not copy-deployed) via `manifest.yml`'s top-level `link:` block, `recursive: true` with the `HOME: $HOME` mapping. Edits go live on save.
- New `## Vocabulary` section, placed after `## Tools & workflow`. Terms: rp, panel, rmrf, bkup, lappy, desk, shipit, bump, sdv, handoff.
- **Nothing mechanical reads WHOAMI.** Its only consumer is the `@~/.claude/WHOAMI.md` include in `CLAUDE.md`. So this change is documentation with no enforcement seam, which is a departure from the program's enforcement-before-prose rule and is recorded as such rather than claimed as a guard.

## Implementation Plan

Order is enforcement before prose: nothing is deleted from a rule until the thing replacing it is live and green.

#### Phase 0: prove the injection survives
**Model:** opus
- **Mechanism, because this needs stating:** pasting the candidate text into a prompt does NOT test this. `additionalContext` arrives as harness-supplied context, not as user text, and 0b-3a's refusal was of the hook path specifically. So Phase 0 registers a throwaway hook in a scratch project's `settings.local.json`, emitting the candidate string. No production file is written and nothing lands in `HOME/.claude/`.
- Id arm: a prompt carrying a session id. Phrase arm: a prompt carrying only "the session where we...".
- **The spike's text names the clyde tools directly, NOT `Skill(session-recall)`.** Phase 0 runs before Phase 1 creates that skill, so a criterion phrased as "produces a `Skill(session-recall)` invocation" is satisfied by an unresolvable attempt at a skill that does not exist. Round 1 caught that. The signal Phase 0 is actually reading is refusal versus no-refusal.
- Record both responses verbatim in `docs/design/2026-09-17-session-recall-phase0/evidence.md`.
- Also re-measure the seven payload keys at the running harness version, since the design leans on their absence and the last measurement was 2.1.274.
- **Third probe, new in round 2: does bail 1 eat slash commands?** 546 `<command-*>` records sit in the tagged bucket and one of them trips the trigger. Whether that wrapper is a transcript artifact or the live payload is unsettled: a prior spike saw raw pre-expansion `/command` text at `evidence.md:189-201`, which suggests artifact. Round 1's architect seat asserted flatly that bail 1 "breaks the hook for all slash-command-driven agents"; that is not established, and it is cheap to settle. Type a slash command and log the raw payload. If the live `prompt` begins with `<`, bail 1 needs a carve-out for `<command-`.
- **Success criteria:** the id arm draws **no prompt-injection refusal** (an attempted retrieval counts, a refusal does not); the phrase arm's verdict is recorded either way, and a refusal narrows the shipped trigger to the id arm without failing the phase; the payload key list is recorded and still carries no provenance field; the slash-command probe records whether the live `prompt` value begins with `<`.

#### Phase 1: the `session-recall` skill
**Model:** sonnet
- `HOME/.claude/skills/session-recall/SKILL.md`, mirroring `vault-recall/SKILL.md` structure exactly: frontmatter `name` + `description` (description carries the whole trigger surface with quoted phrases and the "even if he doesn't mention clyde" closer), H1, one-paragraph why, `## Steps` as numbered imperatives, `## Rules` as bullets.
- Steps open with ToolSearch (`select:mcp__clyde__sessions_search,mcp__clyde__session_read,mcp__clyde__session_grep`), then the tools with named params, then the documented fallback.
- `## Rules` copies `vault-recall:22-26`'s shape: context-loading step not a deliverable, keep the summary short; zero results is a fine answer, say so in one line; do not pad.
- **Success criteria:** `SKILL.md` names at least the five retrieval tools and their required parameters; every parameter name it does name appears in clyde's MCP schema; the skill resolves under `Skill(session-recall)`. The floor is required here for the same reason AC3 carries it: the conformance half alone passes for a stub naming nothing.

#### Phase 2: `session-recall-guard.sh` and its matrix
**Model:** opus
- The hook: five bails then two triggers as specified, narrowed further by Phase 0's verdict on the phrase arm, emitting via `additionalContext` and naming `Skill(session-recall)` rather than raw clyde tools.
- UUID predicate excludes `/`-adjacent matches, which is what separates 154 from 849.
- `session-recall-guard-test.sh` with all ten fixture classes from the acceptance criteria, each asserting fire or bail plus the exact emitted string on a fire. The test matrix needs no `.otto.yml` edit: `:126` globs `HOME/.claude/hooks/*-test.sh`.
- **Add `session-recall-guard.sh`, its test, and this design doc to `.otto.yml`'s em-dash lint `FILES` list, which is enumerated rather than globbed and already names every prior chunk's doc/hook/test triple.** Round 3 found this; it is the same missed-registration class as the `manifest -l` finding in round 1.
- **`manifest -l HOME/.claude/hooks/session-recall-guard.sh` runs in THIS phase.** `~/.claude/hooks` is 36 per-file symlinks, so a new hook file has none and does not go live on commit. Pass 1 put the link step only in Phase 3 for the rule and missed that the hook needs its own; round 1 caught it, and it is chunk B's four-failed-guards lesson exactly.
- Registered in `settings.json` in this phase, after the symlink exists.
- **Success criteria:** corpus replay over the frozen snapshot fires exactly on the id list this phase commits as a fixture, and zero on every non-human record in that snapshot; `otto ci` exits 0. The count is not hardcoded: Phase 0's verdict decides which arms ship, and the snapshot decides the figure. **Settled:** Phase 0 found no refusal on either arm, so both ship, and Phase 2's snapshot measures **48 and 0** (AC2 carries the pinned figure and the reconciliation to round 3's 46).

#### Phase 3: `rules/recall.md`
**Model:** sonnet
- New always-on rule, `<= 1,200` bytes. **Nothing is deleted**: round 1 reclassified `interaction.md:28-29` as STAYS, and round 2 caught this phase still carrying pass 1's deletion in its title, its body and its criterion.
- `manifest -l` **in this phase**: `/home/saidler/repos/.claude/rules/` is per-file symlinks, so a new rule does not go live on commit. Four ported guards failed open this exact way in chunk B.
- **Success criteria:** `recall.md` resolves through the live symlink path; it contains the enumerated phrase list and the clyde tool names, asserted by grep, so an empty or stub file fails; always-on total grows by `<= 1,200` bytes.

#### Phase 4: WHOAMI vocabulary
**Model:** sonnet
- `## Vocabulary` section after `## Tools & workflow`, ten terms.
- **Success criteria:** every term the audit named is present; `~/.claude/WHOAMI.md` resolves to the repo file.

## Acceptance Criteria

Counts below are pinned to a **frozen corpus snapshot** taken in Phase 2, not to a live re-walk. The corpus grew by 5 prompts during this doc's own drafting, so a live count is not reproducible and an exact-count criterion against it would be the measured-before-the-change defect.

- [ ] `session-recall-guard.sh --self-test` exits 0, and its matrix carries at least one fixture per class: id paste (fires), phrase-only (fires), quoted UUID in a diff (bails), `image-cache/` UUID (bails), "yesterday" in diff text (bails), fenced block carrying an id (bails), prompt naming clyde (bails), `You are ...` provenance-summarizer (bails), **leading `<` tag (bails)**, **`Another Claude session sent a message:` wrapper (bails)**.
  **Observed on main:** `HOME/.claude/hooks/session-recall-guard.sh`: "No such file or directory (os error 2)". Cannot pass before Phase 2.
- [ ] Replayed over the frozen snapshot, the hook's fire set is **exactly equal** to the enumerated id list committed in Phase 2 at `docs/design/2026-09-17-session-recall-phase2/fires.tsv`, and empty across every non-human record in that snapshot. **Set equality, not coverage.** Round 3 broke the coverage form two ways: a regex selecting zero records "fires on all of them" and passes, and `predicate OR prompt=="hello"` fires 56 times, misses none of the 46, hits no non-human record, and also passes. Phase 2 commits the id list as a fixture file so the comparison has a fixed left side.
  **Pinned figure, Phase 2's snapshot** (18,093 records, taken 2026-09-18 06:44 local, sha256 `8cdb7907cce747a554d0ca44ba2f51925d4d22ad20d14770b9b7d4222aef687e`): **48 non-meta human fires, 0 across all 6,843 non-human records.** Round 3's figures were 46 and 6,820 on an 18,048-record extraction, and both differences are accounted for rather than tuned:
  - `00938fec-3b63-42df-bbc1-3d603e13da61.jsonl:543` is a record typed at 06:25 local on 2026-09-18, after round 3's fold commit at 00:52. This is the case the preamble above pre-authorises: a live count is not reproducible, so 46 was always a snapshot-era figure.
  - `59d90b84-06ce-4305-8069-e6b65a30f7fa.jsonl:94` fires only under the phrase arm's case folding, now stated explicitly in `The predicate`. Round 3's count implied a case-sensitive phrase arm that the doc never specified.
  - The non-human total moved 6,820 to 6,843 on the same corpus growth, and the fire count there is 0 either way.
  - **Reconciliation, for a future reader:** restricting Phase 2's snapshot to records older than round 3's fold commit AND folding the phrase arm case-sensitively reproduces **46 / 0** exactly, and that restriction also reproduces round 3's denominators to the record (isMeta 2,052, security-review 1,862). So the extraction method is confirmed identical and case folding was the only predicate-level difference.
  **Observed on main:** no hook exists, so the zero half is vacuously true and the fire half **fails**. The predicate itself measures 46 non-meta human fires and 0 non-human; without bails 1 and 2 it is 46 and 30.
- [ ] `session-recall/SKILL.md` names **at least the five retrieval tools and their required parameters** from the clyde table above (the table lists six; `session_efficiency` is not required), every parameter name it does name is present in clyde's live MCP schema, and the skill resolves under `Skill(session-recall)`. The floor is there because round 2 found the schema-conformance half passes universally for a stub naming no parameters at all.
  **Observed on main:** `HOME/.claude/skills/session-recall/SKILL.md`: "No such file or directory (os error 2)". Cannot pass before Phase 1.
- [ ] `rules/recall.md` is `<= 1,200` bytes, resolves through `/home/saidler/repos/.claude/rules/recall.md` as a symlink into the repo, opens with `---` at line 1 and `alwaysApply: true` at line 2, and **contains the enumerated phrase list and at least three clyde tool names**. Size and symlink alone passed for an empty file, which round 2 flagged as the reason the +1,200 bytes looked unearned.
  **Observed on main:** `/home/saidler/repos/.claude/rules/recall.md`: "No such file or directory (os error 2)". Cannot pass before Phase 3. The rewritten frontmatter form was checked against the CI gate on a scratch file: `---` / `alwaysApply: true` / `---` passes `.otto.yml:112`'s `awk 'FNR==1 && $0 != "---"'`, so AC4 and AC5 are now jointly satisfiable. The deletion half is **withdrawn**: `interaction.md:28-29` stays.
- [ ] `readlink -e ~/.claude/hooks/session-recall-guard.sh` resolves into the repo, **`jq` finds `session-recall-guard.sh` under `hooks.UserPromptSubmit` in `HOME/.claude/settings.json`**, and `otto ci` exits 0.
  **Why the registration check is explicit:** `hooks-preflight.sh` exits 0 unconditionally (final line) and warns only through `additionalContext`, so an exit-code criterion passes with the hook absent. Round 2 went further and ran it against an in-memory `{"hooks":{}}` fixture: exit 0, empty stdout, empty stderr, with the symlink still resolving. Preflight iterates registrations that exist and never asserts a required one is present, so **linked does not mean registered** and readlink-plus-empty-stdout was vacuous too. Only the `jq` assertion bites. The same hole sits in chunk D's shipped criterion 4 and is handed on.
  **Observed on main:** `readlink -e ~/.claude/hooks/session-recall-guard.sh` resolves nothing. The registration query
  `jq -r '[.hooks.UserPromptSubmit[]?.hooks[]?.command] | map(select(test("session-recall-guard"))) | length' HOME/.claude/settings.json`
  returns **0**. `otto ci` exits **0**. Both halves of the criterion therefore fail on main, which is the point: the earlier exit-code form passed here.

## Resolved Decisions

- **2026-09-18 (panel round 3): AC4 and AC5 were mutually unsatisfiable.** AC4 required `alwaysApply: true` at line 1; `.otto.yml:112-116` fails CI unless every `rules/*.md` except `voice.md` has `---` as its literal first line; AC5 required `otto ci` green. A file satisfying AC4 as written failed CI. Frontmatter is now `---` / `alwaysApply: true` / `---`.
- **2026-09-18 (panel round 3): AC2 was the sixth vacuous criterion**, and coverage was the wrong relation. A regex selecting zero records satisfied "fires on every record the predicate selects", and so did `predicate OR prompt=="hello"` at 56 fires. Replaced with set equality against an id list committed as a fixture in Phase 2.
- **2026-09-18 (panel round 3): probe 3's carve-out branch admits exactly one record, and it is a human ask.** `22a56659...jsonl:4`, a `/doctor` whose args read "in the last session". The prefix bucketing filed it as non-human. The branch reclassifies it (47 fires, 11,226 human) rather than booking a false fire. Measured before the probe runs, so neither branch is a surprise.
- **2026-09-18 (panel round 3): the deletion recurred in two more places**, the Overview and the ship-order note, after round 2 fixed four. Same class both times: a reversed decision landing in the table and the log but not everywhere the plan repeats it.
- **2026-09-18 (panel round 3): Phase 1's success criterion still carried the universal-only schema check** that round 2 fixed in AC3. The fix landed in the AC block and not in the phase gate.
- **2026-09-18 (panel round 3): the pushback's reason is overturned a second time, and the result stands a third.** Round 1 said fence-only is equivalent; round 2 said the ordering argument was right on the result and wrong on the reason; round 3 measured the 12 security records directly: fence-only leaves 11, while the diff-line clause, bail 4 and bail 5 each independently leave 0. The equivalence is held jointly, not by ordering.
- **2026-09-18 (panel round 3): the new artifacts need adding to `.otto.yml`'s em-dash lint `FILES` list**, which is enumerated, not globbed. Neither seat found it. The test matrix does not, because `:126` globs `*-test.sh`.
- **2026-09-18 (panel round 3): the hook is `bash`, not Python.** Performance said "One Python process" from the `inline-skill-tokens.py` precedent, which is cited for its contract, not its language.
- **2026-09-18 (panel round 3): all four load-bearing counts re-derived and confirmed** on a fresh 18,048-record extraction: 46 non-meta human fires, 38 id-arm-only, 29 for bail 4, and the 12/11 security split. The 43,706 and 50,738 byte figures also confirmed. No count changed.
- **2026-09-18 (panel round 2): the corpus carries `isMeta`, and this doc was guessing instead of reading it.** 2,052 meta records sit inside the 11,225, one of them among the fires. 47 -> **46**. Phase 2's replay buckets on the flag. The "no provenance field" claim is true of the live payload only, and the doc now says which.
- **2026-09-18 (panel round 2): the id-arm regex goes in the doc verbatim.** The prose form ("not adjacent to `/`, `\"` or `'`") omits `\w` and `-` and scores 50, not 46. An implementer working from the prose would fail Phase 2.
- **2026-09-18 (panel round 2): Phase 3 stopped ordering a deletion that round 1 had already withdrawn.** Title, body, success criterion and AC4 all still carried it. The fold-in updated the verdict table and the decision log and missed the plan, which is the class of defect an implementation audit catches late.
- **2026-09-18 (panel round 2): three more criteria were vacuous.** AC2 passed for a hook that never fires; AC3 passed for a stub naming no parameters; AC5's readlink-plus-empty-stdout passed with the hook linked but unregistered, proven against a `{"hooks":{}}` fixture. All three now assert the positive case. `hooks-preflight.sh` cannot carry any of this: it iterates the registrations that exist and never asserts a required one is present.
- **2026-09-18 (panel round 2): bail 4 drops 29, not 34, and its wording narrowed.** Naming clyde makes the hook injection redundant, not the skill. All 29 were read: 13 reached MCP tools, 10 the CLI, 6 neither and all 6 accounted for. No case of the model ignoring an eligible ask.
- **2026-09-18 (panel round 2): the security-review zero is jointly held, and pass 4 credited it wrongly.** Of the 12 records that pass the trigger, fence-only leaves 11; the diff-line clause, bail 4 and bail 5 each leave 0. Bail 4 zeroes it only because all 12 are reviews of the clyde repo. The doc records the coincidence rather than banking on it.
- **2026-09-18 (panel round 2): `rules/recall.md` stays, against the architect seat's "cut it".** It is named in F1's scope at `2026-09-13-setup-audit-program.md:30-39`, so cutting it is unrequested scope removal and reopens a settled decision. The defect was that AC4 checked size and symlink only, so an empty file passed. AC4 now greps for the phrase list and the tool names.
- **2026-09-18 (panel round 2): bails 1 and 2 cost zero recall.** All 30 suppressed records were printed and read: task notifications, bash stdout, agent deliveries. The slash-command class is unsettled and became a Phase 0 probe rather than an assumption.
- **2026-09-17 (panel round 1): the denominator was wrong and 30 false fires were hidden by it.** 13,567 -> 11,225 human prompts; 2,351 agent deliveries begin `Another Claude session sent a message:` and slip a `startswith("<")` test. Bails 1 and 2 added; false fires 30 -> 0, human fires unchanged at 47.
- **2026-09-17 (panel round 1): `interaction.md:28-29` is NOT deletable**, reversing this doc's own pass-1 verdict. Its domain is repos/files/configs, the hook's is prior sessions. This chunk is +1,200 bytes with no offset and says so.
- **2026-09-17 (panel round 1): the hook needs its own `manifest -l`, in Phase 2.** `~/.claude/hooks` is 36 per-file symlinks. Pass 1 linked only the rule.
- **2026-09-17 (panel round 1): "hooks-preflight exits 0" is not a criterion.** It exits 0 unconditionally and warns through `additionalContext`. Replaced with a `readlink -e` plus empty-stdout assertion. The same defect is live in chunk D's shipped criterion 4 and is handed to whichever chunk owns it.
- **2026-09-17 (panel round 1): Phase 0 names the clyde tools, not the skill.** It runs before Phase 1 creates the skill, so a skill-invocation criterion passes on an unresolvable attempt. The signal is refusal versus no-refusal.
- **2026-09-17 (panel round 1): the phrase list is enumerated in the doc.** It was unreproducible, which mattered because it is the arm Phase 0 decides.
- **2026-09-17, pushback sustained on measurement: the code-ish bail is one clause.** The architect seat held that fence-only leaves 24 security-review candidates. Measured with bails 1, 2, 4 and 5 in place, fence-only and the full 4-part form both score 46 non-meta human / 0 false. Round 3 overturned the *reason*: it is not that bail 5 runs first. Of the 12 security records passing the trigger, fence-only leaves 11 while the diff-line clause, bail 4 AND bail 5 each independently leave 0, and bail 4 does so only because all 12 are reviews of the clyde repo. Dropping code-ish entirely moves the number (49 non-meta human), so the fence clause stays and the Rust literals and diff-line count go.
- **2026-09-17: the audit's hook trigger is not built.** 38.2% of typed prompts. Recorded as Alternative 1.
- **2026-09-17: predicate (c) is dropped**, not deferred. 5.32% for no gain, and its negative lexical test is a shape already rejected once.
- **2026-09-17: a refusal of arm (b) in Phase 0 shrinks the trigger rather than failing the chunk.**
- **2026-09-17: change 4 ships as documentation.** No enforcement seam exists for WHOAMI. Stated rather than dressed up.

## Alternatives Considered

### Alternative 1: the audit's prescribed trigger
- **Description:** a prompt carrying a URL, a path, or "how do I" appends "read it or search sessions first; cite path:line".
- **Why not chosen:** 5,874 of 15,413 prompts, 38.2%. Two prompts in five would carry an injected paragraph. That is the always-on prefix bloat chunk H exists to trim, arriving through a side door. Its instruction also names nothing present in the prompt, which is the 0b-3a shape that got refused.

### Alternative 2: predicate (c), bare target with no action verb
- **Description:** fire when the prompt names a path or URL and contains no verb naming an action on it.
- **Why not chosen:** 5.32%, five times (d), for no additional recall. The predicate is a negative lexical test over a ~60-word verb list, rejected once already as `inline-skill-tokens`' Alternative 6. Hits are dominated by pasted output and image markers, not by bare targets awaiting instruction.

### Alternative 3: (d-loose), the research brief's recommendation
- **Description:** any non-path UUID, or recall phrasing including "yesterday". Briefed at 272 fires, 1.76%.
- **Why not chosen:** its denominator silently included 1,861 security-review harness messages. Separated, it is 157 typed fires (1.16%) plus **102 harness false fires**, 87 of them a UUID inside a pasted diff. Recorded here so it is not re-derived: the number looked fine because the false fires were inside the denominator rather than beside it.

### Alternative 4: a rule with no hook
- **Description:** ship `rules/recall.md` alone and skip the hook.
- **Why not chosen:** prose is the thing that already failed. `taste.md` and the 09-08 confirm-target rule both say read-the-target-first, and the correction class is still rising at 24.3 per 1000.

## Technical Considerations

### Data Model

None. The hook is a pure function of the prompt string: no cache, no ledger, no state file. This is deliberate and it is why the hook needs no cleanup path, unlike chunk D's SLACK ledger.

### Performance

- `UserPromptSubmit` fires **once per prompt**, not once per tool call. Chunk D's 689 ms figure was ten Bash `PreToolUse` guards summed across every Bash invocation; this is a different budget and a far smaller one.
- One `bash` process, one pass over the prompt. The hook is `session-recall-guard.sh`, matching the tree's other guards; `inline-skill-tokens.py` is cited for its `additionalContext` contract and its verbatim-quoting discipline, not for its language. The bails run first and short-circuit on pasted diffs, which are the longest prompts in the corpus.

### Dependencies
- clyde's MCP server, already installed.
- `manifest -l` for the rules symlink. No new external dependency.

### Security
- The hook reads prompts and emits context. It cannot deny and holds no state.
- No credential path is touched. The UUID predicate is a format match, not a lookup.

### Testing Strategy
- `session-recall-guard-test.sh` in the `*-test.sh` glob, picked up by `.otto.yml`'s test task without an edit.
- Deny-style fixtures do not apply (the hook cannot deny). Fixtures assert fire | no-fire and the exact emitted string.
- Corpus replay is a measurement, not a committed test: it reads `~/.claude/projects` and cannot be hermetic. Decisive cases become fixtures, per chunk D's Phase 3 precedent.

### Rollout Plan
- Single repo, `scottidler/claude`. No PR: this repo takes none. Land with `git push origin session-recall:main`, never `git checkout`, per the 2026-09-13 hazard.
- The hook goes live on commit (per-file symlink into the repo). The rule does not: it needs `manifest -l`.

## Blast radius and ship order

- One repo. No cross-repo work, unlike D2.
- Phase 2 before Phase 3: the rule points at the hook's behaviour, so the hook is live and green first. No prose is deleted in either phase.
- Phase 1 before Phase 2: both the hook and the rule point at the skill by name.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Arm (b) refused as prompt injection | Med | Low | Phase 0 measures it; trigger shrinks to (a), arm (b)'s job moves to prose |
| Hook fires on harness prompts | High | Low | No provenance field exists; decline branch is explicit, and the harness case is a fixture |
| `recall.md` grows past its budget | Med | Med | Criterion pins <= 1,200 bytes; `otto.md` is the reference |
| Rule ships but never links | Med | High | `manifest -l` in the same phase; chunk B lost four guards this way |
| Skill names a parameter that does not exist | Med | High | Criterion checks every name against the schema; six documented traps |
| A harness prompt with a novel opener fires the hook | Med | Low | No provenance field exists, so opener-matching is the only lever and it cannot be complete. The decline branch is the backstop, and this is stated as a residual hole rather than closed |
| The phrase arm is refused and the hook shrinks to 0.32% | Med | Low | Recorded as a pass. The id arm is 79% of the value |

## Open Questions

None. Everything the five passes and two panel rounds raised is closed in the doc or converted into a Phase 0 probe, which is a phase, not a parked question.

- **Is the audit's trigger shippable?** No. 38.2%. Closed by measurement, Alternative 1.
- **Does the phrase arm survive the injection policy?** Phase 0 probe 1. Not open, because the design specifies both outcomes: refusal narrows the hook to the id arm at 38 of 11,225 (0.34%) and that is a recorded pass.
- **Does bail 1 eat slash commands?** Phase 0 probe 3. Not open, and round 3 measured both branches so neither is a surprise. A `<command-` carve-out admits **exactly one** additional tagged record: `22a56659-7581-452b-b285-92af1ba18d75.jsonl:4`, a `/doctor` whose `command-args` read "...after you cleaned a bunch of things up in the last session". It fires on the phrase arm. **That record is a genuine human recall ask that this doc's prefix bucketing filed as non-human**, so the carve-out branch reclassifies it into the human set (47 human fires, 11,226 human records) rather than counting it as a false fire. The non-human zero survives either way. Under id-only both branches are unchanged.
- **Does the WHOAMI change have an enforcement seam?** No, and it ships as documentation with that stated.
- **Is `rules/recall.md` worth +1,200 bytes with no prose offset?** Settled against the architect seat: it is named in F1's scope, so cutting it is unrequested scope removal. The defect was the acceptance test, now fixed to fail on an empty file.

## References

- Program baton: `docs/design/2026-09-13-setup-audit-program.md`
- Audit overview: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-overview-2026-09-12/
- Audit dense report: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/
- Injection-refusal measurement: `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md:167-187`
- Hook precedent: `HOME/.claude/hooks/inline-skill-tokens.py:66-96,132-140,183-192`
- Skill precedent: `HOME/.claude/skills/vault-recall/SKILL.md`
- Parked bare-word case: `HOME/.claude/hooks/inline/tests.py:57-63`
