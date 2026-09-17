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
