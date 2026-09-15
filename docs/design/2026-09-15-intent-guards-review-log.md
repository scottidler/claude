# Chunk D review log: intent guards

Minutes for `docs/design/2026-09-15-intent-guards.md`. Rounds are capped at 3 by `panel-round-guard.sh`.

## Pre-panel: `design-research` fold-in, 2026-09-15

Dispatched before the panel; reported after round 1 was already running, so the seats reviewed the pre-fold snapshot. Six corrections folded:

1. Item 8's `Environment=` vector is the wrong artifact. No unit file under `~/.config/systemd/user/` holds a secret value; the only names are `PATH` and `SCCACHE_*`. The credentials ride `EnvironmentFile=` into mode-0664 `/run/user/1000/{borg,cortex,sb-harvest}.env`, plus `~/.config/eratosthenes/digest.env`, `~/.cache/okta/tokens.json` and `~/.cache/slack/token.json` (singular).
2. The `Read` deny's interaction with `Read(**)` in `permissions.allow` is unproven, so it became a Phase 0 gate instead of an assumption.
3. "An allowlisted skill is active" is not implementable: no payload field, and the only transcript signal has no end marker. Refused in both places it appeared.
4. Chunk B handed this chunk an open hole the draft missed entirely: `'echo' $GH_TOKEN` allows while `"echo" $GH_TOKEN` denies, because `mask_squote` erases the verb before an unanchored regex sees it. Now Phase 1, ahead of every new rule.
5. The two exempt Slack ids cannot be resolved from the cache (`#clipboard` is a private single-member channel, absent from the 823 `channels`), so both are hardcoded.
6. The write fence on `settings.json`, `agents/`, `skills/` is Bash-only; the Edit tool reaches them, proven by `f257ddb` and `ca3bfe8` inside this program.

One thing the dig got wrong, refuted by the panel in the same round: the `last-prompt` ordering claim, generalized from a session with one typed prompt. See M10.

## Round 1, 2026-09-15

Run dir `/tmp/review-panel/GOX7yywR/`. Architect (gemini-3.1-pro-preview) rc=0. Staff engineer (codex gpt-6-astra) rc=124 at the 10m cap mid-exploration, re-dispatched once at 18m, rc=0. 10 must-fix, 7 cheap wins, 2 defers, 8 rejected with measurements.

Five must-fix were re-verified in this session before folding, because each changes a predicate:

| finding | verification |
|---|---|
| M1 PUBLIC-REPO's commit half is inert on its founding incident | the incident is one Bash call, `git add ... && git commit`, so the index is empty at hook time |
| M3 LN denies its own legitimate shape | `realpath -m` on an existing link and on its target return the identical path |
| M4 INGEST misses the incident's shape | ran `stmts` on the loop body: the `$( )` ingest splits out with no loop keyword |
| M5 GH-WRITE's parser allows `-XDELETE` | `flag_value -X` returns empty for the attached form, `DELETE` for the separated one; `gh` parses both |
| M8 hooks go live on save | `~/.claude/hooks/*` are per-file symlinks into the working tree |

Folded without argument: M1, M2, M3, M4, M5, M6, M7, M8, M9, M10, C1 through C7. Nothing was dropped or deferred against a reviewer's wishes.

Two findings changed a decision rather than a predicate:

- **M6** is the sharpest of the round. `--broadcast`, `dm_mentioned` and `follow_ups` each reach recipients past the named target, so the Slack exemption became a bound on the full recipient set.
- **The STAGING Rec was attacked successfully on justification, not volume.** The deny's own recovery instruction (`git add docs/design && git commit`) permits the identical violation, so the rule cannot claim item 1. It narrowed to `-A`/`.`/`--all` justified purely as phantom prevention, and item 1 moved to Non-Goals with five measured predicates.

## Findings rejected in round 1, with the measurement

Recorded so round 2 does not re-derive them.

