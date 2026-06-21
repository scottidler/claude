# Architect (agy) Failure Log

Running log of `/architect` failures since the **gemini -> agy (Antigravity)**
migration. The recurring symptom: a review is requested but **no review content
comes back** - the run goes quiet / a subagent driving the skill goes idle with
nothing relayed. Collecting concrete instances here so we can root-cause later.

This is the agy-era companion to `limitations.md` (which documents the older
gemini-cli failure modes: sandbox jail, ripgrep fallback, absent shell). Those are
a different backend; keep agy incidents here.

## Known agy pathologies (from `script.sh` header — the usual suspects)

When a run produces no review, it is almost always one of these. Capture which.

- **Silent model downgrade.** agy ignores `--model` in `-p` mode and reads its
  model ONLY from `~/.gemini/antigravity-cli/settings.json` by **exact display
  label**. A wrong/stale label silently downgrades to a weaker tier (or misbehaves)
  with no error. Check the label in that settings file against `agy models`.
- **`-p` buffers all output to the end.** agy's print mode emits nothing until the
  very end; `--print-timeout` only resets on activity, so a hung model produces
  **zero output** right up until the wall-clock `timeout` kills it. "No content"
  is the expected shape of a hang, not a crash.
- **Wall-clock kill.** `script.sh` wraps agy in `timeout` (`ARCHITECT_WALL_CLOCK`).
  On overrun agy is killed and the script exits **124** with:
  `error: agy exceeded the <WALL_CLOCK> wall-clock limit and was killed — no review was produced.`

## What to capture for each incident

Record as much of this as is available — the exit code alone usually narrows it:

| Signal | Where | Meaning |
|---|---|---|
| **exit code** | `script.sh` return | `0`+empty = agy returned nothing; `124` = wall-clock kill (hang); `127` = agy not found; `2` = bad args / mode-detect fail |
| **the "running" line** | stderr: `architect: agy review running — pid $$` | present = reached the agy call; absent = failed earlier (args/agy-missing) |
| **wall-clock message** | stderr | confirms the `124` hang path |
| **model label** | `~/.gemini/antigravity-cli/settings.json` vs `agy models` | mismatch = silent-downgrade suspect |
| **PIDFILE** | `/tmp/architect.pid` (or `$ARCHITECT_PIDFILE`) | alive = still running; gone = exited |
| **stdout length** | captured output | 0 bytes with exit 0 = empty-return (distinct from hang) |
| **driver relay** | if a subagent ran the skill | subagents must `SendMessage`; an idle with no message suggests the skill returned empty and the agent never surfaced it |

Fastest reproduction with full diagnostics:

```bash
cd <repo-with-the-doc>
~/.claude/skills/architect/script.sh <doc-path> 2>&1 | tee /tmp/architect-run.log; echo "exit=$?"
```

## Incidents (most recent first)

### 2026-06-20 — design-doc review via subagent: agy hung, SIGKILLed twice (exit 124), zero output
- **Context:** Driving the skill from a background subagent (`architect-review`,
  general-purpose) to Design-Review
  `tatari-tv/github-actions/docs/design/2026-06-20-rust-cli-release-reusable.md`
  with **three extra `--add-dir` workspaces** (marquee, whitespace, the survey
  dir) and a **broad 6-target verification** prompt. A parallel `staff-engineer`
  subagent (codex) on the same doc returned its full review normally.
- **Symptom:** first delivery to the parent was an `idle_notification` with **no
  review content**.
- **Exit code / stderr:** agy **hung and was SIGKILLed twice** — first at
  `script.sh`'s internal 10m wall-clock, then at a 15m `ARCHITECT_WALL_CLOCK`
  override — **exit 124 both times, zero output**.
- **Root cause:** the documented **`-p` end-buffering / (High)-variant grind**. An
  actively-reasoning Pro model ("Gemini 3.1 Pro (Low)") on a **large multi-repo
  prompt** (6 targets, 3 `--add-dir` repos) emits nothing until the end, so it
  presents as a dead hang and the wall-clock kills it before any output lands.
  **agy itself was healthy** — a trivial smoke prompt returned in seconds and the
  doc + all repos resolved fine. NOT a model-label downgrade and NOT an agy outage.
- **Mitigation that worked:** **narrow scope** — drop the three extra `--add-dir`
  repos (verify only files in the doc's own repo) and cut the prompt to the
  load-bearing questions. The review then completed and returned in full. Cost: the
  Architect did NOT verify the cross-repo claims (marquee's current shape, the
  whitespace REL-1 source, the survey counts); those need a separate focused pass.
- **Lead (deal-with-later):** failure scales with prompt size x workspace count,
  and `-p` end-buffering means a killed run yields **no partial output to salvage**.
  Candidate fixes: lower the reasoning tier for broad prompts; raise the default
  wall-clock only when scope is large; or have the skill/driver **split a broad
  multi-repo review into several narrowly-scoped agy calls** rather than one grind.
- **Status:** ROOT-CAUSED (characterized). Recurring per user since gemini -> agy;
  this is the first instance with the exit code + mechanism captured.
- **Confirmation (same day, round-2 review):** re-ran with the narrow-scope
  mitigation - doc + the one repo's files only, NO extra `--add-dir` repos. agy ran
  to completion: **exit 0, no SIGKILL, no timeout**, stayed on the in-repo files and
  did not range cross-repo. This confirms the root cause (broad scope x workspace
  count drives the `-p` grind past the wall-clock) and that the mitigation works:
  **keep `/architect` runs scoped to a single repo; for cross-repo verification, run
  several narrow passes rather than one wide one.**

### 2026-06-20 — single-repo design review via subagent: first agy run hung (killed at 10m), retry succeeded
- **Context:** Driving the skill from a background subagent (`architect-review`,
  general-purpose) for a Design Review of
  `scottidler/second-brain/docs/design/2026-06-20-oracle-trace-availability.md`.
  **Single repo, NO extra `--add-dir`**, default review prompt. A parallel
  `staff-engineer` subagent (codex) on the same doc returned its full review normally.
- **Symptom:** first agy run produced no review; **hung and was killed at the 10m
  wall-clock**. The subagent retried and the **second run completed and returned the
  full review**.
- **Exit code / stderr:** not captured at the parent — the relay only reported
  "first agy run hung at the 10m limit and was killed; retry succeeded." Consistent
  with the `124` wall-clock-kill path (the `-p` end-buffering hang shape).
- **Diagnosis:** notable because it hung at **narrow (single-repo) scope**, which the
  prior 2026-06-20 incident's conclusion ("broad scope x workspace count drives the
  grind") does NOT explain. Points instead at pathology #3 (clean-slate / transient
  agy flakiness) and/or an **orphaned-`agy` proc holding the global settings.json
  lock** from an earlier run — both consistent with "first attempt hangs, retry on a
  freed lock succeeds." Not root-caused for this instance (no pre-flight `ps` /
  pidfile capture). Reinforces the standing need for `script.sh` to pre-flight-kill
  stale `agy` procs and/or retry once automatically before surfacing a hang.
- **Status:** OPEN (retry-recovered; mechanism for the single-repo hang not confirmed).

<!-- Append new incidents above this line, newest first. Template:

### YYYY-MM-DD — <one-line symptom>
- **Context:** <doc, mode, how invoked (direct vs subagent), --dirs>
- **Symptom:** <what came back / didn't>
- **Exit code / stderr:** <exit N; key stderr lines>
- **Diagnosis:** <which pathology, or unknown>
- **Status:** OPEN | ROOT-CAUSED | MITIGATED
-->
