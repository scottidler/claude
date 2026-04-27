---
alwaysApply: true
---

# Function-Level Debug Logging

A DEBUG-level log must tell the full story of a run without reading the source. When something fails, the operator scrolling logs at DEBUG should see exactly what entered each function — every parameter, every value — and exactly what came back out.

## The rule

**Every non-trivial function emits a DEBUG log on entry that records the function name and each meaningful parameter with its value.**

- Entry log names the function and prints every parameter that could matter for diagnosis.
- Exit records the outcome: a count, a status, the chosen branch. DEBUG on success; WARN on recoverable failure; ERROR on unrecoverable failure propagating out.
- Scope-identifying keys (the IDs the function operates on — a work ID, a request ID, a path) are carried so downstream warnings and errors inherit them.

## When to demote

- **Tight loops** (per-item validation, per-record iteration, anything firing dozens or more times per call) log at TRACE, not DEBUG. The surrounding function's entry/exit stays at DEBUG.
- **Trivial helpers** — getters, two-line transformers, pure formatting functions — need no log.
- **Sensitive or large payloads** — API keys, full prompts, full LLM responses, full subprocess stdouts — get logged as previews or length summaries, never inlined at full size.

## Why this rule exists

The failure mode: a function detects a problem, constructs a human-readable error string, returns it upward, and logs nothing. The caller catches the string and logs that — but by then the parameters that caused the failure are gone. The operator sees "same action repeated 3 times" with no trace of *which* action; "request failed" with no trace of *which* request; "file not found" with no trace of *which* file. Diagnosing requires rerunning at higher verbosity, which costs time, money, or both.

Every function missing its entry log is one diagnosis session spent rerunning a job that should have told its own story the first time.

## Test

After writing a function, ask: **"If this returned an error right now, could someone diagnose the cause from the DEBUG log without reading the source?"**

If the answer is no — the entry log is missing, or the wrong parameters are recorded — the function is not done.
