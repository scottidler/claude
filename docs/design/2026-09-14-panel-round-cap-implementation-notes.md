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

## Phase 2: Register it and wire the gates

### Design decisions
- New `PreToolUse` matcher entry `"Agent"` added to `settings.json`, one hook,
  `~/.claude/hooks/panel-round-guard.sh`, matching the JSON shape of the
  existing `"AskUserQuestion"` entry exactly (single-hook array, `type:
  "command"`, tilde-path `command`). Placed directly after the
  `AskUserQuestion` entry and before the catch-all `""` matcher (`clyde permit
  log`), preserving the existing ordering convention of named matchers before
  the blank one.
- Link step run as `manifest -l 'panel-round-guard' | bash` from the repo
  root, per the doc's "link step runs in this phase" rule and the exact
  method the guard-precision Phase 7 orchestrator note used
  (`docs/design/2026-09-13-guard-precision-implementation-notes.md:222-223`).
  Confirmed the pattern is scoped to exactly the two new files by inspecting
  the generated (unexecuted) bash script first:
  `manifest -l 'panel-round-guard'` emitted only two `linker` lines, one per
  file, before piping to `bash`. `~/.claude/hooks/` is NOT a single directory
  symlink into this repo (unlike `~/.claude/skills` and `~/.claude/agents`,
  which are whole-directory links per `manifest.yml`'s `link.dirs`); it is a
  real directory populated by `manifest.yml`'s top-level `link.recursive: true`
  HOME entry, one symlink per file. So a new hook file needs its own link
  created, which is exactly the failure mode the guard-precision Phase 7 note
  describes ("three files this PR's phases add are not yet symlinked").
  `ln` failed once under the Bash sandbox (`Read-only file system`, writing
  into `~/.claude/hooks/`) and was retried unsandboxed per the sandbox-phantom
  guidance; the retry created both symlinks cleanly.
- `review-panel-notes.md` (which Phase 3 creates) is added to the `.otto.yml`
  lint list NOW, per the design doc's Phase 2 bullet, after checking rather
  than assuming how the lint task iterates. Traced the exact mechanics: the
  lint task is `if rg -n '\x{2014}' "${FILES[@]}"; then echo "Found..."; exit
  1; fi` under `set -e`. `rg` exits 2 (IO error) on a missing path, not 0 or
  1; a command inside an `if` condition is exempt from `set -e`; and `if`
  treats any nonzero exit (1 "no match" or 2 "error") identically as false, so
  the `exit 1` branch never fires. Proved directly:
  `bash -c 'set -e; FILES=(missing.md real.md); if rg -n "\x{2014}"
  "${FILES[@]}"; then exit 1; fi; echo reached'` prints `rg: missing.md: No
  such file or directory (os error 2)` to stderr, then `reached`, exit 0.
  Re-ran the full `otto ci` with the file still absent: it printed that exact
  `rg` IO-error line under `[lint]` and still finished
  `✅ All CI checks passed!`, exit 0. So the lint list tolerates a missing
  path (does not fail the build); the doc's instruction to add it now stands.

### Deviations
- None. Registration, the link step, the lint-list additions and the doc
  correction all match the design doc's Phase 2 bullets and the landmine
  guidance.

### Tradeoffs
- Left the `rg` IO-error line as a known, harmless side effect of adding
  `review-panel-notes.md` to the lint list before the file exists, rather than
  working around it (e.g. a `[ -f ... ] &&` guard per path). The design doc's
  own precedent (chunk B's CW5, cited in the Phase 2 bullet) is "a file not on
  the list drifts em-dashes back in where CI cannot see it"; the fix for that
  is exactly this list entry, and the stderr noise is temporary (Phase 3
  creates the file). Adding conditional guards per-entry would be scope this
  phase does not own and would blur why the line briefly errors.
- Verified the production hook via the `~/.claude/hooks/` symlink path with an
  isolated `PANEL_ROUND_CACHE_DIR` pointed at a scratch directory under
  `$TMPDIR`, rather than the test matrix's own fixtures, so the verification
  proves the actual registered artifact (the symlink, the settings.json entry)
  rather than re-running Phase 1's already-green matrix. The env prefix was
  placed on the hook invocation only (`PANEL_ROUND_CACHE_DIR="$CACHE_DIR"
  "$HOOK"`), never on `jq`, per Phase 1's own postmortem about a stray real
  counter entry from a misplaced prefix.

### Open questions
- None.

### Verification: `bin/hooks-resolve`
```
hooks-resolve: all hook files resolved (0 PATH warning(s))
```
Exit 0.

### Verification: `otto ci`
Full run (lint + test) exits 0, ending:
```
[test] === bin/hooks-resolve ===
[test] hooks-resolve: all hook files resolved (0 PATH warning(s))
[test] bun test v1.3.14 (0d9b296a)
[test]  114 pass
[test]  0 fail
[test]  188 expect() calls
[test] Ran 114 tests across 1 file. [45.00ms]
[test] finished successfully
[ci] ✅ All CI checks passed!
[ci] finished successfully
```
`HOME/.claude/hooks/panel-round-guard-test.sh` inside that run: `pass=95
fail=0`. The `[lint]` phase of the same run also printed
`rg: HOME/.claude/agents/review-panel-notes.md: No such file or directory (os
error 2)` (expected, see Design decisions) and still finished
`finished successfully`.

### Verification: production symlink path, isolated counter
`readlink -f ~/.claude/hooks/panel-round-guard.sh` -> the repo path
(`.../HOME/.claude/hooks/panel-round-guard.sh`), confirming `$0` is the
production path for this run. Four dispatch payloads for one fake doc, piped
through `~/.claude/hooks/panel-round-guard.sh` with `PANEL_ROUND_CACHE_DIR`
set to a scratch directory under `$TMPDIR` (never the user's real
`~/.cache/review-panel/rounds/`):
```
round 1: exit=0 stdout=[]
round 2: exit=0 stdout=[]
round 3: exit=0 stdout=[]
round 4: exit=0 stdout=[{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"panel-round-guard: this is round 4 on <doc>; the cap is 3 (rules/interaction.md). ..."}}]
```
Cache entry after the run: `path=<doc>`, `mode=1`, `rounds=3`. Confirmed
`~/.cache/review-panel/rounds/` is empty afterward (the user's real counter
was never touched).

## Phase 3: Shrink review-panel.md to the contract

### Design decisions
- Moved every dated incident narrative to
  `HOME/.claude/agents/review-panel-notes.md`, keeping the rule each incident
  produced stated explicitly in `review-panel.md`, verified present after the
  move:
  - "Why this agent exists" (serialize/re-resolve/die-silently): rule
    ("resolve context once, dispatch both in parallel... synthesize once")
    kept in the shortened intro paragraph.
  - Step 0's three 2026-08-13 inheritance-panel failures: rules kept as Step
    0.3 ("never refuse a round on a stale diff"), Step 0.4 ("enumerate the
    caller's questions... explicit answered/unanswered verdict"), and the
    Step 5 hard exit contract.
  - Step 1's 2026-08-08 mid-round-edit anecdote: rule kept ("snapshot it
    immediately... pass the snapshot path, never `$DOC_PATH`... diff the
    snapshot against the live file before writing the synthesis").
  - Step 3's four dispatch incidents (detached seats 2026-08-31,
    single-reviewer-as-panel risk, the 2026-08-03/08-04 timeout tie, the
    2026-07-13-to-08-03 rc=3 sandbox era): rules kept as "never detach the
    seats", "`dispatch-status-r$ROUND.txt` is a durable record... read it
    back", "do NOT wrap the scripts in your own `timeout`", and the rc=3
    remedy paragraph plus the rc-decode table.
  - Step 3.5's 2026-07-19 Scott approval: rule kept (the fallback mechanics
    and its four bulleted rules), dropped only the approval-date attribution.
  - Step 3.75's otto PR #3 (2026-09-03) regression story: rule kept ("you
    have Bash, and closing that gap is why this step exists", plus the
    4-step probe procedure).
  - Step 4's idle-signal-gap history (2026-07-03 to 2026-08-07) and three
    wrong-absolute anecdotes (APPROVED-ready-to-build, "no 8th key", "no
    ninth key"): rules kept as "write the synthesis to a file first... never
    depend on the chat turn" and "before you repeat any seat's negative
    claim... run the command that tests it yourself... or label it
    `[UNVERIFIED]`".
  - Step 5's SendMessage length measurement and the 2026-08-13 unchecked-exit
    incident: rules kept as "content reaches the caller ONLY through an
    explicit `SendMessage` call" and the hard exit contract, "check them
    literally, as a shell command, not from memory".
  - Step 6's 2026-08-13 dropped-questions incident: rule kept ("Questions is
    non-negotiable... name every question you did not answer... say `0
    answered` and list all of them").
- Moved Step 2's two reviewer prompt bodies (Mode 1 and Mode 2, 3,505B in the
  original) to `HOME/.claude/agents/review-panel-prompts.md`, one section per
  mode, referenced by one line from Step 2. Not moved into the seat scripts,
  per the design doc's Non-Goals (would couple standalone `/architect` and
  `/staff-engineer` runs to panel behavior).
