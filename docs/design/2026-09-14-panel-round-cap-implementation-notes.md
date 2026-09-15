# Implementation notes: panel round cap

Append-only. One section per phase, all four buckets every time, "None." where empty.
Companion to `2026-09-14-panel-round-cap.md` and its review log.

## Phase 0: Prove the Agent seam

### Design decisions
- Ran Phase 0 inline in the orchestrating session rather than delegating it to
  `phase-implementer`. The probe needs a live `Agent` dispatch to fire a
  `PreToolUse(Agent)` hook, and `phase-implementer` has no `Agent` tool, so it
  physically cannot produce the payload the phase exists to capture. The nested
  `claude -p --settings` harness is chunk A Phase 0b's method verbatim.
- Measured the doc-path extraction hit rate over **all 348** corpus dispatches
  rather than the 25-prompt sample the success criterion asks for. Same cost,
  no sampling error, and it makes the miss set enumerable in full.
- Companion artifacts (`*-review-log.md`, `*-implementation-notes.md`) are
  dropped from the candidate pool before the `design/` preference is applied.
  The design doc's extractor sketch does not mention them, and without the drop
  a round-2 prompt that cites its own review log can key on the wrong file.
  Recorded here because Phase 1 must implement this step.

### Deviations
- Corrected the doc's absolute-versus-relative split. The doc says 290/346 (84%)
  absolute and 43 (12%) relative; re-measured with the actual extractor it is
  221/348 (64%) absolute and 118 (34%) relative. The doc's conclusion (`cwd` is
  mandatory) is unchanged and strengthened. Evidence file carries the numbers
  and the reason the two differ. The doc body is not amended: this is a Phase 0
  measurement, and the evidence file is where Phase 0 measurements live.
- The em-dash in one verbatim quoted corpus prompt was replaced with a colon in
  `evidence.md`, disclosed inline in that file. `rules/safety.md` admits no
  quotation exemption and the repo lints for the character.

### Tradeoffs
- Probe hook denied rather than allowed-and-logged. A deny costs one blocked
  dispatch and proves the block path in the same run; an allow would have let a
  real 10-minute panel launch to prove strictly less.
- Scratch settings went through `--settings` on a nested session rather than a
  temporary edit to `HOME/.claude/settings.json`. The latter is live on every
  session on the machine through the manifest symlink, so a probe registered
  there would have denied real panel dispatches in any concurrent session.

### Open questions
- None. The success criteria all passed, so the doc is not reopened.

### Observations, not gates
- The `Agent` `tool_input` carries two keys the doc did not predict,
  `description` and `run_in_background`. Neither is load-bearing.
- Claude Code 2.1.272 adds an `effort` key to the PreToolUse payload that was
  not present in chunk A's 2.1.270 capture. Unused.

## Phase 1: panel-round-guard.sh and its matrix

### Design decisions
- Allow is exit 0 with **no stdout**, not the siblings' `{}`. AC1 asserts the
  first three dispatches are "empty with exit 0" and AC2 asserts empty stdout
  for a non-panel dispatch, so the matrix pins emptiness rather than a decision
  string. The fail-open paths (missing `lib.sh`, non-panel subagent, unparseable
  prompt) all take the same empty-stdout exit for consistency.
- Mode detection is anchored to a Status **line**
  (`^[[:space:]]*(\*\*)?Status(\*\*)?:(\*\*)?[[:space:]]*Implemented`), not the
  substring search `review-panel.md:90` Step 1.2 describes. Same defect class as
  the door: the design doc this guard enforces discusses `Status: Implemented`
  in its own prose at `:135` and `:296`, so a "contains" test reads an In Review
  doc as Mode 2 and hands it a second set of three rounds. Pinned by the "a
  Status line in PROSE is not the doc's status" group in the matrix.
- Path normalization is lexical (awk: drop `.` and empty segments, pop on `..`),
  not `realpath`. The counter must key the same way for a doc that has not been
  written yet as for one that has, and `realpath` answers a question about the
  filesystem instead of about the path string. Four spellings of one doc
  (`abs`, `rel`, `./rel`, `rel/../rel`) are asserted onto one entry.
- The counter key is `sha256(<abs doc path>\n<mode>)` with no trailing newline,
  built with `printf '%s\n%s'`. Stated because the byte-exact input is what any
  future reader of the cache has to reproduce.
- Debug logging is `PANEL_ROUND_GUARD_DEBUG=1` to stderr, entry plus decision
  (`rules/logging.md`). The stderr warn on an unparseable prompt is
  unconditional, because the design specifies it as user-visible.

