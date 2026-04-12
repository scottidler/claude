---
name: rwl-a-plan
description: Execute a phased implementation plan from a design document using rwl (ralph-wiggum-loop). Delegates the entire plan to a single rwl run with fresh-context iterations and external validation via otto ci. Use this skill whenever the user wants to execute a design doc with rwl, says "rwl a plan", "execute this plan", "implement this design doc", or references a design doc for implementation. Prefer this over /how-to-execute-a-plan when the project has rwl installed.
---

# RWL-a-Plan

Execute a design document by pointing `rwl run` at it. RWL handles everything - fresh-context iterations, validation, progress tracking, phase transitions, auto-commits. This skill sets it up, kicks it off, reads the structured result, and acts on it.

## Why This Exists

The old approach (`/how-to-execute-a-plan`) runs all phases inside a single Claude conversation. As context grows, quality degrades. RWL solves this: every iteration starts fresh, reads progress from disk, does one small thing, and exits. Phases are just milestones within the plan - rwl's loop naturally progresses through them.

## Prerequisites

1. A design document with distinct implementation phases (typically from `/create-design-doc`)
2. `rwl` installed and on PATH
3. `otto` configured (`.otto.yml` exists) for CI validation

## Workflow

### Step 1: Initialize RWL

```bash
rwl init
```

Creates `.rwl/` if it doesn't exist.

### Step 2: Run RWL

Launch rwl in the background since it can take many iterations:

```bash
rwl run --plan <path-to-design-doc>
```

Run this via the Bash tool with `run_in_background: true`. While it runs, you can tell the user it's in progress - don't poll or sleep.

### Step 3: Read the Result

When the background task completes, read the output to get the session path (always the last `session:` line printed):

```bash
# Extract session path from rwl output
SESSION=$(grep '^session:' <output> | tail -1 | cut -d' ' -f2)
```

Then read result.json - this is the single source of truth for what happened:

```bash
cat "$SESSION/result.json"
```

**result.json fields:**
| Field | Meaning |
|-------|---------|
| `outcome` | `"complete"`, `"max-iterations"`, `"stopped"`, or `"error"` |
| `exit_code` | 0=success, 1=max-iters, 2=stopped, 3=runtime error |
| `iterations` | How many iterations ran |
| `duration_secs` | Wall-clock time |
| `validation_passed` | Whether the last validation check passed |
| `quality_gates_passed` | Whether quality gates passed (true only on complete) |
| `error` | Error/stop reason (null on success) |
| `plan` | Path to the plan file |

### Step 4: Act on the Outcome

Branch on the `outcome` field from result.json:

**`"complete"` (exit 0)** - Success. Report iterations and duration to the user, then proceed to Step 5 (Finalize).

**`"max-iterations"` (exit 1)** - The loop exhausted its iteration budget without completing. This is the most common failure mode. Diagnose it:
1. Read `$SESSION/progress.txt` - look at the last few iterations. Are validation errors repeating? Is the plan stuck on a particular phase?
2. Report to the user: how many iterations ran, whether validation was passing, and the pattern you see in progress.txt.
3. Common remedies: increase `--max-iterations`, fix an external issue (flaky test, wrong validation command), or simplify the plan.

**`"stopped"` (exit 2)** - The user hit Ctrl-C. WIP was auto-committed. Just report that it was interrupted and how many iterations completed.

**`"error"` (exit 3)** - A runtime error (Claude timeout, spawn failure). Read the `error` field from result.json for the specific message. If it's a timeout, suggest increasing `iteration_timeout_minutes` in `.rwl/rwl.yml`. For other errors, read `$SESSION/session.log` for the full context.

**Setup error (exit 4)** - rwl couldn't start (config parse failure, plan file missing, claude CLI not found). The error message on stderr explains what's wrong. Fix the prerequisite and retry.

### Step 5: Finalize

Only after a successful `"complete"` outcome:

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

## Session Files Reference

All session files live in the session directory (under `/tmp/rwl/<reposlug>/<timestamp>/`, not in the repo):

| File | Purpose | When to Read |
|------|---------|-------------|
| `result.json` | Structured outcome - the "what happened" answer | Always, first |
| `progress.txt` | Iteration-by-iteration log with validation errors | When diagnosing max-iterations or stuck phases |
| `session.log` | Full captured output (Claude output, validation, timing) | When you need the complete picture of a failure |

## What NOT to Do

- **Don't implement code yourself** - rwl spawns fresh Claude instances for that
- **Don't run `otto ci` yourself** - rwl handles validation
- **Don't split the plan into per-phase files** - rwl's iterations track phase progress naturally via progress.txt
- **Don't ask the user between phases** - rwl runs to completion autonomously
- **Don't guess what happened** - always read result.json for the structured outcome

## Integration

| Tool | Role |
|------|------|
| `rwl` | The entire execution engine - iteration, validation, progress, commits |
| `otto ci` | External validation (invoked by rwl) |
| `/create-design-doc` | Creates the design doc this skill consumes |
| `/bump` | Version bumping during finalization |
