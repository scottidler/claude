# Phase 0 evidence: panel round cap

Run 2026-09-14 on desk.lan, Claude Code 2.1.272.
Design doc: `docs/design/2026-09-14-panel-round-cap.md`.

Scratch artifacts under `/tmp/claude-1000/p0c/` (probe hooks, scratch `--settings` file,
captured payloads). Method is chunk A Phase 0b verbatim: a scratch hook that tees stdin to a
file and returns a deny decision, registered via `--settings` on a nested `claude -p` run.

**Verdict: PASS on all four facts. Phase 1 is unblocked and the doc is not reopened.**

## 0c-1: a `PreToolUse` hook on matcher `Agent` fires, and its payload carries the keys the design needs

Scratch settings registered exactly one `PreToolUse` entry, `"matcher": "Agent"`. A nested
`claude -p` session (model sonnet, cwd `/home/saidler/repos/scottidler/claude`) was told to
issue one `Agent` call with `subagent_type` `review-panel`.

One payload captured, verbatim (session/tool/prompt ids and transcript path redacted, nothing
else altered):

```json
{
  "cwd": "/home/saidler/repos/scottidler/claude",
  "effort": {
    "level": "high"
  },
  "hook_event_name": "PreToolUse",
  "permission_mode": "auto",
  "prompt_id": "<redacted>",
  "session_id": "<redacted>",
  "tool_input": {
    "description": "panel probe",
    "prompt": "Design Review of docs/design/2026-09-14-panel-round-cap.md",
    "run_in_background": false,
    "subagent_type": "review-panel"
  },
  "tool_name": "Agent",
  "tool_use_id": "<redacted>",
  "transcript_path": "<redacted>.jsonl"
}
```

Against the design's "What the dispatch payload carries" section:

- `tool_name` is `Agent`, so the matcher name is the tool name. PASS.
- `tool_input.subagent_type` and `tool_input.prompt` are both present, as sibling keys. PASS.
  This was the one fact "Nothing anywhere shows a PreToolUse payload for the `Agent` tool"
  said was unproven. It is now proven.
- `cwd` is present and absolute. PASS. The doc called this mandatory rather than optional;
  see 0c-3 for the re-measured cost of ignoring it.
- Two keys the doc did not predict: `tool_input.description` and `tool_input.run_in_background`.
  Neither is load-bearing for the guard. Recorded so Phase 1 does not treat the key set as
  closed.
- `effort` is new at 2.1.272 relative to the Stop payload chunk A captured at 2.1.270. Not used.

## 0c-2: a deny from that hook blocks the dispatch, and the denial text reaches the caller

The probe returned:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"probe: phase 0c Agent matcher fired and denied"}}
```

The nested session reported, verbatim:

```
The Agent call was denied verbatim:

PreToolUse:Agent hook error: probe: phase 0c Agent matcher fired and denied

Not retrying per instructions.
```

Two things proven at once, both of which the Bash design (Alternative 3) fails:

- The subagent never started. No `/tmp/review-panel` run dir was minted by this dispatch.
- The `permissionDecisionReason` text landed in the **caller's** context, which is where the
  party that overruns lives. The design's whole argument for moving off the Bash seam was that
  a deny inside the panel subagent may never reach its caller (`review-panel.md:281-288`).
  The `Agent` seam does not have that problem.

## 0c-3: doc-path extraction hit rate

Gate: at or above 96% over at least 25 sampled real prompts. Measured over **all 348** real
`review-panel` `Agent` dispatches in `~/.claude/projects`, not a sample of 25.

Extractor under test (the reference algorithm Phase 1 implements):

1. Collect every `[A-Za-z0-9_./~@+-]*\.md` token in `tool_input.prompt`.
2. Drop companion artifacts, `*-review-log.md` and `*-implementation-notes.md`, unless they
   are the only candidates. They are never the doc under review.
3. Prefer the first candidate under a `design/` path; otherwise the first candidate.
4. Expand `~`, then resolve a relative path against the payload's `cwd`.

```
dispatches: 348  extracted: 339  no-path: 9  hit rate: 97.4%
```

**97.4%, above the 96% gate. PASS.**

The 9 misses are exactly the 9 docless Mode 2 audits the doc already names as an uncapped
Non-Goal. Enumerated in full, first 110 chars each (one em-dash in the last quote replaced with a
colon so this file passes the repo's em-dash lint):

```
Run an **Implementation Audit** (post-implementation mode) cross-model review
Run an **Implementation Audit** (post-implementation, verify-by-doing)
Run an IMPLEMENTATION AUDIT with both reviewers (Architect/Gemini and Staff Engineer/Codex)
Review a code change (not a design doc) on the `tatari-tv/clyde` repo: PR #54
Run the panel (Architect/Gemini + Staff Engineer/Codex) in PARALLEL as an IMPLEMENTATION REVIEW
Run the Architect (Gemini) and Staff Engineer (Codex) reviewers IN PARALLEL in Implementation Audit mode
Run the Architect (Gemini) and Staff Engineer (Codex) reviewers IN PARALLEL in Implementation Audit mode
Run the Architect (Gemini) and Staff Engineer (Codex) reviewers IN PARALLEL in Implementation Audit mode
**Implementation Audit: fifteen commits that have had at most one pair of eyes.**
```

So the miss set is not a parse defect with an unknown tail. It is the known hole, measured at
2.6%, and every miss is a prompt that names no `.md` at all.

### Correction to the doc's absolute-versus-relative split

The doc's payload-facts section says 290 of 346 (84%) name an absolute path and 43 (12%) name a
relative one. Re-measured here with the extractor above:

```
total 348: absolute 221 (64%)  relative 118 (34%)  no-path 9 (2.6%)
relative dispatches whose record carried no cwd: 0
```

The doc's conclusion is unchanged and strengthened: `cwd` is mandatory. Ignoring it costs 34% of
dispatches, not 12%. The two numbers differ because this extractor picks a single doc per prompt
under the rules above, where the doc's figure counted path shapes present anywhere in the prompt.
Recorded as a measurement update rather than a contradiction; Phase 1 must not skip the `cwd`
resolution step.

## 0c-4: free measurement, does `UserPromptSubmit` fire during an autonomous dispatch

Registered alongside the `Agent` matcher, costing nothing. Result: it fired **twice, both times
on the prompt handed to `claude -p`**, once per nested run, and **zero times on the `Agent`
dispatch itself**.

`UserPromptSubmit` payload keys at 2.1.272: `cwd`, `hook_event_name`, `permission_mode`,
`prompt`, `prompt_id`, `session_id`, `transcript_path`.

This settles M1 with data rather than reasoning. The disease this chunk fixes is autonomous:
7, 5 and 10-round runs with zero Scott prompts. A `UserPromptSubmit` counter increments only
when a human types, so it cannot count a round a human never triggered. The rejected fallback
is rejected on measurement now, not on argument.

## What Phase 1 inherits

- Matcher string is `Agent`. Narrow on `tool_input.subagent_type == "review-panel"` and allow
  everything else before any other work.
- `tool_input.prompt` and `cwd` are both guaranteed present on this version. Still read them
  defensively and fail open, per the Resolved Decision on unparseable paths.
- The four-step extractor above is the reference algorithm and its measured hit rate is 97.4%.
- The deny shape used here is the one the guard ships, and it is proven to reach the caller.
