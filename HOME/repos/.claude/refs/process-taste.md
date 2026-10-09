# Process Taste

The process and evidence half of Scott's judgment standards, split out of
`rules/taste.md` so it loads on demand instead of every session. The always-on
half (quality bar, architecture, security) stays in `rules/taste.md`; worked
examples are in `refs/design-exemplars.md`.

## The pipeline is the process

- Triage every change out loud: targeted fix (just do it) vs real behavior
  change (design doc first). When ambiguous, ask "targeted fix or design doc?"
- The funnel is inviolable: discuss/probe -> /create-design-doc (all five
  passes) -> review-panel -> consensus loop -> /how-to-execute-a-plan (per-phase
  commit, otto ci green) -> implementation audit -> /cli-shakedown -> ship ->
  verify live. Never substitute another methodology for it.
- **Never build with open questions or disputes.** Ready-to-build means: every
  reviewer finding folded in or pushed back with rationale, Open Questions
  empty, no unresolved pushbacks. Ask "no pushbacks? no open questions? ready
  to build?" and mean it.
- Consensus loop: fold in everything you agree with; send pushbacks WITH
  rationale back to the reviewer seeking consensus; escalate to Scott only what
  the agents cannot close. NEVER silently drop or defer a finding.
- Reviewers advise, the owner decides. Absent a named concrete flaw, build the
  owner's requested option. A full solution is never marked "deferred". Once
  Scott overrides or defers something, it stays decided: do not relitigate.
- Open questions are the author's to close: probe, read code, run the thing.
  Never punt a verifiable fact to another human ("you confirm that; don't put
  that on someone else").

## The design doc is the source of truth

- Everything agreed lands IN the doc: no follow-on lists, no agent memory, no
  side notes. Rejected alternatives and deferred options get an addendum with
  the reasoning (capture the road not taken).
- Every requirement is traceable to who asked for it. Unrequested scope is
  illegitimate regardless of quality ("I don't remember discussing this").
- Docs state their cross-repo blast radius and the ship order they force.
- Status fields reflect ground truth (flip to Implemented when true, not
  before; use Superseded). Design docs are point-in-time; README / CLAUDE.md /
  AGENTS.md are living and must track shipped reality.
- Never fabricate process ("Review Passes 3/5" that never ran) and never claim
  future state (a version number that hasn't merged) as current.

## Phasing

- Phases are small, legible, countable ("how many fucking phases are there?"),
  independently committable, each otto-ci-green with exactly one commit; a
  fresh context per phase; deterministic/cheap work first, LLM/expensive last.
- When a design rests on an unproven environmental assumption, phase 0 is a
  zero-code spike that proves it (curl the gateway before building anything).
- Deferral requires Scott's say-so ("why are we deferring? did I say so?").
  Blockers must be concrete and named, with enumerated solution options.
- Land in-flight PRs before opening the next design doc; rebase early and
  often; nothing gets orphaned: every branch/PR tracked to landed or closed.

## Evidence standards

- No guesses, hunches, or "probably", ever. If it can be searched, read, or
  run, do that before answering. "Unknown" is unacceptable when every repo is
  checked out locally. When contradicting someone, cite a reputable source.
- Watch for circular authority: "did we write that spec just now?" A claim is
  not evidence if you authored it this session.
- Quality claims become measurable: labeled eval sets, calibrated judges, and
  the eval's own questions vetted against the real corpus. Null results are
  accepted and redirect effort; they are never spun.
- Precedent hunts go org-first then industry-wide (blogs, GitHub, talks) with
  fan-out, and a claimed impossibility must survive the obvious composition of
  existing steps before it is believed.
- A complete review covers three altitudes: mechanical findings, architecture/
  systemic design, and product utility. Reports have no large unattributed
  buckets, name the repo with every PR number, and cite full URLs down to the
  file and line range.
