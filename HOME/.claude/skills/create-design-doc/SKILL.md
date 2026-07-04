---
name: create-design-doc
description: Create high-quality design documents using Jeffrey Emanuel's Rule of Five methodology. USE WHEN the user wants to create a design doc, technical specification, RFC, or architecture document for a feature or system.
---

# Create Design Document

Apply **Jeffrey Emanuel's Rule of Five**: agents produce best output when forced to review their work 4-5 times until convergence.

> **Full research:** `~/repos/scottidler/obsidian/notes/jeffrey-emanuel-rule-of-five-agentic-llm.md`

## The Five Passes

| Pass | Name | Focus |
|------|------|-------|
| **1** | **Draft** | Breadth over depth. Get the shape right. Use template below. |
| **2** | **Correctness** | Fix errors, bugs, invalid assumptions. Is the logic sound? |
| **3** | **Clarity** | Can someone else understand and implement this? |
| **4** | **Edge Cases** | What could go wrong? What's missing? *Ask: "Are we solving the right problem?"* |
| **5** | **Excellence** | Is this something you'd be proud to ship? |

**Task size guidelines:** Small features: 2-3 passes. Large/critical: 4-5 passes.

## Process

0. **Load the owner's judgment** — read `~/repos/.claude/rules/taste.md` and
   `~/repos/.claude/refs/design-exemplars.md` before drafting. Designs are
   judged against those standards (copy in-house precedent, decompose along
   change frequency, config drives behavior, fail loudly/closed, phase-0
   spikes for unproven assumptions), not generic best practice. Keep the prose
   direct: bullets before paragraphs, pipes/arrows where useful, flat verdicts,
   and no em-dashes.

1. **Gather context** — understand the problem and explore the codebase.
   **Default: delegate the dig to the `design-research` agent** (pass it the
   artifact path — shakedown/bullets/issue — plus the repo root). It runs the
   heavy investigation in its own context and returns a brief: verified root
   cause, the affected `path:line` surface, prior art/constraints, and a draft
   phased plan with model tags. Draft from that brief.
   *Fallback:* if no agent is available or the artifact is trivial, research
   inline as before — the rest of this skill is unchanged either way.
2. **Draft** — use template below, focus on breadth
3. **Refine** — run passes 2-5, announcing each pass and documenting changes.
   The pass counter in the header reports ONLY passes that actually ran —
   never fabricate "X/5" (write "0/5" honestly if the ritual was skipped).
4. **Converge** — when no significant changes, document is ready
5. **Review panel** — send the doc (plus your open questions) to the
   `review-panel` agent. Then run the consensus loop: fold in everything you
   agree with, send pushbacks WITH rationale back to the reviewers seeking
   consensus, escalate to Scott only what the agents cannot close. NEVER
   silently drop or defer a finding. **The doc is ready to build only when
   every finding is dispositioned and Open Questions is empty** — Scott never
   builds with open questions or disputes.

See [example.md](example.md) for a sample review process.

## Prompts for Each Pass

**Correctness:**
> "Review with 'fresh eyes' for logical errors, invalid assumptions, technical inaccuracies. Fix what you find."

**Clarity:**
> "Review as a new team member who must implement this. What's confusing? Simplify."

**Edge Cases:**
> "What are the weakest parts? What could go wrong? What's missing?"

**Excellence:**
> "Final pass. Make it shine. Proud to ship? Fits the larger system?"

## Output

Save to `docs/design/YYYY-MM-DD-feature-name.md` or user-specified location.

## Key Rules

- Start with the problem, not the solution
- Be explicit about non-goals (distinguish "excluded" from "parked with a revisit condition")
- Always include alternatives considered; rejected drafts and deferred options go in an Addendum so they aren't re-litigated
- Every requirement is traceable to who asked for it — unrequested scope is illegitimate regardless of quality
- Acceptance criteria are falsifiable assert statements (3-5 overall, 1-3 per phase) — they are what the implementation audit verifies
- State the cross-repo blast radius and the ship order it forces
- The doc is the single source of truth: agreed changes land IN the doc, not in follow-on lists or agent memory
- NEVER include time estimates
- NEVER pre-name future version numbers in filenames or content

## Template

```markdown
# Design Document: [Feature Name]

**Author:** [Name]
**Date:** [YYYY-MM-DD]
**Status:** Draft | In Review | Approved
**Review Passes Completed:** [X/5]

## Summary
[2-3 sentence overview]

## Problem Statement

### Background
[Context and history]

### Problem
[Clear statement of the problem]

### Goals
- [Goal 1]

### Non-Goals
- [Explicitly out of scope]

## Proposed Solution

### Overview
[High-level description]

### Architecture
[Components and interactions]

### Data Model
[Structures, schemas, models]

### API Design
[Interfaces, endpoints, signatures]

### Implementation Plan

Each phase must include a **Model** annotation indicating which Claude model
should execute it. Pick based on complexity:

- **sonnet** - scaffolding, boilerplate, mechanical refactors, simple wiring
- **opus** - complex logic, algorithmic work, tricky integrations, novel design

Each phase also gets **Success criteria:** 1-3 falsifiable assert-style
statements (a named test, a command with expected output, a probe result).
If the design rests on an unproven environmental assumption, Phase 0 is a
zero-code spike that proves it.

Example:

#### Phase 0: Prove the gateway passes Bearer tokens
**Model:** sonnet
- curl the deployed endpoint with an existing token — zero code
- **Success criteria:** authenticated request returns 200; unauthenticated returns 302 to Okta

#### Phase 1: Scaffold CLI structure
**Model:** sonnet
- [tasks...]
- **Success criteria:** [assert...]

#### Phase 2: Core algorithm
**Model:** opus
- [tasks...]
- **Success criteria:** [assert...]

#### Phase 3: Tests and cleanup
**Model:** sonnet
- [tasks...]
- **Success criteria:** [assert...]

## Acceptance Criteria

[3-5 assert statements that evaluate TRUE when the work is finished —
falsifiable and mechanically checkable, not mission statements. The
implementation audit verifies these.]

- [ ] [assert 1]
- [ ] [assert 2]

## Resolved Decisions

[Dated decisions closed during review, with who converged and any recorded
override. Settled items are not re-litigated.]

## Alternatives Considered

### Alternative 1: [Name]
- **Description:** [Approach]
- **Pros:** [Benefits]
- **Cons:** [Drawbacks]
- **Why not chosen:** [Reasoning]

## Technical Considerations

### Dependencies
[Internal and external]

### Performance
[Characteristics, benchmarks]

### Security
[Implications and mitigations]

### Testing Strategy
[How tested]

### Rollout Plan
[Deployment approach]

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| [Risk] | Low/Med/High | Low/Med/High | [Mitigation] |

## Open Questions
- [ ] [Question needing resolution]

## References
- [Links to relevant docs]
```
