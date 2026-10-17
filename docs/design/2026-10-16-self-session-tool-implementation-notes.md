# Implementation notes: `self` session tool

## Phase 0: Prove the tool path headless
### Design decisions
- Probe returned strings, not objects, from every `tool.call` hook after core rejected an object result - `$TMPDIR/p0/probe/hooks/index.ts` (throwaway, outside the repo) - the output shape is string | array | undefined, so the whole design's `{ result: SessionFacts }` becomes `{ result: JSON.stringify(facts) }`.
- Arm (b) was run with two separate tools (`obj`, `str`) plus a `report` tool that reads `ToolUseSummary.text` from `$.session.messages()`, so the judgment is mechanical as the doc specified.
- Arm (e) discriminated parent from child by `tokens`, not `window` - all models share one window on this machine (haiku main reports 1,000,000; 200,000 with `CLAUDE_CODE_DISABLE_1M_CONTEXT=1`), so `window` cannot tell "own" from "parent's"; the child's `tokens` (35319) sat between the parent's two readings (34196, 36369) after the child read a 1,945-line file, so the figures are the main conversation's.
- Folded rulings into the design doc: Architecture arrow and a sentence, the description's subagent caveat, API Design's schema-enforcement bullet, Phase 1's first bullet and the first test's name.

### Deviations
- The doc's Architecture `{ result: SessionFacts }` is wrong at the seam; the correct seam is a JSON string. Same effect, correct seam. Not a deviation from Phase 0's own steps.
- The `(e)` decision rule says "`window` matches the parent's model -> caveat". Window matched both models equally here; the caveat was applied on the `tokens` evidence. Recorded in Results.

### Tradeoffs
- Probe logged via `--debug-file` and the stream-json tool results vs. a transcript: `claude -p` in the sandbox may not write a transcript, and the debug log redacts ids, so ids were compared in the tool result against the `init` event.

### Open questions
- None blocking. Phase 1 should note that `window` is not a discriminator for a subagent on this machine, so the kit test for the caveat cannot be a window comparison.
