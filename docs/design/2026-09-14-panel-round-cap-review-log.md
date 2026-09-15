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

## Implementation audit, round 1 (2026-09-14, Mode 2)

Rulings are in the design doc's Implementation Audit section. These are the
minutes. Recorded here because the run dir (`/tmp/review-panel/EQQ6ToY8`) is on
tmpfs and does not survive a reboot, which is the same fact that forced this
doc's evidence to be re-derived in the first place.

Seats: architect rc=0 (6,535B, attempt 2 of 2 after the known Invalid-stream
retry); staff-engineer rc=0 (7,836B). Snapshot equalled the live file, 0 lines
of drift. 5 questions asked, 5 answered. Counts: 3 must-fix, 4 cheap wins,
4 defer.

### The seats disagreed, and that was the finding

The Architect (Gemini) reported zero defects: "the regex is robust", "prose
discussing `Status: Implemented` will not trigger a mode flip". It ran no
commands. Two of its five verdicts were falsified by probes. The Staff Engineer
(Codex) named both parser defects and disclosed that it could not execute the
matrix under a read-only `mktemp`. It was right on both. Step 4's
verify-every-negative-claim rule is what caught the difference, which is an
argument for that rule surviving Phase 3.

### Verified, not taken on either seat's word

Q2, the compression risk, was the finding most expected to bite. The audit
diffed `762016f`'s 26,322B agent file against the shipped 19,954B one,
enumerated all 190 removed lines, and confirmed each of the 12 rules the moved
incidents produced is still stated explicitly: Step 0.3 stale-diff, Step 0.4
questions, Step 1.1 snapshot-and-pass-the-snapshot, Step 3 never-detach,
Step 3 dispatch-status-is-the-record, Step 3 no-outer-timeout, Step 3 rc=3
remedy, Step 3.5 substitute-labeling, Step 3.75 probes-and-UNVERIFIED, Step 4
file-first, Step 4 unverified-absolutes, Step 5 SendMessage-is-the-path, Step 6
questions-non-negotiable. Frontmatter intact, nine step headers present,
em-dashes 44 to 0 across all three files. The only content that left the tree
entirely was Step 4's four rejected-dogma examples, since restored.

### Defer, all four ride as disclosed

- Artifact-name inconsistency in `review-panel.md`. Now in Open Questions, and
  upgraded from untidiness to measured friction: this audit's own artifacts are
  `-r1`-suffixed while Step 3.75 tells it to read `arch.out`, so the reviewer
  tripped over it while reviewing it.
- `review-panel.md` joining the lint list in Phase 4 rather than Phase 2.
  Coherent: `aa25d97` updated the exclusion comment in the same commit.
- Docless Mode 2 audits uncapped. Named in Non-Goals with the measurement.
- The companion-drop step in `extract_doc()`. Not in the doc body, disclosed in
  `evidence.md` and the Phase 0 and 1 notes, and judged the right behavior.

### Rejected

Gemini's "zero undisclosed deviations, no behavioral regressions, every AC
holds." Two of five verdicts falsified; the rest rested on command output it
could not produce. Nothing from Codex rejected: its five verdicts (FAIL,
mostly-PASS, PARTIAL, PASS, PARTIAL) all matched what was measured.
