# Implementation notes: handoff ownership and waiting discipline

Append-only. Design doc: `docs/design/2026-09-18-handoff-and-waiting-discipline.md`.
Branch: `worktree-f2-handoff`, built in the worktree `.claude/worktrees/f2-handoff` so that
no edit to `HOME/.claude/**` is live while it is being written. The live `~/.claude` symlinks
resolve into the MAIN checkout, so an in-place edit there changes every running session's hooks
and rules mid-turn; that is the reason this chunk is built out of a worktree at all.

## Phase 0: harness spike, zero code

Both probes ran out of a scratch project (`$SCRATCH/phase0`) under headless `claude -p`, never
against the live `~/.claude/settings.json`. Claude Code version on the box: **2.1.278**
(the doc's measurements were taken on 2.1.276; the two probes below were re-taken on 278).

### Probe 1: hook vs `validateInput` ordering. DECISIVE.

Setup: a project-local `PreToolUse(Bash)` hook that denies unconditionally with the reason
`PHASE0_HOOK_DENY_MARKER`, registered only in the scratch project's `.claude/settings.json`.

- `sleep 26` returned the **native** text: `Blocked: standalone sleep 26. To wait for a
  condition, use Monitor with an until-loop (e.g. \`until <check>; do sleep 2; done\`). To wait
  for a command you started, use run_in_background: true. Do not chain shorter sleeps to work
  around this block.` The hook's marker is absent from the whole transcript.
- Control, same project, same hook: `echo hi` returned `PHASE0_HOOK_DENY_MARKER` (3 occurrences
  across the stream). So the hook **was** registered and firing; only the sleep case bypassed it.

**Observed fact, recorded as the criterion asks: `validateInput` runs BEFORE the `PreToolUse`
hook chain.** Consequence for Phase 4, folded into the doc: our rule never sees a statement-0
bare `sleep >= 25`, because the harness has already refused it. The rule's whole domain is what
the native check lets through, which is exactly the three bypass classes B1, B2 and B3. T1's
`>=` boundary therefore matters for summed and multiplied totals (`echo A; sleep 25`), not for
the bare statement-0 case, which never reaches us.

### Probe 2: `silent_turn_reminder` at TURNS=2. INCONCLUSIVE HEADLESS, root cause localized.

Two runs, each six consecutive assistant turns carrying nothing but `Bash` tool calls:

1. `CLAUDE_CODE_SILENT_TURN_REMINDER_TURNS=2` alone: no reminder in the output stream.
2. `CLAUDE_CODE_SILENT_TURN_REMINDER=1` plus `..._TURNS=2`: no reminder in the output stream.

Rather than guess, the gate chain was read out of the 2.1.278 binary. The attachment is emitted
when `Ee && e===null && !y?.isRegularUserPrompt && !ute() && fxn(n.options.mainLoopModel)`:

- `Ee` is the main-session flag, resolved from the sibling ternary
  `callSite: Ee ? "attachments_main" : "attachments_subagent"`. True for a `-p` run.
- `ute()` is focus mode / brief transcript (`Ke().viewMode === "focus"`), not headlessness. False.
- `fxn(model)` is `_2("silent_turn_reminder", ..., a.CLAUDE_CODE_SILENT_TURN_REMINDER)`, and
  `_2` returns the env value directly when it is defined (`if(l!==void 0)return l`), so run 2
  forced this true and removed the served-capability question entirely.
- The counter `ojo()` treats a turn as user-visible only when the assistant message carries
  non-empty text or a `tool_use` in `rjo = new Set([Os, Cxn, qUo, z_, ey])`, of which two
  resolve to `"ExitPlanMode"` and `"SendUserFile"`. `Bash` is not in that set, so the six probe
  turns should have counted as silent.

**So the remaining unknown is not the gate, it is the surface.** Attachments are injected into
the model request, not echoed to stdout, and a headless `-p` run leaves no transcript under
`~/.claude/projects/` to inspect (searched: the only file on the box containing the probe marker
is this session's own transcript). A negative in the `-p` output stream is therefore not
evidence that the attachment did not fire.

**Status: the criterion is not satisfied and Phase 5 is NOT dropped on this evidence.** What
settles it is one interactive fresh session with `CLAUDE_CODE_SILENT_TURN_REMINDER_TURNS=2`
in `settings.json` `env`, two silent turns, then `grep -c silent_turn_reminder` over that
session's `~/.claude/projects/**/<session-id>.jsonl`. Phase 5 stays open until that runs.

## Phase 4: sleep-loop rule in `intent-guard.sh`

One new rule, SLEEP, in `HOME/.claude/hooks/intent-guard.sh`, plus its fixtures in
`intent-guard-test.sh`. No `lib.sh` change, as the doc predicted. Matrix: **187 -> 332, fail=0**.

### Design decisions

- **Two parts, one threshold.** A rule-local loop-span scan (`loop_spans`, awk) emits one
  TAB-separated record per region (`FLAT` outside every loop, `MULT n` for a loop whose
  iteration count resolved, `OPEN` for an uncomputable bound, `UNBOUND` for `while true` with
  no `break`). The bash side sums `sleep_ms` per record, multiplies by the record's
  multiplier, and denies at `>= 25000 ms`. Splitting it this way is what lets the flat sum
  exclude loop-body sleeps: a terminating loop's own pacing sleep is never in the total, so
  Monitor's `sleep 30` poll still allows while `echo A; sleep 26` still denies.
- **The span scan reads a copy whose QUOTES ARE NOT MASKED**, unlike every other rule in the
  file, and the gate is what makes that safe. `intent-guard.sh:686` -- the wrapper sweep
  requires `eval "for i in 1 2 3; do sleep 30; done"` and its `bash -c` twin to deny, and
  quote-masking erases exactly those bodies. What keeps a quoted loop that is DATA out is
  `sleep_seen`: a sleep must be in executable position per `stmts` + `cmdword_is` somewhere in
  the command before any span arithmetic runs at all, and `echo "for i in 1 2 3; do sleep 30;
  done"` is one statement whose command word is `echo`. Fixture both ways.
- **The gate also opens on a shell-invoking statement carrying the word `sleep`.**
  `intent-guard.sh:690-700`. Measured this phase: `bash -c "for i in $(seq 1 30); do sleep 60;
  done"` tokenizes to `bash -c "(); do sleep 60; done"` | `for i in $` | `seq 1 30`, because
  `find_dashc`'s argument mask and the command-substitution span collide in `lib.sh`, so NO
  statement's command word is `sleep` and a cmdword-only gate closed the door on a deny the
  criteria require. The gate only opens the door; every total is still summed with
  `cmdword_is`, so `bash -c "grep sleep /etc/crontab"` totals nothing. Fixture for both.
- **A loop keyword is stored as the KEYWORD, not the raw token** (`allt[depth] = w`). A wrapper
  leaves its quote attached (`eval "while true; ...` tokenizes to `"while`), and the UNBOUND
  and OPEN branches feed the span text back through `stmts`, where a stray leading quote turns
  the whole span into one quoted word and the sleep inside it vanishes. Caught by the wrapper
  sweep: four spellings of `while true; do sleep 30; done` allowed before this line.
- **A `for`/`while`/`until` that never reaches its `done` is not a loop.** The frame dissolves
  into its enclosing context instead of denying, so `echo for; sleep 10` is priced as the 10s
  it is and `echo for; sleep 30` still denies on the total. Both are fixtures.
- **A bounded loop nested inside a terminating one is still priced.** A terminating frame
  contributes 0 for its OWN direct sleeps (that is the pattern the harness prescribes) but a
  factor of 1 for its descendants, so `until [ -f X ]; do for i in {1..100}; do sleep 30;
  done; done` denies at 3000s. Fixture.
- **Deny text reuses the native deny's wording verbatim** (`SLEEP_ADVICE`), so the two guards
  read as one voice, and each deny names what it could not compute (`*.txt`, `$(cat list)`,
  `a C-style for ((...))`, `a for loop with no \`in\` list`) rather than claiming a total.
- **The rule runs last** in the file. It is the least destructive rule here and the only one
  whose cost lands on commands that are otherwise fine, so it is gated twice: a `*sleep*`
  substring test before any `cmdword_is` spawn, and `sleep_seen` before the span scan. A Bash
  call with no `sleep` in it pays nothing.
- **`run_in_background` wired end to end**, which had zero hits across the three files before
  this phase: read once at `intent-guard.sh:98-101` as `.tool_input.run_in_background`, and
  `run()` in the matrix now builds it into EVERY payload with an optional third argument. Five
  fixtures assert the unconditional allow, paired with the same command denying without it.
- **`runwrappedloop` asserts the exclusion count itself** (`total=18 invalid=4` via `bash -n`),
  so a shape that becomes parseable later fails the matrix instead of silently dropping out of
  the sweep. Loop fixtures ride the 14 parseable spellings; B1 and B2 ride all 18.
- **Break-the-code evidence, five breaks, each flipped its fixture:** bound always 1 -> 6
  cardinality failures; `break` carve-out removed -> the carve-out allow denies; the
  `run_in_background` read disabled -> the background allow denies; intra-iteration summing
  replaced by last-write -> `sleep 4; sleep 5` allows; the `cmdword_is` gate replaced by an
  unconditional true -> `echo "for ...; do sleep 30; done"` denies.

### Deviations

- **The stale RULES block names five rules plus SLEEP, not six plus SLEEP.** The doc's Phase 4
  step says the file implements six and that `INGEST, POST, PUBLIC-REPO and LN` are the four
  omitted. There is no POST rule: `grep -n POST intent-guard.sh` returns only `gh api`'s
  body-flag-implies-POST logic, and `intent-guard-test.sh` asserts no such rule. The file
  implements GH-WRITE, DELETE-OUT, LN, INGEST and PUBLIC-REPO; SLEEP makes six. The block now
  names what is there.
- **The gate widened past `cmdword_is sleep` alone**, for the `bash -c` + command-substitution
  tokenizer collision described above. Same effect as the doc's design, correct seam: the doc
  assumed `stmts` would always surface the sleep as a statement, and it does not in that one
  shape. No `lib.sh` change was made, per the doc's constraint.
- **A quoted loop inside a shell-invoking statement denies as code.** `bash -c "echo 'for i in
  1 2 3; do sleep 30; done'"` is data nested two deep and this rule denies it. That is the
  price of the gate widening; the plain `echo "for ...; done"` case, which is the measured
  false-positive class, allows.

### Tradeoffs

- **One threshold on total wait vs. any per-iteration cap.** T2 stayed withdrawn, as ruled.
  `until ...; do sleep 60; done` and Monitor's `sleep 30` poll both allow; a `for i in
  {1..60}; do sleep 0.5; done` at 30s denies. Total foreground wait is the only quantity
  priced.
- **Upper-bound arithmetic vs. early exit.** A bounded `for` loop carrying a `break` is still
  multiplied by its full bound, so `for i in $(seq 1 60); do check && break; sleep 0.5; done`
  denies at its worst case of 30s. The `break` carve-out is deliberately confined to the
  unbounded loops, where there is no other number to use.
- **A non-literal sleep duration contributes 0 rather than denying.** `for i in 1 2 3; do
  sleep "$INTERVAL"; done` allows. Denying it is outside this phase's stated domain (the three
  measured bypass classes) and its false-positive size is unmeasured, so it ships as a named
  residual with a fixture rather than as folklore. Same class as the variable-verb limit chunk
  B handed on.
- **Token-level `do`/`done` matching vs. a real parser.** `echo done` inside a loop body would
  close the frame early. Accepted: the alternative is a second shell grammar in awk, and the
  dissolve-on-unclosed rule keeps the failure mode on the allow side for the mirror case.

### Open questions

- **The opaque-bound false-positive size is still `[UNQUANTIFIED]`**, as the doc's risk table
  says. `for f in $(cat list); do sleep 30; done` now denies, and nobody has measured how often
  that shape is legitimate. The doc says the class is re-measured before any widening; this
  phase did not widen it and did not measure it either.
- **Phase 4 is NOT deployed and does not need to be.** `intent-guard.sh` is an EXISTING hook
  with a live symlink into the MAIN checkout, so this rule goes live the moment the branch
  lands there. That is worth Scott knowing: unlike Phase 3's new hook, this one needs no step,
  and it arrives on every running session at merge.
- **The main checkout's uncommitted `intent-guard.sh` PUBLIC-REPO range fix (branch
  `session-recall`, chunk D territory) touches this same file** and will conflict. Named in the
  handoff already; recorded here because Phase 4 is the phase that makes it a merge problem.

## Phase 6: ToolSearch section in `general.md`

New `## ToolSearch` section in `HOME/repos/.claude/rules/general.md`, between `## CI` and
`## Version Control`. `wc -c`: **5,285 -> 5,649, +364 bytes.**

### Design decisions

- **All three facts from the doc's `:205-220`, not the prefix alone**, per the audit correction
  (re-measured: prefix-dropping is 6 of 19 ToolSearch zero-match failures, not 12 of 18):
  `select:` needs exact, comma-separated names; an MCP tool's exact name is `mcp__server__tool`;
  names come from the session's own deferred-tool list, never memory.
  `HOME/repos/.claude/rules/general.md:84-88`.
- **The citation names three concrete sites** (memory tools, the artifact tool,
  `EndConversation`), each of which uses the harness's own `select:<name>` form per the doc's
  `:215`, so a future reader can grep the running harness's own prompts rather than trust the
  rule's say-so.
- **`general.md`, not a new `rules/tools.md`**, per the doc's `:217`: `~/.claude/tools.md` is
  already Scott's custom-CLI inventory, and a name collision on two unrelated things is the
  cognitive dissonance `general.md` itself forbids.
- **The `SendMessage` line is explicitly labelled "Guidance"**, not phrased as a rule, because
  the doc's Resolved Decisions section (`:375`) already closed the "build a template that loads
  SendMessage" idea as dropped, not deferred: there is nothing to enforce, only a habit to name.

### Deviations

- None. The section states the three facts the doc specifies, cites the three usage sites the
  doc names, and carries the `SendMessage` line as guidance, matching the phase's success
  criteria at `:305-308` verbatim.

### Tradeoffs

- **Citation completeness vs. AC5's byte ceiling, and citation won.** Five compression passes
  were run against `wc -c` before landing on 364 bytes: 649 -> 490 -> 402 -> 379 -> 364. Below
  364, the remaining cuts started dropping the concrete site names (memory tools / artifact
  tool / `EndConversation`) that make the citation re-verifiable rather than a bare assertion,
  which is what the phase spec asked for over a shorter but unverifiable sentence. The doc's own
  projection was ~250 bytes for this phase; the actual is 364, +114 against that projection.
- **One `## ToolSearch` section vs. folding the guidance line into an existing section.** A
  fourth bullet under `## CI` would have saved the `## ToolSearch\n\n` heading overhead (~16
  bytes), but CI and tool discovery are unrelated concerns, and `general.md`'s own existing
  sections are each single-topic; a stray bullet under the wrong heading is exactly the
  cognitive-dissonance failure mode `general.md` itself calls out elsewhere in the file.

### Open questions

- **AC5's 400-byte ceiling does not hold.** Phase 2's `WHOAMI.md` measured +138
  (`24a9403`: 2,887 -> 3,025). Phase 6's `general.md` measured +364 (5,285 -> 5,649). Combined:
  **+502, 102 bytes over the 400-byte ceiling** (64,166 + 502 = 64,668 against a 64,566 cap).
  Phases 1, 3, 4 and 5 add zero to this basis (Phase 4 touches only `intent-guard.sh`, which is
  a hook, not a rule or memory file); Phase 7 is not yet run. Whether the overage is acceptable
  as-is, or the ToolSearch citation should be cut to close the gap (at the cost of
  re-verifiability), is Scott's call. Recorded in the design doc under AC5 and the Phase 6
  Result line, not resolved here.

## Phase 7: waiting discipline in `release-driver.md`

Replaced the two vague-pacing bullets in `HOME/.claude/agents/release-driver.md` (originally
`:167`, the CI-poll pacing note in step 4, and `:186`, the `sdv probe` pacing note in step 6)
with an explicit mechanism, and touched nothing else. `release-driver.md:4` is
`tools: Bash, Read, Grep, Glob`; both new bullets name only `run_in_background` (a Bash tool
parameter) and shell constructs (`until`, `sleep`) the agent already shells out to via Bash.

### Design decisions

- **`run_in_background` plus a terminating `until` loop, in one Bash call.** Since
  `release-driver` has no `Monitor` tool (`tools:` line confirmed before writing either bullet),
  the mechanism is: run the whole poll loop (`until <condition>; do sleep 30; done`) as a
  single `run_in_background: true` Bash call, so the harness notifies the agent when the loop
  exits instead of the agent re-invoking Bash every few seconds. Both bullets state this the
  same way (step 4's `gh pr checks` poll, step 6's `sdv probe` poll), with step 6 referring back
  to step 4 rather than repeating the full explanation.
- **The `review-panel.md` carve-out is cited by name and span, `review-panel.md:146-151`**, at
  the first (step 4) bullet: its dual-seat launch deliberately stays foreground with `wait`,
  never `run_in_background`, because a detached child is reaped by the sandbox's PID namespace.
  That carve-out is for two seats sharing one call, not for a solo polling wait, so the new
  release-driver text names it as a boundary, not a contradiction.
- **`babysit/SKILL.md:80-91`'s `/loop` timer is cross-referenced, not duplicated.** Babysit
  already solves the analogous "don't hand-poll the user's patience" problem for the main
  session, which has a `Skill` tool release-driver lacks. The new text names that file and line
  range and states the `run_in_background` + `until` loop above is the equivalent mechanism for
  an agent that cannot invoke `/loop`, rather than adding a second waiting mechanism to
  `babysit/SKILL.md` itself (that file was read, not edited).

### Deviations

- None. The doc's Phase 7 step asked for `run_in_background` plus a terminating `until` loop,
  named explicitly, not `Monitor`; the `review-panel.md` carve-out added by name; and a
  cross-reference (not a second mechanism) to babysit's `/loop`. All three landed as specified.

### Tradeoffs

- **Repeating the mechanism at both bullets vs. cross-referencing step 4 from step 6.** Chose to
  restate the `run_in_background` + `until` pattern briefly at step 6 (with its own `sdv probe`
  example) rather than only pointing back to step 4, since a reader mid-way through step 6 for a
  `cli`/`service` release may not have step 4 fresh; the `review-panel.md` and `babysit`
  cross-references are stated once, at step 4, rather than duplicated at step 6, to keep the doc
  from repeating the same citation twice.

### Open questions

- None.

## Finalization: acceptance-criteria walk and the AC5 amendment

### Design decisions
- Doc `Status` set to "Implemented, except Phase 5" rather than plain "Implemented" (design doc `:5`): Phase 5 is parked on Scott's interactive `silent_turn_reminder` probe and was never dropped, so a bare "Implemented" would misreport it. The word "Implemented" is present so a mode-2 Implementation Audit reads the doc correctly.

### Deviations
- **AC5's ceiling amended 400 -> 502 bytes, on Scott's explicit ruling, recorded as Addendum A.4.** This is an amendment to a criterion, so the evidence is here rather than only in the doc. Measured at branch tip `f851161`: 64,668 bytes total, being 51,849 in the 14 always-on rules (`cat HOME/repos/.claude/rules/*.md | wc -c`, less the 6 path-scoped files' share per the doc's stated basis) plus 12,819 in the four memory files (`wc -c HOME/.claude/CLAUDE.md HOME/.claude/WHOAMI.md HOME/.claude/tools.md HOME/repos/CLAUDE.md` -> 5,707 + 3,025 + 3,349 + 738). Pre-F2 was 64,166. Delta +502: Phase 2's WHOAMI.md +138, Phase 6's general.md +364. The criterion was NOT amended to make a failing implementation pass on the implementer's own authority: it was reported as a FAIL, the choice was put to Scott as accept / cut the citation / claw back elsewhere, and he chose accept.

### Tradeoffs
- Keeping Phase 6's three citation sites costs 102 bytes over the original cap and buys a rule whose facts a future reader can re-verify against the harness. Cutting them would have closed the gap and left three unfalsifiable assertions in always-on context.

### Open questions
- None from finalization. Phase 4's opaque-bound false-positive class remains `[UNQUANTIFIED]` (its own section), and Phase 5 remains parked on the interactive probe.

### Acceptance criteria, verified at branch tip `f851161` (2026-09-20)
- AC1 PASS: `Skill(HOME:handoff)` returned the skill body, no `disable-model-invocation` refusal.
- AC2 PASS: `bash HOME/.claude/hooks/handoff-guard-test.sh` -> `pass=37 fail=0`.
- AC3 PASS: `bash HOME/.claude/hooks/intent-guard-test.sh` -> `pass=332 fail=0`, up from 187.
- AC4 PASS: `git -C ~/repos/mattpocock/skills status --porcelain` and `git -C ~/repos/Q00/ouroboros status --porcelain` both empty.
- AC5 PASS against the amended 502-byte ceiling, FAIL against the original 400. See the deviation above.
- AC6 PASS both directions.
