# Phase 0 evidence: harvested artifacts

Two corpora this doc's phases depend on, both harvested off tmpfs on 2026-09-17 before a reboot could take them. Both are PINNED: they are the denominator for a measurement, and re-walking the live session tree moves the denominator.

## `replay/` : the Phase 3 TARGET corpus

Chunk D's Slack replay harness. Addendum A recorded it as "lived in a session scratchpad on tmpfs and is gone". It was not gone.

| file | what it is |
|---|---|
| `rowsFinal.json` | **evidence of what chunk D measured, NOT a comparison arm.** 216 rows, 26 denies = 9 TARGET + 17 body-file replay artifacts, md5 `5ade36f7fead9c5973b2398a2cbe6473`. See trap 4: today's guard scores differently |
| `slackrecall.py` | the replay driver. `python3 slackrecall.py <rows-out.json> [/path/to/guard.sh]` |
| `variantA.sh` | the two-condition rule as of the harvest. `PROMPT_WINDOW=3`, recipient loop wrapped in `if ! posting_intent`. **NOT the shipped guard, see the third trap** |
| `variantB.sh` | the per-recipient prototype, loop UNWRAPPED at `:621-630`. The starting point for both Phase 3 variants |
| `lib.sh` | symlink to the repo's `HOME/.claude/hooks/lib.sh`. **Both variants source `$HOOKS/lib.sh` at `:142` and deny 100% of inputs without it** (measured: 237 posts, 0 allow, 237 deny, every one "lib.sh is unreadable"). The original harvest directory had this symlink and the first harvest dropped it |
| `windowdist.py` | the `PROMPT_WINDOW` distance study |

**Four traps, all load-bearing. Trap 3 came from panel round 1, trap 4 from running the harness during round 2.**

1. **`slackrecall.py` on disk carries `WINDOW = 12`. `rowsFinal.json` was produced at `WINDOW = 3`.** Set it to 3 or the baseline does not reproduce. Verified by counting `" || "`-joined turns per row: `rowsFinal.json` max is 3.
2. **It reads the LIVE `~/.claude/projects` tree**, so a re-run today yields more than 216 rows. Compare against `rowsFinal.json`, do not regenerate it.
3. **`variantA.sh` is NOT the shipped guard.** `variantA.sh:354-356` greps the raw prompt; the shipped `slack-post-guard.sh:396-405` pipes through `sed 's/<[^>]*>/ /g'` first to strip harness tags, and its own comment measures 58 of 400 sampled transcripts carrying the `<command-message>` wrapper. Re-derive the baseline arm from the guard on disk. Comparing a post-fix variant against this pre-fix copy invalidates the measurement.

4. **`rowsFinal.json` does not reproduce against today's guard, and that is not a bug in the harness.** Measured 2026-09-17 with the repaired driver:

```
pinned  rows=216 deny=26 TARGET=9 multi-stmt=0
today   rows=236 deny=34 TARGET=8 multi-stmt=9
```

   Two causes: the corpus grew (trap 2), and the guard gained a multi-statement rule AFTER this baseline was made. So the baseline is a record of chunk D's measurement, not something a post-fix variant can be diffed against. Phase 0a re-pins a corpus snapshot and re-measures today's shipped guard against it.

**`slackrecall.py` was patched on harvest, then REWRITTEN after panel round 2. The round-1 shape was wrong four ways; the file's own header records them so nobody re-derives it.**

- The original `rmtree`'d `$HOME/.cache/slack/sent-ledger` once per row: the LIVE ledger (`slack-post-guard.sh:113`), destroyed 216 times per replay.
- The round-1 fix added a `REPLAY_LEDGER` env var. Useless: the guard hard-codes `LEDGER` and reads no such variable, so the guard kept writing reservations into the live ledger while the per-row reset stopped touching the one it used. It also turned `REPLAY_LEDGER=` (set, empty) into `rmtree('.')`, and its lexical equality check was bypassed by `..` or a symlinked parent. It additionally raised on `{}`, which IS the guard's allow (`:139`), so it died on the first of 190 allows.
- **The shape that works:** isolate through `HOME`. The guard's only `$HOME` uses are `IDS` (`:112`), `LEDGER` (`:113`) and a `~/` body-file expansion (`:248`), so a scratch `HOME` holding a copy of the ids cache redirects the ledger with no edit to the guard and no variable it does not read. Verified: live ledger 10 entries before a full run and 10 after.

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

**Scoring protocol, and it is not optional.** Score each record at ITS OWN occurrence: the token starts at `context[offset + 1]`, and `offset` points at the `/`. Do NOT run the matcher across the window and count hits. 435 of the 2,004 records carry more than one `/token` in their window, 428 of them false positives, so the per-window reading returns entirely different numbers (a faithful `dSt` port scores 6/583 and 77/1421 instead of 0 and 0) and makes the doc's criterion unreachable.

## Still to be produced by Phase 0

`evidence.md`, carrying the answers to the four spikes: 0a (a committed rows snapshot plus a `--from-rows` replay mode), 0b (the `UserPromptSubmit` / `prompt.submit` probes), 0c (the six dispatch cells), 0d (mid-phase wake and worker reaping). Every answer is an observed log line or tool result, never an inference from the bundle.

0a also commits its rows file here. Until it exists, every count in this directory drifts: measured on one afternoon, the live tree gave 236 posts, then 237, then 239, then 240.
