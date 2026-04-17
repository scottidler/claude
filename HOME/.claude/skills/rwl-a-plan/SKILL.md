---
name: rwl-a-plan
description: Execute a phased implementation plan from a design document using rwl (ralph-wiggum-loop). Reads per-phase model annotations from the design doc and runs rwl once per phase with the appropriate model. Use this skill whenever the user wants to execute a design doc with rwl, says "rwl a plan", "execute this plan", "implement this design doc", or references a design doc for implementation. Prefer this over /how-to-execute-a-plan when the project has rwl installed.
---

# RWL-a-Plan

Execute a design document phase-by-phase using `rwl run`. Each phase gets its own rwl invocation with the model specified in the design doc's `**Model:**` annotation. Progress resets between phases so each starts clean.

## Why This Exists

The old approach (`/how-to-execute-a-plan`) runs all phases inside a single Claude conversation. As context grows, quality degrades. RWL solves this: every iteration starts fresh, reads progress from disk, does one small thing, and exits. This skill adds phase-level orchestration on top, reading model annotations from the design doc and calling rwl once per phase with the right `-M` flag.

## Prerequisites

1. A design document with distinct implementation phases (typically from `/create-design-doc`)
2. Phases should have `**Model:**` annotations (sonnet or opus). If missing, default to opus.
3. `rwl` installed and on PATH
4. `otto` configured (`.otto.yml` exists) for CI validation

## Workflow

### Step 1: Parse the Design Doc

Read the design doc. Extract the ordered list of phases and their model annotations. Each phase heading looks like:

```markdown
#### Phase N: <name>
**Model:** sonnet
```

Build and print the execution plan:
```
Phase 1: Scaffold CLI structure - Model: sonnet
Phase 2: Core algorithm - Model: opus
Phase 3: Tests and cleanup - Model: sonnet
```

### Step 2: Initialize RWL

```bash
rwl init
```

Creates `.rwl/` if it doesn't exist.

### Step 3: Execute Phases

Loop through each phase sequentially. For each phase:

1. **Clear progress** - remove `.rwl/progress.txt` so rwl starts fresh for this phase:
   ```bash
   rkvr rmrf .rwl/progress.txt
   ```

2. **Run rwl** with the phase's model in the background:
   ```bash
   rwl run --plan <path-to-design-doc> -M <model>
   ```
   Run via the Bash tool with `run_in_background: true`.

3. **Check the outcome** when the background task completes:
   - **Exit 0 (complete)** - Phase succeeded. Report iteration count, move to next phase.
   - **Exit 1 (max-iterations)** - Phase exhausted its budget. Read `.rwl/progress.txt` to diagnose. Report to user and **stop**.
   - **Exit 2 (stopped)** - User hit Ctrl-C. Report and **stop**.
   - **Exit 3+ (error)** - Runtime error. Report and **stop**.

4. **Report phase result** before moving on:
   ```
   Phase 1 (sonnet): complete in 4 iterations
   Phase 2 (opus): complete in 8 iterations
   ```

If any phase fails, stop execution and report which phase failed and why. Do not continue to subsequent phases.

### Step 4: Finalize

Only after ALL phases complete successfully:

1. **Update design doc status** - change `**Status:** Draft` to `**Status:** Implemented`
2. **Commit**:
   ```bash
   git add docs/design/<design-doc>.md
   git commit -m "docs: mark <feature> design doc as implemented"
   ```
3. **Bump version** using `/bump` (default patch; use minor/major for breaking changes)
4. **Push**:
   ```bash
   git push && git push --tags
   ```
5. **Install** (Rust projects):
   ```bash
   cargo install --path .
   ```

## How Phase Scoping Works

rwl's prompt template tells the LLM to read progress.txt and the plan file. When progress.txt is cleared between phases, the LLM starts from the beginning of the plan but sees the already-committed code from prior phases in the repo. It naturally picks up the next incomplete phase because earlier phases already exist as code.

If rwl is re-doing work from a previous phase, leave progress.txt intact instead of clearing it. The accumulated context helps the LLM understand what's already done. Try clearing first (cleaner), fall back to preserving if needed.

## What NOT to Do

- **Don't implement code yourself** - rwl spawns fresh Claude instances for that
- **Don't run `otto ci` yourself** - rwl handles validation
- **Don't ask the user between phases** - execute all phases in sequence
- **Don't continue past a failed phase** - stop and report
- **Don't guess what happened** - read rwl's exit code and `.rwl/progress.txt`

## Integration

| Tool | Role |
|------|------|
| `rwl` | Execution engine - iteration, validation, progress, commits |
| `otto ci` | External validation (invoked by rwl) |
| `/create-design-doc` | Creates the design doc with per-phase model annotations |
| `/how-to-execute-a-plan` | Alternative executor (single conversation, no rwl) |
| `/bump` | Version bumping during finalization |
