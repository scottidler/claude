# Implementation notes: guard-precision (chunk B)

Append-only record of how the implementation interprets or departs from
`2026-09-13-guard-precision.md`. One section per phase, four buckets each.

## Phase 0: prove the harness assumptions

### Design decisions
- The nested-session method is chunk A's, reused unchanged: scratch hooks behind `--settings` on `claude -p --model sonnet`, every hook appending its payload to its own log. Evidence: `2026-09-13-guard-precision-phase0/evidence.md`.
- 0a needed an interactive session because `SessionStart` never fires under `-p`. It was driven under a detached tmux server (`tmux -L p0a`), sandbox off, because tmux talks over a unix socket the sandbox denies. The transcript of that session (`a4faad78`) is the primary record.
- 0f was extended from the two orderings the doc asked for to seven runs, because two runs could not separate registration order from a completion race. The sleep variants are what settled it.

### Deviations
- The doc's plan changes are recorded INLINE in the design doc under `Phase 0 outcome` markers (Status line, problem 1, Overview, Architecture, Data Model masker table, API Design, Phase 5, Phase 6 rewritten, Phase 7, AC1, AC5, decision 9, Rollout Plan) rather than in a separate addendum, so a phase implementer reading its own section sees the current plan without cross-referencing.
- Phase 6 is rewritten wholesale: the `git -C` strip folds into `rewrite-cd-read.py` and `git-no-dash-c.sh` is deleted. This is the fallback the doc's Rollout Plan pre-committed to for a failed 0e, so it is a deviation the doc authorized in advance, not a new decision.

### Tradeoffs
- `additionalContext` over plain stdout for Phase 7, when 0a showed both reach the model. The documented field, and its rendering names itself as context rather than as a hook's stdout.
- AC5's observable became the hook's own log line rather than anything model-visible, because 0b proved a shell hook has no channel to tell the model a rewrite happened. The alternative was to keep a deny (visible, but the round trip the chunk exists to remove).

### Open questions
- None. 0a's finding that `ssh-agent-check.sh`'s WARN would have been heard changes nothing this chunk builds; it corrects the doc's stated cause for the zero-WARN audit finding.
