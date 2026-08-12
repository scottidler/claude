# Phase 0 eval: does a blind verifier beat the builder's self-report?

**Date:** 2026-08-10
**Design doc:** `docs/design/2026-08-02-per-phase-verification-node.md`
**Status:** COMPLETE. n=6 met, all three stated conditions met, and the result
still does not support building the design as specified.
**Recommendation:** do not build Phases 1-4. Reshape the design first.

## The kill condition, quoted from the doc

> that file exists and holds, for >= 6 labeled missed-implementation items, recall
> and precision for BOTH arms. The design proceeds only if the verifier's recall
> exceeds the self-report's recall on the same set AND the verifier's
> false-positive rate is at or below 1 in 3.

| condition | result | met |
|---|---|---|
| >= 6 labeled items | 6 | yes |
| verifier recall > self-report recall | 33% vs 0% | yes |
| verifier false-positive rate <= 1 in 3 | 0 | yes |

**All three conditions pass, and the criterion is wrong.** See "The criterion was
defective" below. This is recorded as a passing criterion over a failing result,
not spun into a green light.

## Method

**Ground truth.** Six defects, each confirmed by a later fix commit whose own
message names it. Not "an audit mentioned it": Scott shipped a fix for each.

**Leakage control.** Trees staged with `git archive` at the phase commit, every
`*-implementation-notes.md` removed from the tree, AND every diff generated with
`':(exclude)*implementation-notes*'` and verified at 0 matches. The second half
of that was missing in the first attempt and is the reason case B had to be rerun.

**Two arms, same items.**
- Arm A: fresh Opus session, doc + phase spec + phase diff. No build memory, no notes.
- Arm B: the builder's implementation notes **as of the phase commit**, never today's.

**Scoring.** Blind, by Gemini 3.1 Pro, arms labelled System A / System B with no
indication which was which. HIT = named it and treated it as a problem. PARTIAL =
right mechanism, wrong conclusion. MISS = missed it or asserted it was fine.

## Ground truth and results

| id | repo | defect | fix commit | in phase diff? | self-report | verifier |
|---|---|---|---|---|---|---|
| GT1 | persona-cli | tool table said `Employee`/`username string(s)`/`Vec<Employee>`; code returned `ManagerResult`/`GithubResult`/`Vec<AnniversaryEntry>` | `ab5c8f3` | yes | MISS | PARTIAL |
| GT2 | persona-cli | mid-session 401 routed to `McpError`, contradicting the doc's own Resolved Decision | `7af464c` | yes | MISS | **HIT** |
| GT3 | persona-cli | no HTTP timeout on any reqwest client | `7af464c` | no | MISS | MISS |
| GT4 | marquee | raw `Identity.email` into `capture()`; `auth.rs:180` can yield a `sub`; sibling path guards, capture did not | `dd750ae` | yes | MISS | PARTIAL |
| GT5 | manifest | `deploy_secret_file`/`render_secrets_env` join a raw manifest name with no `validate_name`, unlike `encrypt_named` | `3442622` | **yes** | MISS | MISS |
| GT6 | manifest | `setup_logging()` `eprintln!` not TTY-gated, unlike the sibling banner | `3442622` | no | MISS | MISS |

**Recall: verifier 2.0/6 (33%), self-report 0/6 (0%).** HIT=1, PARTIAL=0.5.

**Precision.** Clean-case arm: `gx-lib-decomposition` at `68c83f5`, a phase a
prior independent audit found clean. The verifier reported 5 deviations and
labelled every one acceptable, zero unacceptable. Judge: "raising zero false
alarms." False-positive rate 0.

## The finding that matters more than the score

Split the six by whether the defect was inside the phase's own diff.

| scope | items | verifier recall |
|---|---|---|
| inside the phase diff | GT1, GT2, GT4, GT5 | 2.0/4 (50%) |
| outside the phase diff | GT3, GT6 | 0/2 (0%, structurally impossible) |

A per-phase node sees per-phase defects. Two of six ground-truth items were never
reachable by it. That is not a tuning problem and no prompt fixes it. It means the
Mode 2 whole-doc audit is covering a class this node cannot reach, and the doc's
framing of the audit as a mere non-goal understates the dependency.

