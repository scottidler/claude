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

## Phase 1: sandbox config and text fixes (PARTIAL, two files blocked)

### Design decisions
- Landed out of order, after Phase 2, because Phase 1 was blocked when the loop
  reached it. Nothing else was resequenced.
- `ssh-agent-check.sh` was rewritten rather than patched at line 10. Its whole
  premise was agent reachability, and Phase 0 proved the sandbox denies
  `socket(AF_UNIX)` creation outright, so no sandboxed process can ever reach an
  agent. The hook now checks file readability of both halves of the active
  `user.signingkey`, which is the thing that actually determines whether a
  sandboxed `git commit` succeeds. `ssh-add -l` is kept only as an
  unsandboxed-push warning.
- The hook expands a leading `~/` in `user.signingkey` itself. git accepts that
  form in its config and the shell does not expand it for us, so without this the
  readability test would fail on a path that is actually fine.
- `review-panel.md` keeps its 44 existing em-dashes. The design doc names it as
  the one exemption in the touched set, because chunk C rewrites it wholesale.
  This edit introduced zero new ones.

### Deviations
- **`HOME/.claude/settings.json` was NOT edited. Blocked.** Every `sandbox` and
  `env` change in the Phase 1 bullet list is unlanded: the `allowWrite` additions
  (`/var/tmp/rmrf`, `/var/tmp/bkup`), the five `allowRead` absolute paths, the
  `excludedCommands` additions, and `env` gaining `TMPDIR` and `RUSTC_WRAPPER`.
- **`HOME/.claude/CLAUDE.md` was NOT edited. Blocked.** The two sandbox lines are
  unlanded.
- Cause in both cases: the Claude Code auto mode classifier denies the write with
  `[Self-Modification]`. Hit three times, on a `phase-implementer` dispatch whose
  prompt described the edits, on a direct Edit of `settings.json`, and on a direct
  Edit of `CLAUDE.md`. This is exactly the operator note in the doc's
  Implementation Plan preamble, item (b): these phases must run with auto mode
  off. It is an environment gate, not a code problem, so no workaround was
  attempted past the second failure.

### Tradeoffs
- Committed the three unblocked files rather than holding the whole phase. The
  alternative was one clean Phase 1 commit later, but that would have left the
  `ssh-agent-check.sh` rewrite and the `review-panel.md` correction unrecorded
  while the branch moved on. Phase 1 therefore takes two commits, and the second
  is owed.

### Open questions
- None for the author. One for the operator: auto mode must be off for the
  settings.json and CLAUDE.md half of this phase, and for Phase 3 (hook
  registration) and Phase 5 (the rails plugin under `HOME/.claude/skills/`).
