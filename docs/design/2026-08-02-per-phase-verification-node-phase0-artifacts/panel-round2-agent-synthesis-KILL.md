# Review Panel Round 2 -- Per-Phase Verification Node (post-Phase-0)

Doc: /home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node.md
Eval: /home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node-phase0-eval.md
Mode: 1 (Design Review), Status: Draft
Snapshot sha256: 083304150acc34d36e03b1c4e083a903517c10058ac1ddb5d7812104369f1da5 (design)
Drift: none on either doc at synthesis time.

architect rc=0 (5060 bytes)
staff-engineer rc=0 (7552 bytes)

Headline: ARCHITECT=KILL, STAFF-ENGINEER=RESHAPE, PANEL=RESHAPE (narrow)

## [ARCHITECT] (gemini, raw)

KILL.

The Phase 0 eval successfully falsified the core premise of this design. A per-phase LLM verifier does not meaningfully beat the builder's self-report on semantic and security defects (33% recall), is structurally blind to out-of-diff regressions (0% recall), and its remaining value is enforcing process rules that are cheaper as bash hooks. The deterministic tier (`criteria.sh`) was entirely dependent on the agent for extraction (Condition A) and is therefore orphaned. There is nothing here to reshape. The Per-Phase Verification Node is dead.

Here are the explicit answers to your questions:

**1. THE RECOMMENDATION**
KILL. The author's recommendation to "Reshape" is a refusal to accept his own null result. Reshaping this design into a set of git hooks for process violations is not a reshape of a "Verification Node"; it is a different mechanism entirely. The design as specified—an Opus agent running 277 times a month to catch 1/3 of semantic bugs—is an architectural failure. Cut it.

**2. THE CRITERION DEFECT**
The author is absolutely right that this is a criterion defect. Measuring a system's recall exclusively against a dataset constructed from things the baseline system missed guarantees a 0% baseline, making any random hit a "pass."
**Absolute recall floor:** 80% for in-diff semantic defects.
**Derivation:** This node is designed to stop the line *before* the Mode 2 audit. A gate that lets 67% of defects pass is a sieve, not a gate. It breeds false confidence and forces the Mode 2 audit to catch everything anyway. If it cannot reliably clear 80%, it is not load-bearing and the latency/cost of spawning an agent per phase is unjustified. 

**3. GT5**
I verified this against the `scottidler/manifest` codebase. In `src/age.rs`, `encrypt_named` calls `validate_name` (L854). `deploy_secret_file` (L1478) and `render_secrets_env` (L1256) do not call it. (The fix was eventually placed higher up the stack in `main.rs`). The author's characterization is confirmed.
This miss is **DISQUALIFYING**, not a bad draw. The verifier was given the exact diff and explicitly prompted to find "sibling-path inconsistencies." It produced a 5-item list of superficial inconsistencies and completely missed the path-traversal vulnerability. This proves the LLM pattern-matches text but lacks the architectural context to understand *why* `validate_name` matters in a deployment lane. It is blind to semantic weight.

**4. THE VALUE-PROFILE REFRAME**
The reframe is correct, and it KILLS the agent. The measured value is enforcing process and hygiene, which do not require a frontier model.
- **Version bump in a phase commit:** Mechanizable as a 3-line bash hook (`git diff Cargo.toml | grep -q '+version'`).
- **Errno catch-all:** Mechanizable via a linter (`clippy::match_wild_err_arm`) or caught by standard Mode 2 code review.
If the mechanizable set is the entirety of the demonstrated value, the agent is deleted. You do not use Opus for regex checks.

**5. THE SCOPE SPLIT**
The scope split changes everything. If the per-phase node structurally cannot see out-of-diff defects (GT3, GT6), then framing the Mode 2 whole-doc audit as a "non-goal" is dishonest. The Mode 2 audit is a hard dependency. Claiming it is just "not replacing" Mode 2 hides the fact that a phase commit is not an independently verifiable unit for systemic regressions, and the per-phase gate is fundamentally blind to half the failure surface.

