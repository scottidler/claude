# Review log: panel round cap

Companion to `2026-09-14-panel-round-cap.md`. Round-by-round panel minutes,
pushbacks and their rationale live here. Only rulings land in the design doc.

Opened before round 1, per chunk B's lesson: chunk B's Resolved Decisions
reached 22% of its word count, roughly half of it minutes rather than rulings,
and the doc grew 378 to 536 lines across three rounds. This is the doc about
review-process inflation, so it does not get to inflate.

## Pre-panel: the research fold-in (2026-09-14, no panel involved)

Not a review round. A codebase dig run before dispatch, recorded here because it
rewrote the design's core and the reasoning should not be lost.

- **The seam was wrong.** The doc through pass 5 put the cap on a
  `PreToolUse(Bash)` guard at the seat scripts. Two measurements killed it:
  every round is a fresh `Agent` dispatch that `mktemp -d`s a new run dir
  (`review-panel.md:79-83`), so the run-dir counter reads zero at round 4 for
  ~92% of dispatches; and a deny inside the panel subagent does not reach the
  caller, who is the party that overruns (`review-panel.md:281-288`). Rewritten
  onto `PreToolUse(Agent)` keyed on (doc, mode). Old design kept as Alternative 3.
- **`/tmp` was never viable for counter state.** tmpfs, 16G, box booted 10:16
  on 2026-09-14, which is why all 328 historical run dirs are gone. Counter
  moved to `~/.cache/review-panel/rounds/`.
- **Mode collision, found in the rewrite.** Keyed on the doc alone, a doc that
  spent its 3 design rounds would have its first implementation audit denied.
  Key is now (doc, mode), read off the `Status:` line as Step 1.2 does.
- **AC4 was a census of a wrong number.** The draft asserted under 12,000 bytes.
  Per-section measurement puts pure lore extraction at ~19,970 and lore plus the
  Step 2 prompt-body move at ~16,500. Restated as properties, per chunk B's
  recorded lesson about census criteria.
- **Evidence upgraded from concession to measurement.** The round distribution
  was thought unrecoverable after the reboot. It re-derives from
  `~/.claude/projects`: 46 run dirs with round-paired evidence, 17 over 3
  rounds, 7 over 5, worst 14 (`8wLUyVus`). A looser second derivation returned
  56 / 19 / 8. Both confirm the audit's max of 14.

## Round 1 (2026-09-14): 3 must-fix, 4 cheap wins, 2 rejected

Seats: architect rc=0 (10,056B), staff-engineer rc=0 (6,785B) after a first
dispatch died rc=124 on the 10m wall clock, burning its budget on jq sweeps over
the 3.4GB transcript corpus because the panel prompt asked it to re-derive the
round distribution. Re-dispatched once, disclosed. Drift vs live doc: 0 lines.
Questions: 5 asked, 5 answered.

Verdict: seam, (doc, mode) key, and both Non-Goal refusals survived both seats.
The Phase 0 fallback and the door's match rule did not.

### Must-fix, all folded in

- **M1, both seats. The Phase 0 fallback was incoherent.** It named a
  `UserPromptSubmit` counter, which fires on human input, against a disease the
  doc itself measures as autonomous (7, 5 and 10-round runs with zero Scott
  prompts). Fallback is now "no preventative seam proven, reopen the doc", plus
  a free measurement: register `UserPromptSubmit` alongside the Agent matcher in
  the Phase 0 scratch hook and record whether it fires on an autonomous dispatch.
- **M2, staff only, verified here. The door could be opened by the document it
  guards.** The guard matched the marker anywhere in `tool_input.prompt`, and
  this doc carries `PANEL_ROUNDS_ORDERED_BY_SCOTT=<int>` literally four times
  (`:162`, `:167`, `:204`, `:279`). Quoting prior findings back into a round-4
  prompt, which is the normal shape of re-engagement, would silently raise the
  cap to 5 or 10. The marker is now required as its own control line,
  `^PANEL_ROUNDS_ORDERED_BY_SCOTT=[0-9]+$`, with a matrix case proving the
  marker inside quoted doc text does not open it. The earlier draft treated the
  door purely as a forgery question; accidental self-trigger is a different
  defect and was unaddressed.
- **M3, staff only, verified here. The `shapes.sh` sweep was the wrong
  instrument.** It exists for "the command word was not the first word of the
  statement" and wraps shell command words. This hook consumes a prompt: no
  command word, no shell. All 16 shapes could pass while proving nothing.
  Replaced with six prompt-appropriate mutations. Inherited ceremony in the doc
  about deleting ceremony.

### Cheap wins, all folded in

- C1: the doc-path extraction hit rate moved from the risk table into Phase 0's
  success criteria, since a parse miss means an uncapped dispatch.
- C2: dropped "or into the seat scripts" from the Step 2 move; it would couple
  standalone `/architect` and `/staff-engineer` to panel behavior.
- C3: `emdash.sh:166-176` is live production proof that `tool_input` arrives for
  non-Bash tools (it reads `.content`, `.new_string`, `.new_source`, and walks
  every string for `mcp__*`), stronger than the chunk A scratch hook. Narrows
  Phase 0 to one question.
- C4: suffixed run dirs is 30, not 35. Re-measured here: 30 suffixed, 4
  unsuffixed.

### Method repair

`:140` claimed 346 records match the literal
`"subagent_type":"review-panel","prompt":"`. A raw grep returns ~173; the
structural jq returns 347. The number was right, the stated method did not
reproduce it, because the keys are literally adjacent in only about half the
records. Restated as the structural pass.

### Rejected, with reasons

- Architect wanted an unparseable doc path to fail CLOSED, citing taste.md.
  Rejected: every guard in this tree fails open on an unreadable payload
  (`emdash.sh:92,97`, `prose.sh:107`, both branch guards, `git-release-guard.sh:150`,
  tracing to `rewrite-cd-read.py:911-914`), and the Blast radius section prices
  the alternative at every panel dispatch on every machine. The concern's
  correct form is C1, which is now a gate.
- Architect wanted a separate deny log. Rejected: the counter file already
  records where a doc stopped and the deny text is in the transcript. A third
  record of one fact is the inflation this chunk removes. Cheap for Scott to
  overturn.

### Raised by neither seat, added anyway

The counter increment is a read-modify-write with no lock. Two concurrent
dispatches on the same doc and mode can both read 2 and both write 3, costing
one extra round, once. Not worth a lock, worth one clause so no reader assumes
atomicity.

### Verification the panel ran on this doc's own claims

- Round distribution CONFIRMED by two independent derivations: panel got 47 run
  dirs (the +1 is its own run), 17 over 3, 7 over 5, worst `8wLUyVus` at 14,
  with the architect independently enumerating r1 through r14. Doc says 46/17/7.
- Payload proven/unproven split HONEST and understated. Every cited artifact
  checks out, including that `block-question-picker.sh:20` really does read only
  `.tool_name`, so the caveat was correct. Nothing anywhere shows an Agent
  PreToolUse payload.
