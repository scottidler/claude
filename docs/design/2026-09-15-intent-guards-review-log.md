# Chunk D review log: intent guards

Minutes for `docs/design/2026-09-15-intent-guards.md`. Rounds are capped at 3 by `panel-round-guard.sh`. Round 4 ran on Scott's order, through the guard's `PANEL_ROUNDS_ORDERED_BY_SCOTT=<n>` control line.

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

## Round 4, 2026-09-15

Ordered by Scott past the cap to review the round-3 fold, which no reviewer had read. Dispatched with `PANEL_ROUNDS_ORDERED_BY_SCOTT=4` on its own control line, which is the only way `panel-round-guard.sh` allows a fourth dispatch. Architect (gemini) rc=0, staff engineer (codex) rc=0. 8 must-fix, 3 cheap wins, 0 defers, 3 rejected. Both seats returned "not ready to build" independently and neither reopened a settled ruling. **Live vs snapshot: 0 lines**, the second clean round running; the doc was held still and both seats read sha256 `d97a5701...`.

Five of round 3's nine fixes verified clean: the `O_EXCL` replacement for `flock`, the `PostToolUseFailure` fail-closed ruling, `-X=VALUE` stripping, the push-destination three-outcome table, and the directory-expansion and zero-denies-propagation halves. Four needed another pass.

**Two findings are working bypasses, executed against the live endpoint, not reasoned from a man page:**

```
$ gh api -XDELETE -p -XGET /rate_limit --verbose 2>&1 | sed -n 3p
> DELETE /rate_limit HTTP/1.1
$ gh api -XDELETE --header "-XGET: x" /rate_limit --verbose 2>&1 | sed -n 3p
> DELETE /rate_limit HTTP/1.1
```

Round 3 fixed the `-H` operand-poisoning case and hand-listed the skip flags. The hand-list omitted `--header` (the long alias of the flag it had just fixed), `-p`/`--preview` and `--cache`. The fix is the complete `gh api --help` specification, short and long alias per flag, with one operand-skip fixture each in Phase 2.

Four findings re-verified in this session before folding, because each changes a predicate:

| finding | verification |
|---|---|
| M1 the skip list is incomplete | `gh api --help` lists ten value-taking flags; the doc carried seven names and missed three aliases |
| M2 LN's raw-paren fallback over-denies | 51 `ln -s` corpus commands, 8 carry a `(`, only 3 carry a structural `$(`; `lib.sh:68` says class `P` survives masking, so the masked copy separates them |
| M5 `has(...)` admits expressions | `printf '{"example":"visible"}' \| jq 'has(.example \| debug)'` prints `["DEBUG:","visible"]` to stderr and returns `false` |
| M6 `git commit --include` misses a prior `git add` | scratch repo: `git diff --cached --name-only` empty at hook time, `git add secrets/new.txt && git commit --include README.md` commits both files |

Three findings were mechanisms that could not do the stated job, the same class every prior round produced:

- **M2, LN.** The paren test ran on the raw command, so a paren in a comment or a quoted string stopped cwd accumulation and denied a legitimate command. That makes Phase 3's "exactly 3 denies" unsatisfiable, which is a criterion the fold had just corrected for a different reason.
- **M3, INGEST.** Step 2's "read-only verbs always allow" stated no scope, so `sb borg log; sb borg ingest --file urls.txt` returned allow for the whole command and never reached step 3. Round 3 fixed the door's reachability and introduced this one directly above it. Both seats found it independently.
- **M4, the door.** `BULK_INGEST_ORDERED_BY_SCOTT=<n>` called `<n>` a maximum and never compared it, so `=0` allowed and `=1` allowed five ingests.

Two more were specification gaps the fold exposed without creating: **M5**'s jq grammar (a substring pattern where a whole-filter match was needed) and **M7**'s sourcing contract (the doc asserted SLACK and PUBLIC-REPO fail closed while prescribing the fail-open snippet that exits with an allow before any rule runs). **M8** is one lifecycle sentence: RESEND named no reaper, so two processes could both reclaim an expired entry and both `O_EXCL` create. Reclamation is now an atomic `rename` by whichever guard next touches the expired entry.