**6. METHODOLOGY VALIDITY**
- **(a) Glob timeout:** Author error, wasted time, no data impact.
- **(b) `rm` vs `rkvr rmrf`:** Rule violation, no data impact.
- **(c) Staging case A at a later commit:** The verifier caught this scope violation. If the author did not correct the tree and re-run on the exact phase diff, GT1/GT2/GT4/GT5 are tainted for Case A because the verifier was distracted by future-phase code.
- **(d) Leaking notes into the diff:** The author explicitly ran a clean case and a contaminated case for GT4, proving that with the notes, the verifier anchored and missed the defect, while without them, it found it. This *validates* the finding and proves the anchoring hypothesis.
The 33% score stands on the clean runs. The sloppy execution in (c) could have lowered the score by drowning the verifier in extra diffs, but the GT5 miss (which was in-diff and explicitly prompted) proves the fundamental semantic blindness holds regardless.

**7. WHAT IS THE AUTHOR STILL FOOLING HIMSELF ABOUT?**
The sunk cost fallacy. The author explicitly proved that the agent's premise is false, that its recall is abysmal, and that its only real value is enforcing things cheaper done as bash hooks. Yet he recommends "Reshape" and wants to "reopen Open Questions" to figure out a "code-versus-agent split." There is no split. The agent is dead. He wants the panel to kill it so he doesn't have to throw away his own design work. 

I am killing it. Accept the null result, abandon the node, and move on.

## [STAFF-ENGINEER] (codex, raw)

RESHAPE

1. **The Recommendation**

RESHAPE is the right call. Not build: the Phase 0 gate passed by its written criteria while producing only 33% total recall and 50% in-scope recall. Not kill: the eval did surface real value, but mostly in process/scope/hygiene.

Concrete reshape:

- Ship mechanized guards first: phase commit must not bump versions unless the phase explicitly says “release/version bump”; verifier/eval inputs must exclude implementation notes from both tree and diff; phase doc blob changes must be reported; missing verdict must stop advancement.
- Cut the always-on hard-gating Opus verifier as written.
- Keep Mode 2 whole-doc audit mandatory and state it as a dependency, not merely a non-goal.
- Re-run a redesigned eval before any hard agent gate ships.

New gate: **>=75% recall on in-scope missed-implementation defects, false-positive rate <=1/3, zero implementation-notes leakage in both tree and diff, and at least one GT5-class sibling-path/security inconsistency caught.**

2. **The Criterion Defect**

The author is right. The design’s Phase 0 criterion says the verifier only needs recall greater than the self-report plus FP <=1/3 ([design](</home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node.md:454>)). The eval shows that passes at 33% vs 0% ([eval](</home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node-phase0-eval.md:16>)).

That is a criterion defect, not a green result. The labeled set was selected from things the self-report missed, so the baseline is structurally zero as the eval says ([eval](</home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node-phase0-eval.md:108>)).

My floor is **75% in-scope recall**. Derivation: the node can only fairly be scored against defects its diff-bounded design can see. In this eval that denominator is four in-diff defects; the minimum acceptable outcome would have been 3/4, not 2/4 ([eval](</home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node-phase0-eval.md:64>)). Below that, a hard gate still lets too much load-bearing broken work advance for the cost and operational friction of one Opus verifier per phase.

3. **GT5**

Confirmed.

At `3971d2d`, `encrypt_named` calls `validate_name(name)?` before deriving the target path: `3971d2d:src/age.rs:805`. The deploy lane introduced in that same phase joins the raw manifest name into `<secrets_dir>/<name>.age` with no validation: `3971d2d:src/age.rs:1437`. The env lane does the same raw join: `3971d2d:src/age.rs:1223`.

The CLI wiring also lacked up-front validation before dry-run/deploy at `3971d2d:src/main.rs:515-541`. The fix commit `3442622` adds `validate_secret_names` and documents that it mirrors `encrypt_named` so all three lanes behave identically: `3442622:src/age.rs:705-719`; it then wires it into deploy before dry-run/decrypt/write at `3442622:src/main.rs:515-520` and env before resolving/touching secrets at `3442622:src/main.rs:647-652`.

So the author’s GT5 characterization is correct. This is disqualifying for **the design as written** because it was in the phase diff, in the claimed semantic/security value class, and matched the prompt’s sibling-path-inconsistency shape. It does not prove the verifier is structurally blind to that class, but it proves this prompt/model/eval does not justify a hard gate.

4. **The Value-Profile Reframe**

Correct. The design was sold on catching spec-conformance and semantic/security defects before Mode 2 ([design](</home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node.md:267>)). The eval says the verifier’s clear wins were a phase version bump and an errno catch-all ([eval](</home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node-phase0-eval.md:88>)).

Mechanizable:

