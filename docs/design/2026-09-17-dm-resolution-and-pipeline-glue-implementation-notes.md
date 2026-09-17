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

## Phase 1: `slack-cli` gains `dms` on the cache

Commit: `873e417` on `dms-cache-and-fill` (`tatari-tv/slack-cli`), one commit, `otto ci` exit 0.

### Design decisions
- **The merge arm collapses both `Merge` variants**, per the doc's Data Model listing, rather than
  `unreachable!` on `Replace`: `Merge::Extend | Merge::Replace => current.dms.extend(...)` at
  `src/slack/cache.rs:439-446`. `unreachable!` would panic a caller into oblivion for a policy the
  type system permits, and this way a future sibling sync that copies a neighboring constant gets
  the extend semantics the immutable-edge argument assumes, not a silent wholesale replace. The
  comment says exactly that, so the collapse is not read later as laziness.
- **`dms_write_survives_upsert` asserts on the RELOADED file**, not the returned value
  (`src/slack/cache/tests.rs`). A `merge_and_save` missing the arm still returns a cache whose
  `dms` came from `current`, so a weaker assertion on the return value would pass without the arm
  and be worthless. Proven: see Success criteria below.
- **Added `dms_extends_under_every_full_sync_policy`** beyond what the phase asked for. Sites 1
  through 3 fail to compile if a constant is missing the field, but nothing makes a constant
  written as `Merge::Replace` fail to compile, and `Replace` is exactly the behavior the design
  rejected. The test asserts the surviving edge through all three full syncs.
- **`sample()` in `cache/tests.rs` gained a `dms` entry** rather than an empty map, so
  `round_trip_serialize_deserialize` and `json_shape_matches_design` cover the new key for free,
  and so the survives-upsert test's extend half has a pre-existing edge to preserve.
- **The `users` invariant test lives in `src/command/read/tests.rs`**, not `cache/tests.rs`. The
  sole writer is `command::read::enrich` (`read.rs:561`), verified by grep across all non-test
  source, so the test must drive the writer and not the cache. It reads a DM target (`D0123456789`
  satisfies `looks_like_channel_id`, and `conversations.info` returns no `name` for an `im`, which
  is the exact shape that tempts an opportunistic `D…` write), then asserts every `users` key
  starts with `U` and that the DM id is absent. It also asserts `dms` is still empty, which is a
  true statement of Phase 1's scope: the map, not the fill.
- **`adding_dms_does_not_change_current_schema` pins `CURRENT_SCHEMA == 2`** so the no-bump
  decision is enforced by CI rather than remembered from the doc.
- **The `read()` debug log was left alone.** It enumerates `channels`/`users`/`subteams` and
  already omits `handles`/`profiles`; it is not one of the doc's six sites, and `merge_and_save`'s
  entry and exit logs (sites 5 and 6) are what diagnose a dropped `dms` write.

### Deviations
- **`MergePolicy`'s own doc comment was also fixed** (`cache.rs:318-323`), not just the specified
  `merge_and_save` comment at the old `:350-354`. It read "How a merge folds `handles` and
  `channels` respectively", which was already false for `subteams` and `profiles` and is the doc
  comment attached to the struct site 2 edits. Same class of fix as the one the phase named, on a
  site this phase changes anyway.
- **`IdCache`'s own doc comment at `cache.rs:55-57` was NOT fixed and is still stale.** It renders
  the on-disk shape as `{channels, users, handles, self}`, omitting `subteams`, `profiles` and now
  `dms`. Fixing it is not in Phase 1's scope and is listed as an open question rather than folded
  in silently.
- **A `dms` entry in `sample()` changes two existing tests' fixtures** (`round_trip`,
  `json_shape_matches_design`, the latter gaining one assertion). Additive, no existing assertion
  was weakened or removed.

### Tradeoffs
- Collapsed match arm vs `unreachable!` on `Replace`: chose the collapse because the failure mode
  of the alternative is a runtime panic on a type-legal input, and the doc offered either.
- `dms` placed after `profiles` in the struct (the doc's site 1 said "after `cache.rs:117`", which
  is the `profiles` field) rather than beside `self_`, so the serialized key order groups it with
  the other id-maps ahead of the watermarks.
- The `users`-invariant test drives the full `read` command through mockito rather than calling
  `enrich` directly: more moving parts, but it exercises the actual DM path where a `D…` key would
  be introduced, which a direct `enrich` call cannot reach.

