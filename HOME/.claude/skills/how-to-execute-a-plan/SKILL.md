---
name: how-to-execute-a-plan
description: Execute a phased implementation plan from a design document. Implements each phase with tests, validates with otto ci, and commits with meaningful messages.
---

# How to Execute a Plan

A systematic workflow for implementing multi-phase design documents created with the Rule of Five methodology.

## Execution Mode

Pick one. Both produce the same result — per-phase commits, `otto ci` green,
implementation notes, then finalization. They differ only in *who* implements
each phase.

- **Delegated (default).** For each phase, spawn the `phase-implementer` agent
  with that phase's **annotated model** (the `**Model:**` tag in the design
  doc — sonnet/opus/fable). Pass it the doc path, the phase, and the prior
  phase's commit SHA. It implements the phase in its own context and returns a
  report (commit SHA, CI status, notes appended, deviations, open questions).
  **You (the skill) stay the orchestrator:** sequence the phases, gate the next
  phase on the prior report being green, own the implementation-notes file's
  coherence, and run finalization once after the last phase. This is the only
  mode that actually honors per-phase model tags, and it mirrors the
  per-phase-per-context pattern by hand — but automated and in one session.
  - *Fallback if delegation isn't available* (no agent, or you'd rather drive
    it directly): just run the Inline mode below. Nothing else changes.

- **Inline (the original loop).** Implement every phase yourself in this
  context, exactly as the rest of this document describes. This is the proven
  path; use it whenever you want full visibility or the delegated path misbehaves.

Everything below — the loop steps, the commit format, the notes discipline, the
finalization sequence — applies to **both** modes. In Delegated mode the
`phase-implementer` agent performs steps 1-6 per phase and you perform step 7
(sequencing) and the finalization; in Inline mode you perform all of it.

## Prerequisites

Before using this skill, you must have:

1. **A design document** created using `/create-design-doc` with the Rule of Five methodology
2. **Phased implementation plan** - the design doc must have distinct phases
3. **Otto configured** - `.otto.yml` must exist for CI validation

**Ready-to-build gate (check before phase 1, HARD STOP on failure):** Scott
never builds with open questions or disputes. Verify in the doc:

- **Open Questions is empty** (or every remaining item is explicitly gated on a
  named external dependency)
- **Review-panel consensus reached** - findings folded in or pushed back with
  rationale; no unresolved pushbacks
- **Acceptance criteria present** - falsifiable overall asserts, and success
  criteria per phase (flag their absence; older docs may predate them)
- **Acceptance criteria EXECUTED** - every criterion naming a flag, column,
  path, exit code, count, or command carries a recorded observed-output line
  from having been run against current `main` (`/create-design-doc`'s
  ready-to-build gate). A criterion with no recorded output has not been
  checked against the running system, and that is the defect class that costs
  five phases of green CI before anyone notices. **Run the missing ones NOW,
  before phase 1** - it takes seconds and it is the cheapest point to find a
  criterion that names a flag which does not exist. Amending the doc here is
  free; amending it at finalization means the phases were built against a
  criterion nobody had verified.

If any check fails, STOP and report exactly what is unresolved instead of
starting phase 1. Building anyway is the process violation this gate exists
to prevent.

## The Execution Loop

For each phase in the design document:

```
┌─────────────────────────────────────────────┐
│  1. Read the phase requirements             │
│  2. Implement code                          │
│  3. Write tests for the implementation      │
│  4. Run `otto ci` to validate               │
│  5. Fix issues until CI passes              │
│  6. Commit with meaningful message          │
│  7. Move to next phase                      │
└─────────────────────────────────────────────┘
```

## Detailed Workflow

### Step 1: Read the Phase Requirements

Before writing any code:

```bash
# Read the design doc
cat docs/<feature>-design.md
```

Extract for the current phase:
- **Goals**: What must this phase accomplish?
- **Components**: What files/modules need to be created or modified?
- **Dependencies**: What from previous phases does this build on?
- **Success criteria**: How do we know this phase is complete?

### Step 2: Implement the Code

Follow the design doc specifications exactly. If the design doc uses `/rust-cli-coder` conventions:

- Create new modules in the appropriate location
- Use dependency injection (ports/traits)
- Return data, not side effects
- Keep the shell thin

**Key principle**: Implement ONLY what the phase specifies. No gold-plating.

### Step 2.5: Maintain Implementation Notes

As you implement, maintain `docs/design/<feature>-implementation-notes.md` — a
running, **append-only** record of anything a future reviewer should know about
how the implementation diverges from or interprets the design doc.

For each phase, append a section with all four buckets — even when empty, write
"None." so the agent is forced to consider each axis:

