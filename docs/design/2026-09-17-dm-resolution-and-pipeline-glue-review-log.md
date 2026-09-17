# Review log: 2026-09-17-dm-resolution-and-pipeline-glue.md

## Round 1, 2026-09-17, Mode 1 design review

Run dir `/tmp/review-panel/zxJsuIzb/`. Architect rc=0, staff-engineer rc=0, both on re-dispatch (attempt 1: architect hit the Bash sandbox network filter reaching Gemini's API host, staff hit its own 10m cap while still working; both traces preserved under `attempt1/`). Doc held still: live sha256 identical to the round snapshot, diff 0 lines.

**Verdict: not ready to build. 7 must-fix, 5 should-fix, 2 nits. All folded.**

Both overturnings survived. The seats did not disagree on anything substantive.

### The two findings that would have shipped a broken feature

**MF-2. A faithful `dSt` port matches zero slash-prefixed tokens.** The doc named `if(e.startsWith("/")) return []` as "the rule that is easy to miss" and missed the one that kills the feature: `if(ye==="/"||ye==="\\"||ye==="-")continue`, where `ye` is the character BEFORE the match. `dSt` was built to match a bare `ultraplan` and EXCLUDE `/ultraplan`. E7 needs the exact opposite.

Re-verified here by porting the function and running it:

```
'please /bump next'                 kw='bump'     -> []
'merge, pull main, /bump, install'  kw='bump'     -> []
'please bump next'                  kw='bump'     -> [('bump', 7, 11)]
```

Phase 5 now takes the span and trailing-neighbor logic and INVERTS the leading-neighbor rule, and names the trap in the phase body so a phase agent cannot port it faithfully by accident.

**MF-3. The `source:"user"` discriminator does not exist.** The doc made it the reason mechanism A is safe. This repo's own chunk C evidence refutes it: `2026-09-14-panel-round-cap-phase0/evidence.md:142` lists the measured `UserPromptSubmit` keys at 2.1.272 as `cwd, hook_event_name, permission_mode, prompt, prompt_id, session_id, transcript_path`, no `source`. The same file records the hook firing on a prompt handed to `claude -p`, so "only human-typed prompts" was false twice over. A hook filtering on `.source == "user"` would have been inert.

Notable: the refuting evidence was in this repo, written by this program, three chunks ago. The claim was inherited from the research brief and not checked against it.

### The rest

| # | finding | fold |
|---|---|---|
| MF-1 | `resolve_dm_user` has no caller Bash can reach. `CacheAction` is `List\|Add\|Refresh` (`cli.rs:563-580`) and `Add` warms a CHANNEL | Phase 2 adds `slack cache resolve <id>`; Phase 4's backstop shells out to it |
| MF-4 | `variantA.sh` is not the shipped guard: it greps the raw prompt, the guard strips harness tags first (`:396-405`, 58 of 400 transcripts carry the wrapper) | Phase 3 re-derives the baseline arm from the guard on disk; README trap 3 |
| MF-5 | the replay driver rmtree'd the LIVE sent-ledger once per row, 216 times, and scored a crashed guard as ALLOW | driver patched on both counts, refuses to run against the live path |
| MF-6 | AC6 not falsifiable: every path in `hooks-preflight.sh` exits 0, including the unresolved-hooks branch (`:40-48`) | AC6 rewritten to a registration count plus absence of the warning |
| MF-7 | the Stop-hook backstop cannot cover the dispatch boundary: `Stop hook block discarded (turn ended by tool result)` | claim withdrawn; heartbeat rests on the teammate-report wake, residual mid-phase silence named as a limit |
| SF-1 | Phase 2's edit list incomplete: `channel_display_name` takes no `cache_path`, `sync_dms` must paginate, two output projections need `dms` | all three added |
| SF-2 | Phase 4 silently breaks the 18 legacy `D…` keys, and has an ordering hazard against any pre-Phase-2 writer | both stated in Phase 4 |
| SF-3 | `pr-open`'s handoff is a phrase, not a protocol; running `gh` in the helper still bypasses PreToolUse | Phase 9 specifies the `PR creation required` result and the caller-runs-the-literal protocol |
| SF-4 | `release-driver.md:4` grants Bash/Read/Grep/Glob, so it cannot call `Skill(cli-shakedown)`; its inputs also lack URL, version and acceptance commands | shakedown stays with the caller; inputs grow |
| SF-5 | the discussion-class closure is argued, not measured: the feature works when the model does NOT ignore the injection | the injected wording makes invocation conditional; two discussion prompts added to Phase 7's criteria |
| N-1 | Phase 5's implementation language unspecified | Python, named |
| N-2 | Phase 2's cited line ranges spot-checked, no drift | no change |

### Corrected rather than accepted

**The 82%-silent figure does not reproduce and is no longer load-bearing.** It came from joining each dispatch to the next teammate message regardless of sender, which pairs a dispatch with a different phase's idle notice (counterexample at `drata-cli/7114f1fa….jsonl:180,184,192`). An exact worker-name join gives 390 pairs and a 14.53-minute median. The doc now states the silence qualitatively. The decision it supported is untouched: that rests on `652/0`, which round 1 reproduced exactly under both top-level-only and including-subagents scopes.

The `1,906` dispatch denominator also drifts (1,877 top-level / 2,042 with subagents on re-count; the corpus grew 25 dispatches during the session). Not load-bearing either.

### Rejected

**Architect: "The acceptance criteria are excellent. Every single criterion is falsifiable."** Rejected as an unverified absolute. AC6 evaluated true with the feature absent and AC3's premise was false; the seat ran neither check. Its two "Verification Record" blocks are reconstructions rather than transcripts (the byte offset does not land on the string it quotes, and the tool-result literal appears in no transcript). Its conclusions on items 7 and 8 were right and are cited from the synthesis lead's measurements instead.

Neither seat raised the combined-doc override, which was out of scope by instruction. Neither raised unrequested scope, and both looked.

### Open questions after round 1

None. Every finding is folded; nothing is deferred.

## Round 2, 2026-09-17, Mode 1 design review of the round-1 fold

Same run dir. Architect rc=0 on its THIRD attempt (attempt 1 died on the Bash sandbox network filter reaching Gemini's API host, attempt 2 hit the seat script's 10m wall clock mid-verification, attempt 3 succeeded with the host allowlisted); staff-engineer rc=0. Drift vs round 1: 154 lines, which is the fold under review.

**Verdict: not ready to build. 6 must-fix, 8 should-fix, 2 nits. Three of round 1's must-fix folds did not fix their finding and a fourth was half-applied.**

### The lesson from this round

Round 1's folds were made by editing prose without executing what the prose described. Three of them were wrong in ways one command would have exposed. The rule this doc now follows: **a fold that describes behavior gets run before it is committed.** Every round-2 fold below was measured here first.

### Round-1 fold accounting

| R1 finding | fold verdict | why |
|---|---|---|
| MF-1 unreachable resolver | fixed | `slack cache resolve` added |
| MF-2 `dSt` inversion | **NOT fixed** | see M2 |
| MF-3 `source` discriminator | fixed | claim removed, gate added |
| MF-4 stale `variantA.sh` | fixed, and generalized further while folding round 2 | the whole baseline is stale, not just variant A |
| MF-5 replay driver | **NOT fixed, made worse** | see M1 |
| MF-6 AC6 falsifiability | **NOT fixed** | see M3 |
| MF-7 Stop-hook backstop | half-applied | see M4 |

### Round 2 must-fix

**M1. The MF-5 fold broke the driver four ways and never isolated it.** (a) `{}` IS the guard's allow (`:139`), and the patched parser raised on it, so the driver died on the first of 190 allows. (b) The guard hard-codes `LEDGER` at `:113` and reads no `REPLAY_LEDGER`, so the guard kept writing 216 reservations into the LIVE ledger while the per-row reset stopped touching it. (c) `REPLAY_LEDGER=` empty resolves to `Path('')` = `.`, an `rmtree` of the working directory. (d) The equality check was lexical, bypassable by `..` or a symlinked parent.

Rewritten to isolate through `HOME`, which is the seam the guard already has. **Tested this time:** live ledger 10 entries before and after a full run; the driver completes at 236 posts / 202 allow / 34 deny instead of dying on row 1.

**M2. The inverted matcher spec scored 195 false positives of 1,421 against a criterion of 0.** Requiring `/` before the token while checking nothing before the slash accepts `~/repos/scottidler/bump`, `category/risk/status`, `bump/shipit/babysit`. Independently ported and measured here, reproducing the panel lead exactly (the architect seat's 573/205 did not reproduce and is not cited):

```
faithful    survivors   0/583   false-positives    0/1421
doc spec    survivors 561/583   false-positives  195/1421
+ boundary  survivors 560/583   false-positives    7/1421
+ deny list survivors 554/571   false-positives      2
```

All 7 residuals are window-clipping artifacts (6 odd backtick parity, 1 unbalanced quote; 375 of 832 `code-span` records have odd parity in-window). Phase 6's generic-word deny list removes 5. Criterion 7 restated to enumerate the 2 rather than move the denominator.

**M3. AC6 still passed with the feature absent.** `rg -c 'UserPromptSubmit'` returns 1 against `{"hooks":{"UserPromptSubmit":[]}}`. Now asserts the executable path is registered under the event and resolves.

**M4. The MF-7 fold contradicted itself**, `:206` ("converts a silent 22-minute gap into a heartbeat") against `:213` ("the 22-minute case has NO mechanism today"), and the risk table still cited the Stop-hook fallback the fold had retracted. `:206` deleted, risk row rewritten, and the deleted prose-saturation evidence restored so the doc still carries the reason prose alone is untrusted here.

**M5. Phase 9 specified the bypass its own protocol rejected.** `:350` said `release` calls `pr-open`; a subprocess call leaves `gh` invisible to PreToolUse exactly as `--fill` does. Rewritten to the stop-and-hand-back protocol, with the three transitions named, `release-driver.md:74-80` given the new result as a consumer, and the human-at-a-terminal path stated.

**M6. The rollout condition was not achievable by installing a binary, and old writers ERASE `dms`.** `IdCache` is not `deny_unknown_fields` (`cache.rs:62-67`), `save()` serializes wholesale (`:591`), and `cache/tests.rs:103` already asserts the erasure. `slack mcp serve` is long-running (`main.rs:84`) and reaches `save` through `users_search`, so replacing the binary does not replace resident code. Condition now names restarting persistent MCP writers and verifying a post-install MCP operation preserves `dms`.

### Should-fix, all folded

S1 absolute path for the backstop (`/usr/bin/slack` is the Slack desktop app). S2 the ordering-hazard failure mode is PATH-dependent, not uniformly fail-closed. S3 stale `slackrecall.py` citations. S4 0d asserts the reaping effect, not the send. S5 Phase 0 has four spikes, ordered. S6 the acceptance-evidence summary miscounted what was run. S7 "running it against the live hooks" now means feeding the hook its payload on stdin. S8 `channel_display_name`'s fill had become optional and is now required.

### Found while folding, by neither round

**`rowsFinal.json` does not reproduce against today's guard:** `216/26/9 TARGET/0 multi-stmt` pinned versus `236/34/8/9` today. The corpus grew AND the guard gained a multi-statement rule after the baseline was made. Phase 0a now re-pins rather than diffing against it. This generalizes round 1's MF-4 from one variant file to the whole baseline.

### Open Questions after round 2

None.

## Round 3, 2026-09-17, Mode 1 design review of the round-2 fold. THE CAP.

**One seat.** Architect rc=0 on attempt 2. **Staff-engineer FAILED both attempts** (rc=124, its own 10m wall clock, no review produced); traces preserved. Not retried a third time per the 2-strike rule, and Step 3.5's substitution does not apply to a timeout. The architect is read-only and could execute nothing: it wrote a Python port of the matcher and asked the synthesis lead to run it. Treat this round as one seat plus the lead's measurements.

**Verdict: 4 must-fix, all foldable without a fourth round. All folded.**

### The round-2 rule held, mostly

Four of six round-2 folds were verified by execution and hold: M1 (replay driver), M3 (AC6), M4 (Stop-hook), M6 (rollout). M2's numbers reproduce exactly. It failed for the stale-baseline fold, which landed in 4 places and left 7 stale.

### Round 3 must-fix

**M-1. The stale-baseline fold contradicted itself two lines apart and missed 7 sites.** `:268` said 0a reproduces 26/9/17; `:270` said it will NOT be 26/9/17. Stale also at `:306`, `:311`, `:471`, `:503`, `:547` and in `slackrecall.py:75`'s own header. **And AC3 was unsatisfiable by the SHIPPED guard:** measured `posts=236 allow=202 deny=34`, splitting 17 artifacts / 8 TARGET / 9 multi-statement, so "non-artifact denies <= 9" fails at 17 before any variant is tried. The escape hatch did not fire because it keyed on TARGET while the rule keyed on all non-artifact denies. AC3 and the decision rule now scope to TARGET only, with the multi-statement rule named as orthogonal.

**M-2. `variantA.sh` and `variantB.sh` denied 100% of inputs from the directory they are committed to.** Both `. "$HOOKS/lib.sh"` at `:142` with `HOOKS` = their own directory, and the harvest dropped the `lib.sh` symlink the original directory had. Measured: 237 posts, 0 allow, 237 deny, every one "lib.sh is unreadable". Phase 3 names `variantB` as its starting point. Symlink restored and verified: `posts=240 allow=204 deny=36`, now producing the per-recipient deny class.

**M-3. Phase 0a named no artifact and the driver has no replay-from-file mode**, so it always re-walks the live tree and 0a inherits the drift one level up, across a whole cross-repo ship. Drift measured on one afternoon: 236, 237, 239, 240 posts. 0a's deliverable is now an artifact, not a number: a `--from-rows` mode, a committed snapshot, and a count taken against it.

**M-4. `bin/release`'s gh calls run as the WRONG GitHub account.** `release` is a bash script, so the `.zshenv` `gh()` persona function does not exist in it and the rails `tool.call` hook does not rewrite a subprocess. Measured from inside a bash script in `~/repos/scottidler/claude`: `GH_PERSONA` unset, `gh api user --jq .login` returns `escote-tatari`. So the caller would create the PR as home and `release` verify it as work. This repo is public so it passes here; four personal repos are private and it would not. Every `gh` call in `release` now sets `GH_PERSONA` explicitly. The architect called this safe because `gh pr view` is read-only and PreToolUse does not gate reads: true, and the wrong axis.

### Should-fix, folded

**S-1 is the one that mattered:** the doc's matcher numbers reproduce exactly, but ONLY if each record is scored at its own occurrence (`context[offset+1]`). Score per-window, which is the obvious reading of "run the matcher on fixtures.json", and a faithful port gives 6/583 and 77/1421 instead of 0 and 0, because 435 of 2,004 records hold more than one `/token` in their window (428 of them false positives). Nothing stated the protocol. Now stated in both the phase and the README.

### Verified and holding, do not re-fold

The guard's only `$HOME` uses are the three claimed (`:112`, `:113`, `:248`). The live ledger is byte-identical with the same mtime before and after a full 236-row run, and no remaining path writes or deletes it. The `~/` expansion at `:248` shifts nothing: ZERO of the 162 slack-write commands in the corpus use a tilde-prefixed `--body-file`. AC4, AC5's string half, AC6 and AC8 (`pass=129 fail=0`) reproduce verbatim, and AC6 correctly fails against a hollow `{"hooks":{"UserPromptSubmit":[]}}`. `slack-cli`'s gates re-checked live and unchanged. Every spot-checked file:line citation is correct.

### Open Questions after round 3

None.