- Version bump inside a normal phase commit: hook/diff check. Verified: `3971d2d:Cargo.toml:3` changed to `0.4.0` from `0.3.3`.
- Notes leakage into verifier diff: artifact-generation check.
- Wrong staged commit/tree mismatch: compare requested phase commit, archive commit, and diff endpoints.
- Missing verdict/gate file: deterministic parent check.
- Recursive repo glob / unsafe `rm`: better as tool/runtime policy guard than Opus judgment.

Judgment model required or at least not cheaply hookable:

- GT2 401 routed through wrong error contract.
- GT1 doc/tool type mismatch unless schemas are generated.
- GT4 analytics identity capture mismatch.
- GT5 sibling input-validation inconsistency.
- `symlink_metadata Err(_)` masking EACCES/ELOOP: a model can flag this; a lint would be noisy unless narrowly custom.

The mechanizable set is most of the measured value. That shrinks the agent; it does not kill all future agent use.

5. **The Scope Split**

Yes, it changes the relationship to Mode 2. The design says replacing Mode 2 is a non-goal and that Mode 2 still runs at the end ([design](</home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node.md:67>)). But the verifier is explicitly bounded to the phase diff and touched files ([design](</home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node.md:259>)).

The eval shows out-of-diff recall was 0/2 and structurally unreachable ([eval](</home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node-phase0-eval.md:68>)). Calling Mode 2 merely a non-goal now understates reality. Mode 2 is a required downstream control for whole-doc and cross-phase defects the per-phase node cannot see.

6. **Methodology Validity**

- Recursive glob timeout: process defect, but I see no reason it taints GT1-GT6 final scores.
- `rm` instead of `rkvr rmrf`: safety/process defect, not a scoring taint.
- Wrong Case A staging: the initial Case A run was invalid. The final table survives only if the corrected staging described in the eval actually replaced it ([eval](</home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node-phase0-eval.md:31>)). I found no raw transcript artifacts beyond the eval file, so I cannot independently audit that rerun.
- Notes leaked into the diff: the contaminated GT4 run is tainted and must be discarded. The clean rerun is the one that should count ([eval](</home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node-phase0-eval.md:135>)).

Final scoring as reported: GT1-GT6 survive, with the caveat that raw arm artifacts were not checked in for independent replay. GT4’s contaminated run does not survive; its clean rerun does.

7. **What The Author Is Still Fooling Himself About**

The author is still giving too much life to “the premise survived in a weakened, different form” ([eval](</home/saidler/repos/scottidler/claude/docs/design/2026-08-02-per-phase-verification-node-phase0-eval.md:165>)). The measured premise that survived is not the design’s premise. The design’s premise was semantic/spec defect detection by a blind per-phase verifier. The eval says it delivered process/scope/hygiene and missed GT5 while staring at the right code.

The harder question is: after code handles the mechanizable process failures, what remaining defect class is valuable enough to justify a per-phase Opus hard stop? The eval does not answer that. That is the real Open Question to reopen.
## [SYNTHESIS]

### The call: RESHAPE -- narrower than the author's, wider than KILL

The Opus per-phase verifier as a hard gate is dead. Both seats agree, and the
evidence supports it: 50% recall on the only defects it can structurally see,
with a confirmed miss on a defect it was explicitly prompted to find, does not
justify 277 spawns as a blocking gate.

What survives is not what the author or either seat named. See divergence #1.

### Convergence (both seats, independently)

1. **The criterion defect is real.** Both confirm the author is right that
   "verifier recall > self-report recall" cannot fail on a set selected from what
   the self-report missed. This is a passing criterion over a failing result.
2. **GT5 is confirmed, and it is disqualifying for the design as written.** Both
   seats verified it in the repo. I verified it independently (below). Triple-confirmed.
3. **The value-profile reframe is correct, and the mechanizable set is most of
   the measured value.** Both seats reached this independently.
4. **"Non-goal" is a dishonest framing for the Mode 2 audit.** Architect: "hides
   the fact that a phase commit is not an independently verifiable unit for
   systemic regressions." Staff: "Mode 2 is a required downstream control."
   Convergent and strong. Fix the doc regardless of the build decision.
5. **Methodology: (a) and (b) taint nothing; (d) validates rather than
   invalidates; (c) is the only real taint risk.** Both seats agree per-item.
6. **The author over-preserves the design in his own recommendation.** Architect
   calls it sunk cost; staff says "the premise that survived is not the design's
   premise." Both right.
