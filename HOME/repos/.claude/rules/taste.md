<!-- WORKAROUND: YAML array syntax for paths: is broken in Claude Code.
     See https://github.com/anthropics/claude-code/issues/26868
     Fix: use alwaysApply: true for catch-all rules -->
---
alwaysApply: true
---

# Design & Judgment Taste

Distilled from a forensic pass over all ~1,629 sessions (4,202 typed messages,
2026-05 through 2026-07): the recurring judgment calls Scott makes when
designing, reviewing, and shipping. Style rules live in `general.md` etc; this
file is how he DECIDES. Worked examples with verbatim quotes:
`~/repos/.claude/refs/design-exemplars.md` (read it before authoring or
reviewing a design doc).

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

## Quality bar: done means live

- Done = merged + bumped + deployed + probed until the version lands + the
  affected surface exercised (curl/playwright/shakedown). Localhost is not
  shipped. Green CI is not done. "Kick the tires and prove it."
- Tests must bite: break the code to prove the test fails; positive AND
  negative cases; comprehensive regression tests specified in the design doc
  so the bug class cannot recur. Flaky tests get hardened, not retried.
- Every fix carries causal closure: what was the issue, what action fixed it,
  why did it break (against "it worked for weeks"), and what mechanism
  prevents recurrence. "I'll be more disciplined" is an empty non-fix; the
  remedy is structural (hook, guard, schema) that makes the failure impossible.
- A fix that abandons the feature's value (turn it off, disable the cache) is
  not a fix. A regression is fixed forward from the current design; never
  revert to a superseded design without first recovering why it was replaced.
- Implementation audits walk the plan bullet-by-bullet against the code.
  Undisclosed deviations are the primary finding; disclosed-and-reasoned
  deviations may ride. Cross-module wiring, config loading, and registration
  steps are the most-skipped and get checked explicitly.

## Architecture instincts

- Decompose along change frequency: fast-changing data (published JSON) never
  forces a rebuild of slow-changing logic (the lib consuming it).
- Copy the proven in-house pattern before inventing: find the org repo that
  does it right (persona-cli, otto, pagerduty-cli), harvest it exactly; or
  generate a throwaway scaffold and harvest the bits. Converge on the org
  standard; deviate only on a concrete blocker, and treat that as temporary.
- House CLI shape: workspace of lib crates + thin clap main.rs shim; shared
  contract crate for cross-boundary types (named for its role); single flat
  version/tag per repo; split along deployment/consumption boundaries.
- Config drives behavior or it doesn't exist: XDG ~/.config/<tool>/<tool>.yml,
  repo ships ONE annotated example, env vars never .env, cache in ~/.cache not
  ~/.config, tunables through the standard delivery path (never hardcoded).
- Fail loudly, fail closed: unparseable input is a loud error, never an empty
  result; safety gates abort on the unhappy path; degrade visibly (banner) and
  true-up on reconnect; error pages self-contained in the binary.
- Names tell the truth: the most literal name for what it does; an identifier
  that says one thing and means another is "cognitive dissonance, NEVER
  allowed". A field derived from another never diverges: drop it rather than
  sync it. Two signals never encode the same meaning.
- Siblings behave identically: sister CLIs share auth/infra/flag semantics;
  parallel variants are symmetric; naming schemas unify across layers
  (yaml/env/docs); recurring cross-page inconsistency demands shared code that
  kills the class, not spot fixes.
- Prefer the simple direct mechanism: block on the command, drop the file,
  one script with modes, flags instead of subcommands on a one-verb tool,
  TTY-detect output (yaml for humans, json when piped, one --format override,
  no boolean format flags). Magic that can't be made predictable and tested
  gets ripped out.
- Ask the multi-replica question up front: the design either collapses to
  trivial at N=1 or runs uniformly with the complexity inert across 1 -> 2+.
- Write as if more are coming, but only implement one (extensible seams,
  single concrete case). Defer capacity features until they're an observed
  problem ("no pagination for now; let's make it be a problem first").

## Security instincts

- Secrets ride the established channel (external-secrets -> env vars). Never
  decrypt or re-derive what the environment already provides; verify without
  exposing (compare lengths, "don't burn the secret"); never out-of-band.
- Classify precisely what is secret before designing custody (a PKCE public
  client id is committable with a cited doc comment; Slack IDs are not
  secrets; private channel names are). Ask where the keys actually live and
  whether the store becomes a rich target.
- Least-privilege arguments must quantify the actual permission delta; if two
  apps are identical but for the name, separation bought nothing: consolidate.
  But match granted scopes to the real working set; speculative trimming that
  forces repeated privileged re-grants is the wrong trade.
- Writes impossible by default against live data: read-only creds, fail-closed
  write guard at the narrowest chokepoint (covering future paths), env-var
  kill switch on risky always-on behavior, price the blast radius before merge.
- Platform SSO edge (Okta at Envoy) over roll-your-own auth, always. Infra
  that cannot weld onto the existing auth edge is disqualified.
- Calibrate to the actual threat model: no privacy scaffolding for uniformly
  work-scoped data, no manufactured permission objections for org-visible
  internal tools; but plaintext credential transmission is challenged on sight.

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
