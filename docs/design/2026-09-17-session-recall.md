# Design Document: Session recall

**Author:** Scott Idler
**Date:** 2026-09-17
**Status:** Draft
**Review Passes Completed:** 1/5

## Summary

Chunk F1 of the setup-audit program, audit item 9. 73 sessions open by asking Claude to go find a previous session, and nothing in the setup encodes that. This builds the retrieval path (a `session-recall` skill over clyde's MCP surface), a narrow `UserPromptSubmit` hook that points at it when the prompt names a session, an always-on `rules/recall.md`, and a vocabulary section in WHOAMI.

The audit's prescribed hook trigger is not built. Measured, it fires on 38.2% of typed prompts. The trigger here fires on 1.76%.

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

- **The audit's prescribed hook trigger** ("a URL, a path, or how do I"). Excluded on measurement: 5,874 of 15,413 typed prompts, 38.2%. See Alternative 1.
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
  -> session-recall-guard.sh          trigger (d), 1.76% of prompts
     -> additionalContext             quotes the trigger verbatim, two branches
        -> session-recall skill       ToolSearch -> mcp__clyde__sessions_search | session_read
rules/recall.md (always-on)           covers the prompts the hook's predicate misses
WHOAMI vocabulary                     glossary, no enforcement seam
```

### The trigger, measured

Denominator: 15,413 typed user prompts in `~/.claude/projects`, harness-tagged `<...>` and `Caveat:` messages excluded.

| predicate | prompts | rate |
|---|---|---|
| (a) bare session-id UUID, `image-cache/` excluded | 154 | 1.00% |
| (b) recall phrasing: previous/last/prior/earlier session\|conversation\|chat, "yesterday", "that doc/design/spec we wrote", "the session where" | 127 | 0.82% |
| **(d) union of (a) and (b), the shipped trigger** | **272** | **1.76%** |
| (c) path or URL with no action verb, REJECTED | 820 | 5.32% |
| the audit's trigger, URL or path, REJECTED | 5,874 | 38.2% |
| reference: `inline-skill-tokens` survivors | 583 of 2,004 candidates | |

A naive UUID match returns 849 (5.51%). The bulk are `[Image: source: /home/saidler/.claude/image-cache/<uuid>/1.png]` markers. Excluding UUIDs adjacent to a `/` collapses it to 154, every sampled one a genuine session-id paste.

### The two arms are not equivalent, and Phase 0 decides arm (b)

- **(a) is resolvable.** The prompt names an id the hook quotes back verbatim. That satisfies the corroboration requirement by construction.
- **(b) is not.** "yesterday" names no target, so an injected line citing it is an instruction corroborated by nothing in the visible prompt.

This matters because it has already been measured. `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md:167-173` (0b-3a) recorded the model refusing exactly that shape: *"Flagging per prompt-injection policy rather than acting on it."*

If Phase 0 shows arm (b) refused, **the hook ships as (a) alone at 1.00% and that is a pass, not a failure.** Arm (b)'s work moves to `rules/recall.md`, which is prose and cannot be read as injection.

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
> - asking about that session's content (what was decided, what was built, where a file went) -> resolve it first with `mcp__clyde__session_read` for an id, or `mcp__clyde__sessions_search` for a phrase, then answer citing `path:line`.
> - naming it in passing (a statistic, an aside, a session you are already reading) -> resolve nothing. This line is context, not an order.

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

#### Phase 0: prove the injection survives, zero code
**Model:** opus
- Run both arms through a live session and record the model's response verbatim: (a) a prompt carrying a session id, (b) a prompt carrying only "the session where we..." with no id.
- Arm (b) is the one at risk. 0b-3a already recorded a refusal for an uncorroborated injected instruction.
- Record in `docs/design/2026-09-17-session-recall-phase0/evidence.md`.
- **Success criteria:** arm (a) produces a clyde call rather than a refusal; arm (b)'s verdict is recorded either way, and a refusal reduces the shipped trigger to (a) alone without failing the phase.

#### Phase 1: the `session-recall` skill
**Model:** sonnet
- `HOME/.claude/skills/session-recall/SKILL.md`, mirroring `vault-recall/SKILL.md` structure exactly: frontmatter `name` + `description` (description carries the whole trigger surface with quoted phrases and the "even if he doesn't mention clyde" closer), H1, one-paragraph why, `## Steps` as numbered imperatives, `## Rules` as bullets.
- Steps open with ToolSearch (`select:mcp__clyde__sessions_search,mcp__clyde__session_read,mcp__clyde__session_grep`), then the tools with named params, then the documented fallback.
- `## Rules` copies `vault-recall:22-26`'s shape: context-loading step not a deliverable, keep the summary short; zero results is a fine answer, say so in one line; do not pad.
- **Success criteria:** every parameter name in `SKILL.md` appears in clyde's MCP schema; the skill resolves under `Skill(session-recall)`.

#### Phase 2: `session-recall-guard.sh` and its matrix
**Model:** opus
- The hook, trigger (d) as narrowed by Phase 0, emitting via `additionalContext`.
- UUID predicate excludes `/`-adjacent matches, which is what separates 154 from 849.
- `session-recall-guard-test.sh` with the fixture classes: id paste, phrase-only, image-cache marker, security-review harness prompt, and a prompt already inside a clyde read.
- Registered in `settings.json` and verified by `hooks-preflight.sh` **in this phase**, per chunk B's lesson.
- **Success criteria:** corpus replay fires on the measured (d) set and zero times on the 95+ security-review harness prompts; `otto ci` exits 0.

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

- [ ] The hook fires on the measured (d) set and **zero** times on harness-submitted security-review prompts.
- [ ] Every parameter name appearing in `session-recall/SKILL.md` exists in clyde's MCP schema.
- [ ] `rules/recall.md` is `<= 1,200` bytes, resolves through the live symlink, and `interaction.md:28-29`'s clause is gone.
- [ ] `hooks-preflight.sh` exits 0 with the new hook registered, and `otto ci` exits 0.
- [ ] Every term the audit named appears in WHOAMI's vocabulary section.

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

### Alternative 3: a rule with no hook
- **Description:** ship `rules/recall.md` alone and skip the hook.
- **Why not chosen:** prose is the thing that already failed. `taste.md` and the 09-08 confirm-target rule both say read-the-target-first, and the correction class is still rising at 24.3 per 1000.

## Technical Considerations

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

## Open Questions

- [ ] None yet. Pass 1 has not been reviewed.

## References

- Program baton: `docs/design/2026-09-13-setup-audit-program.md`
- Audit overview: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-overview-2026-09-12/
- Audit dense report: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/
- Injection-refusal measurement: `docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md:167-187`
- Hook precedent: `HOME/.claude/hooks/inline-skill-tokens.py:66-96,132-140,183-192`
- Skill precedent: `HOME/.claude/skills/vault-recall/SKILL.md`
- Parked bare-word case: `HOME/.claude/hooks/inline/tests.py:57-63`