## GT5 is the case against the design

`deploy_secret_file` is **created by the phase under review**. The verifier's
prompt explicitly asked it to report "any place where sibling code paths handle
the same input inconsistently." It produced a five-item "Sibling-path
inconsistencies" section. `encrypt_named` validating while the deploy lane does
not was not in it.

Right question asked, right code in scope, still missed. This is the single
strongest argument against the value claim and it should be the first thing the
panel sees.

## What the verifier is actually good at

The judge's verdict, verbatim: "System A completely failed to detect either of the
actual ground truth vulnerabilities/bugs, focusing entirely on process and
cosmetic issues."

That is damning as written and it is also a finding. The verifier produced two
genuine defects the ground truth did not contain:

- **A version bump (0.3.3 -> 0.4.0) inside a phase commit** (`Cargo.toml:3`),
  which violates the owner's phasing rule that a phase commit does not bump. The
  verifier called it "Unacceptable as scope."
- **`symlink_metadata`'s `Err(_)` catch-all masking EACCES/ELOOP as "missing"**
  (`age.rs:1336`), misattributing the failure cause.

So the value profile is real but different from the one the design claimed. It
finds process, scope, and hygiene violations against the doc and the house rules.
It does not find semantic or security defects. The design was sold on the second
and delivers the first.

## The criterion was defective

"Verifier recall exceeds self-report recall" cannot fail. The labeled set is built
from defects the self-report missed, so arm B scores 0 by construction and any
non-zero verifier score passes. The panel raised exactly this ("the baseline is 0%
by definition, which makes any nonzero hit rate better"), the fix that was folded
in was to run the baseline arm and measure it, and measuring a structurally-zero
baseline does not repair the comparison.

**What was missing is an absolute recall floor.** A gate that catches a third of
known defects still passes two of three through. That belongs in the criterion and
was not there.

This is a defect in the acceptance criterion, found by executing it. It is the
same class the criterion was designed to catch, one level up.

## Methodology defects hit during this run

All the author's.

1. Recursive `glob` over `~/repos`, which the search rule forbids. Timed out.
2. `rm` instead of `rkvr rmrf`, three times. Files regenerable; rule has no exception.
3. Case A staged at `76ebedc`, which included later Phase 5 work, so the tree did
   not match the phase diff. **The verifier caught this unprompted; the author did not.**
4. Leakage control verified on the tree, then defeated by the diff, which still
   carried the notes file. Partial coverage of a guard.

Defect 4 produced the eval's cleanest incidental result. Case B ran twice, one
variable:

| run | notes visible | verdict on GT4 |
|---|---|---|
| contaminated | yes, via the diff | "Acceptable ... declared in the implementation notes." Concluded **"No unacceptable deviations found."** |
| clean | no | located `auth.rs:180` and the missing guard itself |

With the notes in view it adopted the builder's framing and stopped looking. The
doc's rule that the verifier never sees the builder's report was argued from first
principles and accepted by the panel on argument. It now has a measurement, and it
needs one extra condition: **exclude the notes from the DIFF, not only the tree.**

Unrelated environment finding: `/tmp` is a 16G tmpfs that hit 100% mid-run
(`/tmp/claude-1000` accounted for all of it, plus 3,819 `claude-empty-*` dirs).
Only this session's ~4.4G was reclaimed; no other session's scratch was touched.

## Recommendation

**Do not build Phases 1-4.** Three reasons, in order:

1. 33% recall, and 50% even on in-scope defects, does not justify one Opus agent
   per phase across 277 phase spawns. GT5 shows it misses a defect while looking
   directly at the question that would find it.
2. The measured value is process and scope enforcement, not semantic defect
   detection. Much of that class is cheaper as code: a phase-commit-does-not-bump
   check is a hook, not an Opus agent.
3. The acceptance criterion needs an absolute recall floor before it can gate
   anything, and setting that floor is a design decision, not an eval fix.

**Send this back to the panel.** The design's premise survived in a weakened,
different form, which is a reshape and not a pass or a kill. Open Questions on the
design doc should reopen with the recall floor and the code-versus-agent split for
the process-violation class.

Null result, reported as one. Not spun.