- **Design decisions** — choices you made where the spec was ambiguous
- **Deviations** — places where you intentionally departed from the spec, and why
- **Tradeoffs** — alternatives you considered and why you picked what you did
- **Open questions** — anything you'd want the user to confirm or revise

Rules:

- **Append, never edit.** If a later decision overrides an earlier one, add a
  new entry that supersedes it. Do not rewrite history.
- **Be specific.** Cite the file and function the decision affects.
- **Distinguish design-doc deviations from gap-filling.** A deviation modifies
  what the doc said; a design decision fills a gap the doc didn't address.
- **Never edit by hand mid-phase.** Append once per phase as part of the
  commit prep, not after every code change.

Template per phase:

```markdown
## Phase N: <phase name>

### Design decisions
- <decision> — <file:function> — <why>

### Deviations
- <deviation from spec> — <why>

### Tradeoffs
- <choice> vs. <alternative> — <why this one>

### Open questions
- <question for the user>
```

The file is committed with the final-phase commit alongside the design doc.
This pattern is from Thariq Shihipar (Anthropic, Claude Code lead); adapted
from `implementation-notes.html` to `.md` per repo conventions.

### Step 3: Write Tests

**Make sure we have tests that ensure the correctness of our implementation.**

Tests must accompany the implementation:

```rust
// Unit tests for each new function
#[test]
fn test_new_function_happy_path() { ... }

#[test]
fn test_new_function_error_case() { ... }
```

For Rust projects, tests go in:
- `#[cfg(test)] mod tests` blocks for unit tests
- `tests/` directory for integration tests

**Coverage target**: Every public function should have at least one test.

### Step 4: Run Otto CI

Validate the implementation:

```bash
otto ci
```

This runs:
- `cargo check` - compilation
- `cargo clippy` - linting
- `cargo fmt --check` - formatting
- `cargo test` - all tests

### Step 5: Fix Until CI Passes

If `otto ci` fails:

1. **Read the error carefully**
2. **Fix the specific issue** - don't introduce new changes
3. **Re-run `otto ci`**
4. **Repeat until green**

Common fixes:
- `cargo fmt` for formatting issues
- Address clippy warnings
- Fix test failures

### Step 6: Commit with Meaningful Message

Once CI passes, commit the phase.

**For the final phase commit**: include the design document itself in the commit and update its status to "Implemented" before committing. This ensures the design doc and its implementation are shipped together:

```bash
# Update design doc status
sed -i 's/^**Status:** Draft/**Status:** Implemented/' docs/design/<feature>.md

# Stage implementation + updated design doc + implementation notes
git add <implementation files> docs/design/<feature>.md docs/design/<feature>-implementation-notes.md
git commit -m "$(cat <<'EOF'
<type>(<scope>): <description>

<body explaining what this phase accomplishes>

Phase N of N: <phase name from design doc>
Design doc: docs/design/<feature>.md
EOF
)"
```

**For non-final phase commits**:

```bash
git add <implementation files>
git commit -m "$(cat <<'EOF'
<type>(<scope>): <description>

<body explaining what this phase accomplishes>

Phase N of M: <phase name from design doc>
Design doc: docs/design/<feature>.md
EOF
)"
```

**Commit message format**:

| Type | Use When |
|------|----------|
| `feat` | New functionality |
| `fix` | Bug fix |
| `refactor` | Code restructuring |
| `test` | Test additions |
| `docs` | Documentation changes |

**Example**:
```
feat(executor): implement task executor with Anthropic API

Add TaskExecutor that runs agentic loops for tasks, calling the
Anthropic API for completions and executing tool calls.

Phase 2 of 5: Task Executor
Design doc: docs/claude-code-parity-design.md
```

### Step 7: Move to Next Phase

After committing, **IMMEDIATELY** proceed to the next phase:

1. **Update your tracking** - note phase N is complete
2. **Read the next phase** - understand what comes next
3. **Check dependencies** - ensure previous phase provides what's needed
4. **Begin the loop again** - DO NOT STOP, DO NOT ASK THE USER

**CRITICAL: Do NOT ask the user "Ready for phase N?" or "Should I continue?"**
**CRITICAL: Do NOT pause between phases. Execute ALL phases in sequence until done.**

The user invoked this skill expecting all phases to be executed. Stopping to ask breaks the workflow.

## Phase Completion Checklist

Before moving to the next phase, verify:

- [ ] All code for this phase is implemented
- [ ] Tests exist and pass
- [ ] `otto ci` passes
- [ ] Implementation notes appended for this phase (all four buckets, "None." where empty)
- [ ] Commit message references the phase and design doc
- [ ] No unrelated changes were introduced
- [ ] **Final phase only**: Design doc status updated to "Implemented" and included in commit
- [ ] **Final phase only**: Implementation notes file included in commit