- Fixed Step 3's dispatch code block to write `dispatch-status-r$ROUND.txt`
  (was unsuffixed `dispatch-status.txt`), matching Step 0.1 and Step 5's
  exit contract exactly, and updated every downstream reference to the same
  file (Step 4 item 1, Step 6's Seats rule). Left `doc-snapshot.md`,
  `prompt.txt`, `arch.out`, `staff.out` unsuffixed in Step 1/2/3/3.5, exactly
  as they stood on `main`: the design doc's Landmine section and Step 5's
  exit contract single out only the dispatch-status name as the live
  inconsistency; the other four names are a softer, non-blocking
  inconsistency with Step 0.1 that this phase's instructions did not ask to
  fix, so widening the change would be scope this phase does not own.
- Step 4: `synthesis.md` now documented to carry `[SYNTHESIS]` only; removed
  the `[ARCHITECT]`/`[STAFF-ENGINEER]` raw-output headers and pointed readers
  at `$RUN_DIR/arch.out` / `$RUN_DIR/staff.out` by path instead, naming the
  4,035-line synthesis file as the reason.
- Step 6: `Round: <n>` in the report template is now `Round: <n> of 3`, with
  a one-line rule underneath saying to use the door's ceiling instead of 3
  when the door raised it for that doc. Also merged the template's two
  separate (and redundant) "Drift" bullets into one; a pre-existing defect,
  not part of this phase's assigned edits, but touched incidentally while
  fixing the same paragraph's dispatch-status reference and em-dashes.
- Documented the door in Step 0 as its own paragraph after the numbered
  list (not as a 6th numbered item, since it is a fact about enforcement the
  agent reads, not an action it takes each round): the control-line regex
  `^PANEL_ROUNDS_ORDERED_BY_SCOTT=[0-9]+$`, "never a word-boundary match
  anywhere", and the ceiling semantics, copied to match
  `panel-round-guard.sh`'s header and implementation rather than paraphrased
  from the design doc.
- Removed every em-dash (U+2014) from `review-panel.md`: the pre-Phase-3 file
  carried 44, used throughout as a general-purpose connector, not only inside
  the moved narratives. Replaced each with a colon, comma, parens, or a split
  sentence, chosen per site as `rules/voice.md` directs. Also fixed the same
  in the two new files: `review-panel-prompts.md`'s two prompt bodies
  (copied verbatim from the pre-Phase-3 Step 2) carried 7 em-dashes between
  them; `rules/safety.md` admits no quotation exemption, so these were
  rewritten too, not carried over as "verbatim historical text".
- Added `HOME/.claude/agents/review-panel-prompts.md` to `.otto.yml`'s lint
  FILES list (`review-panel-notes.md` was already there from Phase 2).
- No manifest link step needed: `~/.claude/agents` is a whole-directory
  manifest symlink into this repo (`readlink -f ~/.claude/agents` resolves to
  `HOME/.claude/agents`), unlike `~/.claude/hooks` which Phase 2 found is
  populated file-by-file. Verified both new files resolve to the repo path
  via `readlink -f`.

### Deviations
- The design doc's Phase 3 bullet estimates "lore extraction alone lands at
  ~19,970, zero margin. With the Step 2 move, ~16,500." Measured: after
  moving both the lore and the Step 2 prompt bodies, the file was still
  21,690 bytes, well above both predictions, because those two moves alone
  did not remove the file's 44 em-dash-joined clauses or its remaining
  verbose prose. Trimmed prose throughout (compressing repeated phrasing in
  Steps 0, 1, 2, 3, 3.75, 4, 5 and 6, while preserving every rule) to land at
  19,954. Reported here per the design doc's instruction to record the byte
  count as an observation; AC4 gates on the properties, not this number, and
  all of them pass (checked above).
- `review-panel.md` itself is not on the `.otto.yml` lint FILES list. The
  list's own leading comment says it "deliberately excludes review-panel.md,
  which chunk C rewrites wholesale," which reads as a note to revisit after
  this phase lands. Not added: the Phase 3 task instructions listed only
  `review-panel-notes.md` and `review-panel-prompts.md` as files to add to
  the lint list, and adding `review-panel.md` unprompted would be scope this
  phase was not asked to take. Manually verified zero em-dashes in it
  (`rg` check above) as a one-time check instead of a standing CI gate.
  Flagged here as an open question for whoever owns the next chunk.

### Tradeoffs
- Chose to compress prose rather than cut additional rule content to hit the
  under-20,000 target. The alternative (dropping a bullet, e.g. the "Declare
  each seat's tool limits" rule in Step 4) would have been faster but risks
  exactly the "Shrinking review-panel.md drops a rule that was load-bearing"
  risk the design doc's own risk table rates Med/High. Compression cost more
  edit passes; it cost zero rules.
- Left the pre-existing softer artifact-naming inconsistency
  (`doc-snapshot.md`/`prompt.txt`/`arch.out`/`staff.out` vs Step 0.1's
  suffixed names) unfixed, per the Deviations note above. Fixing it now would
  have been a larger, more scope-creepy edit than this phase's instructions
  called for, and it is not wired to any hard downstream check the way
  `dispatch-status.txt` is to Step 5's exit contract.

### Open questions
- Should `review-panel.md` itself join the `.otto.yml` lint FILES list now
  that Phase 3 has finished the "wholesale rewrite" the list's comment refers
  to? It currently relies on a one-time manual `rg` check rather than a
  standing CI gate.
- Should the artifact-naming inconsistency in Step 1/2/3/3.5
  (`doc-snapshot.md`, `prompt.txt`, `arch.out`, `staff.out`, `staff-sub.txt`
  unsuffixed, against Step 0.1's `-r$ROUND` convention) be fixed in a later
  chunk, the same way this phase fixed `dispatch-status.txt`?

## Phase 4: Delete the poll snippet, point the rule at the guard

### Design decisions
- Cut `create-design-doc/SKILL.md:54-67` (the "Poll its run dir" block)
  exactly, keeping `:69-74` ("Trust the findings, not the verdicts"). Verified
  the boundaries against the live file with `Read` before cutting rather than
  trusting the doc's cited line numbers blindly; they matched exactly.
- `rules/interaction.md:111`'s cap sentence is now a pointer to
  `panel-round-guard.sh`, in the shape `rules/git.md`'s "Branch names: no
  slash, mechanically enforced" section already uses for
  `branch-name-guard.sh` (name the hook, state what it denies mechanically,
  say there is nothing left in prose to compensate for). Named the door
  (`PANEL_ROUNDS_ORDERED_BY_SCOTT=<n>` as a control line in the dispatch
  prompt) and its ceiling semantics in the same sentence, per the task's
  instruction, so a reader of the rules file knows the escape hatch exists
  without having to go read the hook.
- `rules/interaction.md` lives under `HOME/repos/.claude/rules/`, a real
  directory in this repo, and `~/repos/.claude/rules/interaction.md` was
  already a live per-file symlink into it (confirmed with `readlink -f`,
  dated 27 Jun, predating this phase). No link step was needed: editing the
  repo file is editing the live rule directly.
- Folded in, from Phase 3's open question: added
  `HOME/.claude/agents/review-panel.md` to `.otto.yml`'s lint `FILES` list and
  deleted the comment that excluded it ("deliberately excludes
  review-panel.md, which chunk C rewrites wholesale"). That rewrite is Phase
  3, already landed, so the stated reason for the exclusion is spent. This is
  the design doc's own Phase 2 rationale applied to the file it was withheld
  from: "a file not on the list drifts em-dashes back in where CI cannot see
  it." `otto ci` confirms zero em-dashes in the file under the standing gate
  now, not a one-time manual `rg` check.
- Checked and left all five deliberately-untouched locations the doc names,
  confirming each still carries the reason the doc gives:
  `docs/2026-09-08-rails-function-hooks-handoff.md:65,84,113,133` (a dated
  handoff, point-in-time per `rules/taste.md`);
  `docs/design/2026-09-08-rails-bash-rewrite.md:91,518,527` (same class);
  `docs/sandbox-filesystem-allowlist.md` (documents the `/tmp/review-panel`
  allowlist and `mktemp -d` shape, both left intact by this chunk);
  `README.md:31` (references `bin/check-review-panel` by name only, nothing
  about polling); `bin/check-review-panel` (runs the seat scripts directly,
  never touches the `Agent` tool, so it was never in this guard's path).

### Deviations
- None. The cut boundaries, the rule pointer's content, and the lint-list
  change all match the task's scope; the (doc, mode) key, the door syntax and
  the ceiling semantics were already implemented in Phases 1-3 and are only
  being described here, not re-implemented.

### Tradeoffs
- Wrote the interaction.md pointer as three sentences (mechanism, door,
  ceiling) rather than one terse line matching git.md's exact length. The
  git.md precedent is one rule with one hook and no runtime door; this rule
  has a door Scott can invoke, and the task explicitly asked for the door and
  ceiling to be named so a reader does not have to open the hook file to find
  the escape hatch. Chose completeness over matching git.md's brevity
  exactly.

### Open questions
- None.
