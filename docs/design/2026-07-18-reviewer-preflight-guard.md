# Reviewer preflight guard (architect / staff-engineer / review-panel)

**Status:** Idea / proposal, not built (verified still unbuilt 2026-07-22: no
preflight/typed-outcome logic in either script; the /tmp pidfile wart below is
also still present).
**Date:** 2026-07-18.
**Relates to:** the recovery layer this detection feeds is BUILT --
`HOME/.claude/agents/review-panel.md` Step 3.5 (commit `c185a48`, 2026-07-19):
on a credits/tokens/auth failure the panel re-runs that seat's persona on an
Anthropic model, labeled as a substitute. This doc is the detection layer;
Step 3.5 is the consequence.
**Trigger:** During a clyde implementation audit, the Staff Engineer (Codex) reviewer failed with "Your workspace is out of credits." The `review-panel` skill crashed mid-run and recovered to a single-reviewer pass instead of declining cleanly up front. We want a guard so the skills fail fast with a clean, typed message instead of wasting a full call.

## Goal

When a reviewer CLI cannot run (no auth, missing binary, unreachable, out of credits), the skill should report a clean typed reason and skip the expensive review call, rather than spinning up the full invocation (large prompt, high reasoning, retries) and belly-flopping partway.

## The one hard constraint

"Out of credits" is the only failure that cannot be detected without SOME call. Neither CLI exposes a free balance/quota endpoint. Everything else (auth present, binary present, endpoint reachable) is checkable for free. So a fully call-free guard can catch every failure mode EXCEPT the exact one that triggered this (credits).

That is acceptable because the credits rejection is instant: codex returned "out of credits" in ~2s, right after `SessionStart`, before generating a single token. The API rejects it up front. The real waste in the incident was the retries and the mid-run crash-recover, not the initial fast rejection.

## Primitives found (verified 2026-07-18)

- **codex** (v0.144.5): `codex login status` (free, auth state) and `codex doctor` (free: auth signals + HTTP reachability + exit code). Neither reports credits. `doctor` exit 0 even when the workspace is out of credits.
- **gemini** (0.49.0): no `doctor` / `login status` / `auth` subcommand. Only `mcp` and `-m`. Cheapest free signal is auth-token/env presence.

## Design: two tiers + shared helper

Put the classify-and-decline logic in ONE shared helper that all three skills call.

1. **Free preflight (zero calls):** `codex login status` / `codex doctor`; gemini auth-token presence + binary-on-PATH. Catches `NO_AUTH`, `CLI_MISSING`, `UNREACHABLE` before any call. Clean instant decline.
2. **Fast-fail on the real call:** wrap the actual invocation, match the CLI's known error strings (`out of credits`, quota, auth) into a typed reason, and on hit report a clean message with NO retries, NO flailing. Worst-case waste = one ~2s rejection.

Typed outcomes: `READY | NO_AUTH | NO_CREDITS | UNREACHABLE | TIMEOUT | CLI_MISSING`.

`review-panel` composes: preflight both, run the ready ones. SUPERSEDED
2026-07-19 (Scott: "use anthropic models for any codex missing tokens"): on
`NO_CREDITS`/`NO_AUTH` the panel does NOT degrade to "running Architect only";
it routes that seat to the Anthropic-model substitute per review-panel Step
3.5, before any wasted dispatch, with the typed outcome replacing Step 3.5's
post-hoc string matching. `TIMEOUT` and substantive failures still report as
failures (both docs agree). The standalone `/architect` and `/staff-engineer`
skills DO decline cleanly with the typed reason (the substitute rule is
panel-scoped); the caller can then substitute by hand if wanted.

## Bonus finding (latent wart, not the cause here)

`codex doctor` flagged mixed auth: a ChatGPT login AND an `OPENAI_API_KEY` env var, with HTTP reachability using API-key mode. This looked like a gh-token-style wrong-credential trap. Tested by re-running the codex probe with `OPENAI_API_KEY` unset (falls back to the ChatGPT login): STILL "out of credits." So both auth paths lead to the same exhausted workspace -- the mixed-auth was a red herring for the credits failure. Still worth having the preflight surface the mixed-auth signal generally, since it is a real config ambiguity.

## Also worth fixing while in here

The `review-panel` / `architect` / `staff-engineer` scripts `mktemp` their pidfiles/traces into `/tmp/` (`/tmp/architect.pid`, `/tmp/staff-engineer-*`), which is read-only under the command sandbox (`os error 30`), forcing sandbox-off runs. Move those under a sandbox-writable dir (`/tmp/review-panel` or `$TMPDIR`).
