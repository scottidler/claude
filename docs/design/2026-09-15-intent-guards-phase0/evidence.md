# Phase 0 evidence: intent guards

Design doc: `docs/design/2026-09-15-intent-guards.md`. Zero code, measurement only.

**Status: partial.** Five of eight criteria are answered. Three are deferred and named below with the reason. One of the five FAILS.

| # | criterion | verdict |
|---|---|---|
| 1 | `transcript_path` reaches `PreToolUse` | answered before this phase, not re-spiked |
| 2 | the guard reads `user` records, not `last-prompt` | answered by panel round 1's measurement |
| 3 | is the record flushed at the instant a hook fires | **deferred**, needs a live scratch hook |
| 4 | does a `Read` matcher fire, and does its deny beat `Read(**)` | **deferred**, needs a live deny registration |
| 5 | what a `PostToolUseFailure` payload carries | **deferred**, needs a live failed MCP call |
| 6 | is `promptId` constant across one turn | measured, provisional yes |
| 7 | total added latency under 250 ms per Bash call | **measured, FAILS** |
| 8 | extractor false authorizations, zero of either class | measured, PASSES with both fixes applied |

## Why three are deferred

Criteria 3, 4 and 5 all require registering a scratch hook in the live `settings.json`, and `~/.claude/hooks/` holds per-file symlinks into the working tree, so a registration is live the instant it is written. Panel round 4 was running against this doc while this phase ran. Criterion 4 is the blocking one: it registers a **deny** on the `Read` matcher, which would fire inside the panel's own seats and corrupt the round. Criteria 3 and 5 are lower risk (a dump hook exits 0 with no stdout) but share the same live-harness surface, so all three wait for the round to land rather than splitting the registration across it.

Nothing about these three is blocked on a decision. They run as soon as the harness is free.

## Criterion 8: extractor false authorizations

The criterion: at least 40 turns from `~/.claude/projects`, zero false authorizations of the teammate-relay class and the `<command-*>` wrapper class. A miss that returns no prompt is measured separately, threshold 20%.

The doc names two defects in `prose.sh:131-153` that get FIXED rather than measured, so both extractors were run over the same turns: the current one, and the corrected one this chunk ships.

- Sample: 250 transcripts modified since 2026-08-25 -> **1,237 turns**, where a turn is a user string record followed by the first `tool_use` after it. Well past the 40-turn floor.
- Simulation: for each turn, both extractors run over the transcript prefix ending before that `tool_use`, which is what a `PreToolUse` hook sees.

| extractor | prose | command | relay | miss |
|---|---|---|---|---|
| current (`prose.sh` user fallback) | 960 | 0 | **272** | 5 |
| corrected (this chunk) | 1,092 | 138 | **0** | 7 |

**Current extractor: 272 of 1,237 turns = 22.0% false authorizations**, every one of them the teammate-relay class. A guard keyed on it would read another Claude session's relay as Scott's typed instruction on better than one turn in five. Criterion pass is zero. The current extractor fails it outright.

**Corrected extractor: 0 relay, 0 wrapper.** Criterion PASSES. The 138 `command` results are slash-command turns that the current `startswith("<")` clause discards entirely; the fix parses them instead of dropping them.

Miss rate 7 / 1,237 = **0.57%**, against a 20% threshold. Pass.

Both fixes are load-bearing, and the relay one is the larger of the two. Independent counts over the same 400-transcript window: 524 user records with string content carrying the relay prefix, and 59 carrying a `<command-*>` wrapper.

```
$ # user records whose string content is a teammate relay, 400 transcripts
524
$ # angle-bracket-prefixed user records, same window, by class
    220 other-wrapper
     59 command-wrapper
      4 local-command
      2 system-reminder
```

## Criterion 6: is `promptId` constant across one turn

`promptId` and `promptSource` live on `user` records. Assistant records carry `requestId`, not a prompt id, so the transcript answers this for user records only and the hook payload's `prompt_id` still needs criterion 3's live dump to confirm.

First cut segmented turns on `promptSource=="typed"` and got 117 of 677 varying, 17.3%. That number is wrong: it lumps `sdk`, `queued`, `system` and `suggestion_accepted` prompts into the preceding typed turn, and each of those legitimately opens a new prompt id. Re-segmented on ANY non-null `promptSource`:

```
    652 typed:constant
    163 sdk:constant
     86 system:constant
     37 suggestion_accepted:constant
     31 queued:constant
     24 typed:varies
      2 system:varies
      1 typed:some-null
      1 suggestion_accepted:varies
      1 queued:varies
```

998 segments, **969 constant (97.1%)**. Typed segments alone: 652 of 676 constant (96.4%).

Chased the 24 varying typed segments rather than reporting them as noise:

```
     21 {"distinct_other":1,"monotonic":"single-shift"}
      2 {"distinct_other":4,"monotonic":"multi"}
      1 {"distinct_other":2,"monotonic":"multi"}
```