7. **A recall floor around 75-80% would have been the honest bar.** Architect 80%
   in-diff, staff 75% in-scope. Near-convergent derivations.

### Divergence, with my read

**1. KILL (architect) vs RESHAPE (staff). I side with staff, on a reason neither
gave.**

Architect's KILL rests substantially on `criteria.sh` being orphaned: Condition A
makes the script's input the agent's extraction, so killing the agent kills tier 1.
I verified this -- architect is correct about the doc as written
(doc lines 186-199, "the agent extracts, the script executes and compares").

But the dependency is an artifact of a choice the doc never revisited: criteria
live as prose in design docs, so something must extract them. Fix the SOURCE and
the dependency vanishes. Require `/create-design-doc` to emit per-phase criteria
as structured `(command, expected)` pairs at authoring time, and `criteria.sh`
becomes a pure deterministic runner with no model anywhere in the gate path.
The author already writes criteria this way when he tries: THIS doc's AC1-AC5 are
literal commands with recorded observed exit codes. Deleting tier 1 because tier 2
failed is throwing away the component Phase 0 never tested.

**2. Phase 0 measured the wrong class, and neither seat caught it. This is the
most important finding in this round.**

The design's originating motivation is `clyde` #77: "three of seven acceptance
criteria could not pass as written" (doc lines 50-55). That is a DEFECTIVE-CRITERION
defect, not a missed implementation.

Round 1 then explicitly scoped Phase 0 to exclude that class: "Label each item by
class: missed implementation vs defective criterion. **Only the first class tests
this design's premise**" (doc lines 443-445).

So Phase 0 falsified the missed-implementation premise and never measured the class
that motivated the doc. And the verifier's demonstrated wins cluster in exactly the
excluded class:
- it caught case A staged at a commit containing later phase work, UNPROMPTED, when
  the author did not -- that is a setup/claim-validity finding
- it caught the version bump as a scope violation against the doc's own phasing rule
- the author's own AC5 defect (`ls` returns exit 0 on a missing file, so the
  criterion could never fail) is this class, and was found by executing it

You cannot kill a design on a test that deliberately excluded its originating use
case. This cuts AGAINST architect's KILL and against the author's own "do not build."

**3. The errno catch-all is a semantic security defect, not hygiene. The author
under-credits his own verifier; architect gets this wrong too.**

Verified at `manifest` 3971d2d, `src/age.rs:1336`: `ensure_secret_parent` matches
`Err(_)` from `symlink_metadata` and falls into the "parent missing -> create at
0700" branch. The function's entire purpose is to REFUSE a symlinked parent. An
ELOOP -- the exact errno a symlink attack produces -- lands in the create branch.
EACCES likewise gets misreported as "missing."

