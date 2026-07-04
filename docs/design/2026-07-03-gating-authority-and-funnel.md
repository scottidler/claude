# Design Document: Gating Authority and the Funnel

**Author:** Claude (Fable 5), directed by Scott Idler
**Date:** 2026-07-03
**Status:** Draft
**Review Passes Completed:** 0/5 (author draft; Rule of Five not yet run)

## Summary

Give the pipeline's checkpoints real pass/fail authority. Today review-panel
and otto ci produce findings that Scott triages by hand, and the only hard
gate is per-action permission approval. This design makes the review-panel
emit a machine-readable verdict against the doc's acceptance criteria, makes
the execute/finalize skills consume that verdict as a blocking gate, and
chains the whole funnel (research -> design -> review -> implement -> audit ->
shakedown -> ship -> verify-live) into one orchestrated run. Once these gates
demonstrably hold, automode + retiring the per-action permit becomes removing
scaffolding instead of removing the only checkpoint.

## Problem Statement

### Background

Scott's funnel is already real and documented: /create-design-doc (Rule of
Five, phased plan, per-phase model tags) -> review-panel (Gemini Architect +
Codex Staff Engineer in parallel) -> consensus loop -> /how-to-execute-a-plan
(phase-implementer per phase, otto ci green, one commit per phase) ->
implementation audit -> /cli-shakedown -> ship -> verify live. As of
2026-07-03 the pipeline also carries his judgment corpus: reviewers get
`rules/taste.md` injected, design docs carry falsifiable Acceptance Criteria
and per-phase Success criteria, and /how-to-execute-a-plan has a ready-to-
build gate and an acceptance-criteria verification step.

### Problem

Every gate is advisory. Review-panel returns a prose findings list; nothing
downstream can branch on it. The ready-to-build gate is an instruction to a
model, not a checkable artifact. otto ci has real authority inside a phase
but none over the pipeline shape. The result: Scott is the only real gate, at
the per-action approval level (permit), which is both too blunt (approves
individual tool calls, not work quality) and too expensive (he reads nothing
by default, so approval is theater). Automode is blocked on exactly this:
removing permit today removes the only checkpoint that exists.

### Goals

- Review-panel emits a structured verdict (PASS / FAIL + must-fix list),
  scoped to the doc's Acceptance Criteria and the owner's standards, that
  downstream automation can branch on
- /how-to-execute-a-plan refuses to start without a PASS verdict on the doc,
  and refuses to finalize without a PASS implementation-audit verdict
- The funnel is runnable as one orchestrated unit with hard stops at each
  gate, surviving context windows (state lives in files, not chat)
- Gate outcomes are auditable artifacts on disk beside the doc

### Non-Goals

- Retiring permit / enabling automode - that is the follow-on decision once
  gates are observed holding; this doc only builds the gates (revisit after
  ~2 weeks of verdict-gated runs)
- Overriding Scott's authority - PASS/FAIL is computed against criteria HE
  approved in the doc; his recorded override always wins (reviewers advise,
  the owner decides)
- Changing otto or repo CI - otto ci already has authority; parked
- Multi-user / org rollout of the funnel - personal pipeline first; parked
  until it proves itself

## Proposed Solution

### Overview

Three additive pieces:

1. **Verdict contract.** review-panel appends a fenced `verdict` block (YAML)
   to its synthesis and writes it to `<doc>-verdict.yml` beside the design
   doc: `mode`, `verdict: pass|fail`, `must_fix: []`, `criteria: [{id,
   status}]`, `reviewers: {architect: ok|failed, staff: ok|failed}`, `date`.
   FAIL iff any must-fix finding stands or any acceptance criterion is
   unverifiable/false. One reviewer dying -> `verdict: fail` with reason
   `reviewer-unavailable` (fail closed, never fabricate).
2. **Gate consumption.** /how-to-execute-a-plan's ready-to-build gate checks
   for a Mode-1 verdict file with `pass`; its finalization checks for a
   Mode-2 (audit) verdict with `pass` before bump/push is even offered.
   Missing or FAIL verdict -> hard stop with the must-fix list.
