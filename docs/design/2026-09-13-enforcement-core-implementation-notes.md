# Implementation notes: enforcement core

Companion to `docs/design/2026-09-13-enforcement-core.md`. Append-only, one
section per phase, written at the end of that phase. Prior entries are never
edited.

## Phase 2: Stop hook prose.sh

### Design decisions
- Stale guard compares FILE POSITION, not timestamp (`prose.sh`, the prompt
  block). `last-prompt` records carry no timestamp: their keys are exactly
  `lastPrompt, leafUuid, sessionId, type`, verified against a live 1,491-record
  transcript. Position is equivalent to time in an append-only file and works
  for every record type, so one rule covers both prompt sources.
- Transcript reads are bounded to the last 4 MB (`TAIL_CAP`), dropping the
  necessarily partial first line of a truncated read. Records are one JSON
  object per line and the newest prompt always sits near the end; an unbounded
  read on every turn end is not acceptable.
- Quoted text in reason strings is truncated through jq (`head_chars`,
  `tail_chars`, `.[0:200]`). Bash substring and `cut -c` count BYTES under a C
  locale and would hand jq a split multibyte character, which is exactly the
  case the em-dash rule always hits.
- Rule order is em-dash, offer, decision ask. Em-dash is the only rule that
  needs neither the prompt nor a line count, so it still fires when the
  transcript is unreachable.
- Every reason quotes the offending line; the offer reason also quotes the
  prompt that made it imperative, so the model can see why the rule fired
  rather than guessing (the 8-block cap makes a second miss expensive).
- The banned character is built from a bash `$'...'` escape rather than typed,
  so neither file carries a literal U+2014 and the repo lint added in Phase 4
  will pass over them.

### Deviations
- A slash-command prompt counts as imperative (`is_imperative`, the `/?*`
  case). Same effect, correct seam: the doc's amendment made `last-prompt` the
  primary source precisely so `/skill` turns yield a prompt, but the imperative
  test is a first-word verb list and `/how-to-execute-a-plan` is in no verb
  list, so every slash turn would extract a prompt and then fail the gate,
  leaving the amendment inert. Invoking a command is an order. One line,
  reversible, fixture `offer after a slash command (last-prompt record)`.
- Fail-open is scoped to the OFFER rule, not the whole hook. The Phase 2 bullet
  lists "the transcript cannot be read" among the pass-throughs; the Data Model
  scopes fail-open to prompt extraction, and the risk table says "em-dash and
  length rules do not need the prompt". Implemented the Data Model reading.
  Measured effect: a headless `claude -p` reply carrying U+2014 is still
  blocked (live check below), which is what G2 asks for.
- The final-sentence cut requires a terminator FOLLOWED BY WHITESPACE. The doc
  says "after the last `.`, `!`, `?` or newline boundary"; a bare-dot cut
  truncates "Want me to update edges.md?" to "md" and misses the offer.
  Fixture: `offer whose sentence carries a dotted filename`.
- Offer phrases and go-ahead tokens match case-insensitively. The doc does not
  specify case; insensitive is the strictly wider gate and costs nothing.
- The linker step named in the Phase 2 bullet was NOT run: the phase dispatch
  excluded it. `prose.sh` is inert under `~/.claude/hooks` until the per-file
  link step for `HOME/.claude/hooks/*` runs from the repo root with the glob
  unquoted. Deferred prerequisite, not done and not faked.
- Only the `hooks` hunk of `HOME/.claude/settings.json` is in this commit. The
  working tree carried two unrelated uncommitted edits to that file (an emoji
  escaped in a permission entry, an `autoMode.allow` block) plus one to
  `HOME/.claude/CLAUDE.md`; they are none of this phase's business and stay
  unstaged.

### Tradeoffs
- jq for transcript parsing vs python3: jq matches the house hook shape and is
  already a dependency. Cost is a handful of jq invocations per turn end.
- Bounded 4 MB tail vs a full read: a turn that appends over 4 MB of records
  since the last typed prompt loses the prompt and the offer rule stands down.
  Chosen over an unbounded read on every single turn end.
- Synthetic transcript fixtures vs live session checks: the matrix pins the
  lagging, flushed and partially flushed orderings deterministically, which a
  live session cannot do on demand. The live checks stay in Phase 6.
- No warn-only path, per the doc's resolved decision: the hook blocks or
  passes.

### Open questions
- Is the slash-command imperative rule what Scott wants? If not, the doc's
  `last-prompt` amendment buys nothing for `/skill` turns and that should be
  recorded as the accepted cost.
- Phase 2's live offer criterion is unsatisfiable as written: `claude -p` writes
  no transcript at all (spike 0h defect 1), so the offer rule fails open in
  headless sessions by construction, which the doc's own Resolved Decisions
  already records. The live offer block needs an interactive session and
  belongs to Phase 6.
