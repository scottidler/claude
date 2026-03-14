---
name: how-to-execute-a-plan
description: Execute a phased implementation plan from a design document. Implements each phase with tests, validates with otto ci, and commits with meaningful messages.
---

# How to Execute a Plan

A systematic workflow for implementing multi-phase design documents created with the Rule of Five methodology.

## Prerequisites

Before using this skill, you must have:

1. **A design document** created using `/create-design-doc` with the Rule of Five methodology
2. **Phased implementation plan** - the design doc must have distinct phases
3. **Otto configured** - `.otto.yml` must exist for CI validation

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

# Stage implementation + updated design doc
git add <implementation files> docs/design/<feature>.md
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
- [ ] Commit message references the phase and design doc
- [ ] No unrelated changes were introduced
- [ ] **Final phase only**: Design doc status updated to "Implemented" and included in commit

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
| `/bump` | Version bumping after all phases complete |

## What NOT to Do

- **Don't stop to ask the user between phases** - execute ALL phases automatically
- **Don't ask "Ready for phase N?" or "Should I continue?"** - just continue
- Don't skip `otto ci` validation
- Don't commit without tests
- Don't combine multiple phases in one commit
- Don't deviate from the design doc without updating it first
- Don't gold-plate - implement exactly what the phase specifies
- Don't push to remote until the user requests it
- Don't finish the final phase without updating the design doc status to "Implemented"
- Don't leave the design doc out of the final phase commit

## After All Phases Complete

When all phases are implemented:

1. **Review the full implementation** against the design doc
2. **Run final `otto ci`** to ensure everything works together
3. **Verify the design doc** was updated to "Implemented" and included in the final phase commit
4. **Consider version bump** with `/bump` if appropriate

**CRITICAL**: The design doc status MUST be updated to "Implemented" and the design doc MUST be included in the final phase commit. This is not optional -- it ensures the design doc and its implementation are always in sync in git history.
