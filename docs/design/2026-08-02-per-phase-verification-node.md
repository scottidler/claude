# Design Document: Per-Phase Verification Node

**Author:** Claude (Opus 5), directed by Scott Idler
**Date:** 2026-08-02
**Status:** Draft
**Review Passes Completed:** 5/5 (draft, correctness, clarity, edge cases, excellence)
**Review Panel:** Round 1 complete 2026-08-08. Architect (Gemini) rc=0, Staff Engineer (Codex) rc=0. All 14 findings dispositioned: 13 folded in, 1 pushed back and closed by consensus. Open Questions empty.

## Summary

`phase-implementer` grades its own work. It verifies its own success criteria
(step 4b), writes its own deviations (step 5), and the parent gates the next
phase on that self-report. Insert a verification node on the edge between
phases: a deterministic criteria runner first, then a fresh-context Opus
verifier for what the runner cannot reach. Undisclosed deviations and failed
criteria stop the run before the next builder inherits the work.

## Problem Statement

### Background

`/how-to-execute-a-plan` in Delegated mode spawns one `phase-implementer` per
phase, sets its model from the doc's `**Model:**` tag, passes `PRIOR_SHA`, and
gates phase N+1 on the returned report. Measured over 1,999 transcripts
(2026-07-03 .. 2026-08-02): 277 `phase-implementer` spawns, 153 `review-panel`,
15 `/how-to-execute-a-plan` invocations, 40 `/create-design-doc`.

The builder node currently owns every judgment about its own output:

- `phase-implementer.md` step 4b: "verify each one explicitly and report
  pass/fail per criterion"
- step 5: writes its own Deviations bucket into the implementation notes
- Return value: `Criteria: pass/fail/unverified`, `Deviations: one line each`

The parent reads that report and starts the next phase.

### Problem

Self-review is the weakest check in the funnel, and it sits on 277 edges.

- `otto ci` is a real external gate, but it proves compile + tests pass. It does
  not prove the phase did what the doc said. The builder wrote those tests.
- The only unbiased spec-conformance check is the Mode 2 implementation audit
  (`review-panel`), and it runs after every phase is committed.
- `PRIOR_SHA` chains phase N+1 onto phase N's self-graded work. A miss in phase
  1 is load-bearing by phase 4.
