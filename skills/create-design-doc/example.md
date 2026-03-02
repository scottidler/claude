# Example: Rule of Five Review Process

## Pass 1: Draft

Creating initial design document...
Focusing on breadth over depth. Getting the shape right.

[Initial draft created]

## Pass 2: Correctness

Reviewing with fresh eyes for errors, bugs, invalid assumptions...

**Findings:**
- Incorrect assumption about database constraint in Data Model
- API endpoint naming doesn't follow existing /api/v2/* pattern
- Implementation plan has dependency ordering issue (step 3 depends on step 5)

**Changes made:**
- Corrected database constraint description
- Renamed endpoints to match existing conventions
- Reordered implementation steps

## Pass 3: Clarity

Checking: Can someone else understand and implement this?

**Findings:**
- Architecture section uses undefined acronyms
- Data Model section missing field descriptions
- Rollout Plan is vague

**Changes made:**
- Expanded acronyms and added glossary
- Added field descriptions and constraints
- Detailed rollout plan with specific phases

## Pass 4: Edge Cases

Asking: What could go wrong? What's missing?

**Findings:**
- No handling for concurrent updates
- Missing rate limiting consideration
- Security section doesn't address auth token expiration
- EXISTENTIAL CHECK: Yes, we're solving the right problem

**Changes made:**
- Added optimistic locking strategy
- Added rate limiting to API Design
- Expanded security section with token refresh flow

## Pass 5: Excellence

Final check: Is this something we'd be proud to ship?

**Findings:**
- Minor: Risk table missing one edge case from Pass 4
- Document is comprehensive and implementable

**Changes made:**
- Added concurrent update risk to table
- No other changes needed

**CONVERGENCE REACHED:** Document complete after 5 passes.
