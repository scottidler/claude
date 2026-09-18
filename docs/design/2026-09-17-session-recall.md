# Design Document: Session recall

**Author:** Scott Idler
**Date:** 2026-09-17
**Status:** Draft
**Review Passes Completed:** 5/5

## Summary

Chunk F1 of the setup-audit program, audit item 9. 73 sessions open by asking Claude to go find a previous session, and nothing in the setup encodes that. This builds the retrieval path (a `session-recall` skill over clyde's MCP surface), a narrow `UserPromptSubmit` hook that points at it when the prompt names a session, an always-on `rules/recall.md`, and a vocabulary section in WHOAMI.

The audit's prescribed hook trigger is not built. Measured, it fires on 38.2% of typed prompts. The trigger here fires on 0.41%: 56 of 13,567 typed prompts, zero of 1,861 security-review harness prompts.

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
3. `rules/recall.md`: always-on prose for what the hook cannot see, plus deletion of the one clause it replaces.
4. WHOAMI vocabulary section.

### Architecture

```
UserPromptSubmit
  -> session-recall-guard.sh          trigger (d), 0.41% of prompts
     -> additionalContext             quotes the trigger verbatim, two branches
        -> Skill(session-recall)      the skill owns ToolSearch and the clyde call
rules/recall.md (always-on)           covers the prompts the hook's predicate misses
WHOAMI vocabulary                     glossary, no enforcement seam
```

### The trigger, measured

Denominator: **13,565 typed user prompts** in `~/.claude/projects`. Harness-tagged `<...>`, `Caveat:`, and the 1,861 security-review harness messages are all excluded and counted separately, because the hook's false-fire rate on them is the thing that decides the predicate.

| predicate | typed | rate | harness false fires |
|---|---|---|---|
| the audit's trigger, URL or path | 5,874 | 38.2% | not measured, dominated |
| (c) path or URL with no action verb, REJECTED | 820 | 5.32% | not measured |
| (d-loose) any non-path UUID, or recall phrasing incl. "yesterday" | 157 | 1.16% | **102** |
| (d-tight) unquoted UUID, or recall phrasing minus "yesterday" | 111 | 0.82% | 12 |
| **(d) shipped: (d-tight) AND prompt is not code-ish** | **93** | **0.69%** | **0** |

**(d-loose) is what the research brief recommended, and it is wrong.** Two corrections, both measured:

- Its 1.76% was computed over a 15,413 denominator that silently included the 1,861 security-review harness messages. Separated, the typed rate is 1.16% and the harness class contributes **102 false fires**.
- 87 of those 102 are a UUID inside a pasted diff, e.g. `const SID_SHARED: &str = "9d4c1f28-7a3b-4a9c-93b1-6e2a90d1f042"`. The remaining 14 are the word "yesterday" inside diff text. Neither is a recall ask, and neither is peculiar to harness prompts: the same class appears in typed prompts that paste code.

So the shipped predicate is three conjoined tests:

1. **UUID is unquoted and not path-adjacent.** Not preceded or followed by `/`, `"` or `'`. This is what separates a session id from a string literal and from `image-cache/<uuid>/1.png`.
2. **Recall phrasing excludes "yesterday".** It names no target, so it is the least resolvable arm and the most code-contaminated. Dropped on both counts.
3. **The prompt is not code-ish.** Bails on a fenced block, more than three diff-marker lines, or the literals `const ` / `&str`. That is the whole test, stated exactly so the implementation has no latitude. It is a positive test on prompt shape, not a negative verb list, which is what separates it from rejected predicate (c).
4. **The prompt does not already name clyde.** 34 of the 93 say `clyde` outright. On those the hook is redundant: the model has already been handed the tool. Bailing is free recall loss and a real bloat saving.
5. **The prompt does not open agent-shaped.** Bails on a leading `You are `, `Summarize this Claude Code`, `Review this change for security`, `Analyze the following`. 5 more fires, all of them the marquee provenance-summarizer carrying a session id.

Bails 4 and 5 came out of pass 4 and they matter more than their size: **bail 5 is a second harness class the security-review filter never saw.** The payload has no provenance field, so opener-matching is the only lever, and this is the honest limit of it. Any harness prompt with a novel opener will fire, and the decline branch is what catches it.

Final: **56 fires, 0.41% of 13,567 typed prompts.**

| stage | fires | note |
|---|---|---|
| (d-tight), non-code-ish | 93 | 0.69% |
| minus already-names-clyde | -34 | redundant, model already has the tool |
| minus agent-shaped opener | -5 | provenance-summarizer class (2 overlap) |
| **shipped** | **56** | **0.41%** |

Test 3 is a heuristic and the doc says so. Its warrant is 0 false fires across 1,861 security-review messages, and it is pinned by fixtures rather than trusted.

### The two arms are not equivalent, and Phase 0 decides arm (b)

The shipped 56 splits: **the id arm** 41 alone, **the phrase arm** 12 alone, 3 prompts carrying both. The id arm is 79% of the value.

- **The id arm is resolvable.** The prompt names an id the hook quotes back verbatim, so the injected line is corroborated by the prompt's own text. That satisfies the anti-injection requirement by construction.
- **The phrase arm is not.** "the session where we..." names no id. The hook can quote the matched phrase but cannot name a target, so the injected line is closer to an instruction the prompt does not support.

This is not speculation. `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md:167-173` (0b-3a) recorded the model refusing exactly that shape: *"Flagging per prompt-injection policy rather than acting on it."*

**If Phase 0 shows the phrase arm refused, the hook ships as the id arm alone at 44 of 13,567 (0.32%) and that is a pass, not a failure.** The phrase arm's job moves to `rules/recall.md`, which is always-on prose and cannot be read as injection. The phase is written so that either verdict is a result.

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

- Frontmatter: `alwaysApply: true`, inside `---` fences, starting line 1. That is the only key.
- **Budget target: <= 1,200 bytes**, the `otto.md` size class (1,085). Current always-on total is 43,706 across 11 files; effective prefix is 50,738 once `voice.md` (2,815, no frontmatter, loaded anyway) and `safety.md` (4,217, glob `**/*`) are counted.
- Carries what the hook's predicate cannot see: a recall ask with no id and no trigger phrase, and the tool-surface pointer.
- **Deletes `interaction.md:28-29`**, the read-the-actual-thing-first clause, once the hook is live and its matrix is green.

**This is not a clean swap, and the doc says so rather than dressing it up.** One clause out, one file in. Everything else in the neighbourhood stays because it covers more than this chunk:

| clause | verdict |
|---|---|
| `interaction.md:28-29` read the actual thing first | DELETABLE, the hook carries it whole |
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
- Record both responses verbatim in `docs/design/2026-09-17-session-recall-phase0/evidence.md`.
- Also re-measure the seven payload keys at the running harness version, since the design leans on their absence and the last measurement was 2.1.274.
- **Success criteria:** the id arm produces a `Skill(session-recall)` invocation or a clyde call rather than a refusal; the phrase arm's verdict is recorded either way, and a refusal narrows the shipped trigger to the id arm without failing the phase; the payload key list is recorded and still carries no provenance field.

#### Phase 1: the `session-recall` skill
**Model:** sonnet
- `HOME/.claude/skills/session-recall/SKILL.md`, mirroring `vault-recall/SKILL.md` structure exactly: frontmatter `name` + `description` (description carries the whole trigger surface with quoted phrases and the "even if he doesn't mention clyde" closer), H1, one-paragraph why, `## Steps` as numbered imperatives, `## Rules` as bullets.
- Steps open with ToolSearch (`select:mcp__clyde__sessions_search,mcp__clyde__session_read,mcp__clyde__session_grep`), then the tools with named params, then the documented fallback.
- `## Rules` copies `vault-recall:22-26`'s shape: context-loading step not a deliverable, keep the summary short; zero results is a fine answer, say so in one line; do not pad.
- **Success criteria:** every parameter name in `SKILL.md` appears in clyde's MCP schema; the skill resolves under `Skill(session-recall)`.

#### Phase 2: `session-recall-guard.sh` and its matrix
**Model:** opus
- The hook: five conjoined tests as specified, narrowed further by Phase 0's verdict on the phrase arm, emitting via `additionalContext` and naming `Skill(session-recall)` rather than raw clyde tools.
- UUID predicate excludes `/`-adjacent matches, which is what separates 154 from 849.
- `session-recall-guard-test.sh` with all eight fixture classes from the acceptance criteria, each asserting fire or bail plus the exact emitted string on a fire.
- Registered in `settings.json` and verified by `hooks-preflight.sh` **in this phase**, per chunk B's lesson.
- **Success criteria:** corpus replay over the frozen snapshot fires 56 times and zero times on the 1,861 security-review harness messages; `otto ci` exits 0.

#### Phase 3: `rules/recall.md`, and the one deletion
**Model:** sonnet
- New always-on rule, `<= 1,200` bytes.
- Delete `interaction.md:28-29`. Nothing else in that section moves.
- `manifest -l` **in this phase**: `/home/saidler/repos/.claude/rules/` is per-file symlinks, so a new rule does not go live on commit. Four ported guards failed open this exact way in chunk B.
- **Success criteria:** `recall.md` resolves through the live symlink path; `interaction.md` no longer contains the deleted clause; always-on total grows by less than 1,200 bytes net of the deletion.

#### Phase 4: WHOAMI vocabulary
**Model:** sonnet
- `## Vocabulary` section after `## Tools & workflow`, ten terms.
- **Success criteria:** every term the audit named is present; `~/.claude/WHOAMI.md` resolves to the repo file.

## Acceptance Criteria

Counts below are pinned to a **frozen corpus snapshot** taken in Phase 2, not to a live re-walk. The corpus grew by 5 prompts during this doc's own drafting, so a live count is not reproducible and an exact-count criterion against it would be the measured-before-the-change defect.

- [ ] `session-recall-guard.sh --self-test` exits 0, and its matrix carries at least one fixture per class: id paste (fires), phrase-only (fires), quoted UUID in a diff (bails), `image-cache/` UUID (bails), "yesterday" in diff text (bails), security-review harness prompt (bails), prompt naming clyde (bails), `You are ...` provenance-summarizer carrying an id (bails).
  **Observed on main:** `HOME/.claude/hooks/session-recall-guard.sh`: "No such file or directory (os error 2)". Cannot pass before Phase 2.
- [ ] Replayed over the frozen snapshot, the hook fires on the id and phrase classes and **exactly zero** times on the 1,861 security-review harness messages. (Zero is the guarded value; the loose predicate scores 102 there, so this criterion bites.)
  **Observed on main:** no hook exists, so the fire count is 0 everywhere and the harness half is vacuously satisfied. The id/phrase half **fails** on main and only becomes meaningful after Phase 2. The predicate itself was measured today at 56 typed fires and 0 harness fires; the loose form scores 102 harness fires, which is what makes the zero non-trivial.
- [ ] Every parameter name appearing in `session-recall/SKILL.md` is present in clyde's live MCP schema, checked name by name, and the skill resolves under `Skill(session-recall)`.
  **Observed on main:** `HOME/.claude/skills/session-recall/SKILL.md`: "No such file or directory (os error 2)". Cannot pass before Phase 1.
- [ ] `rules/recall.md` is `<= 1,200` bytes, resolves through `/home/saidler/repos/.claude/rules/recall.md` as a symlink into the repo, and `rg -c 'read the actual thing first' HOME/repos/.claude/rules/interaction.md` returns no match.
  **Observed on main:** `/home/saidler/repos/.claude/rules/recall.md`: "No such file or directory (os error 2)". `rg -c 'read the actual thing first' HOME/repos/.claude/rules/interaction.md` returns **1** (one matching line), which is the pre-state this criterion inverts. Cannot pass before Phase 3.
- [ ] `hooks-preflight.sh` exits 0 with the new hook registered, and `otto ci` exits 0.
  **Observed on main:** `hooks-preflight.sh` exits **0** and `otto ci` exits **0** today, both without the new hook. The criterion's force is the phrase "with the new hook registered", which only Phase 2 can satisfy.

## Resolved Decisions

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
- One Python process, one regex pass over the prompt. The code-ish bail runs first and short-circuits the expensive path on pasted diffs, which are the longest prompts in the corpus.

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
- Phase 2 before Phase 3: the hook is live and green before its prose is deleted.
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

None. Five passes run, and the three questions they raised are closed in the doc rather than parked:

- **Is the audit's trigger shippable?** No. 38.2%. Closed by measurement, Alternative 1.
- **Does the phrase arm survive the injection policy?** Unknown until Phase 0 runs, but it is not an open question because the design specifies both outcomes: refusal narrows the hook to the id arm at 0.32% and that is a recorded pass.
- **Does the WHOAMI change have an enforcement seam?** No, and it ships as documentation with that stated.

## References

- Program baton: `docs/design/2026-09-13-setup-audit-program.md`
- Audit overview: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-overview-2026-09-12/
- Audit dense report: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/
- Injection-refusal measurement: `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md:167-187`
- Hook precedent: `HOME/.claude/hooks/inline-skill-tokens.py:66-96,132-140,183-192`
- Skill precedent: `HOME/.claude/skills/vault-recall/SKILL.md`
- Parked bare-word case: `HOME/.claude/hooks/inline/tests.py:57-63`