- Measured precedent: `tatari-tv/clyde` #77
  (https://github.com/tatari-tv/clyde/pull/77) shipped five phases `otto ci`
  green before anyone noticed three of seven acceptance criteria could not pass
  as written. Cited in `how-to-execute-a-plan` as the reason its own gate
  exists.

The gap is structural, not a discipline problem. The node that built the thing
is the wrong node to judge it, and no instruction added to `phase-implementer`
changes that.

### Goals

- Every phase gets a spec-conformance check by something that did not build it,
  before the next phase starts
- Criteria that carry a literal command are checked by running the command, not
  by asking a model
- Undisclosed deviations stop the run; disclosed-and-reasoned deviations ride
- Verdicts land as artifacts on disk, greppable and diffable
- No change to what `otto ci` owns

### Non-Goals

- Replacing `otto ci`. It stays the per-phase compile/test gate.
- Replacing the Mode 2 implementation audit. Whole-doc, cross-model, still runs
  at the end.
- Cross-model verification per phase. Parked: cross-model independence stays at
  the doc boundary where it is affordable. Revisit if the in-harness verifier
  measures as a rubber stamp in Phase 4.
- Depending on `2026-07-03-gating-authority-and-funnel.md`. That doc's
  `verdict.yml` covers whole-doc modes. This ships independently.
- Backfilling success criteria into legacy docs. Only 42 of 448 design docs
  carry per-phase criteria (measured 2026-08-02). Legacy docs get the judgment
  tier and a flag, not a hard stop.

## Proposed Solution

### Overview

One node on the edge, splitting work between a model and code by what each is
actually good at.

The seam is **extraction vs execution**, not cheap-tier-then-expensive-tier.
Language work goes to the model, execution and comparison go to code, and the
script runs INSIDE the verifier rather than ahead of it.

```
phase-implementer (builder, model per doc tag)
        |
        v  commit SHA
   phase-verifier (fresh context, opus)
        |
        |-- extract (command, expected) pairs from prose criteria   [model]
        |       |
        |       v
        |-- criteria.sh: execute + compare, byte-identical          [code]
        |       |
        |       +--> phase<N>.criteria.out  (raw, script-written)
        |
        +-- judge the residue: unextractable criteria + deviations  [model]
        |
        v  findings (return value)
   parent reconciles vs the builder's disclosed Deviations
        |
        +--> phase<N>.yml  (verdict, parent-written)
        |
        +-- pass ------------------> phase N+1
        |
        +-- fail --> repair round (amend, cap 1) --> re-verify
                                                        |
                                              +-- pass -+--> phase N+1
                                              +-- fail ----> HARD STOP, report
```

Who writes what. Two artifacts per phase, and **each file has exactly one
writer**:

| artifact | writer | contents |
|---|---|---|
| `phase<N>.criteria.out` | `criteria.sh` | raw stdout: every command echoed, its `observed`, its comparison result |
| `phase<N>.yml` | the parent | the verdict, after reconciliation |

The verifier agent writes neither. It returns findings to the parent as its
return value.

The panel's version had the agent write the criteria block and the parent append
`must_fix`, which is two writers on one file and the exact defect finding 4
raised. Splitting the artifacts keeps one writer per file AND preserves what the
script is for: `phase<N>.criteria.out` is the script's unmediated record, so the
agent's narration of what the commands did is checkable against what they
actually did. A model summarizing its own tool output is not evidence; the raw
file is.

### Architecture

**Tier 1: deterministic execution.** Some per-phase success criteria are already
written as literal shell commands with a stated expected result. Those are
decidable without a model.

**How many, honestly.** Three independent scans of the same corpus
(`scottidler/claude`, `tatari-tv/clyde`, `tatari-tv/slack-cli`,
`tatari-tv/marquee`, `scottidler/loopr`) disagree, and the disagreement is the
finding:

| scan | raw files | unique by content | command-bearing | command AND expected |
|---|---|---|---|---|
| author, round 1 | 448 | not deduped | 39% | not measured |
| review panel | 448 | 391 | 37% | 23% |
| author, round 2 | 450 | 393 | 57% | 35% |

Two corrections came out of this. **The corpus was inflated ~15%:** 57 of the
files are git-worktree duplicates (`loopr/{main,v4,v5}`,
`clyde/{cost,permit,pricing,report}`), so the real denominator is ~391 unique
docs, ~254 blocks, ~39 docs carrying per-phase criteria. **And the percentage is
an artifact of the classifier, not a property of the corpus:** command-bearing
swings 37% to 57% purely on regex breadth.

So the doc states a range, not a point estimate, and publishes the classifier.
Round 2 regex:

```
command:  `[^`]*(rg|cargo|git|yq|clyde|otto|jq|test|\./|bash|wc|grep|curl|sdv|bump|ls|find|fd)\b[^`]*`
expected: \b(returns?|>=|<=|exits?|prints?|emits?|equals?|exactly|zero|non-zero)\b
```

**What survives the correction:** roughly a third of per-phase criteria carry
both a command and a stated expectation, which is enough to justify running them
deterministically and not enough to make determinism the primary mechanism. The
earlier framing ("the free 39%", "the deterministic tier widens on its own") was
built on the undeduped number and the wrong metric. Cut.

**Where the seam landed (round 1, closed by consensus).** Both seats argued the
original tier 1 saved zero agent spawns and that a shell script parsing prose
expectations was the wrong shape. Both accepted. Their remedy was to fold
everything into the agent's Bash; that was rejected, because an Opus agent
adjudicating whether `wc -l` returned 7 is a model doing what `test` does for
free and identically forever. The objection landed on the script's INPUT, not on
determinism.

Resolution: the agent extracts, the script executes and compares. Three
conditions make the seam hold, and none of them is optional.

**Condition A: extraction may SELECT and PAIR, never SYNTHESIZE.** The `command`
in the verdict must be a verbatim substring of a backticked span inside that
phase's criteria block. `criteria.sh` enforces it mechanically: any command it
cannot find verbatim in the doc is refused and the criterion goes
`unverifiable`. This is load-bearing. Without it a model authors shell that a
script then executes, and the author-controlled property that the denylist cut
depends on is gone.

**Condition B: `expected` is a closed schema, not a free string.** Otherwise the
script is interpreting prose again, relocated one hop. Comparators:
`exit-code`, `exact`, `contains`, `regex`, `numeric` with an operator. If the
agent cannot express an expectation in that schema, the criterion is
`tier: judgment` and the agent owns it end to end.

**The schema boundary IS the tier boundary.** That is the first crisp definition
this design has had, and it replaces the estimated share above with a measured
one: whatever the agent can express in the schema is deterministic, the rest is
judgment, and Phase 4 counts both.

**Condition C: extraction is pinned across repair rounds.** Re-extracting in
round 2 is a second non-deterministic draw, so a criterion that failed in round 1
could be re-extracted into a weaker pair and pass. Round 1's `ran` and `expected`
are recorded verbatim and reused in round 2. Same failure class as the
disclosure bypass, one layer down: the gate must not move under the builder.

**Tier 2: `phase-verifier` (agent).** A new agent, `model: opus`, spawned by the
parent with DOC_PATH, PHASE, and the commit SHA. It judges only what tier 1
could not: criteria with no command, plus a scan of the phase diff for spec
deviations.

What it is deliberately NOT given:

- the builder's report
- the implementation notes

Both are the builder's self-assessment. Handing them to the verifier anchors it
on the answer. The verifier judges blind against the doc.

**Reconciliation (parent). Disclosure changes severity, never the verdict.**

Round-1 panel finding, convergent across both seats, and it was the hole that
made this whole design optional. The original table said any deviation "recorded
with reasoning" rides. The builder writes that bucket *before* the verifier runs,
and `phase-implementer.md:36` already instructs it to deviate at "the correct
seam" and record it. A builder that pre-discloses broadly immunizes a real
product defect, and the gate becomes something the checked node can opt out of.

The verifier judges the deviation on its merits first. Disclosure is then applied
as a severity modifier, not as a pass:

| verifier judgment | disclosed? | outcome |
|---|---|---|
| deviation is acceptable (same effect, correct seam) | yes | rides, logged |
| deviation is acceptable | no | rides, logged as UNDISCLOSED |
| deviation is **unacceptable** | yes | `must_fix`, disclosed-but-unacceptable |
| deviation is **unacceptable** | no | `must_fix`, top severity |
| criterion fail | either | fail |

The "disclosed but unacceptable" row is the one that was missing. Nothing the
builder writes about its own work can move a finding from `must_fix` to `rides`.

Note this reads `rules/taste.md` ("undisclosed deviations are the primary
finding; disclosed-and-reasoned deviations may ride") as ranking severity, which
is its meaning in an audit performed by an outside reviewer. Treating it as a
pass/fail rule at a gate the builder writes input to inverts it.

`must_fix` is the output of this table: every row resolving to `hard stop` or
`fail`, stated as the concrete thing to change. A non-empty `must_fix` forces
`verdict: fail`. The list is what the repair round receives, and what the
hard-stop message prints verbatim.

**Context budget.** The verifier reads `git show <SHA>`, the phase's section of
the doc, and files the diff touches. Not the whole repo. The diff is the unit of
work, so it is the unit of review.

**Both execution modes.** Tier 1 is a script and tier 2 is a separate agent, so
both work in Delegated and Inline mode alike. In Inline mode the main context is
the builder, which makes an outside verifier worth more, not less.

**The premise, stated so it can be attacked.** This design assumes a blind
verifier seeing only the diff catches defects the builder's self-report missed.
That is unproven. It is not proven by the fact that self-review is biased in
general, and `clyde` #77 proves a criterion-quality problem, not a code-quality
one. Phase 0 measures the premise against real past misses and kills the doc if
it does not hold. Nothing after Phase 0 should be built until that table exists.

**Verifier death is a stop, not a skip.** If `phase-verifier` errors, times out,
or returns nothing, the parent reports it and hard-stops. It does not fall
through to phase N+1 on a missing verdict, and it does not substitute the
builder's self-report for the verdict. Absent evidence is not passing evidence.
`review-panel` learned this the expensive way (its Step 3.5 exists because a
reviewer died silently mid-run).

**The doc is mutable under the verifier, and that is the subtlest hole.**
Round-1 panel finding, raised by neither seat. `how-to-execute-a-plan/SKILL.md`
explicitly licenses amending a criterion mid-run when the criterion is a doc
defect. The verifier judges against the doc as it reads it, which is *after* the
phase ran. So an amended criterion presents to the verifier as satisfied, and
the amendment is invisible.

Both seats read `doc_blob` as dead state and said cut it. They were right that
it was passive and wrong that it should go: it is the only proposed guard
against this. Promoted to an enforced comparison. The parent records
`doc_blob_at_start` when the phase begins and `doc_blob_at_verify` when the
verifier runs. A difference in the doc's criteria section between those two
points is itself a finding, reported and reasoned, never silent. Legitimate
doc-defect amendments survive this; they just have to be declared.

**Repair rounds rewrite the SHA.** `git commit --amend` produces a new commit.
The parent re-reads it, updates `commit:` in the verdict file, and passes the
amended SHA as `PRIOR_SHA` to phase N+1. Passing the pre-amend SHA forward would
point the next builder at a commit that no longer exists.

**Recovery from a bad repair round.** The Architect read `--amend` as destroying
the original with no rollback. Overstated, but the doc never said otherwise, so
it says it now: the pre-amend commit survives in the reflog
(`git reflog show HEAD`), and the commit is local and unpushed at that point, so
recovery is `git reset --hard <pre-amend-sha>`. The hard-stop message prints
that SHA so the operator is not hunting for it.

**Phases with no success criteria.** Not a hard stop. The verifier reports
`criteria: none-specified`, judges the diff against the phase's bullets, and
still runs the deviation scan. `how-to-execute-a-plan`'s existing gate already
flags absent criteria and explicitly tolerates older docs; this design does not
tighten that.

### Data Model

`docs/design/<doc-basename>-verdicts/phase<N>.yml`, one per phase, overwritten on
a repair round.

A subdirectory, not a `-phase<N>-verdict.yml` suffix. Round-1 panel finding: the
sibling gating doc writes `<doc-basename>-verdict.yml`, and a `*-verdict.yml`
glob would match both contracts. The subdirectory keeps them disjoint with no
coordination required, so the sibling doc can stay Draft without blocking this
one.

```yaml
doc: docs/design/2026-08-02-example.md
doc_blob_at_start: 4f2a91c # git hash-object of the doc when the phase STARTED
doc_blob_at_verify: 4f2a91c# ...and when it was verified; a difference is a finding
phase: 2
commit: a1b2c3d            # rewritten after a repair round amends
verdict: pass              # pass | fail
round: 1                   # 2 after a repair round
criteria:
  - id: phase2-1           # positional: phase number + bullet order, 1-based
    tier: command          # command | judgment
    status: pass           # pass | fail | unverifiable
    ran: "clyde scope --list | wc -l"   # verbatim substring of the doc (cond. A)
    observed: "7"
    expected:              # closed schema, never a free string (cond. B)
      comparator: numeric  # exit-code | exact | contains | regex | numeric
      op: ">="             # numeric only
      value: 7
    pinned_from_round: 1   # cond. C: reused verbatim in a repair round
deviations:
  - finding: "settings loader moved to parser.rs, doc said loader.rs"
    judgment: acceptable   # acceptable | unacceptable, decided on merits ALONE
    disclosed: true        # severity modifier only; never moves the verdict
must_fix: []               # non-empty forces fail
date: 2026-08-02
```

`expected` comparators:

| comparator | fields | compares |
|---|---|---|
| `exit-code` | `value` | the command's exit status |
| `exact` | `value` | stdout, trimmed, string-equal |
| `contains` | `value` | stdout contains the substring |
| `regex` | `value` | stdout matches |
| `numeric` | `op`, `value` | stdout parsed as a number, against `>= <= > < ==` |

Anything the agent cannot express in that table is `tier: judgment`.

`unverifiable` forces `fail`. Same rule as the sibling gating doc: unverifiable
is not passing.

### API Design

`criteria.sh --repo <ROOT> --doc <DOC_PATH> --phase <N> --pairs <PAIRS_YAML>`

The caller is the **verifier agent**, not the parent. The agent extracts the
pairs and hands them in; the script never parses prose. Space-separated flags,
no comma-joined values, per `rules/cli.md`.

Emits the `criteria:` block on stdout and writes `phase<N>.criteria.out`. Exit
codes, consumed by the agent:

| code | meaning | agent does |
|---|---|---|
| 0 | every command criterion passed | judge the residue |
| 1 | at least one failed | judge the residue, carry the failure into findings |
| 2 | no extractable pairs in this phase | the whole phase is judgment |
| 3 | no `Success criteria` block found | report a doc defect, judge the bullets |
| 4 | a criterion could not run here | `unverifiable`, does NOT consume the repair round |
| 5 | a supplied command is not a verbatim substring of the doc | refuse, `unverifiable`, report a condition-A violation |

Exit 2 is not a failure. It means the phase is entirely judgment.

**Exit 3 exists because 2 and 3 must not collapse.** "Parsed the block, found no
commands" and "failed to find the block at all" produce identical output if both
return 2, and a parser regression would then read as a clean pass on every
phase. Distinguishing them is what keeps a broken parser loud instead of
fail-open. Same reason the script exits non-zero on a parse error rather than
emitting an empty `criteria:` list.

**Exit 5 enforces condition A in code, not in a prompt.** The script greps the
doc's criteria block for the literal command it was handed. No match, no
execution. This is the mechanical guard that keeps a model from authoring shell
that a script runs, and it is what the denylist cut depends on.

**Exit 4 exists because a blocked command is not a failed one.** Round-1 panel
finding: a sandbox denial, a missing binary, or an unreachable host is
indistinguishable from a real failure if both return 1, and the phase then burns
its single repair round trying to fix code that was never broken. The panel
reported this from its own run history (dispatches dying on sandbox denials that
read as substantive failures). Environment failures report `unverifiable`, land
in the verdict, and do not trigger a repair.

**Repo argument.** `criteria.sh` deploys by symlink into `~/.claude/`, and
criteria commands are repo-relative. It takes `--repo` explicitly rather than
inferring it from `$PWD`.

**Finalization glob.** `docs/design/<doc-basename>-verdicts/phase*.yml`, named
here so the Mode 2 audit hand-off is unambiguous.

**Regression sweep: CUT.** Round-1 panel, convergent, with a decisive named
failure mode: per-phase criteria are point-in-time assertions, so a phase-1
criterion asserting an empty list fails correctly once phase 3 populates it.
Re-running prior phases' criteria generates false stops on correctly-built work.
It was also unrequested scope added during the author's edge-case pass. Removed,
along with the `regressions:` field.

### Implementation Plan

#### Phase 0: Prove a blind verifier beats the builder's self-report
**Model:** opus
- Zero code. This is the kill gate for the whole design.

Round 1 rewrote this phase. The original was rigged and both seats said so
independently. Four defects, all fixed below:

| defect | why it made Phase 0 unfalsifiable | fix |
|---|---|---|
| No baseline | "materially better than the self-report" was never measured; the self-report scores 0% on a set built from what it missed, so ANY hit rate wins | run the self-report arm on the identical set |
| No false-positive term | a verifier that flags everything scores 100% on a hits-only rubric | report precision alongside recall, with a ceiling |
| Answer-key leakage | 58 files under the five repos' `docs/design/` name the audit findings, mostly `*-implementation-notes.md`, all readable by the runner | hold the labeled set outside the verifier's reachable paths |
| Same-family scoring | an Opus verifier scored by Opus | score blind, and not by the verifier's model family |

Revised design:

- Build the labeled set from past Mode 2 audit findings, but do NOT treat "an
  audit found it" as proof the self-report missed it. Staff Engineer is right
  that `clyde` #77 was mainly a criteria-quality problem, not a missed
  implementation. Label each item by class: **missed implementation** vs
  **defective criterion**. Only the first class tests this design's premise
- Stage the phases under test in a location where the implementation notes and
  audit records are not reachable. Leakage is the difference between measuring
  the verifier and measuring its ability to read the answer
- Run BOTH arms on the identical set: the blind verifier, and the builder's
  own self-report for that phase
- Score blind, by a non-Opus judge
- Write the result to
  `docs/design/2026-08-02-per-phase-verification-node-phase0-eval.md`
- **Success criteria:** that file exists and holds, for >= 6 labeled
  missed-implementation items, recall and precision for BOTH arms. The design
  proceeds only if the verifier's recall exceeds the self-report's recall on
  the same set AND the verifier's false-positive rate is at or below 1 in 3.
  Fail either and this doc is marked Superseded.
- **The kill answer, stated plainly** (Staff Engineer's hardest question): if the
  blind verifier does not beat the builder's own self-report on the same hidden
  set, scored by someone else, the node is ceremony and does not ship.

#### Phase 1: `criteria.sh`, deterministic execution and comparison
**Model:** sonnet

Unblocked 2026-08-08: the seam closed by consensus at extraction vs execution.
The script no longer parses prose.

- `HOME/.claude/skills/how-to-execute-a-plan/criteria.sh`
- Accept `(command, expected)` pairs from the caller; execute and compare
- Implement all five `expected` comparators (condition B). Reject any expectation
  outside the schema rather than interpreting it
- Enforce condition A in code: refuse with exit 5 any command that is not a
  verbatim substring of the doc's criteria block for that phase
- Exit 4 when a criterion cannot run here, distinct from exit 1 (failed)
- Exit 3 on no `Success criteria` block found, never exit 2
- Echo every command before running it; write `phase<N>.criteria.out`
- **Destructive denylist: CUT.** Round-1 panel, convergent. Staff Engineer
  enumerated what a partial list misses (`sed -i`, `tee`, `git clean`,
  `cargo install`, `systemctl`, redirection variants); the Architect noted the
  doc itself called the denylist a backstop rather than the control. A half-guard
  buys false assurance. The control is the stated convention that criteria are
  read-only probes, plus echo-before-run. Unrequested scope, removed
- **Success criteria:** handed a command NOT present verbatim in the doc, it
  exits 5 and executes nothing (verify with a command that would create a file:
  the file must not exist afterward). Handed a pair whose `expected` value is
  altered to something false, it exits 1. Handed a command naming a missing
  binary, it exits 4, not 1. Against these five named docs it locates the
  criteria block for every phase with no spurious exit 3:
  `claude/docs/design/2026-07-03-gating-authority-and-funnel.md`,
  `claude/docs/design/2026-07-03-voice-corpus-wiring.md`,
  `clyde/docs/design/2026-07-29-excise-api-key.md`,
  `clyde/docs/design/2026-07-31-close-the-open-register.md`,
  and this doc. A `(command, expected)` pair whose expected value is altered to
  something false makes the script exit 1. A command pointing at a missing binary
  exits 4, not 1

#### Phase 2: `phase-verifier` agent
**Model:** opus
- `HOME/.claude/agents/phase-verifier.md`, `model: opus`, tools Read/Grep/Glob/Bash
- Inputs DOC_PATH, PHASE, COMMIT. Reads `git show <COMMIT>` and the phase spec.
  Does NOT read the implementation notes or the builder report
- Extracts `(command, expected)` pairs from the phase's prose criteria and calls
  `criteria.sh` with them. Selects and pairs only; never synthesizes a command
  (condition A). Expresses expectations only in the closed comparator schema
  (condition B); anything else it keeps as judgment
- On a repair round, reuses round 1's pinned pairs verbatim rather than
  re-extracting (condition C)
- Judges the residue, scans the diff for spec deviations, emits findings as its
  return value. Writes no verdict file: the parent owns that
- Judges each deviation acceptable or unacceptable ON ITS MERITS, with no
  knowledge of what the builder disclosed. Disclosure is applied later, by the
  parent, as severity only
- Defaults to `unverifiable` (which fails) when it cannot prove a criterion
- **Success criteria:** the named fixture is `clyde` commit `fc1a6e97` phase 2
  with one bullet's target file changed to a different module. Spawned via
  `Agent(subagent_type="phase-verifier")` with DOC_PATH, PHASE=2, COMMIT, it
  emits an unacceptable-deviation finding naming that module; spawned against the
  unmodified commit it emits none. A finding is still emitted when the same
  deviation is pre-listed in the builder's Deviations bucket

#### Phase 3: Wire the node into the parent
**Model:** sonnet
- `how-to-execute-a-plan/SKILL.md`: after each `phase-implementer` report, spawn
  `phase-verifier` (which calls `criteria.sh` itself), reconcile its findings
  against the builder's Deviations as severity only, write `phase<N>.yml`, gate
  phase N+1 on `verdict: pass`
- Repair round: on `fail`, respawn `phase-implementer` for the SAME phase with
  the `must_fix` list, amend into the phase's single commit (`git commit
  --amend`, local and unpushed, preserves one-commit-per-phase). Cap at one
  round, then hard stop and report
- `phase-implementer.md`: step 4b keeps reporting criteria, but the report is
  now advisory input to reconciliation, not the gate. Say so in the file
- Verifier death, timeout, or empty return hard-stops. No fall-through
- Finalization hands the collected `*-phase*-verdict.yml` files to the Mode 2
  audit as input, so the panel starts from what each edge already found
- **Success criteria:** `rg -c 'phase-verifier' HOME/.claude/skills/how-to-execute-a-plan/SKILL.md`
  returns >= 1; the skill's phase loop names the hard stop and the verifier-death
  stop; a phase whose verdict file is missing does not advance

#### Phase 4: Observation window and addendum
**Model:** sonnet
- Run the gated funnel on real work. Log every verdict file produced
- Log schema, per phase: `tier1_exit`, `tier2_tokens_in`, `tier2_tokens_out`,
  `tier2_wall_ms`, `tier2_timeout` (bool), `findings_total`,
  `findings_false_positive`, `repair_rounds`, `verdict`
- Cost is measured, not asserted. Round-1 panel, convergent: "the verifier reads
  only the diff" is not a bound, because the doc also grants it the phase's doc
  section and every file the diff touches. A one-line import change to a large
  file pulls the whole file in. Phase 4 records the actual distribution and the
  design gets a context ceiling with defined overflow behavior once there is data
- **Success criteria:** addendum cites >= 5 verified phases and reports, for
  each, the full log schema above. A false-positive rate above 1 in 3, or any
  phase exceeding the context ceiling, triggers a prompt or scope revision, never
  a silent loosening of the gate

## Acceptance Criteria

Every criterion below was executed against `main` on 2026-08-02 and its output
recorded. All five are expected to fail today: this is the before-state.

- [ ] **AC1.** `criteria.sh` exists and is executable.
      `test -x HOME/.claude/skills/how-to-execute-a-plan/criteria.sh`
      `Observed on main:` exit 1 (file does not exist)
- [ ] **AC2.** The verifier agent exists and pins the judge model.
      `rg -c '^model: opus' HOME/.claude/agents/phase-verifier.md`
      `Observed on main:` exit 2, `No such file or directory (os error 2)`.
      Agents dir today holds only design-research, phase-implementer,
      release-driver, review-panel
- [ ] **AC3.** The parent gates on the verdict file.
      `rg -c 'verdict: pass' HOME/.claude/skills/how-to-execute-a-plan/SKILL.md`
      `Observed on main:` exit 1, no matches
- [ ] **AC4.** An unacceptable deviation lands in `must_fix` whether or not the
      builder disclosed it.
      `yq '.must_fix | length' docs/design/<doc>-verdicts/phase2.yml` returns
      >= 1 when run against the Phase 2 fixture (`clyde` commit `fc1a6e97`
      phase 2, one bullet's target file changed) with that deviation pre-listed
      in the builder's Deviations bucket.
      NOT RUNNABLE YET: depends on Phase 2, which creates the agent under test.
      Stated as a literal command so it is executable the moment Phase 2 lands
- [ ] **AC5.** Phase 0's scored eval exists.
      `test -f docs/design/2026-08-02-per-phase-verification-node-phase0-eval.md`
      `Observed on main:` exit 1 (file does not exist)

AC5 originally read `ls docs/design/*phase0*`, which returned **exit 0** on a
missing file and could therefore never fail. Caught by running it. Recorded here
because it is the same defect class the gate exists to find, found in this doc's
own criteria on the first pass through the gate.

## Resolved Decisions

- **2026-08-02: Verifier does not see the builder's notes.** Anchoring defeats
  the purpose. Reconciliation against disclosed deviations happens in the parent,
  after the verdict.
- **2026-08-02: In-harness Opus, not cross-model, per phase.** 277 phases times
  two external CLIs is the wrong cost point. Cross-model stays at the doc
  boundary where `review-panel` already runs it.
- **2026-08-02: Missing success criteria are flagged, not hard-stopped.**
  Measured: only 42 of 448 design docs carry per-phase criteria, so a hard stop
  would wall off most legacy docs. `how-to-execute-a-plan`'s gate already flags
  absence and explicitly tolerates older docs. The verifier falls back to
  judging the phase bullets. No new mechanism, no tightening.
- **2026-08-02: Repair rounds amend, not append.** Keeps one commit per phase.
  Safe because the commit is local and unpushed at that point. The amended SHA
  becomes the next phase's `PRIOR_SHA`.
- **2026-08-02: Verdict files are committed, not gitignored.** They are the
  audit trail, and the Mode 2 panel consumes them at finalization. Matches the
  sibling gating doc's lean.
### Round 1 panel, 2026-08-08

Architect (Gemini) rc=0, Staff Engineer (Codex) rc=0. Both seats produced real
reviews; no seat was substituted.

- **Disclosure changes severity, never the verdict.** [convergent] The original
  reconciliation table let any deviation "recorded with reasoning" ride, and the
  builder writes that bucket before the verifier runs. Broad pre-disclosure
  immunized real defects and made the gate opt-out. Table rebuilt with a
  disclosed-but-unacceptable row.
- **Phase 0 rewritten.** [convergent] It could not falsify its own premise: no
  baseline arm, no false-positive term, answer-key leakage from 58 on-disk files,
  and same-family scoring. All four fixed; kill condition now compares the
  verifier against the builder's self-report on a held-out set, scored by a
  non-Opus judge.
- **Measured claims corrected.** [convergent] The corpus was inflated ~15% by 57
  git-worktree duplicates, and the headline percentage moved 37% to 57% purely on
  classifier breadth. Doc now states a range and publishes the regex.
- **Parent is the sole verdict writer.** [staff] `disclosed` and `must_fix` are
  computable only after reconciliation, so naming tier 2 as writer named two
  writers for one file.
- **Regression sweep CUT.** [convergent] Per-phase criteria are point-in-time
  assertions; re-running phase 1's criterion at phase 3 fails correctly-built
  work. Unrequested scope, added by the author in the edge-case pass.
- **Destructive denylist CUT.** [convergent] A partial list buys false assurance.
  Unrequested scope, same origin.
- **`doc_blob` KEPT and promoted, against both seats.** Both said cut it as dead
  state. Correct that it was passive, wrong that it should go: `SKILL.md`
  licenses amending a criterion mid-run, so the doc is mutable under the verifier
  and this was the only proposed guard. Now an enforced start-vs-verify
  comparison.
- **Verdict files moved to a subdirectory.** A `*-verdict.yml` glob would have
  matched both this contract and the sibling gating doc's.
- **Exit 4 added** for environment failures, so a sandbox denial cannot burn the
  single repair round. **Repair recovery path named** (reflog, local, unpushed).
  **Phase 4 now instruments cost**, not just false positives.

### Round 1 consensus on the pushback, 2026-08-08

One finding was pushed back rather than folded. It closed by consensus.

- **The seam is extraction vs execution.** Both seats' remedy (fold everything
  into the agent) was rejected and the panel converged on the author's
  counter-proposal, agreeing the original objection landed on the script's input
  rather than on determinism. Conditions A (select, never synthesize), B (closed
  comparator schema), and C (pin pairs across repair rounds) are the price of
  the seam and are written into Architecture. Condition A is enforced by exit 5
  in code, not by a prompt.
- **The schema boundary IS the tier boundary.** Consequence of condition B, and
  the first crisp definition of where code stops and judgment starts. It also
  replaces the estimated command-bearing share with a measured one.
- **`criteria.sh` runs inside the verifier, not before it.** The agent is its
  caller. This obsoleted the original two-tier flow and the parent-side exit-code
  table, both rewritten.
- **Finding 4 resolved differently than the panel proposed.** The panel's
  restructure had the agent write the criteria block and the parent append
  `must_fix`, which is two writers on one file: the exact defect finding 4
  raised. Resolved instead by splitting artifacts, one writer each:
  `criteria.sh` owns `phase<N>.criteria.out`, the parent owns `phase<N>.yml`.
  The raw script record is also what makes the agent's narration checkable.
- **Denylist cut is coupled to condition A, not independent.** The cut is
  defensible only because the executed command is verbatim author text. If
  extraction could synthesize, a read-only allowlist would be mandatory. Recorded
  so a future edit cannot relax A without reopening the denylist.
- **Naming confirmed.** Zero `*verdict*` files exist anywhere in the five repos,
  so the contract is unconstrained and this was the cheapest moment to pick.
  A different path depth beats a hyphen-vs-dot distinction the next person globs
  straight through.

## Alternatives Considered

### Alternative 1: Push all criteria into `otto ci`
- **Description:** encode each phase's criteria as shell asserts in `.otto.yml`
- **Pros:** pure code, zero tokens, already the per-phase gate
- **Cons:** criteria are per-doc and per-phase, `.otto.yml` is per-repo and
  permanent; a phase's criteria are dead weight the moment the phase lands
- **Why not chosen:** wrong lifetime. Adopted in part: tier 1 is exactly this
  idea, scoped to the phase instead of the repo.

### Alternative 2: Run the Mode 2 panel after every phase
- **Description:** reuse `review-panel` per phase instead of building a new node
- **Pros:** no new agent, cross-model, proven
- **Cons:** two external CLIs per phase, 10-minute timeouts each, whole-doc
  framing on a single-phase diff
- **Why not chosen:** cost and latency. The panel's value is whole-doc
  architectural read, which is not what an edge check needs.

### Alternative 3: `phase-implementer` spawns its own verifier
- **Description:** the builder subcontracts its own review
- **Pros:** no parent changes
- **Cons:** same context lineage, and the builder writes the verifier's prompt
- **Why not chosen:** the node under review cannot own the review.

## Technical Considerations

### Dependencies
- `yq` for reading verdict files (already installed, per the sibling gating doc)
- No new crates, no build. Markdown plus one shell script.

### Blast Radius
- One repo: `scottidler/claude`. Two files added
  (`how-to-execute-a-plan/criteria.sh`, `agents/phase-verifier.md`), two edited
  (`how-to-execute-a-plan/SKILL.md`, `agents/phase-implementer.md`).
- Deploys by symlink: `manifest.yml` links `HOME/.claude/agents` and
  `HOME/.claude/skills` into `$HOME/.claude/`. No install step, no version bump
  required for the change to take effect.
- Ship order: independent of `2026-07-03-gating-authority-and-funnel.md`. If that
  doc ships first, the two schemas merge under one convention.
- This repo has no `.otto.yml`, so `how-to-execute-a-plan`'s own "otto ci green
  per phase" step does not apply when executing this doc. Phases are verified by
  their success criteria only.

### Performance
- Tier 1 is shell. Tier 2 adds one Opus agent per phase.
- Context is bounded to the phase diff, not the repo.

### Security
- `criteria.sh` runs commands transcribed from a design doc, and design docs are
  frequently LLM-authored. The script echoes every command before running it.
- **No denylist.** Round-1 panel, convergent cut. A partial denylist misses
  `sed -i`, `tee`, `git clean`, `cargo install`, `systemctl`, and redirection
  variants, and buys false assurance in exchange. The control is the stated
  convention that criteria are read-only probes, plus echo-before-run.
  `rules/safety.md` already bans `rm` outright, so a criterion carrying one is a
  doc defect caught at authoring, not at execution.
- Residual risk, accepted and named: a doc author who writes a destructive
  criterion gets it executed. The mitigation is the convention and the review
  that every doc already passes through, not a regex.

### Testing Strategy
- Phase 0 is the eval, against a labeled set of real past misses.
- Phases 1 and 2 each carry a planted-defect test: break it, prove the gate bites.

### Rollout Plan
- Symlinked, so live on merge. No staged rollout available.
- Phase 4 is the observation window that decides whether the gate stays hard.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Verifier rubber-stamps | Med | High | Defaults to `unverifiable` = fail; Phase 4 measures |
| False positives block real work | Med | Med | Reconcile against disclosed deviations before stopping |
| Agent count per execute run doubles | High | Med | Tier 2 sees the diff only, not the repo; tier 1 is free |
| Builder and verifier deadlock | Low | Med | One repair round, then hard stop for Scott |
| Extraction synthesizes a command instead of selecting one | Med | High | Condition A enforced in code: exit 5 on any non-verbatim command |
| Repair round re-extracts a weaker pair and passes | Med | High | Condition C: round 1's pairs pinned and reused |

## Open Questions

None. All 14 round-1 findings are dispositioned: folded in, or pushed back and
closed by consensus. Nothing was dropped or deferred.

OQ1 (where the code/model seam belongs) closed 2026-08-08 by consensus on the
author's counter-proposal, subject to conditions A, B, and C, all now written
into the Architecture section. Phase 1 is unblocked.

## References

- `docs/design/2026-07-03-gating-authority-and-funnel.md` (the `verdict.yml` contract)
- `HOME/.claude/agents/phase-implementer.md` (steps 4b, 5, return value)
- `HOME/.claude/skills/how-to-execute-a-plan/SKILL.md` (Delegated mode, gates)
- `~/repos/.claude/rules/taste.md` (undisclosed deviations, fail closed, phasing)
- `notes/anthropic-just-fixed-graph-engineerings-greatest-flaw.md` (vault; the
  self-review bias and judge-node model claims this design acts on)
- `tatari-tv/clyde` #77 (https://github.com/tatari-tv/clyde/pull/77)