The author files this under "process and cosmetic." It is not. Architect calls it
mechanizable via `clippy::match_wild_err_arm` -- wrong: that lint fires on every
wildcard error arm in a codebase and understands nothing about the symlink guard's
purpose. Staff is right ("a model can flag this; a lint would be noisy unless
narrowly custom"). The judge's "process and cosmetic" quote was about System A on
the persona-cli case; the author generalized it across all cases, including the one
where his verifier found a real semantic defect in a security guard.

### My independent verification

- **GT5 confirmed, and stronger than the author states.** At 3971d2d,
  `validate_name` is called at `src/age.rs:805` inside `encrypt_named`;
  `deploy_secret_file` (`src/age.rs:1430`) joins the raw name via
  `secrets_dir.join(format!("{}.age", name))` with no validation; `render_secrets_env`
  (`src/age.rs:1208`) does the same. `deploy_secret_file` is a `+`-added NEW function
  in that very commit -- 100% in-diff. And `encrypt_named`'s own docstring at
  `src/age.rs:769` states in prose: "1. Validate `name` with `validate_name`."
  The invariant was written in English in the same file and the verifier still
  missed the asymmetry. Fix commit 3442622's message names the vulnerability class:
  a key like `../../other-store/key` sources ciphertext outside the declared store.
- **GT3 and GT6 out-of-diff labels are correct.** GT3's reqwest clients live at
  `persona-cli src/api/mod.rs:24` and `src/commands/whoami.rs:19` -- pre-existing
  files the MCP phase never touched. GT6's `setup_logging` is at `src/main.rs:191`;
  `main.rs` IS in the phase commit but the diff touches `setup_logging` zero times.
  The author's labeling is careful and accurate.
- **Both "extra" findings are real.** Cargo.toml 0.3.3 -> 0.4.0 in 3971d2d, and the
  errno catch-all above.
- **Case A is persona-cli.** 76ebedc ("test(mcp): concurrency test proving
  token_lock does exactly one refresh") is a later commit than the phase under
  review (1b1f41b). The author's account of defect (c) checks out.
- **The implementation-notes file IS in commit 3971d2d**, confirming the leakage
  vector in defect (d) was real and not hypothetical.

### On the recall floor (Q2): the question is unmeasurable at this n, and the
### reshape dissolves it

Both seats gave a number (80% / 75%). Neither number is measurable at n=6 with a
4-item in-scope denominator. The difference between staff's 75% floor and the
observed 50% is ONE ITEM. A threshold stated to two significant figures against a
4-item denominator is a coin flip in a lab coat.

Worse, the headline 33% is itself fragile: it is 2.0/6 with PARTIAL=0.5. The eval's
own contamination table says the clean GT4 run "located `auth.rs:180` and the
missing guard itself" -- score that HIT instead of PARTIAL and recall is 2.5/6 =
42%. One boundary call moves the headline 9 points. Not misconduct; the author's
weighting is stated and defensible. But it means no floor can be defended at this
sample size.

The honest answer: **do not pick a floor. Delete the model from the gate path.**
A floor only matters if a judgment model is making a recall-bearing decision. The
reshape removes it, and the question becomes moot. If an advisory verifier is
evaluated later, it needs n>=20 with BOTH defect classes represented before any
floor means anything.

### Ranked actions

**Must-fix (do these regardless of the build decision)**
1. Promote the Mode 2 whole-doc audit from Non-Goal to a named hard dependency,
   with the structural reason: a per-phase node cannot see out-of-diff defects.
   Convergent, both seats.
2. Add to Phase 0's leakage control, as a permanent rule: exclude implementation
   notes from the DIFF, not only the tree. Already earned by measurement.
3. Correct the eval's value-profile paragraph: the errno catch-all is a semantic
   defect in a security guard, not "process and cosmetic." The author is
   under-reporting his own result.
4. Record in the eval that Phase 0 measured the missed-implementation class only,
   and that the defective-criterion class -- the doc's originating motivation via
   clyde #77 -- was excluded by Round 1's own scoping and remains unmeasured.

**Ship (the reshape)**
5. Structured per-phase criteria at authoring time in `/create-design-doc`:
   `(command, expected)` pairs, closed comparator schema (Condition B survives
   intact as a schema; Condition A becomes unnecessary).
6. `criteria.sh` as a pure deterministic runner over those pairs. No extraction,
   no model, no spawn. This is the only part of the design Phase 0 did not falsify.
7. The mechanizable guards as hooks/checks, not agent judgment: no version bump in
   a phase commit; notes excluded from tree and diff; staged commit == phase commit;
   missing verdict stops advancement. Convergent, both seats.

**Cut**
8. `phase-verifier` as a blocking per-phase Opus agent: Phases 2, 3 as written,
   and 4. The 277-spawn hard gate does not survive its own kill gate.
9. The recall-floor question, as moot once no model gates. Do not spend a round
   defending a number.

**Defer (a separate, smaller doc with its own eval -- not Phases 1-4 of this one)**
10. Whether an ADVISORY, non-blocking verifier earns its cost on the
    criteria-quality class specifically. That is the untested hypothesis, it is
    where the measured wins actually cluster, and it must not be smuggled back in
    as a hard gate without n>=20.

### Q7: what the author is still fooling himself about

Both seats say he is over-preserving. I agree, but the specific self-deception cuts
in BOTH directions and neither seat saw the second one:

- **Over-preserving:** "the premise survived in a weakened, different form" is doing
  a lot of work for a 0-for-2 on the security/semantic class it was sold on. The
  vague "reshape" with no named target is a kill he does not want to say out loud.
  Staff is right that the surviving premise is not the design's premise.
- **Over-flagellating, which is the more interesting error:** he wrote "do not build
  Phases 1-4" on the strength of a test that, on Round 1's advice, deliberately
  excluded the defect class that motivated the doc -- and he under-reports his own
  verifier's one genuine semantic find. The four-item methodology-defect confession
  is honest and unusually rigorous, but it also buys credibility that then carries a
  conclusion broader than the evidence.

The eval is a genuinely good null result. It is over-generalized in one direction and
under-credited in another, and the component with the clearest independent value
(deterministic criteria) is being cut as collateral.