3. **Funnel orchestrator.** A `/funnel` skill that chains the existing
   skills/agents with the gates between them: design-research -> author doc ->
   review-panel (loop until PASS or escalate) -> how-to-execute-a-plan ->
   review-panel Mode 2 (loop until PASS) -> shakedown -> ship checkpoint
   (Scott approval stays for irreversible actions) -> verify live. Each stage
   reads/writes state files (`docs/design/*.md`, `*-verdict.yml`,
   implementation notes), so the funnel resumes from artifacts, not memory.

### Architecture

No new binaries. The verdict contract lives in the review-panel agent (it
already Edits files); gates are additions to existing skill text; the funnel
is one new skill that only sequences existing pieces. Consensus rounds stay
as they are - the verdict is computed AFTER the fold-in/pushback loop, so it
records the converged state, not the first pass.

### Data Model

`<doc-basename>-verdict.yml`, one per mode per doc, overwritten per round:

```yaml
doc: docs/design/2026-07-03-example.md
mode: design-review        # or implementation-audit
round: 2
verdict: pass              # pass | fail
must_fix: []               # strings; non-empty forces fail
criteria:
  - id: AC1
    status: pass           # pass | fail | unverified
reviewers:
  architect: ok            # ok | failed
  staff: ok
date: 2026-07-03
```

`unverified` on any acceptance criterion forces `fail` - unverifiable is not
passing (no guessing).

### API Design

None (file contract only). The verdict block is also printed in the panel's
synthesis so a human reads the same thing the machine consumes.

### Implementation Plan

#### Phase 0: Prove the contract shape on a real doc
**Model:** sonnet
- Run review-panel by hand on an existing Implemented doc (Mode 2); write the
  verdict YAML manually from its findings; confirm the schema captures
  everything a gate needs
- **Success criteria:** a filled `*-verdict.yml` exists for a real doc and a
  5-line shell check (`yq .verdict`) can branch on it

#### Phase 1: Verdict emission in review-panel
**Model:** opus
- Extend review-panel Step 4 to compute and write the verdict file + print the
  block; fail-closed rules (reviewer death, unverified criteria, must-fix)
- **Success criteria:** panel run on a doc with a known planted gap yields
  `verdict: fail` naming it in `must_fix`; clean doc yields `pass`

#### Phase 2: Gates in how-to-execute-a-plan
**Model:** sonnet
- Ready-to-build gate requires Mode-1 `pass` verdict file; finalization
  requires Mode-2 `pass`; hard-stop messages list `must_fix`
- **Success criteria:** invoking the skill against a doc with a `fail`
  verdict stops before phase 1 and prints the must-fix list verbatim

#### Phase 3: /funnel orchestrator skill
**Model:** opus
- New skill chaining research -> doc -> panel(loop) -> execute -> audit(loop)
  -> shakedown -> ship checkpoint -> verify-live, resuming from artifacts
- **Success criteria:** one end-to-end run on a small real change produces
  every artifact (doc, two pass verdicts, notes, shakedown report) with zero
  mid-funnel questions to Scott other than the ship checkpoint

#### Phase 4: Observation window + automode decision addendum
**Model:** sonnet
- Run the funnel on real work; log every gate outcome; after the window,
  write an addendum with the evidence for/against retiring permit
- **Success criteria:** addendum cites >=3 funnel runs with zero gates
  wrongly passed (a wrongly-passed gate = a defect Scott later found that a
  criterion claimed to cover)

## Acceptance Criteria

- [ ] review-panel writes a `*-verdict.yml` beside every doc it reviews, and
      a planted must-fix gap yields `verdict: fail` naming it
- [ ] /how-to-execute-a-plan hard-stops (before phase 1) on missing/fail
      Mode-1 verdict, and finalization hard-stops on missing/fail Mode-2
- [ ] A reviewer failure (timeout/empty output) produces `fail /
      reviewer-unavailable`, never a fabricated pass