**M6 and C1 are the fold-propagation class**: the `-i`/`--include` commit row one row below the `-am` row that was fixed, and an Edge-cases bullet still prescribing the `cd_target`/`cd_at` helpers the LN rule explicitly rejects. Round 2 found six of these, round 3 found one, round 4 found two.

## Findings rejected in round 4, with the measurement

- **The architect's `--cache -XGET` bypass.** `gh api --cache -XGET /rate_limit` fails with `invalid argument "-XGET" for "--cache" flag: time: invalid duration "-XGET"` and nothing executes. The architect never ran `gh` and marked the item `REQUIRES EXECUTION` itself; the staff seat ran it. `--cache` goes on the skip list for completeness, not as a vector.
- **The architect's demand to name `git diff --name-only HEAD` for the `-am` row.** The row already says "every tracked modification", which specifies the path set. No other row names its command either.
- **Nothing settled was reopened.** No sixth item-1 predicate, no reversal of LN's cycle direction, no reopening of `flag_value`, no attack on the staging drop. The architect checked the `~/Claude` symlink rule against `CLAUDE.md` and confirmed it traceable.

## Phase 0, partial, 2026-09-15

Run alongside round 4, read-only half only. Evidence: `docs/design/2026-09-15-intent-guards-phase0/evidence.md`.

