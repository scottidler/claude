# Implementation notes: DM resolution and pipeline glue

Append-only. Design doc: `docs/design/2026-09-17-dm-resolution-and-pipeline-glue.md`.

## Phase 0a: re-pin the baseline; add a replay mode

### Design decisions
- The snapshot stores full payloads, not the scored rows — `replay/slackrecall.py:walk` —
  the scored rows clip `target` to 60 and `text` to 90 chars, so replaying them would hand
  the guard a different body than the one that was posted. The doc said "replays committed
  payloads"; this is what that requires.
- Snapshot named `rows-0a.json` — matches criterion 3's phrase "Phase 0a's committed rows
  file" and the `--from-rows` flag, and does not collide with `rowsFinal.json`, which is
  chunk D's scored record.
- Posts sorted by `(session, tool_name, tool_input)` — `replay/slackrecall.py:walk` —
  `rglob` returns filesystem order, so a re-walk reshuffles. The gate only asks for equal
  counts; the sort buys a byte-identical comparison, which is a stronger check for free.
- `deny_class()` added as a named function rather than inline grepping —
  `replay/slackrecall.py:deny_class` — Phase 3's decision rule scopes to TARGET, so the
  three deny families have to be separable by the driver, not by eye.
- Converted to `argparse` with a positional `out` plus `--guard` — the old interface read
  `sys.argv[2]` for the guard path, which cannot carry two more modes. Space-separated
  hyphenated flags per `rules/cli.md`.

### Deviations
- **The doc's "`slackrecall.py` needs `WINDOW = 3` (it ships `WINDOW = 12`)" was already
  stale when 0a ran.** Commit 1c6ccf2 (round 3's fold) had already set `WINDOW = 3`.
  Verified, not assumed: `32:WINDOW = 3`. No change made.
- Implementation notes are committed per phase rather than only with the final-phase
  commit, which is what the skill's own "append once per phase as part of the commit prep"
  implies. The design doc's status flip still rides the last commit alone.

### Tradeoffs
- Kept the driver a single script with modes rather than splitting walk and replay into two
  files: one script with modes is the `rules/taste.md` preference, and the two halves share
  `verdict`, `typed_prompt` and the scratch-`HOME` isolation.
- No structured logging added. `rules/logging.md` exists for diagnosable services; this is a
  measurement script in a `phase0` directory whose stdout IS its record, and the counts it
  prints are the artifact. Noted rather than silently skipped.

### Open questions
- None.
