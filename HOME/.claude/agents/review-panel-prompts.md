# Review panel: reviewer prompt bodies

Companion to `review-panel.md`. These are the verbatim prompt bodies piped to
the Architect (Gemini) and Staff Engineer (Codex) seats, moved out of the
agent file because they are reviewer-facing text, not agent instruction: none
of it tells this agent what to do. Kept out of the seat scripts themselves
(`architect/script.sh`, `staff-engineer/script.sh`) so a standalone
`/architect` or `/staff-engineer` run is not coupled to panel behavior.

Step 2 of `review-panel.md` copies the body for the detected MODE into
`$RUN_DIR/prompt.txt` before dispatch.

## Mode 1: Design Review

Same body to both seats:

> Review this design document. Implementation has NOT started. Identify: (1) the top risks to correctness/architecture/operability and why; (2) unverified assumptions or ones that break under load / on the unhappy path; (3) missing design decisions that should be explicit (failure handling, migration, rollback, observability); (4) whether the doc has falsifiable acceptance criteria, overall AND per phase (assert-style statements that evaluate true when done); flag every phase whose success is vague or unstated; (5) unrequested scope: anything in the doc no one asked for; (6) your hardest question for the author. Judge against the Owner's Standards section included in this prompt, not generic best practice. Verify against the actual codebase before asserting. Be specific: cite exact sections, files, lines. Do not praise without cause.

## Mode 2: Implementation Audit

Embed the COMMIT_CONTEXT from Step 1 of `review-panel.md`:

> Review this design document. The implementation is COMPLETE. Commit log + diff stat since last tag: `<COMMIT_CONTEXT>`. Audit whether the implementation delivered the spec. **COMPLETENESS IS REQUIRED**: walk the Implementation Plan phase by phase, bullet by bullet; for each bullet, verify it was actually implemented by reading the code. Cross-module wiring, config loading/deserialization, daemon/service integration, and registration steps are the most commonly skipped, check these explicitly. Identify: (1) completeness gaps (the primary finding, name the exact bullet and the file/function where it's missing); (2) requirements unimplemented or partial; (3) UNDISCLOSED deviations from the spec (distinguish them from deviations disclosed in the implementation notes: undisclosed ones are the top severity; disclosed-and-reasoned ones may ride); (4) code patterns contradicting the design or the Owner's Standards included in this prompt; (5) acceptance criteria: verify each one in the doc actually holds against the code, and say which you could not verify; (6) anything skipped, deferred, or changed without acknowledgment; (7) **behavioral regressions**: for every commit that changes runtime behavior, what a user could observe that changed against the PREVIOUS release: an input, command, or config accepted or producing result A before and now erroring, hanging, or producing result B. Hunt two shapes specifically: a commit message claiming to fix a CLASS ("every X", "all Y forms") that fixed one instance (name the cases still broken), and a change reached by an unrelated code path the phase never touched (a converter still emitting what a new loader rejects, a default another caller reads). The doc's stated behavior changes are the ALLOWED set; anything relied upon that changed and is NOT called out is a regression. Read the base version to compare (`git show <PREV_TAG>:<path>`). For each, emit a line prefixed `PROBE:`, the exact command or input, what the previous release did, what the current tree does, so it can be run. Cite files and lines for what you verified. Do not praise without cause.

## Both modes

If the caller gave a focused question, append: "Focus specifically on: <focus>."
