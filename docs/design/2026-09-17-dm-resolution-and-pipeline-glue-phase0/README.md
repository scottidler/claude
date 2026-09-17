# Phase 0 evidence: harvested artifacts

Two corpora this doc's phases depend on, both harvested off tmpfs on 2026-09-17 before a reboot could take them. Both are PINNED: they are the denominator for a measurement, and re-walking the live session tree moves the denominator.

## `replay/` : the Phase 3 TARGET corpus

Chunk D's Slack replay harness. Addendum A recorded it as "lived in a session scratchpad on tmpfs and is gone". It was not gone.

| file | what it is |
|---|---|
| `rowsFinal.json` | **the pinned baseline.** 216 rows, 26 denies = 9 TARGET + 17 body-file replay artifacts. Reproduces chunk D's acceptance criterion 3c exactly. md5 `5ade36f7fead9c5973b2398a2cbe6473` |
| `slackrecall.py` | the replay driver. `python3 slackrecall.py <rows-out.json> [/path/to/guard.sh]` |
| `variantA.sh` | the SHIPPED two-condition rule. `PROMPT_WINDOW=3`, recipient loop wrapped in `if ! posting_intent` |
| `variantB.sh` | the per-recipient prototype, loop UNWRAPPED at `:621-630`. The starting point for both Phase 3 variants |
| `windowdist.py` | the `PROMPT_WINDOW` distance study |

**Two traps, both load-bearing.**

1. **`slackrecall.py` on disk carries `WINDOW = 12`. `rowsFinal.json` was produced at `WINDOW = 3`.** Set it to 3 or the baseline does not reproduce. Verified by counting `" || "`-joined turns per row: `rowsFinal.json` max is 3.
2. **It reads the LIVE `~/.claude/projects` tree**, so a re-run today yields more than 216 rows. Compare against `rowsFinal.json`, do not regenerate it.

It also `shutil.rmtree`s `~/.cache/slack/sent-ledger` before every post. Keep that: without it, replaying a year of traffic in one minute makes every repeated body look like a RESEND.

**Not harvested:** the first-cut guard variant (recipient named in the CURRENT turn, no `posting_intent`). It exists in no file. Chunk D's "79 denies in 216" cannot be re-derived from what survives, and this doc does not restate it as a live measurement.

## `inline-token/` : the Phase 5 matcher fixtures

Every `/token` occurrence matching a live skill name, across 9,899 deduped typed prompts, 2026-06 through 2026-09.

| file | what it is |
|---|---|
| `fixtures.json` | **the pinned fixture set.** 2,004 records: 1,421 false positives + 583 survivors. Each carries `date`, `token`, `label`, `offset`, `context` (a 100-char window) |
| `scan.py` | typed-prompt extraction from `~/.claude/projects` |
| `cmds.py` | position-0 `<command-name>` extraction |
| `m2.py`, `m4.py` | the classifier and the 70-row hand-labeling sample (`random.seed(7)`) |
| `skillnames.json` | the 122 installed skill names as measured |

Label distribution:

```
code-span       832
path-glued      544
url              36
path-continues    8
filename-ext      1
                ----
false positives 1421
survivor         583
```

**`prompts.json` is deliberately NOT committed.** It is 11 MB and it is the full typed-prompt corpus. `fixtures.json` carries only the 100-char window around each match, which is what the matcher is tested against. Scanned for credential-shaped content before commit: zero hits on token, key, JWT and private-key patterns. The 2,020 lines matching `token` are the JSON field name.

**The scripts are provenance, not runnable as committed:** `scan.py` and `m2.py` read `$TMPDIR/prompts.json`, which is not here. `fixtures.json` is the self-contained artifact.

## Still to be produced by Phase 0

`evidence.md`, carrying the answers to the three spikes: 0a (baseline reproduction), 0b (the six `UserPromptSubmit` / `prompt.submit` probes), 0c (the six dispatch cells). Every answer is an observed log line or tool result, never an inference from the bundle.
