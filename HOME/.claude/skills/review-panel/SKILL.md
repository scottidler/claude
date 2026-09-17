---
name: review-panel
description: Dispatch cross-model review (Gemini Architect + Codex Staff Engineer) on a design doc. Use after /create-design-doc's draft passes, or after /how-to-execute-a-plan finishes every phase, or when the user says "get the reviewers on this", "have the panel look at it", "send it to review-panel", or "run a design review" / "run an implementation audit". review-panel is an agent, not a skill; this is the only entry point that reaches it as Skill(review-panel).
---

# Review Panel

`review-panel` is an **agent** (`~/.claude/agents/review-panel.md`), so
`Skill(review-panel)` has no file to find on its own. This skill is that file:
it dispatches the agent and relays what comes back. **It replaces every
"send it to the `review-panel` agent" instruction elsewhere** (e.g.
`create-design-doc/SKILL.md`'s Pass 5) so there is one entry point, not two
signals for the same action.

The agent is the whole point: it fans the **Architect** (Gemini) and **Staff
Engineer** (Codex) out in parallel, monitors both, and writes one reconciled
findings list. Never substitute your own review for theirs.

## What to do

1. **Gather what the agent needs**, from the caller or the current context:
   - **DOC_PATH**, the design doc, absolute path.
   - **Open questions**, numbered, if the caller has any; the agent answers
     each one explicitly.
   - **Scope for this round**: "full design review", "review only the
     deltas since round N", "implementation audit", etc. Pass it literally;
     the agent's Step 0 decides the round number and mode from the doc itself.
2. **Spawn the `review-panel` agent** (Agent tool, `subagent_type=review-panel`)
   with DOC_PATH, the open questions, and the scope. Don't pre-chew the
   doc or summarize it, the agent re-snapshots and re-hashes it itself.
3. **Relay its report as-is**: the synthesis file path, the findings, and any
   UNANSWERED verdicts. The consensus loop (fold in agreements, push back
   with rationale, escalate only what can't be closed) is the caller's job,
   not this skill's, this skill's job ends at the dispatch and the relay.

## The round cap is enforced at dispatch, not here

`panel-round-guard.sh` (a `PreToolUse` hook on the Agent dispatch, matched on
`tool_input.subagent_type == "review-panel"`) denies a round past the cap in
`rules/interaction.md`. A denial comes back in place of a report: fold the
existing findings into the doc and build, or get Scott's explicit
`PANEL_ROUNDS_ORDERED_BY_SCOTT=<n>` per that rule. Don't retry the dispatch
to work around a denial, that is exactly the silent overrun the guard exists
to stop.

## Rules that never bend

- **Never** review the doc yourself and call it a panel round. The value is
  the two *different models*; this skill exists only to reach them.
- **Never** skip straight to a second dispatch because the first "seemed
  incomplete". Read what came back, and if the doc changed, say so and
  dispatch again with that named as the scope.
