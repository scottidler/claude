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
Each is corroborated against the official tracker
(`github.com/google-antigravity/antigravity-cli`) below — all cited issues are
**OPEN** as of 2026-06-20 against agy **1.0.10**.

- **Silent model downgrade.** `--model` was *added* in agy **1.0.5** (issue
  [#83](https://github.com/google-antigravity/antigravity-cli/issues/83)), so the
  old "`--model` is ignored in `-p`" framing is now stale — the flag works. The
  live hazard is what #83's comments document: `--model` takes the **exact display
  label**, not the API slug (`--model=gemini-3.1-pro-high` → "model no longer
  available"; you must pass `--model "Gemini 3.1 Pro (High)"`), and the current
  behavior is **"if model is valid route to it, else use the default model"** — a
  mistyped/stale label **silently downgrades to the default with no error**.
  `script.sh` still drives the model via `~/.gemini/antigravity-cli/settings.json`;
  verify the label there against `agy models`.
- **`-p` buffers / hangs on non-TTY, and `--print-timeout` is unreliable.** In
  print mode against a non-TTY (pipe, redirect, subprocess — i.e. every way this
  skill calls it), agy emits **zero bytes** until the very end, so a slow/hung
  model is indistinguishable from a dead one until the wall-clock `timeout` kills
  it. "No content" is the expected shape of a hang, not a crash. Heavily
  corroborated upstream:
  [#76](https://github.com/google-antigravity/antigravity-cli/issues/76) (canonical
  — author migrated ~10 orchestration commands off gemini-cli, all silently empty,
  **rolled back to gemini-cli**; presents as empty-exit-0 on Windows, **indefinite
  hang on macOS**),
  [#408](https://github.com/google-antigravity/antigravity-cli/issues/408),
  [#318](https://github.com/google-antigravity/antigravity-cli/issues/318),
  [#187](https://github.com/google-antigravity/antigravity-cli/issues/187), and the
  predecessor repo
  [google-gemini/gemini-cli#27466](https://github.com/google-gemini/gemini-cli/issues/27466).
  **Correction to the earlier "`--print-timeout` only resets on activity" claim:**
  the tracker does NOT support that mechanic and reports it broken in two opposite
  directions — [#266](https://github.com/google-antigravity/antigravity-cli/issues/266)
  finds a **hardcoded 5-minute kill** (`printmode.go:263 timed out after N polls`)
  that triggers *because* `<thinking>` chunks aren't emitted as user-facing
  `ModifiedResponse`, so it does NOT extend while the model reasons; #76's macOS
  comment finds `--print-timeout` **non-functional the other way** (passing 230s/45s
  didn't bound a 17-min hang). Net: treat `--print-timeout` as unreliable and rely
  on the script's own wall-clock, not agy's.
- **Wall-clock kill.** `script.sh` wraps agy in `timeout` (`ARCHITECT_WALL_CLOCK`).
  On overrun agy is killed and the script exits **124** with:
  `error: agy exceeded the <WALL_CLOCK> wall-clock limit and was killed — no review was produced.`
- **No read-only / plan-mode equivalent.** Unlike the gemini path's
  `--approval-mode plan` hard-block, agy has no non-interactive read-only mode
  (open feature request
  [#45](https://github.com/google-antigravity/antigravity-cli/issues/45)), which is
  why `persona.md` is the *sole* enforcer of read-only behavior in this skill.

## What to capture for each incident

Record as much of this as is available — the exit code alone usually narrows it:

| Signal | Where | Meaning |
|---|---|---|
| **exit code** | `script.sh` return | `0`+empty = agy returned nothing; `124` = wall-clock kill (hang); `127` = agy not found; `2` = bad args / mode-detect fail |
| **the "running" line** | stderr: `architect: agy review running — pid $$` | present = reached the agy call; absent = failed earlier (args/agy-missing) |
| **wall-clock message** | stderr | confirms the `124` hang path |
| **model label** | `~/.gemini/antigravity-cli/settings.json` vs `agy models` | mismatch = silent-downgrade suspect |
| **PIDFILE** | `/tmp/architect-agy.pid` (or `$ARCHITECT_PIDFILE`) | alive = still running; gone = exited |
| **stdout length** | captured output | 0 bytes with exit 0 = empty-return (distinct from hang) |
| **driver relay** | if a subagent ran the skill | subagents must `SendMessage`; an idle with no message suggests the skill returned empty and the agent never surfaced it |

Fastest reproduction with full diagnostics:

```bash
cd <repo-with-the-doc>
~/.claude/skills/architect-agy/script.sh <doc-path> 2>&1 | tee /tmp/architect-agy-run.log; echo "exit=$?"
```

## Incidents (most recent first)

### 2026-06-20 — upstream tracker survey: the local pathologies are confirmed bugs in agy itself
- **Context:** searched the official issue tracker
  (`github.com/google-antigravity/antigravity-cli`, agy 1.0.10) for the three
  shortcomings this skill had self-diagnosed, to confirm they are upstream bugs and
  not local misconfiguration.
- **Findings (all issues OPEN):**
  - **`-p` no-output / hang on non-TTY — confirmed, multiple reporters.** The
    canonical report
    [#76](https://github.com/google-antigravity/antigravity-cli/issues/76) describes
    exactly our failure: a headless caller capturing agy's stdout gets nothing; the
    author **migrated ~10 multi-agent orchestration commands off gemini-cli, found
    every one silently empty, and rolled back to gemini-cli** — the same decision we
    made. Root-caused by commenters as an `isatty()` gate on the emission path;
    presents as empty-exit-0 on Windows and **indefinite hang on macOS** (killed
    after 17 min), which matches our exit-124 wall-clock kills on Linux. Dupes:
    [#408](https://github.com/google-antigravity/antigravity-cli/issues/408),
    [#318](https://github.com/google-antigravity/antigravity-cli/issues/318),
    [#187](https://github.com/google-antigravity/antigravity-cli/issues/187),
    [google-gemini/gemini-cli#27466](https://github.com/google-gemini/gemini-cli/issues/27466).
  - **Model selection — partially evolved.**
    [#83](https://github.com/google-antigravity/antigravity-cli/issues/83) shows
    `--model` was added in 1.0.5 (so "ignored in `-p`" is stale), but confirms the
    exact-display-label requirement and the **silent downgrade to default on a bad
    label** — our real hazard.
  - **`--print-timeout` — confirmed broken, but our "resets only on idle"
    explanation was wrong.**
    [#266](https://github.com/google-antigravity/antigravity-cli/issues/266) reports
    a **hardcoded 5-min kill** during long `<thinking>` blocks (the timeout does NOT
    extend while the model reasons) — the inverse of our framing — while #76's macOS
    comment reports it not bounding a hang at all. Corrected in the pathologies
    section above.
  - **No headless read-only mode —** open FR
    [#45](https://github.com/google-antigravity/antigravity-cli/issues/45),
    explaining why `persona.md` must be the sole read-only enforcer here.
- **Status:** RESEARCH — corroborates the buffering/hang and model-label hazards as
  genuine upstream bugs; corrects the timeout mechanic. No code change; doc-only.

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