### Open questions
- **`IdCache`'s doc comment (`src/slack/cache.rs:55-57`) still lies about the on-disk shape**,
  omitting `subteams`, `profiles` and `dms`. Left untouched as out of Phase 1's scope. Fold it into
  Phase 2 (which already edits this area) or leave it: Scott's call.

## Phase 0d and the environment re-measurement

Appended after Phase 1's section on purpose, and the file is append-only: 0d was **measured on
Phase 1's own dispatch**, so it genuinely finished later than Phase 1 did.

### Design decisions
- **0d ran against the real Phase 1 dispatch rather than a synthetic probe.** The doc discounts
  its own prior observation because it was "one data point on a different agent type, not the
  gate", so a `general-purpose` stand-in would have reproduced exactly that weakness. Measuring
  on the actual `phase-implementer` dispatch costs nothing extra and answers the gate.
- **Fact 1 is reported as an absence over a bounded window**, not as a proof of impossibility:
  zero wakes across ~12 minutes and roughly a dozen parent tool rounds. That is what the gate
  needs (the heartbeat covers report boundaries only), and it is the honest shape of the claim.
- **Fact 2 asserts the roster, not the send.** The doc says "assert the EFFECT (the worker is
  gone from `ListAgents`), not that a message was sent", and the before/after listings are
  recorded rather than the `success: true` response.

### Deviations
- **Recorded a Phase 0 environment section that is not one of the four spikes.** The write fence
  governs whether Phases 7, 8, 10 and 11 can run from a session at all, and it was
  mis-stated once during this run (reported as blocking, from Bash `touch` probes alone) before
  being corrected by a `Write` that reached `HOME/.claude/skills`. Chunk D had already proven it
  twice by commit. It is in the evidence because the next agent to hit it should not re-derive it.

### Tradeoffs
- Chose to resolve Phase 1's open question (the stale `IdCache` shape comment at
  `cache.rs:55-57`) by **folding it into Phase 2** rather than leaving it or opening a phase for
  it. It is the same class of defect the doc already ordered fixed for `merge_and_save`, `dms` is
  what made it wronger, and Phase 2 edits that file anyway. Recorded here as a disclosed
  deviation so the audit does not find it unattributed.

### Open questions
- None for Phase 0. The two carried forward are already written down: 0b-4/0b-5 need an
  interactive session, and Phase 7's hook wording must corroborate itself against the visible
  prompt (0b-3a).

## Phase 2: slack-cli fills `dms`, eagerly and on a miss

Commit: `tatari-tv/slack-cli` branch `dms-cache-and-fill`, on top of Phase 1's `873e417`.

### Design decisions
- **One predicate, three fillers.** `edge(&Channel) -> Option<(&str, &str)>` (`src/slack/dm.rs`)
  is the single place that decides what a recordable DM is: `is_im` AND a non-empty `user`.
  `sync_dms`, `record_edge` and `resolve_dm_user` all go through it, so the eager and lazy halves
  cannot disagree about what lands in the map.
- **`record_edge` is the single `dms` writer** (`src/slack/dm.rs`). The lazy resolver and the
  opportunistic read-path fill both call it rather than each building their own patch; the sync
  builds one patch for the whole listing because it is one `upsert`, not N.
- **`resolve_dm_user` re-tests `is_im` itself** instead of reading it off `record_edge`'s `None`.
  The two `None`s are different facts and `rules/logging.md` requires the exit log to say which:
  `not-an-im` (nothing will ever resolve this id) vs `miss` (it IS a DM whose counterpart Slack
  did not report). Writing is still gated by `edge` alone.
- **`Ok(None)` is an answer, `Err` is a failure to ask.** `slack cache resolve` exits 0 with
  `.user: null` for a non-DM or a counterpart-less DM, and propagates auth/transport failures.
  Phase 4's backstop needs to distinguish "answered: nobody" (a decision) from "could not ask"
  (a fail-closed deny), and a single non-zero exit for both would collapse them. The JSON shape
  `{"dm": …, "user": …|null}` is the documented contract for the guard; the text form is human.
- **`fill_dms` carries no `dms_filled_this_run` flag and no staleness gate**
  (`src/slack/mention.rs`), unlike its three siblings. There is no watermark, no TTL, and no
  reverse-lookup miss that could trigger a second fill inside one run, so there is nothing for a
  once-per-run bound to bound. The cold-miss path is one `conversations.info`, not a re-listing.
