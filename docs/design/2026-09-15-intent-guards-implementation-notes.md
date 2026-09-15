# Implementation notes: intent guards

Running record for `docs/design/2026-09-15-intent-guards.md`. Append-only. A later entry supersedes an earlier one; nothing here is rewritten.

## Phase 0: prove what is left unproven (PARTIAL)

Evidence: `docs/design/2026-09-15-intent-guards-phase0/evidence.md`. Five of eight criteria answered, three blocked.

### Design decisions
- Ran the read-only half while panel round 4 was still in flight, and held the design doc still for the duration. The evidence file is a new path, so it drifts nothing the seats were reading.
- Measured the extractor by simulating both selectors over each transcript prefix ending before a `tool_use`, rather than over the finished file. That is what a `PreToolUse` hook sees, and the finished-file version would have scored the corrected extractor too well.
- Answered the `TAIL_CAP` question statically instead of waiting for the blocked live dump. Reconstructing the transcript's byte length at the instant the hook fires needs no hook: it is the cumulative length of the records before the `tool_use`. This moved a blocked question into an answered one.

### Deviations
- The doc's Phase 0 bullet planned to carry the `TAIL_CAP` measurement on the flush-instant criterion's live dump. It was answered without the dump (above), so that sub-item is closed and the flush criterion is narrower than written. Doc amended.
- Criterion 7's remedy is neither lever the doc named. The doc offered `TAIL_CAP` or rule-count-per-hook; `TAIL_CAP` is dead (a 200K tail reaches the turn's prompt record 51.673% of the time against 99.944% at 4 MB) and the actual fix is gating the transcript scan behind a cheap command predicate, 230 ms -> 27 ms on a non-Slack Bash call. Folded into Phase 5 as a requirement with its own criterion.

### Tradeoffs
- Gating the scan vs. splitting hooks: gating keeps one hook and one registration and removes the cost entirely on the calls that do not need it. Splitting would have paid a second process spawn on every call to save a scan that gating already skips.

### Open questions
- None. Criteria 3, 4 and 5 are blocked on a live hook registration that the harness's auto-mode classifier refuses as self-modification. They need Scott's hands, not a decision.

## Phase 1: close chunk B's secret-guard hole

Commit: this phase. `secret-echo-guard.sh` and `secret-echo-guard-test.sh`.

### Design decisions
- The verb test moved out of the Python matcher and into the shell as `cmdword_is`, evaluated **per statement**, exactly as the doc specifies. Two masked copies per statement now: the command-word test runs on `mask_heredoc | mask_comment` only (the implementation contract's CW1 finding, since quote-masking makes the verb read as no verb), and the payload match stays on the squote-masked copy so `echo '$GH_TOKEN'` remains an allow.
- `stripped` now derives from the selected print statements rather than the whole command, so the `${NAME:+...}` and `${#NAME}` safe-form strips apply where the print check actually runs.
- Kept the statement-start `[ -n "$NAME" ]` strip although per-statement gating already excludes `[` statements: `echo [ -n "$GH_TOKEN" ]` has command word `echo`, must still deny, and the strip is anchored at line start so it does not fire on it. Asserted in the fixture matrix.
- Gated the `cmdword_is` calls behind a `case` on the masked statement, a deliberate superset of the Python `NAME` regex. Every name the matcher can fire on contains one of those tokens, so skipping a statement without them cannot lose a deny.

### Deviations
- **`printenv` was fixed alongside `echo`/`printf`, and the doc's bullet names only the echo/printf check.** Measured in the same run: `'printenv' GH_TOKEN` allowed for the identical reason, `mask_squote` erasing the verb before an unanchored regex saw it. Fixing the two siblings and shipping the third with a known hole was not defensible. Disclosed here rather than folded silently.
- The doc says "the existing 39 assertions in `secret-echo-guard-test.sh` pass unchanged". The file actually carries 73. All 73 pass unchanged; the criterion's count is stale, not its substance. Four new assertions bring it to 77.

### Tradeoffs
- Per-statement gating vs. one blob: per-statement is the only shape that can ask "what is THIS statement's command word", which is the whole fix. The cost was 50 ms per Bash call (96 -> 146 ms on a three-statement command), which the superset `case` gate removes entirely: **95 ms gated, against a 96 ms baseline**. Net zero.
- The superset pattern is a second copy of the secret-name token list, in shell, which can drift from the Python one. Accepted because drift can only make the gate broader (a miss means the shell list lacks a token the Python list has, which loses a deny), so the pairing is noted here and the matrix covers every token in use.

### Open questions
- None.
