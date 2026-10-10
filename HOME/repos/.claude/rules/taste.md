---
alwaysApply: true
load: always
---

# Design & Judgment Taste

Distilled from a forensic pass over all ~1,629 sessions (4,202 typed messages,
2026-05 through 2026-07): the recurring judgment calls Scott makes when
designing, reviewing, and shipping. Style rules live in `general.md` etc; this
file is how he DECIDES. Worked examples with verbatim quotes:
`~/repos/.claude/refs/design-exemplars.md` (read it before authoring or
reviewing a design doc).

Process-and-evidence sections (pipeline, design doc as source of truth, phasing,
evidence standards) live in `~/repos/.claude/refs/process-taste.md`: read it when
authoring or reviewing a design doc, executing a plan, or running a review.

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