- **`sync_dms` extends and stamps nothing.** It copies `sync_channels`'s cursor loop exactly but
  goes through the extending `cache::upsert`, not `upsert_full_channel_sync`: the `D…` -> `U…`
  edge is immutable, so a DM absent from the listing (Slack omits closed DMs) has not changed
  owner and must not be evicted. A test pins that a listing-absent edge survives.
- **`dms` is ENUMERATED in `render()`, not counted** like `profiles`. A count cannot answer
  "whose DM is this `D…`", which is the map's whole purpose.
- **A missing `im` listing scope is NOT tolerated** the way `usergroups:read` is: `fill_dms`'s
  error propagates out of `refresh`. The usergroup `MissingScope` warn arm is an argued
  exception in that code, and the doc gives no equivalent ruling here; the MCP path already
  lists `im` types, so the scope is held. Fail loudly rather than invent a second silent arm.

### Deviations
- **`src/surface.rs` gained a `cache resolve` leaf and an `id` positional arg, plus a re-blessed
  `plugin/README.md`.** Not in the phase's bullets, but the repo's `surface::tests` hard-fails on
  any clap capability with no classification row, and `otto ci` cannot go green without it. Same
  effect as the doc's intent (the verb ships reachable and documented), at the seam the repo
  actually has. The generated README block was regenerated with `BLESS_SURFACE=1`, not hand-edited.
- **`mock_full_refresh` now returns FOUR mocks and both `users.conversations` listings are matched
  on `types=`** (`src/slack/mention/tests.rs`). The DM fill hits the same endpoint as the channel
  fill, so the previously unmatched mock absorbed both calls and reported two against an
  `expect(1)`. Five existing refresh tests, plus three more that build their own mocks
  (`command/cache/tests.rs` x2, `command/users/tests.rs`), were updated the same way. This is the
  "a phase changes behavior, so the old test is updated by name, not deleted" case.
- **`command::read::tests::sole_users_writer_keys_on_a_user_id` was INVERTED, not deleted.** Its
  last assertion was `assert!(cache.dms.is_empty())` with the comment "Phase 1 adds the map, not
  the fill: nothing on the read path populates `dms` yet". Phase 2 makes that false on purpose, so
  it now asserts the edge IS recorded (keyed `D…` in `dms`), and the `users`-key invariant it
  exists for is still asserted beside it.
- **Phase 1's open question folded in, attributed to the orchestrator, not the doc.** The stale
  `IdCache` doc comment at `cache.rs:55-57` rendered the on-disk shape as
  `{channels, users, handles, self}`, omitting `subteams`, `profiles` and `dms`. Fixed in this
  commit: it now lists every map plus the watermarks, and carries a line saying it is the whole
  shape rather than a sample, since that is the defect that let it drift for two phases.
- **`channel_display_name`'s new `cache_path` is for the EDGE, not the name.** The doc ordered the
  signature change; what it buys is documented on the function, because a reader would otherwise
  see a path threaded into a function that returns a name and never touches disk for one.

### Tradeoffs
- **`record_edge` as a third public function in `dm.rs`** vs having `read` call `resolve_dm_user`
  (which would re-fetch `conversations.info`) or inlining a patch at the read site (a second
  writer). The doc names two functions; a third, narrow one keeps the writer single and the
  opportunistic fill free, and it is what `resolve_dm_user` itself writes through.
- **`is_im` from the API is the only DM discriminator; no `D…` prefix short-circuit.** A prefix
  check would save one call on an obviously-wrong id, at the cost of a second, weaker truth about
  what a DM is. `resolve_dm_user` asks the authority and reports `not-an-im`.
- **`sync_dms` requires `is_im` on listed entries even though it asks Slack for `types=im`.**
  Redundant on the happy path, but it is the same predicate the lazy half uses, and a listing that
  ever returns something else writes nothing rather than a wrong edge.
- **The `dms` enumeration in `render()` grows the inspector by one line per DM.** Accepted for the
  reason above; `profiles`' count-only treatment exists because its records are multi-field, which
  a `D… -> U…` pair is not.

### Open questions
- None for Phase 2. One thing for the operator, already in the doc's "Operator steps": Phase 3
  needs the INSTALLED binary (`cargo install`) and every resident `slack mcp serve` restarted,
  since an old writer drops `dms` on `save()`.

## D2 release: the bump, and Phase 2's SHA change

Supersedes the SHA recorded in the Phase 2 section above. That section is left as written, per
append-only.

