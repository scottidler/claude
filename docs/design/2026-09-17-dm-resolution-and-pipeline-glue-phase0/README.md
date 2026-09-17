# Phase 0 evidence: harvested artifacts

Two corpora this doc's phases depend on, both harvested off tmpfs on 2026-09-17 before a reboot could take them. Both are PINNED: they are the denominator for a measurement, and re-walking the live session tree moves the denominator.

## `replay/` : the Phase 3 TARGET corpus

Chunk D's Slack replay harness. Addendum A recorded it as "lived in a session scratchpad on tmpfs and is gone". It was not gone.

| file | what it is |
|---|---|
| `rowsFinal.json` | **the pinned baseline.** 216 rows, 26 denies = 9 TARGET + 17 body-file replay artifacts. Reproduces chunk D's acceptance criterion 3c exactly. md5 `5ade36f7fead9c5973b2398a2cbe6473` |
| `slackrecall.py` | the replay driver. `python3 slackrecall.py <rows-out.json> [/path/to/guard.sh]` |
| `variantA.sh` | the two-condition rule as of the harvest. `PROMPT_WINDOW=3`, recipient loop wrapped in `if ! posting_intent`. **NOT the shipped guard, see the third trap** |
| `variantB.sh` | the per-recipient prototype, loop UNWRAPPED at `:621-630`. The starting point for both Phase 3 variants |
| `windowdist.py` | the `PROMPT_WINDOW` distance study |

**Three traps, all load-bearing. The third was found by panel round 1.**

1. **`slackrecall.py` on disk carries `WINDOW = 12`. `rowsFinal.json` was produced at `WINDOW = 3`.** Set it to 3 or the baseline does not reproduce. Verified by counting `" || "`-joined turns per row: `rowsFinal.json` max is 3.
2. **It reads the LIVE `~/.claude/projects` tree**, so a re-run today yields more than 216 rows. Compare against `rowsFinal.json`, do not regenerate it.
3. **`variantA.sh` is NOT the shipped guard.** `variantA.sh:354-356` greps the raw prompt; the shipped `slack-post-guard.sh:396-405` pipes through `sed 's/<[^>]*>/ /g'` first to strip harness tags, and its own comment measures 58 of 400 sampled transcripts carrying the `<command-message>` wrapper. Re-derive the baseline arm from the guard on disk. Comparing a post-fix variant against this pre-fix copy invalidates the measurement.

**`slackrecall.py` was PATCHED on harvest, twice, and neither change is cosmetic.**

- The original pointed `LEDGER` at `$HOME/.cache/slack/sent-ledger` and `shutil.rmtree`'d it once per replayed row. That is the LIVE ledger (`slack-post-guard.sh:113`), the only thing ruling out duplicate posts, and the guard fails closed when it is unwritable. A 216-row replay destroyed live duplicate-post protection 216 times. It now defaults to a scratch path via `$REPLAY_LEDGER` and REFUSES to run against the live one.
- The original caught a parse failure and returned `allow`, so a crashed or malformed guard scored as permissive. It now raises.

The per-row ledger clear itself is correct and stays: without it, replaying a year of traffic in one minute makes every repeated body look like a RESEND.

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