- **Architect's subagent-type predicate for item 1.** 569 denies of 882 subagent commits, 0 of 5 incidents; `agentType` is free-text across ~190 values and every incident is main-thread. Asserted without measurement.
- **The panel's own path-provenance predicate.** 820 denies, 4 of 5 incidents, precision ~0.5%.
- **Architect's claim that LN's cycle direction is backwards.** Wrong: target-ancestor-of-link is the cycle, and its counterexample (`ln -s .. parent_dir`) creates exactly the infinite path that froze the workstation.
- **Architect's DELETE-OUT expansion.** `gh issue delete` 0, `acli bitbucket` 0, `gh pr close` 28 but a closed PR reopens.
- **Architect's "extend PUBLIC-REPO to `~/repos/*/*`".** No repo outside `scottidler/` has an origin remote Scott owns.
- **Architect's "the `~/Claude` symlink deny is unrequested".** It is in `CLAUDE.md`; both seats found traceability.
- **Staff's "INGEST loses loop context" as a general claim.** The `for` and `xargs` forms each emit one statement carrying both the loop and the ingest; only the command-substitution shape is affected.

## Process notes for later chunks

- **Do not dispatch the panel while a research fold-in is still outstanding.** The live doc moved 194 lines while round 1 ran, both seats reviewed the snapshot, and one of the round's findings exists only because the fold introduced a claim mid-review. Land every fold-in first, then snapshot, then dispatch.
- **A predicate written from a man page is not measured.** M3 and M5 would both have been caught by running the command once. The doc's own rule says every predicate is measured before it ships; the draft applied that to fire counts and not to the predicate's own mechanics.

## Post-round-1: the two open questions close, 2026-09-15

- **Item 1's coverage.** Asked to Scott as an A/B with five measured predicates. Ruling: **A**, accept the gap. Item 1 ships no guard and is recorded in Non-Goals.
- **STAGING's price.** Closed by measurement rather than by ruling, and it reversed the author's own Rec. Every sandbox phantom in the working tree is a character special file, so `git add -A --dry-run` aborts with `error: .bash_profile: can only add regular files, symbolic links or git-directories / fatal: adding files failed` and stages nothing. Git already fails closed on the class. Add the third strike: the one incident the rule was credited with is `git add -A docs/design`, path-scoped, which cheap win C2 requires the rule to allow. Zero of five incidents, no phantom class, no item-1 claim. Dropped to Alternative 5 with a revisit condition (a 0-byte regular-file phantom, which is addable).

Net effect on scope: eight phases, 0 through 7. Seven rules ship. Open Questions is empty.

## Round 2, 2026-09-15

Same run dir. Architect rc=0, staff engineer rc=0, no timeout this round. 10 must-fix, 10 cheap wins, 5 reject/defer. Both seats independently returned "not ready to build" and neither attacked a settled ruling: item 1's gap, the staging drop, LN's cycle direction and every round-1 rejection all survived untouched.

Drift again, and it is the same process failure as round 1: the live file moved 51 lines during the round (commit `4947f06`, the acceptance-criteria execution). Staff read the live tree and credited it; architect read the snapshot. Two rounds, two drifts.

Three findings re-verified here before folding:

| finding | verification |
|---|---|
| `flag_value` is first-wins, `gh` is last-wins | `printf 'gh api repos/o/r -X GET -X DELETE' \| flag_value '' '-X'` returns `GET`, while `gh api -X POST -X GET /rate_limit` returns rate-limit data, which a POST could not |
| a plain commit walk misses merge-introduced content | built a merge whose resolution alone added `.env`: `git log --name-only BASE..HEAD` lists `a.txt s.txt`, `--diff-merges=first-parent` lists `a.txt .env s.txt` |
| the obvious `flag_value` fix corrupts live guards | accepted on the panel's evidence: `-t` yields `esting` from `--body -testing`, `-H` yields `bad/name`, and `lib-test.sh` passes 135/0 over the patched copy, so the matrix does not protect it |

The reversal worth recording: **round 1 decided the parser gap belonged in `lib.sh`, and round 2 reversed it.** `flag_value` has no per-flag arity table, so it cannot distinguish an attached value from a value that begins with a dash. That is not fixable generically without giving the parser a flag spec, which is a chunk-B-sized change to a dependency three shipped guards share. GH-WRITE parses the method itself; the five measured rows land in `lib-test.sh` as characterization fixtures.

Two findings were rules that could not work as written, not predicates that were merely wrong:

- **RESEND was inert.** A `PreToolUse` hook cannot observe a send result, so the state round 1 asked for could never be written. Fixed with a `PostToolUse` registration.
- **INGEST's raw-text scan denies the writing of this design doc**, which contains both `while IFS= read -r url` and `sb borg ingest`. Bounded to heredocs whose redirect target is a shell script, with both shapes pinned as fixtures. Chunk C's self-reference class, caught by a reviewer rather than by the author for the second chunk running.

