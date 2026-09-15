# Implementation notes: panel round cap

Append-only. One section per phase, all four buckets every time, "None." where empty.
Companion to `2026-09-14-panel-round-cap.md` and its review log.

## Phase 0: Prove the Agent seam

### Design decisions
- Ran Phase 0 inline in the orchestrating session rather than delegating it to
  `phase-implementer`. The probe needs a live `Agent` dispatch to fire a
  `PreToolUse(Agent)` hook, and `phase-implementer` has no `Agent` tool, so it
  physically cannot produce the payload the phase exists to capture. The nested
  `claude -p --settings` harness is chunk A Phase 0b's method verbatim.
- Measured the doc-path extraction hit rate over **all 348** corpus dispatches
  rather than the 25-prompt sample the success criterion asks for. Same cost,
  no sampling error, and it makes the miss set enumerable in full.
- Companion artifacts (`*-review-log.md`, `*-implementation-notes.md`) are
  dropped from the candidate pool before the `design/` preference is applied.
  The design doc's extractor sketch does not mention them, and without the drop
  a round-2 prompt that cites its own review log can key on the wrong file.
  Recorded here because Phase 1 must implement this step.

### Deviations
- Corrected the doc's absolute-versus-relative split. The doc says 290/346 (84%)
  absolute and 43 (12%) relative; re-measured with the actual extractor it is
  221/348 (64%) absolute and 118 (34%) relative. The doc's conclusion (`cwd` is
  mandatory) is unchanged and strengthened. Evidence file carries the numbers
  and the reason the two differ. The doc body is not amended: this is a Phase 0
  measurement, and the evidence file is where Phase 0 measurements live.
- The em-dash in one verbatim quoted corpus prompt was replaced with a colon in
  `evidence.md`, disclosed inline in that file. `rules/safety.md` admits no
  quotation exemption and the repo lints for the character.

### Tradeoffs
- Probe hook denied rather than allowed-and-logged. A deny costs one blocked
  dispatch and proves the block path in the same run; an allow would have let a
  real 10-minute panel launch to prove strictly less.
- Scratch settings went through `--settings` on a nested session rather than a
  temporary edit to `HOME/.claude/settings.json`. The latter is live on every
  session on the machine through the manifest symlink, so a probe registered
  there would have denied real panel dispatches in any concurrent session.

### Open questions
- None. The success criteria all passed, so the doc is not reopened.

### Observations, not gates
- The `Agent` `tool_input` carries two keys the doc did not predict,
  `description` and `run_in_background`. Neither is load-bearing.
- Claude Code 2.1.272 adds an `effort` key to the PreToolUse payload that was
  not present in chunk A's 2.1.270 capture. Unused.
