# Design Document: [Feature Name]

**Author:** [Name]
**Date:** [YYYY-MM-DD]
**Status:** Draft | In Review | Approved
**Review Passes Completed:** [X/5]

## Summary

[2-3 sentence overview of what this design accomplishes]

## Problem Statement

### Background
[Context and history leading to this design]

### Problem
[Clear statement of the problem being solved]

### Goals
- [Goal 1]
- [Goal 2]

### Non-Goals
- [Explicitly out of scope item 1 — one-sentence rationale]
- [Parked item — distinguish "excluded" from "parked", and give the revisit condition]

## Proposed Solution

### Overview
[High-level description of the solution]

### Architecture
[System architecture, components, and their interactions]

### Data Model
[Data structures, schemas, or models involved]

### API Design
[Interfaces, endpoints, or function signatures]

### Implementation Plan
[Phased approach. Each phase: **Model:** tag, the tasks, and **Success criteria:**
1-3 falsifiable assert-style statements for that phase. Phases are small,
legible, countable, independently committable; deterministic/cheap first.
If the design rests on an unproven environmental assumption, Phase 0 is a
zero-code spike that proves it.]

## Acceptance Criteria

[3-5 assert statements/phrases that evaluate TRUE when the work is finished.
Falsifiable and mechanically checkable — a named test, a command with expected
output, a probe result — not mission statements. These are what the
implementation audit verifies.]

- [ ] [assert 1]
- [ ] [assert 2]
- [ ] [assert 3]

## Resolved Decisions

[Decisions closed during review, dated, with who converged (author / Architect /
Staff Engineer / Scott) and any recorded divergence or override. Settled items
are not re-litigated — reviewers must not re-raise them.]

## Alternatives Considered

### Alternative 1: [Name]
- **Description:** [What this approach would look like]
- **Pros:** [Benefits]
- **Cons:** [Drawbacks]
- **Why not chosen:** [Reasoning]

## Technical Considerations

### Dependencies
[What this depends on, internal and external. Be direct-vs-transitive precise —
"no new crates" must be verified, not assumed.]

### Blast Radius
[Is this doc limited to this repo? Name every affected repo/consumer and the
ship order this forces. Cross-repo or system-mutating steps are operator steps
or their own tracked work — never buried plan bullets.]

### Performance
[Expected performance characteristics]

### Security
[Security implications and mitigations]

### Testing Strategy
[How this will be tested]

### Rollout Plan
[How this will be deployed/released]

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| [Risk 1] | Low/Med/High | Low/Med/High | [How to address] |

## Open Questions

- [ ] [Question 1 that needs resolution]
- [ ] [Question 2]

## References

- [Link to relevant docs, PRs, or resources — cite `path:line` for every claim
  about existing code, and full URLs down to the file]

## Addendum

[Rejected alternatives and deferred optimizations worth remembering, with the
reasoning — "we are rejecting doing this work for now, but we want to write it
down as a future possibility." Capture the road not taken so a future reader
does not re-litigate it from scratch. Omit the section if empty.]
