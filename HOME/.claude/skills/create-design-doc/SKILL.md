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

1. **Gather context** — understand problem, explore codebase, research if needed
2. **Draft** — use template below, focus on breadth
3. **Refine** — run passes 2-5, announcing each pass and documenting changes
4. **Converge** — when no significant changes, document is ready

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
- Be explicit about non-goals
- Always include alternatives considered
- NEVER include time estimates

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
[Phased approach]

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
