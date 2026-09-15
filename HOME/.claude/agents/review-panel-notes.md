# Review panel: incident notes

Companion to `review-panel.md`. Full incident narratives that produced the
agent's rules live here, one per step, so the agent file carries only the
rule and a pointer. Moved out by
`docs/design/2026-09-14-panel-round-cap.md` Phase 3; nothing here changes a
rule, only where its backstory lives.

## Why this agent exists

Run by hand, the two reviewers get serialized, their doc/mode/dirs context
gets re-resolved twice, and they have died silently mid-run without anyone
noticing. Those three measured failure modes are why this agent resolves
context once, dispatches both reviewers in parallel, and synthesizes once.

## Step 0: round-handling failures (2026-08-13 inheritance panel)

Every failure in the 2026-08-13 inheritance panel was a round-handling
failure, not a review failure. Three, all avoidable, and each produced a rule
now stated directly in Step 0:

- Round 2 was dispatched against the ROUND 1 snapshot with "do not re-review
  the doc", so four of the caller's five questions were never answered. The
  drift line mentioned the snapshot; nothing said "your questions went
  unanswered." The caller believed they were answered and wrote "Ready to
  build" into a doc that then failed round 3 with five must-fix. Produced the
  rule: enumerate the caller's questions and give each an explicit
  answered/unanswered verdict (Step 0.4).
- A later round diffed a snapshot taken at dispatch against the live file and
  reported "zero changes to any phase", after the caller had rewritten four
  phases. The diff was stale and the panel refused to run on that basis.
  Produced the rule: never refuse a round on a stale diff; report the
  measured diff and dispatch anyway (Step 0.3).
- The final round dispatched, both seats returned rc=0, and the agent exited
  without writing a synthesis or sending anything. The caller sat waiting on
  an idle notification while the results sat on disk. Produced the hard exit
  contract (Step 5).

## Step 1: the 2026-08-08 mid-round edit

Scott, 2026-08-08: a doc changed 6 times under a running panel (phase
renumbering, a new section, reordered phases, an added observation, a
measured number, new alternatives/risk rows), and the panel had no way to say
what it actually reviewed. Produced the rule: snapshot the doc immediately
and pass only the snapshot path to both reviewer scripts (Step 1.1).

## Step 3: dispatch failures

- **Detached seats, 2026-08-31.** A child process that outlives its own Bash
  call is reaped by the sandbox's PID namespace and dies silently, leaving a
  banner-only output file (~100 bytes) with no error anywhere. This killed
  the round-4 architect seat and both round-5 seats; foreground re-dispatch
  of the identical commands succeeded both times. Produced the rule: never
  detach the seats, one foreground Bash call for both launches and the
  `wait`.
- **Single-reviewer result presented as the panel, Scott 2026-08-08.** Before
  `dispatch-status-r$ROUND.txt` existed, a report could rest on chat memory
  of the dispatch rather than a durable record, so a silent single-seat
  failure could read as a full panel result. Produced the rule:
  `dispatch-status-r$ROUND.txt` is the record of whether both seats ran;
  read it back rather than trusting memory.
- **The timeout tie, 2026-08-03, ruled on 2026-08-04.** This agent once
  wrapped the seat scripts in its own `timeout 600` while the script's own
  cap was also 600s; the outer kill won the tie, the script's EXIT trap
  never ran, and the panel got a 110-byte banner-only file, rc=124, a stale
  pidfile, and zero diagnostic, twice in a row on the same doc. Scott ruled
  the script must always win: no outer `timeout` wrapping the scripts, only
  the Bash tool's own `timeout` parameter as a non-racing backstop.
- **The rc=3 sandbox era, 2026-07-13 through 2026-08-03.** 37% of ALL panel
  dispatches in that window (55 of 149) failed rc=3: the scripts wrote
  scratch files to bare `/tmp`, which the sandbox mounts read-only, so both
  seats died in ~3s with an 82-byte output. Fixed by moving the scripts to
  `$TMPDIR` and allowlisting the reviewer CLIs' state dirs and the scripts
  themselves in `settings.json`.

## Step 3.5: the credits/tokens fallback

Scott approved the Anthropic-model substitute for a credits/tokens failure on
2026-07-19: a failed seat is re-run on the same persona and prompt via
`claude -p --model opus` rather than dropped, labeled as a substitute in the
synthesis.

## Step 3.75: the otto PR #3 regressions (2026-09-03)

The audit's oldest blind spot: an implementation matched the design doc
bullet for bullet and still shipped four regressions against the previous
release (otto PR #3, 2026-09-03), because nobody ran the old binary next to
the new one. Both reviewers are read-only and can only name a suspected
regression; Step 3.75 exists so the orchestrator (which has Bash) confirms
it.

## Step 4: the idle-signal gap and three wrong absolutes

**The idle-signal gap, 2026-07-03 through 2026-08-07.** The harness's
idle/completion signal fires whenever this agent's turn ends, independent of
whether a synthesis was ever produced. This bit 15+ panel runs across 6+
repos in that window; every time it was worked around by re-querying the
agent or reading the seat output files by hand, never fixed at the root
(Scott, 2026-08-08: "why does this keep happening"). Produced the rule:
write the synthesis to a file first, and never depend on the chat turn as
the only completion artifact.

**Three wrong absolutes.** Both seats have flatly asserted a negative they
never ran a command to support, and been wrong doing it:
- one returned "APPROVED, ready to build" having rendered nothing, while
  missing two High findings
- one asserted "there is no 8th key" (there was)
- the other asserted "no ninth key" (there was, nested; its scan was
  top-level only)

Produced the rule: before repeating any seat's negative claim, absolute, or
bare verdict, run the command that tests it yourself and cite the output, or
label it `[UNVERIFIED]`.

## Step 5: delivery measurements

- **Length is not the variable.** Measured on two real runs: a
  2,013-character final turn was NOT delivered to the caller; a
  20,366-character `SendMessage` payload WAS. The delivery path is
  `SendMessage`, not turn length.
- **The 2026-08-13 unchecked exit.** Both seats returned rc=0 and the agent
  ended its turn with none of the hard exit contract's checks done:
  `arch-r4.out` (5,555B) and `staff-r4.out` (7,534B) sat on disk, complete
  and unread, while the caller waited on an idle notification and eventually
  had to `cat` them by hand. Produced the hard exit contract, checked
  literally as a shell command, not from memory.

## Step 6: the 2026-08-13 dropped questions

Four of the caller's five questions went unanswered behind a scope note, and
the caller marked the doc ready to build on that basis. Produced the rule:
the Questions field is non-negotiable, every unanswered question is named,
and `0 answered` is stated plainly rather than the field being dropped.