### Design decisions
- **`bump --no-tag -m`, minor rather than patch.** `rules/git.md` defaults to patch "unless the
  design doc describes a breaking change", but both commits are `feat(cache)` and they add a
  user-visible verb (`slack cache resolve`) plus a new persisted cache field. Additive and
  non-breaking, which is the semver definition of a minor. `0.13.1 -> 0.14.0`.
- **D2 ships as its own PR, separate from chunk E.** Scott, 2026-09-17: "if you want for D2 sep
  from E, fine. do it." The doc already permits it: "E7 and E8 are single-repo and independent of
  D2. They can land in any order relative to it."
- PR: `feat(cache): dms cache and fill`,
  https://github.com/tatari-tv/slack-cli/pull/51. Title slugifies to `dms-cache-and-fill`,
  which is the branch, per `branch-pr-title-guard.sh`.

### Deviations
- **Phase 2's commit is `6d9af3f`, not the `6deb4c8` recorded above.** `bump --no-tag` **amends**
  the tip commit rather than adding a version commit, so Phase 2's commit now also carries
  `Cargo.toml` and `Cargo.lock` at 0.14.0 and its message does not mention the bump. That is the
  tool's designed behavior for a gated repo and the doc wants the bump riding the PR, so it was
  kept rather than unwound. Recorded because the audit will otherwise find a phase commit
  carrying an unexplained version change, and because the SHA above no longer resolves.
- **Two pre-existing untracked files were parked in a stash across the bump and restored**:
  `docs/2026-09-15-watch-token-recovery-handoff.md` and
  `docs/2026-09-16-dm-resolution-handoff.md`. Neither is ours and one is cited in the design doc's
  References. `bump` runs `git add -A`, and its PreToolUse guard refuses a dirty tree for exactly
  that reason, so the choice was park-and-restore rather than commit them into a version commit or
  delete them. Both are back, untracked, and Scott's unrelated `stash@{0}` was never touched.

### Tradeoffs
- Pushed and opened the PR from this session rather than handing Scott the commands. He approved
  it explicitly ("do it"). The `git push` itself had to run with the sandbox off: SSH cannot read
  `~/.ssh` under it and fails `Host key verification failed`.

### Open questions
- None. Next gate is human: one CODEOWNER approval on
  https://github.com/tatari-tv/slack-cli/pull/51, then `cargo install` and a restart of every
  resident `slack mcp serve` before Phase 3 starts.

## Phase 5: the inline-token matcher, standalone

### Design decisions
- `matches(context, offset, token) -> bool` is the one scoring primitive (`inline/matcher.py:matches`),
  and it scores exactly one occurrence per the scoring protocol: `offset` is the index of the `/`,
  the token starts at `offset+1`, and the function raises rather than guesses if the two disagree
  with what it was handed. This is the guard against silently reverting to the per-window reading
  the phase explicitly forbids.
- The leading-neighbor rule is inverted at the position the offset contract already guarantees
  (`context[offset] == "/"`), so there is nothing left to check there; the boundary check moves
  one character further back, to `context[offset-1]`, per round 2's finding (`inline/matcher.py:matches`).
- Quote, bracket/angle and code-fence span exclusion is real span-tracking, not a lexical
  heuristic (`_quote_spans`, `_bracket_spans`, `_code_spans` in `inline/matcher.py`). An
  unclosed delimiter (fence, quote, or bracket) inside the 100-char fixture window is treated
  as extending to the end (or, for a lone unpaired code fence marker, the whole window) rather
  than assumed absent: the fixtures.json README documents 375 of 832 `code-span` records with
  odd backtick parity for exactly this reason, and the doc's own zero-false-positive criterion
  makes the conservative reading the only one that clears it.
- `find_matches(text)` added as a thin convenience wrapper around `matches`, scanning a whole
  string for `/token` candidates (`inline/matcher.py:find_matches`). Not requested by the phase
  body, but Phase 7 wires a hook that scans a whole prompt, and `matches` alone gives it no
  entry point to do that with; this is the extensible seam, one concrete case, per
  `rules/taste.md`.
- Package is `inline/matcher.py`, not a single `inline_token_matcher.py`: `rules/general.md`'s
  source-file rule says a compound name decomposes into a directory (first word) plus a
  single-word file. `token` was rejected as the directory name because it shadows the Python
  stdlib `token` module, which `tokenize.py` imports internally, and nothing here needs that
  name in particular.