## Example Session

```
User: Execute phase 1 of docs/claude-code-parity-design.md

Agent:
1. Reading phase 1 requirements...
   - Implement Glob tool
   - Implement Grep tool
   - Implement Edit tool

2. Implementing Glob tool in src/agentic/tools/glob.rs...
   [writes code]

3. Writing tests for Glob tool...
   [writes tests]

4. Running otto ci...
   ✗ Clippy warning: unused variable

5. Fixing clippy warning...
   [edits code]

6. Running otto ci again...
   ✓ All checks pass

7. Implementing Grep tool...
   [continues through all phase 1 items]

8. Final otto ci for phase 1...
   ✓ All checks pass

9. Committing phase 1...
   feat(tools): add Glob, Grep, and Edit tools

   Phase 1 of 5: Tool Expansion
   Design doc: docs/claude-code-parity-design.md

[IMMEDIATELY continues to phase 2 without pausing]

10. Reading phase 2 requirements...
    - Create prompt.rs module
    - Write comprehensive system prompt
    ...

[continues until all phases complete]
```

## Handling Blocked Phases

If a phase cannot be completed:

1. **Document the blocker** in the design doc
2. **Create an issue** if external resolution needed
3. **Skip to next unblocked phase** if possible
4. **Return to blocked phase** when resolved

## Integration with Other Skills

| Skill | Integration |
|-------|-------------|
| `/create-design-doc` | Creates the design doc this skill executes |
| `/rust-cli-coder` | Coding conventions for Rust implementations |
| `/otto` | CI validation tool |
| `/bump` | Version bumping after all phases complete — only after the user approves at the finalization confirmation checkpoint |

## What NOT to Do

- **Don't stop to ask the user between phases** - execute ALL phases automatically
- **Don't ask "Ready for phase N?" or "Should I continue?"** - just continue
- Don't skip `otto ci` validation
- Don't commit without tests
- Don't combine multiple phases in one commit
- Don't deviate from the design doc without updating it first
- Don't gold-plate - implement exactly what the phase specifies
- **Don't push, tag, bump, or install without the finalization confirmation checkpoint** - these are irreversible/externally-visible and require explicit user approval first
- Don't finish the final phase without updating the design doc status to "Implemented"
- Don't leave the design doc out of the final phase commit

## After All Phases Complete

When the final phase is committed and CI is green, prepare the finalization
sequence. The per-phase loop (implement → test → CI → **local commit**) runs
without pausing because every step is local and reversible. Finalization is
different: it bumps the version, **pushes to remote**, **creates/pushes tags**,
and **installs a binary** — all irreversible or externally visible. Those steps
require an explicit user confirmation checkpoint (see step 3a) before they run.

### 0. Surface implementation notes

Before bumping/pushing, print the path to the implementation notes file and a
one-line summary of each phase's open questions. **Do not block** on the user —
they can act on it after the push. Example output:

```
Implementation notes: docs/design/<feature>-implementation-notes.md
- Phase 1 open questions: none
- Phase 2 open questions: Should retry logic also cover 5xx from upstream?
- Phase 3 open questions: none
```

### 0.5 Verify acceptance criteria

Before flipping the status, walk the doc's Acceptance Criteria section and
verify each assert against the actual code/behavior. Report pass/fail per
criterion. A criterion you cannot verify is reported as UNVERIFIED with the
reason - never silently assumed. If any criterion FAILS, the work is not done:
stop and surface it instead of proceeding to finalization.

**A criterion that arrives unexecuted is a DOC DEFECT, not work to do.**
`/create-design-doc`'s ready-to-build gate requires every criterion naming a
flag, column, path, exit code, or count to have been run against `main` and its
observed output recorded in the doc next to it. So if you reach this step and a
criterion has no ``Observed on main:`` line, the doc skipped its own gate:

- Do NOT contort the implementation to satisfy a criterion that was never
  executed. It may name a flag that does not exist.
- Run the command. Then decide WHICH of the two things is wrong, because the
  answer changes what you are allowed to do:

| what you proved | allowed action |
|---|---|
| The criterion is a **doc defect**: it names a flag/column/path that does not exist, contradicts another bullet of its own phase, or pins a count that phase's own work must change | **Amend the criterion in the doc**, with the reasoning and the command output that proves it, then continue |
| The criterion is **sound** and the code does not satisfy it | **STOP.** This is the "If any criterion FAILS" case above. Fix the code, or surface the blocker. Never amend a sound criterion to match the code |

**This distinction is the whole safety property.** "Amend the criterion" is a
license to fix a doc defect, NOT a license to make a failing implementation
pass. If you cannot articulate, in one sentence, why the criterion itself is
wrong independent of your code, then it is not a doc defect and you stop.