Six fold-introduced contradictions were fixed: stale predicates in Edge cases, a stale `last-post` record in Data Model and Phase 5, LN described as a pure function of the command string, Rollout still saying hooks go live on commit, Goal 1 still promising coverage for every class including item 1, and the recorder decision framed as settled while Phase 0 lists its gate as open.

Round 2 nominated four items for Open Questions. All four were decisions rather than unknowns and are decided in the doc: PUBLIC-REPO's outgoing-object set, the stale-private window, RESEND's lifecycle, and which recipient set is authoritative.

## Process notes, both rounds

- **Do not touch the live doc while a panel round is running.** It happened twice. Round 1's drift produced a finding that existed only because of the fold; round 2's split the two seats onto different texts. Snapshot, dispatch, wait, then edit.
- **A predicate written from a man page is not measured.** Round 1 caught `realpath -m` and the `flag_value` gap this way; round 2 caught first-wins-versus-last-wins and the merge walk. Four defects, four one-line commands, none of them run before the text was written.
- **Ask what writes the state before designing the state.** RESEND specified a ledger no registered component could write.

## Round 3, 2026-09-15

The last round under the cap. Architect rc=0, staff engineer rc=0. 9 must-fix, 20 cheap wins, 4 rejected. Both seats returned "not ready to build" independently and neither touched a settled ruling. **Live vs snapshot: 0 lines.** The doc was held still this round and both seats read identical bytes, which is the process fix working.

Both probed bypasses re-verified here before folding:

| finding | verification |
|---|---|
| `gh` accepts `-X=VALUE` | `gh api -X=GET /rate_limit` returns rate-limit data, so a local parse that does not strip the `=` reads `-X=DELETE` as the value `=DELETE` and allows |
| a dash-leading header value poisons last-wins | `printf 'gh api -XDELETE -H "-XGET: x" repos/o/r' \| args` yields `-XDELETE \| -H \| -XGET: x \| repos/o/r`, so a naive last-wins scan resolves the method to `GET` from the operand of `-H` |
| `stmts` erases a subshell boundary | `printf '(cd /tmp); pwd' \| stmts` yields `cd /tmp \| pwd`, so naive cwd accumulation concludes `pwd` runs in `/tmp` |

Of round 2's ten fixes, six held and four did not: RESEND, GH-WRITE's method parse, PUBLIC-REPO's push destination, and PUBLIC-REPO's commit table. LN was right in direction and missing a scope boundary.

Three findings were the same class as round 2's RESEND: a rule whose mechanism could not do what the text claimed.

- **The `flock` claim was false.** A `PreToolUse` process exits before the tool runs, so a lock it holds covers the hook and not the send. Replaced with an `O_EXCL` entry create, where the exclusion spans processes because the create does.
- **`PostToolUseFailure` is a distinct event carrying `error`, not a tool result**, so per-recipient recording had nothing to read. The rule now fails closed on a failure and Phase 0 gained a criterion to dump that payload.
- **The INGEST door was unreachable**, because the deny clauses were evaluated first. Precedence is now stated as door, then read-only verbs, then denies.

One finding is a repeat of my own making: **round 2's "zero denies" fix reached the LN rule text and never reached either criterion.** Phase 3 and the overall acceptance list both still asserted zero denies across a corpus containing three commands the rule exists to deny. Fixed in both places.

Rejected with measurements: the architect's whole-history false-deny severity claim (0 pattern matches across all history, 0 blobs over 1 MB, 2,905 objects), its Goal-1 contradiction claim, its "Phase 1 is unrequested scope" claim, and any reopening of `flag_value`, whose five characterization rows the staff seat re-ran with matching output.

## Standing after three rounds

The cap is reached. Nine must-fix folded, all of them decisions rather than unknowns, and no reviewer has read the post-round-3 text. That is the honest state to hand Scott: the rulings are settled, Open Questions is empty, and the last fold is unreviewed.

Pattern across all three rounds, worth carrying into chunk E: **every round found at least one rule whose stated mechanism could not perform the stated job** (round 1: `realpath -m` denying its own legitimate shape; round 2: a ledger nothing could write; round 3: a lock that does not span the operation it guards). None of the three was a fire-count or precision error. The question that would have caught all three is "what process, at what moment, executes this, and what can it see?"