- Test file is `inline/tests.py` (stdlib `unittest`), invoked by
  `HOME/.claude/hooks/inline-token-matcher-test.sh`, the latter hyphenated because it is
  exec'd directly by `otto ci`'s `test` task, never imported, matching
  `rewrite-cd-read.py`/`-test.sh`'s existing split. No `.otto.yml` edit was needed: the `test`
  task already globs `HOME/.claude/hooks/*-test.sh`, so the new file is picked up by name alone.

### Deviations
- **Function-level debug logging (`rules/logging.md`) is split across two levels, not one.**
  `find_matches` (called once per prompt) logs entry/exit at DEBUG; `matches` (called once per
  candidate inside that scan, dozens of times per prompt) logs its decision at a custom TRACE
  level (`logging.addLevelName(5, "TRACE")`), since Python's stdlib has no built-in TRACE and
  the rule demotes tight-loop logging rather than dropping it.
- **No `.otto.yml` change**, though the task said to say explicitly how Python tests are
  hooked in: they are not hooked in by editing the runner, only by naming the new file to match
  the glob the `test` task already runs (`HOME/.claude/hooks/*-test.sh`). Confirmed by the CI
  run itself: `=== HOME/.claude/hooks/inline-token-matcher-test.sh ===` appears in the log
  unprompted.
- **The design doc's own round-2 measurement table (561/195 -> 560/7 -> 554/571/2) does not
  reproduce against the pinned `fixtures.json` at the numbers it states**, and this phase's
  reported numbers (556/583 survivors, 0/1421 false positives) are measured against the
  committed, pinned fixtures directly rather than reconciled against that table. The doc itself
  says the corpus drifted between measurements (236 -> 240 posts "in one afternoon" for the
  sibling Phase 3 corpus) and names `fixtures.json` as the sole pinned artifact for this phase;
  this implementation trusts the file over the narrative table built while it was still moving.