Record every amendment in the implementation notes, with the evidence.

Record every such amendment in the implementation notes. The pattern this
guards against cost five occurrences on `tatari-tv/clyde` #77
(https://github.com/tatari-tv/clyde/pull/77) before it was named.

### 1. Update design doc status and commit

Change the design doc's `**Status:**` from `Draft` to `Implemented`, then commit:

```bash
git add docs/design/<design-doc>.md
git commit -m "docs: mark <feature> design doc as implemented"
```

### 2. Implementation audit — BEFORE the checkpoint, not after

The doc is now `Status: Implemented`, so the reviewers run in Mode 2 and walk
every Implementation Plan bullet against the committed code. **Run it here**,
while every commit is still local and nothing is tagged, pushed, or deployed.
That is the whole point: a finding at this moment changes what ships. The same
finding after step 5 can only be fixed forward, on an ungated repo into a
`main` that is already live and daemons that have already restarted.

Offer it on its own line so the prompt predictor picks it up (Tab + Enter):

```
send to the review-panel agent for an implementation audit
```

Then **wait for the user**. They may run it, skip it, or defer it — all three
are fine, it is their call and it is not a gate. What is NOT fine is sailing
past it into the checkpoint without offering, or offering it once the push has
already happened.

Fold anything the audit turns up into the phase commits before continuing.

### 3. Confirmation checkpoint (REQUIRED before any irreversible action)

The remaining steps — bump, push, tag, install — are irreversible or externally
visible. **Stop here and get explicit user approval before running any of them.**

Display a summary of exactly what is pending, then wait for the user to confirm:

```
Ready to finalize. The following IRREVERSIBLE / EXTERNALLY-VISIBLE actions are pending:

  - Version bump: <current version> → <proposed version> (<patch|minor|major>)
  - git push (commits to <remote>/<branch>)
  - git push tags (tag <vX.Y.Z> to <remote>)
  - cargo install --path . (installs binary into ~/.cargo/bin)

Reply to approve. You may approve all, a subset (e.g. "bump and push, skip install"),
or decline. I will run ONLY what you approve.
```

Do not proceed past this point without an explicit affirmative response. If the
user declines or does not respond, stop — the per-phase commits are already
safely in local history and nothing is lost. Run only the actions the user
approved, in the order below.

### 4. Bump version (only if approved)

Use the `/bump` skill to increment the version. Default to `patch` unless the
design doc describes a breaking change (then `minor` or `major`).

### 5. Push (only if approved)

Push all commits and tags to the remote:

```bash
git push && git push --tags
```

### 6. Install (only if approved)

Build and install the release binary locally:

```bash
cargo install --path .
```

This step assumes a Rust CLI project (which is ~99% of what we build). If the
project is not Rust, substitute the equivalent install command.

### 7. Done means live (only after approved push/install)

Merged is not shipped. After the approved finalization actions complete,
verify at the runtime surface:

- Deployed service: `/sdv-probe` (or `verify`) until the new version lands,
  then exercise the affected endpoints hunting for defects
- Local CLI: run the installed binary against its real surface; for a new or
  reshaped interface, suggest `/cli-shakedown`
- Report what you exercised and what you observed - "green CI" and "pushed"
  are not evidence the feature works

### Finalization summary

```
┌──────────────────────────────────────────────────┐
│  0. Surface implementation notes (non-blocking)  │
│  1. Update design doc status + commit (local)    │
│  2. OFFER THE IMPLEMENTATION AUDIT — here, while │
│     nothing is tagged, pushed, or deployed       │
│  3. CONFIRMATION CHECKPOINT — get user approval  │
│     for the irreversible actions below           │
│  4. /bump (patch by default)        [if approved]│
│  5. git push && git push --tags     [if approved]│
│  6. cargo install --path .          [if approved]│
│  7. Verify at the runtime surface   [if shipped] │
└──────────────────────────────────────────────────┘
```

**The per-phase loop runs without pausing** (local commits only). But steps 4-6
push, tag, and install — those are gated behind the step 3 confirmation
checkpoint and run ONLY with explicit user approval. Never bump, push, tag, or
install without it.

## Closing

Report what shipped: the phase commits, the tag if one was cut, the CI result,
and anything that came back from the runtime check in step 7. Name explicitly
whatever is left undone and why — a blocked bullet, a criterion that could only
be measured after a deploy, an item the user has to run by hand.

Do NOT close by suggesting the implementation audit. It belongs at step 2,
before the irreversible actions. Suggesting it here asks the user to review
code that is already tagged, pushed, and deployed, where every finding is
fix-forward — which is why they will decline, and rightly.
