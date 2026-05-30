---
alwaysApply: true
---

# Function-Level Debug Logging

## The rule

- Every non-trivial function emits a DEBUG log on entry: the function name and each meaningful parameter with its value
- Exit records the outcome (count, status, chosen branch): DEBUG on success, WARN on recoverable failure, ERROR on unrecoverable failure propagating out
- Carry scope-identifying keys (work ID, request ID, path) so downstream warnings/errors inherit them

## When to demote

- Tight loops (per-item/per-record, firing dozens+ times per call) → TRACE, not DEBUG; the surrounding function's entry/exit stays DEBUG
- Trivial helpers (getters, two-line transformers, pure formatters) → no log
- Sensitive/large payloads (API keys, full prompts, LLM responses, subprocess stdouts) → previews or length summaries, never inlined full

## Why this rule exists

- Failure mode: a function returns an error string upward and logs nothing — by the time the caller logs it, the causing parameters are gone
- Operator sees "same action repeated 3×" / "request failed" / "file not found" with no trace of *which*
- Diagnosing then needs a rerun at higher verbosity — costs time and money
- Every missing entry log = one diagnosis session rerunning a job that should've told its own story

## Test

- Ask: "if this returned an error now, could someone diagnose it from the DEBUG log without reading the source?"
- If no (entry log missing or wrong params) — the function isn't done