- **Extractor criterion PASSES**, and it proves both `prose.sh` fixes are load-bearing. 1,237 turns over 250 transcripts. The current extractor false-authorizes **272 turns, 22.0%**, every one a teammate relay, because the relay filter sits only on the `last-prompt` branch and the `user` branch is now primary. The corrected extractor: 0 relay, 0 wrapper, 138 slash-command turns recovered rather than discarded, 0.57% miss against a 20% threshold.
- **`promptId` is provisionally constant.** 969 of 998 prompt segments. 21 of the 24 varying typed segments are a single monotone shift, which is a prompt start carrying no `promptSource` rather than instability; 3 are genuinely multi-valued and need the live payload.
- **Latency criterion FAILS.** The transcript scan alone costs 230 ms at `prose.sh:95`'s `TAIL_CAP=4000000`; with `intent-guard.sh`'s floor and `ids.json` the chunk adds 274 ms against a 250 ms budget, before the `Read` matcher. Two levers are specified in Phase 0 and the choice waits on one more measurement (whether a 200K tail contains the turn's `user` record), which the flush-instant dump now also records.
- **Three criteria outstanding**, all needing a live `settings.json` registration: the flush instant, the `Read` matcher and its deny against `Read(**)`, and the `PostToolUseFailure` payload. Deferred while round 4 ran because the `Read` criterion registers a **deny** that would have fired inside the panel's own seats.

## Standing after four rounds

Round 4 was the narrow round Scott ordered and it paid for itself: two live bypasses that three rounds of review and a fold had left in the doc. The post-round-4 fold is now the unreviewed text, and the cap is reached again.

Pattern, now four for four: **every round has found at least one rule whose stated mechanism could not perform its stated job.** Round 1 `realpath -m`, round 2 a ledger nothing could write, round 3 a lock that did not span the operation, round 4 a skip list that did not cover the flag it had just fixed. The question that catches them stays the same: what process, at what moment, executes this, and what can it see?

Second pattern worth carrying to chunk E: **the fold is where defects enter.** M6, C1 and arguably M3 are all cases where a fix landed at one site and not at its siblings. Round 2 found six, round 3 one, round 4 two. A fold is not done when the rule text is right; it is done when every place the doc states the same fact has been walked.

## Round 5, 2026-09-16

Ordered by Scott past the cap (`PANEL_ROUNDS_ORDERED_BY_SCOTT=5`), scoped to Addendum A and the five sites it amended. Phases 0 through 7 were explicitly out of scope. Both seats returned "not ready to build": 6 must-fix, 8 cheap wins, 3 defers, 8 of 8 questions answered. Run dir `/tmp/review-panel/GOX7yywR/`, drift during the round 0 lines.

Every must-fix was re-verified against the code before folding, and three of them invalidate the first draft's central claim.

- **M1. The recipient loop is skipped wholesale on a posting ask.** `slack-post-guard.sh:685` is `if ! posting_intent "$prompt"; then` with the `for r in "${nonexempt[@]}"` loop inside it. So the first draft's "a DM gets the strong name condition exactly as a channel does" was true only because neither does. Resolution alone buys back nothing; the control flow has to change too.
- **M2. The stated reason for keeping the weak condition was wrong.** `typed_prompt` (`:357`) joins the whole window into one string and both conditions read it, so the naming turn is already in the strong condition's input. The weak condition's only function is admitting a post no turn's recipient names, which is the hole the addendum exists to close.
- **M3. Nothing fills `dms` before authorization, and a lazy client fill cannot.** `channel_display_name` is called only from `read.rs:150` and `:202`; a raw `D…` short-circuits `resolve_channel_id` at `read.rs:377-383`; the guard is `PreToolUse` on `mcp__slack__chat_post_message` (`settings.json:885`). Cold DM plus name-only prompt would deny the post whose execution would have warmed the cache. Closed by Scott's ruling the same day: eager sync plus lazy backstop.
- **M4. The `dms` merge arm was omitted** from `MergePolicy` (`cache.rs:310-323`) and the merge body (`:379-420`). Neither seat found this; it came out of the fold. Every write would have been dropped silently while looking successful. It is now a Phase 8 success criterion written to fail against a build without it.
- **M5. "Survives a round trip through a binary that predates the field" is unsatisfiable.** `IdCache` retains no unknown fields and the repo asserts the erasure in `resave_of_pre_change_cache_drops_the_groups_key` (`cache/tests.rs:103-124`). Replaced with a stated downgrade behavior: an old binary empties `dms` and the next run refills it.
- **M6. The 18 legacy `D…` keys have a writer, and the first draft checked the wrong file.** `git show a259d79:HOME/repos/.claude/slack-ids.yml` holds 18 `D…` keys byte-identical to the cache's 18 today, zero diff, from the retired `slack.py` whose header reads "id -> name (channels), username (users)". `migrate_legacy` (`cache.rs:544-561`) `fs::rename`s the legacy file into the XDG cache, so the path the first draft probed had been recreated after the move. Non-blocking stands on better reasoning.

## Findings rejected in round 5, with the reason

- **Architect: "fatal deadlock, permanently denies ALL DM posts."** Rejected as stated. With the weak condition in place a cold DM plus a posting ask allows, measured. The gap is confined to the name-only path, which is what M3 records.
- **Architect Q4: dropping the `.users` DM branch breaks `U…` resolution.** Wrong. A `U…` id or handle resolves through `$uits` over `.handles` (`slack-post-guard.sh:294`), a separate branch, and that is how `dm_mentioned` recipients already arrive. The real omission was the SECOND jq program at `:311-324`, which the staff seat caught.
- **Both seats: park the TARGET-variant call in Open Questions.** Refused. Phase 9 is a zero-code measurement with a stated decision rule and both outcomes specified, which is the Phase 0 pattern this doc uses throughout. `rules/taste.md` makes closing it the author's job.

## Standing after five rounds

Pattern now five for five: **every round has found at least one rule whose stated mechanism could not perform its stated job.** Round 1 `realpath -m`, round 2 a ledger nothing could write, round 3 a lock that did not span the operation, round 4 a skip list that did not cover the flag it had just fixed, round 5 a guard whose recipient loop the rule never reaches and a cache fill no process on the post path runs. The question keeps being the same one: what process, at what moment, executes this, and what can it see?

And the fold-is-where-defects-enter pattern held again from the other side: M4 was found during this fold, not by either seat. A fold is done when every place the doc states the same fact has been walked, and this time that included the merge sites the field addition implied.

One process note, handed on rather than fixed here: `review-panel.md` Step 3's documented rc-capture block was denied four times by the auto-mode classifier, the tilde-path head being what trips it since it matches a `sandbox.excludedCommands` pattern. The form that ran was absolute-path heads plus bare `wait`, which cannot assign `$?`, so both seat exit codes are inferred from output rather than captured. That belongs to whichever chunk owns agent definitions.

## Round 6, 2026-09-16: the implementation audit (Mode 2)

The first implementation audit this doc has had. Rounds 1 through 5 were all design reviews. Ordered by Scott, and it needed `PANEL_ROUNDS_ORDERED_BY_SCOTT=6` for a mechanical reason worth recording: `panel-round-guard.sh` derives mode from the doc's `Status:` line, so once the status changed from `Implemented` to `Partially implemented` a Mode 2 audit keys as a design-review round. A partially-implemented doc cannot get an audit without spending the design-review cap. That is a guard defect, not a policy, and it belongs to whichever chunk owns `panel-round-guard.sh`.

Scoped to Phases 0 through 7. Addendum A was explicitly out of scope. Verdict: **not clean.** 7 must-fix, 4 cheap wins, 4 defers, 8 of 8 questions answered. Wiring and registration were clean, all six registrations present and correctly matched, all five hook files resolving through the symlinks, and four of six acceptance criteria held.

**Five of the eight shipped rules carried a live deny-to-allow bypass, and four of them trace to one question the code never answered consistently: which copy of the command a predicate reads.** That is the same class as chunk B's single-quoted-verb hole, which this chunk fixed in its own Phase 1, reappearing in five new places.

Every must-fix was reproduced independently before folding. The fixes landed as `35e4d35` and `5156d60`.

- **M1. GH-WRITE allowed the attached long body form.** `--field=name=x`, `--raw-field=name=x`, `--input=p.json` all allowed while the separated form denied. `is_value_flag` / `is_body_flag` are exact-token tests, and `gh` accepts the attached spelling (verified live), so the call read as a bare GET. Fixed by splitting on the first `=` before testing.
- **M2. SECRET allowed a single-quoted credential path.** The artifact pre-filter gated on `$masked`, which has `mask_squote` applied, so the path was erased before the filter saw it and the whole branch was skipped. The branch below already read the heredoc/comment-masked copy; the `case` now reads the same one.
- **M3. Any slash-command turn authorized an arbitrary post.** `posting_intent` matched the literal word `message` inside the `<command-message>` wrapper tag. 58 of 400 sampled transcripts carry that tag and `/cli-shakedown` is one of the incident classes TARGET exists to catch, so this inverted the rule on its own founding case. Fixed by stripping markup before matching, keeping inner text so `<command-args>send this to russ</command-args>` still counts. The existing slash-command fixture used `<command-name>` only, which is why the matrix never saw it.
- **M4. SLACK judged only the first posting statement.** The statement loop `break`s, and everything downstream is built from one statement's variables, so `slack write scott.idler aaa; slack write engineering bbb` was authorized by the exempt first target. Evaluating every statement properly means restructuring the whole downstream path, so the shape is refused instead: two posting statements in one command deny and the text says to split them. This is also the 2026-06-09 duplicate class. The narrowing is deliberate and Phase 9's replay will surface any legitimate compound post.
- **M5. PUBLIC-REPO ignored extra refspecs and the bulk forms.** The push read `sed -n '2p'`, so `git push origin main dirty` walked only `main`, and `--all` / `--mirror` carry no refspec at all and were never walked. Both are named in the doc's own "cases to model" list. Now every source is walked.
- **M6. INGEST's door was command-wide.** One `BULK_INGEST_ORDERED_BY_SCOTT=1` statement short-circuited the entire deny block, so every later ingest in the same command was laundered. The spec already said the opposite: count <= n allows the STATEMENT. The door now removes only its own statement from scope.
- **M7. `intent-guard.sh` failed OPEN on an unreadable `lib.sh`.** It carries PUBLIC-REPO, which the implementation contract names as fail-closed. `slack-post-guard.sh:182` had it right; this hook shipped the tree's older fail-open line.

Cheap wins, all folded:

- **C1** `cd -- <dir>` defeated the LN cwd tracker, because any operand starting with `-` was dropped. `--` is the end-of-options marker, not an option.
- **C2** No blob-size check on the commit path, while the shared deny text advertises one and the rule head names `git commit`. On commit the bytes are still in the working tree, so size is measured there.
- **C3** The heredoc extractor entered body state only for a `.sh` target, so it kept scanning THROUGH a `.md` body and re-armed on any line inside ending in `.sh` before a `<<`. Measured on the real artifact: writing this design doc through a quoted heredoc made the old extractor emit 1145 lines and deny. Two states now, and the comment that claimed the opposite is corrected.
- **C4** INGEST counted ops on the unquoted copy while the clauses read the masked one, so quoted prose denied. This fired on three of the audit's own commands, including its first attempt to write its probe file, and on two of this session's.

C3 and C4 compound into the exact false-positive class `lib.sh` exists to kill, reappearing in the one rule that deliberately opted out of statement scoping. That is the lesson to carry: an opt-out of the shared parser is an opt-in to re-deriving its bug list.

Recorded, not fixed, with the reason:

- **D1** `gh api repos/o/r/ -X PATCH` allows on a trailing slash, because the glob matches an empty third segment. GitHub 404s that route, verified, so the call cannot write. Predicate brittleness, not a bypass. The architect called it a silent bypass and that is overstated.
- **D3** `slack scheduled deliver` is unguarded; the subcommand matcher is `write|repost`. It drains a queue of follow-ups whose parent `slack write --at` was already checked, so no unchecked body enters.
- **D4** `cur_cwd` is the post-command cwd, so a trailing `cd` moves the repo PUBLIC-REPO audits. The audit could not construct a case that behaved differently from M5.
- **New, found while fixing C3 and out of this chunk's scope:** `lib.sh`'s `mask_heredoc` does not mask heredoc bodies on these inputs at all, which is why body text reaches `verbscan` in the first place. This chunk stopped editing `lib.sh` after round 2 measured an obvious fix there flipping two shipped guards from allow to deny, so it is handed on rather than touched.

Two mutations the audit ran proved the suites were blind to M2 and M4: reverting each fix left its suite at the pre-existing pass count. 16 fixtures were added across the three suites, each one verified to FAIL against the shipped code and pass against the fix. intent 167 -> 183, secret 189 -> 192, slack 123 -> 129.

On the seats: the architect returned rc=0; the staff seat was killed by the 10-minute timeout while composing its report, rc=124, no report produced. Its 737 KB trace was mined for leads and every lead was re-tested independently, with two claims dropped for not reproducing. The panel agent's own report was therefore its synthesis plus its own verification, which is why every finding above carries a probe rather than a citation.

## Standing after six rounds

The pattern is six for six: **every round has found at least one rule whose stated mechanism could not perform its stated job.** Round 1 `realpath -m`. Round 2 a ledger nothing could write. Round 3 a lock that did not span the operation. Round 4 a skip list that did not cover the flag it had just fixed. Round 5 a guard whose recipient loop the rule never reaches and a cache fill no process on the post path runs. Round 6, five predicates reading the wrong copy of the command.

The design-review question that catches this class is "what process, at what moment, runs this, and what can it see?" Round 6 adds the implementation-time sibling, and it is the sharper one for a guard: **which COPY of the command does this predicate read, and does every clause in the rule read the same one?** Five of the seven must-fixes are that question unanswered. It belongs in the implementation contract, not in a review.