### Deviations
- **The door is matched as a control line, not at a word boundary.** The Phase 1
  bullet at `2026-09-14-panel-round-cap.md:249` says "matched at a word boundary
  in the prompt". That contradicts the doc's own "The door" section (`:161-170`)
  and AC3, both of which specify `^PANEL_ROUNDS_ORDERED_BY_SCOTT=[0-9]+$` against
  a nonblank line of its own, with the reasoning spelled out: the guarded
  document carries that literal marker followed by an integer four times, so an
  "anywhere" match lets the document raise its own cap. Implemented the
  control-line rule. The Phase 1 bullet is the stale line and should be corrected
  to match `:161`.
- Extractor step 2 (drop `*-review-log.md` / `*-implementation-notes.md` unless
  they are the only candidates) is implemented as Phase 0's evidence file
  specifies it, which is one step more than the design doc's own sketch carries.
  Phase 0 already recorded this; noting that Phase 1 built to the evidence file.
- `lib.sh` is sourced fail-open per the API Design bullet, and nothing in it is
  used: it parses command text and this guard consumes a prompt. The source line
  carries a comment saying so rather than implying a dependency that is not
  there. Called out because a reviewer will otherwise read it as dead weight
  (it is, deliberately, the house contract).

### Tradeoffs
- No `shapes.sh` sweep, per the doc's Testing Strategy: its 16 templates wrap a
  command word in shell, and this hook has neither. Replaced with the six named
  prompt mutations plus four more the same reasoning produces (a mid-sentence
  marker, a marker with trailing text, the deny text pasted back verbatim, and a
  CRLF prompt).
- The matrix is stateful and order-dependent inside each group, because the
  thing under test is a counter. Each group opens a fresh `mktemp` cache
  directory under `$ROOT` and exports `PANEL_ROUND_CACHE_DIR`, so no case can
  reach the user's `~/.cache/review-panel/rounds/`. The alternative (one
  counter-setting helper per case) would have hidden exactly the accumulation
  the design's central claim rests on.
- Fixture docs are written to a `mktemp` worktree rather than pointed at real
  repo docs, so the mode-flip case can rewrite a `Status:` line without touching
  anything tracked.

### Open questions
- None blocking. One correction for whoever edits the doc next: the Phase 1
  bullet's "word boundary" wording (`:249`) disagrees with `:161` and AC3 and
  should be brought into line with them.

### Break-the-code evidence (Phase 1 success criterion 2)
Baseline: `bash HOME/.claude/hooks/panel-round-guard-test.sh` -> `pass=95 fail=0`,
exit 0.

Reverted the round comparison at `panel-round-guard.sh:220`, `-gt` to `-ge`
(the doc's named mutation), and re-ran. **28 cases failed**, against the
criterion's floor of 4. The first thirteen, verbatim:

```
FAIL  [want allow got deny] alpha round 3
FAIL  [reason missing this is round 4] alpha round 4
FAIL  [reason missing (3 rounds recorded)] alpha round 4 names the counter
FAIL  [reason missing this is round 4] alpha stays at round 4
FAIL  [want rounds=3 got rounds=2] entry carries rounds=
FAIL  [want allow got deny] beta round 3
FAIL  [reason missing this is round 4] beta round 4
FAIL  [reason missing this is round 4] alpha is still capped
FAIL  [want allow got deny] door: round 3 plain
FAIL  [reason missing this is round 6] door: round 6 with the marker
FAIL  [want allow got deny] dot-relative round 3
FAIL  [reason missing this is round 4] dot-dot-relative round 4
FAIL  [want allow got deny] gamma mode 1 round 3
```

(that run predates the two fail-open cases added afterwards, so its totals read
`pass=65 fail=28` over 93 cases). Restored `-gt`: `pass=95 fail=0`, exit 0.

### Observations, not gates
- A stray counter entry for the real design doc was written into
  `~/.cache/review-panel/rounds/` during manual smoke testing, because an env
  prefix landed on `jq` instead of on the hook. Archived out with
  `rkvr rmrf` (`/var/tmp/rmrf/2026-09-14-173544-000/`); the cache directory is
  empty again. Worth knowing that the hook is live-capable before Phase 2
  registers it: anything that pipes a real dispatch payload into it counts a
  round.
- The hook is NOT registered in `settings.json` and `.otto.yml` is untouched,
  per the phase boundary. `otto ci`'s `test` task picks the new matrix up
  anyway, because it globs `HOME/.claude/hooks/*-test.sh`.