- [ ] One real change ships end-to-end through /funnel with the only human
      touchpoint being the irreversible-actions checkpoint
- [ ] Scott's recorded override in a doc's Resolved Decisions is respected:
      the panel does not re-raise it and it cannot flip a verdict

## Resolved Decisions

- (none yet - draft)

## Alternatives Considered

### Alternative 1: Grade findings inline in prose, no file
- **Description:** panel just labels findings must-fix/advisory in its text
- **Pros:** zero new artifacts
- **Cons:** nothing downstream can branch on prose; gate stays a vibe
- **Why not chosen:** the whole problem is that advisory prose has no authority

### Alternative 2: Build gating into otto (an `otto gate` task)
- **Description:** teach the task runner to evaluate verdict files
- **Pros:** real exit codes, CI-native
- **Cons:** otto is per-repo build tooling; the funnel spans skills, agents,
  and repos; couples a personal pipeline to a shared tool
- **Why not chosen:** wrong layer; revisit if verdicts ever need to block
  hosted CI

### Alternative 3: Workflow-engine orchestrator (harness Workflow scripts)
- **Description:** implement /funnel as a deterministic multi-agent workflow
  script instead of a skill
- **Pros:** deterministic control flow, parallel stages
- **Cons:** harness-specific; funnel state should live in repo artifacts so
  ANY session can resume it; stages are sequential anyway
- **Why not chosen for v1:** artifacts-on-disk beats engine state for
  resumability; parked - the skill can later delegate stages to a workflow

## Technical Considerations

### Dependencies
- `yq` for the shell-side verdict check (already installed). No new crates,
  no code - this is all skill/agent text plus one YAML file convention.

### Blast Radius
- scottidler/claude repo only (agents + skills + this doc). No tatari-tv
  repos change. Consumers: every future design-doc run; old docs without
  verdict files are unaffected until re-reviewed (the gate exempts docs whose
  review predates this design, by date).

### Performance
- One extra file write per panel round; negligible.

### Security
- Verdicts gate quality, not permissions. permit stays exactly as is until
  the Phase 4 addendum argues otherwise with evidence. Irreversible-action
  checkpoint (bump/push/tag/install) is retained unconditionally.

### Testing Strategy
- Planted-gap doc for fail-path; known-good doc for pass-path; reviewer-kill
  (timeout 1s) for fail-closed path. All three exercised in Phases 1-2.

### Rollout Plan
- Additive: gates activate only for docs reviewed after this ships. First
  real use is the next design doc through the pipeline.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Verdict theater: panel rubber-stamps `pass` | Med | High | criteria are falsifiable asserts from the doc; planted-gap test; Phase 4 observation window counts wrongly-passed gates |
| Gate friction on trivial fixes | Med | Low | gates apply only to design-doc work; targeted fixes never enter the funnel |
| Reviewer flakiness blocks work | Med | Med | fail-closed but retryable; panel rerun is cheap; persistent failure escalates to Scott, never auto-passes |
| Criteria gamed by writing weak asserts | Low | High | Mode-1 review explicitly judges criteria falsifiability (already wired into the panel prompt) |

## Open Questions

- [ ] Should the Mode-2 verdict also require the shakedown report clean, or
      is shakedown its own later gate? (leaning: own gate, CLI repos only)
- [ ] Verdict file committed with the doc, or gitignored as working state?
      (leaning: committed - it is the audit trail)
- [ ] Does /funnel subsume /rwl-a-plan or leave it as the alternate executor?

## References

- `~/repos/.claude/rules/taste.md` - the judgment corpus these gates enforce
- `~/repos/.claude/refs/design-exemplars.md` - exemplars incl. "acceptance
  criteria are assert statements" (14703cf9 | pentest)
- `~/.claude/agents/review-panel.md` - verdict emitter (Phase 1 target)
- `~/.claude/skills/how-to-execute-a-plan/SKILL.md` - gate consumer (Phase 2)
- Scott's funnel self-description: session c51a4c86 (-home-saidler,
  2026-07-02) - "I never build with open questions, or disputes"
