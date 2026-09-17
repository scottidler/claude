# Implementation notes: DM resolution and pipeline glue

Append-only. Design doc: `docs/design/2026-09-17-dm-resolution-and-pipeline-glue.md`.

## Phase 0a: re-pin the baseline; add a replay mode

### Design decisions
- The snapshot stores full payloads, not the scored rows — `replay/slackrecall.py:walk` —
  the scored rows clip `target` to 60 and `text` to 90 chars, so replaying them would hand
  the guard a different body than the one that was posted. The doc said "replays committed
  payloads"; this is what that requires.
- Snapshot named `rows-0a.json` — matches criterion 3's phrase "Phase 0a's committed rows
  file" and the `--from-rows` flag, and does not collide with `rowsFinal.json`, which is
  chunk D's scored record.
- Posts sorted by `(session, tool_name, tool_input)` — `replay/slackrecall.py:walk` —
  `rglob` returns filesystem order, so a re-walk reshuffles. The gate only asks for equal
  counts; the sort buys a byte-identical comparison, which is a stronger check for free.
- `deny_class()` added as a named function rather than inline grepping —
  `replay/slackrecall.py:deny_class` — Phase 3's decision rule scopes to TARGET, so the
  three deny families have to be separable by the driver, not by eye.
- Converted to `argparse` with a positional `out` plus `--guard` — the old interface read
  `sys.argv[2]` for the guard path, which cannot carry two more modes. Space-separated
  hyphenated flags per `rules/cli.md`.

### Deviations
- **The doc's "`slackrecall.py` needs `WINDOW = 3` (it ships `WINDOW = 12`)" was already
  stale when 0a ran.** Commit 1c6ccf2 (round 3's fold) had already set `WINDOW = 3`.
  Verified, not assumed: `32:WINDOW = 3`. No change made.
- Implementation notes are committed per phase rather than only with the final-phase
  commit, which is what the skill's own "append once per phase as part of the commit prep"
  implies. The design doc's status flip still rides the last commit alone.

### Tradeoffs
- Kept the driver a single script with modes rather than splitting walk and replay into two
  files: one script with modes is the `rules/taste.md` preference, and the two halves share
  `verdict`, `typed_prompt` and the scratch-`HOME` isolation.
- No structured logging added. `rules/logging.md` exists for diagnosable services; this is a
  measurement script in a `phase0` directory whose stdout IS its record, and the counts it
  prints are the artifact. Noted rather than silently skipped.

### Open questions
- None.

## Phase 0b: the `UserPromptSubmit` hook, six probes

### Design decisions
- Probed **obedience** as well as delivery. The doc's probe 1 asks only whether
  `additionalContext` "reaches the model", and that is what its gate turns on. But Phase 7's
  success criterion needs the injected line to CAUSE two skill invocations, so delivery alone
  would have left the load-bearing fact unmeasured. Added 0b-1b; it passes.
- Ran the probes against a scratch `--settings` / `--plugin-dir` on a nested `claude -p`
  rather than the live session, so nothing was registered in `HOME/.claude/settings.json` and
  no session restart was needed. Chunk C's method verbatim.
- Prompts are fed on **stdin**, not as a positional argument: `--mcp-config` and `--debug`
  are variadic and swallow a trailing prompt. Cost two failed runs before it was diagnosed.
- Skipped 0b-6's injected-instruction arm. The `skillOverrides` block is at resolution and
  the harness emits the error itself, so no prompting path can change the outcome. Recorded
  as skipped-with-reason rather than silently dropped.

### Deviations
- **0b-4 and 0b-5 are reported NOT MEASURABLE rather than answered.** Both need a
  `prompt.submit` hook to take effect, and in print mode it does not. This was isolated, not
  assumed: in one run, one plugin, a `tool.call` deny fired and was quoted verbatim by the
  nested model while the `prompt.submit` rewrite control arm produced no change at all. They
  are handed to an interactive session, which is the operator step the doc's own
  `Operator steps` section already predicted.
- The doc names `$.command.run`. The plugin orientation documents `$.process.run` for host
  commands and `command.run` as an *event*. `claude plugin validate` accepts
  `$.command.run` as a call, so the doc's spelling is recognized by this build; the
  discrepancy is recorded rather than resolved, because 0b-5 could not execute it.

### Tradeoffs
- Wrote the probe plugins untyped (`any`) instead of blocking on `/plugin-types`, which is a
  built-in command this session cannot invoke. Types are erased at runtime and
  `claude plugin validate` reports what the engine actually sees, so the probes ran without
  them. The validator turned out to be the stricter check anyway: it rejected passing `$` to
  a helper and rejected reading `$.command` as a value, both of which had to be rewritten.
- Chose a `tool.call` deny as the plugin-loaded isolation signal over `$.ui.log`, because
  chunk C had already proven a deny reaches the caller and `$.ui.log` surfaced nowhere in
  print mode.

### Open questions
- **For Phase 7, and it is not in the design doc yet.** An injected instruction is obeyed
  when it names a token actually present in the prompt, and **flagged as prompt injection and
  refused** when it does not ("Flagging per prompt-injection policy rather than acting on
  it.", 0b-3a). Mechanism A satisfies the condition by construction, but the hook's wording is
  now load-bearing for a reason the doc does not state: it must corroborate itself against the
  visible prompt. Phase 7 should carry this as a written constraint, and the design doc should
  gain a line for it.

## Phase 0c: the dispatch matrix

### Design decisions
- The probe hook **allows** (`{}`) rather than denying. Chunk C's hook denied, because it only
  needed the payload; 0c needs the dispatch to actually run, since the question is whether the
  report comes back inline.
- Every cell dispatched `general-purpose`, not `phase-implementer`. A real `phase-implementer`
  dispatch would implement a phase as a side effect of a probe. The synchrony mechanism is
  `run_in_background`, which is a property of the Agent tool rather than of an agent type, and
  the same key appears in the payload for both. Noted as a scope limit on the measurement.
- Chose six cells to match the doc's stated count, covering both values of each of the three
  factors rather than the full 2x2x2.

### Deviations
- **The design doc was amended, in three places, which 0c's gate explicitly instructs**
  ("If one is, the doc is amended before Phase 10 starts"): Alternative 4's availability claim
  is withdrawn, the item 8 Resolved Decision gains a companion entry, and the 0c gate line
  records its outcome. **The decision itself is unchanged** and was not relitigated: the
  legible-wait design still ships, because the seam argument is what carried it. Only the
  falsified leg was removed.

### Tradeoffs
- Recorded `tool_input.run_in_background`'s presence on the payload even though the doc did not
  ask for it, because Phase 10 can use it to tell sync from async dispatch at hook time without
  inference. One line, and the alternative is a later phase re-deriving it.

### Open questions
- None. 0c's own question ("does the payload carry `tool_input.name`") is answered yes, so
  Phase 10's guard on the named form is possible.
