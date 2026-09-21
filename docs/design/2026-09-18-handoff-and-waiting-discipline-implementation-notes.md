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