### Tradeoffs
- Bracket-span exclusion (parens/brackets/braces/angles) suppresses matches inside ANY
  parenthetical, including ones that only coincidentally wrap a `/token`, e.g. `(/status,
  /deployed, /version)`, rather than trying to distinguish "shielding aside" from "the user
  meant this parenthetical as the instruction." The phase's own success criterion requires
  exactly this parenthetical to score zero matches, so the coarser rule was kept over a
  narrower one that would need the deny-list vocabulary Phase 6 owns, not this phase.
  Consequence: an opening-delimiter character is listed as a valid "boundary" per the design
  doc's literal wording (`_is_boundary` includes `([{<"'`), but in this implementation a slash
  immediately after one is always also inside a span that same character opens, so that arm of
  the boundary check is effectively unreachable. Kept for fidelity to the stated rule rather
  than removed as dead code, and covered by
  `BoundaryTest.test_slash_after_opening_paren_is_suppressed_by_the_bracket_span`, which
  documents the interaction rather than assuming it away.
- `unittest` over `pytest` for the checked-in suite, even though `python.md` names `pytest` as
  the house test runner and it is installed on this machine (`uv run pytest
  HOME/.claude/hooks/inline/tests.py` passes the identical file, verified). The hooks directory
  carries no `pyproject.toml`/`uv.lock` and the repo's one prior Python hook has no test
  dependency either; adding one for a single module seemed like the wrong precedent to set
  standalone, so the CI-invoked suite stays dependency-free and pytest-compatible rather than
  pytest-required.

### Open questions
- None.

## Phase 6: name resolution

### Design decisions
- **Plugin/namespaced enumeration reads `~/.claude/plugins/installed_plugins.json`'s resolved
  `installPath`, not a marketplace-cache crawl** (`inline/resolve.py:plugin_skill_names`). The
  cache holds many hash-versioned directories per plugin (`.../marquee/a90f82b7cbd7-5e689e2b`)
  with no single stable "current" pointer visible from `.in_use` (every version in
  `skill-creator`'s cache carries an `.in_use` marker from some past PID), and
  `known_marketplaces.json` plus each `marketplace.json`'s `source` field would require
  re-deriving version resolution the harness already did. `installed_plugins.json` is that same
  resolution, already done, keyed exactly on the `settings.json` `enabledPlugins` entries this
  phase already has to read. Verified live: `platform@tatari-skills` resolves to
  `.../cache/tatari-skills/platform/1.8.3`, whose `skills/` holds `argocd-ops`, `k8s-debug`,
  `plan-eval`, `pod-placement-audit`, `search-loki`, `turbolift` -- six skills the same as the
  live `plugin_skill_names(...)` call returns for that key.
- **Rule 3 needs no post-hoc filtering step, by construction.** The design doc's own reference
  generator (`docs/design/.../phase0/inline-token/m4.py`) computes a `STRICT` set by starting
  from an `ALL` name list that already contains bare aliases (`argocd-ops`, `k8s-debug`,
  `search-loki` all appear bare in `skillnames.json` with no personal-skill directory backing
  them) and then subtracting them. This implementation's `plugin_skill_names` never emits a bare
  form for a plugin skill in the first place: the only name it produces is `plugin:skill`, read
  from that plugin's own `installPath`. `resolve()`'s exact-match (`n == token`) then has no bare
  alias to accidentally match. `PluginSkillNamesTest.test_no_bare_alias_is_ever_emitted_for_a_plugin_skill`
  pins this directly against a real example from live `skillOverrides` (`platform:argocd-ops`).
- **`skillnames.json` was deliberately NOT reused as the live "ALL" set**, despite the parent
  task pointing at it as the generator's reference. Cross-checking it against live state shows
  it is not a raw, unfiltered name list: `marquee:slides-reveal` (currently off), all of
  `slack:{delete,repost,search,write}` (currently off, only `slack:read` survives) and
  `platform:{argocd-ops,plan-eval,pod-placement-audit,turbolift}` (currently off, only
  `k8s-debug`/`search-loki` survive) are absent from it even though their plugins are installed
  and enabled today. That means the 2026-09-17 harvest already reflects `skillOverrides` state
  as of harvest time, so replaying it now would double-apply (or mis-apply, given
  `skillOverrides` has grown from ~50 to 81 entries since) rule 2 against a stale snapshot. Live
  enumeration plus this module's own `off_skill_names` is the only way to keep rule 2 correct as
  `skillOverrides` continues to change. Recorded here because it is a direct deviation from the
  literal instruction to "match" the generator.
- **`off_skill_names` matches on the literal string `"off"`**, not truthiness or any other
  value, because that is the only value observed in the live 81-entry map and it is what the
  harness's own error text names ("disabled via skillOverrides").
- **The generic-word deny list is applied case-insensitively** (`n.lower() not in deny`) even
  though every observed skill name and every deny-list word is already lowercase-hyphenated per
  `rules/general.md`. Free, and it means a future typo in a skill name's case does not silently
  bypass the deny list.
- **`resolvable_skills` and `resolve` take every data source as an injectable keyword
  argument** (`skills_dir`, `settings`, `installed_plugins`, `skills`), defaulting to the real
  live paths only when omitted, per the phase's constraint to read live state without writing to
  it. Every unit test except the three in `LiveStateTest` injects synthetic fixtures instead.

### Deviations
- **Test file is `inline/resolve_tests.py`, not `inline/tests.py`.** Phase 5 already claimed
  `tests.py` for `inline.matcher`'s suite, and a package cannot hold two files of the same name.
  Forced, not stylistic: the phase's instruction to "match Phase 5's house style" is honored in
  every other respect (stdlib `unittest`, a `*-test.sh` wrapper picked up by the existing glob).
- **Did not reuse `docs/design/.../phase0/inline-token/skillnames.json` or `m4.py`'s `STRICT`
  computation verbatim.** See the design decision above: `skillnames.json` is itself a filtered,
  point-in-time snapshot (post-override, as of 2026-09-17), not the raw universe the parent
  task's framing implied. The *effective behavior* m4.py's `STRICT` rule encodes (a plugin
  skill's bare form never resolves) is preserved, and preserved more robustly (by construction
  rather than by set subtraction against a name list that itself needs to stay in sync with
  what plugins are actually enabled).

### Tradeoffs
- **`plugin_skill_names` fails a single plugin quietly (WARN-logged) rather than raising** when
  an enabled plugin has no `installed_plugins.json` record or an unreadable `installPath`. A
  `UserPromptSubmit` hook (Phase 7's consumer) runs on every typed prompt; one malformed plugin
  entry should not take down name resolution for every other skill. Covered by
  `test_enabled_plugin_missing_install_record_is_skipped_not_raised`.
- **No caching of `enumerate_skills()`'s result across calls.** Phase 7 will call this once per
  `UserPromptSubmit` invocation (a fresh process each time, per the existing hook pattern), so
  there is no long-lived process to cache against yet; premature to add here.

### Open questions
- None.