21 of 24 are a single monotone shift: the segment runs on one prompt id, switches exactly once to exactly one other, and never switches back. That is a prompt start whose record carries no `promptSource`, which is a gap in the segmenter here, not instability in `promptId`. Three segments are genuinely multi-valued and the transcript cannot adjudicate them.

**Provisional yes**: `promptId` is stable within a prompt. It is not confirmed as an exact staleness key until criterion 3 dumps the live payload, because the 3 residual segments and the unmarked starts both need the hook's own view to settle.

## Criterion 7: total added latency under 250 ms per Bash call

FAILS.

### The existing chain, before this chunk adds anything

Ten hooks are registered on the Bash matcher plus `clyde permit log` on the universal matcher. Each measured warm, mean of 5 runs, against three payload classes.

| hook | A: small cmd | B: git cmd | C: 8.7M transcript |
|---|---|---|---|
| `secret-echo-guard.sh` | 89 | 90 | 90 |
| `allow-help.sh` | 8 | 8 | 8 |
| `rewrite-cd-read.py` | 44 | 45 | 43 |
| `git-release-guard.sh` | 102 | 136 | 102 |
| `block-draft-pr.sh` | 25 | 23 | 27 |
| `branch-pr-title-guard.sh` | 58 | 62 | 57 |
| `codex-stdin-guard.sh` | 18 | 20 | 19 |
| `manifest-scope-guard.sh` | 49 | 49 | 50 |
| `emdash.sh` | 32 | 33 | 33 |
| `branch-name-guard.sh` | 62 | 59 | 60 |
| `clyde permit log` | 23 | 24 | 24 |
| **total** | **510 ms** | **549 ms** | **513 ms** |

The 250 ms budget is for what this chunk ADDS, so the baseline is not itself a failure. It is the number that says what the budget is being added to: a Bash call already pays half a second of guard before this chunk registers its first rule.

### What the new registrations cost

Measured the dominant components directly, since `intent-guard.sh` and `slack-post-guard.sh` do not exist yet.

| component | cost |
|---|---|
| bash + source `lib.sh` + read stdin (the floor any new hook pays) | 19 ms |
| floor + `stmts` parse of the command | 32 ms |
| read `~/.cache/slack/ids.json` (204K) | 12 ms |
| transcript scan, 36K transcript | 13 ms |
| transcript scan, 8.7M transcript at a 200K tail | 18 ms |
| **transcript scan, 8.7M transcript at `prose.sh`'s `TAIL_CAP=4000000`** | **230 ms** |
| transcript scan, 8.7M transcript, no cap | 932 ms |

`prose.sh:95` sets `TAIL_CAP=4000000`. At that cap the SLACK TARGET rule's transcript scan costs **230 ms on its own, 92% of the whole chunk's budget**, before `intent-guard.sh` runs at all. Add the floor and the parse:

```
230 (transcript scan at 4MB cap)
+ 32 (intent-guard.sh floor + stmts)
+ 12 (slack-post-guard.sh reads ids.json)
= 274 ms, and the Read matcher is not in that number
```

Over the 250 ms budget on the large-transcript class.

### How often the large-transcript class fires

```
  total=5052  >4MB=83 (1.6%)  >1MB=961 (19.0%)  mean=648KB
  largest: 15.8 MB, 9.5 MB, 9.3 MB, 8.6 MB, 8.0 MB
```

1.6% of transcripts today, and it is not a random 1.6%: a session grows into this class by running long, which is exactly the session that is doing outward work worth guarding. The 15.8 MB case is four times the cap and pays the full 230 ms.

### What this forces

The doc's own text: "Over budget, the design reopens on rule-count-per-hook." That is one lever. The measurement points at a second and cheaper one, and the two are independent:

- **`TAIL_CAP`.** 4 MB -> 200K takes the scan from 230 ms to 18 ms, a 212 ms saving from one constant. Whether a 200K tail reliably contains the current turn's `user` record is unmeasured, and it is the question that decides whether this lever is available. Criterion 3's live dump is the place to settle it.
- **Rule-count-per-hook**, as the doc says.

Both are decisions, not unknowns, once the 200K-tail question is measured. Neither is made here.

## Commands

Every number above came from these, run 2026-09-15 on `desk.lan` against `~/.claude/projects` at 5,052 transcripts.

- Extractor comparison: a jq program that, per transcript, finds each user string record, locates the first `tool_use` after it, and evaluates both the current and corrected selectors over the prefix. Emits one classification pair per turn, never transcript content.
- `promptId` segmentation: same shape, segmenting on non-null `promptSource` and comparing every `promptId` in the segment to the segment head's.
- Latency: `date +%s%N` around 5 invocations of each hook against a synthesized `PreToolUse` payload, warm.

One measurement error worth recording, because it produced a plausible wrong answer rather than a failure: the first latency run reported 3 ms for the whole chain. The loop was `for h in $CHAIN` with `CHAIN` a space-separated string. This shell is **zsh, which does not word-split an unquoted parameter expansion**, so every iteration spawned one bogus filename and exited instantly. A bash-shaped loop in a zsh session fails silently and fast, which reads exactly like a fast hook. Literal lists in the `for`, or `${=CHAIN}`, are the fix.
