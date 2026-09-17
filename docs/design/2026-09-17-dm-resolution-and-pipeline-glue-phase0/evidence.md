# Phase 0 evidence: DM resolution and pipeline glue

Run 2026-09-17 on desk.lan. Design doc: `docs/design/2026-09-17-dm-resolution-and-pipeline-glue.md`.

Every entry below is an observed command output pasted verbatim, never an inference
from the bundle. Scratch artifacts under `$TMPDIR/0a/`.

## 0a: re-pin the baseline, and give the driver a replay mode

**Verdict: PASS. Phase 3 has a pinned denominator and a deterministic replay.**

### The drift is live, not historical

Two full walks of the live `~/.claude/projects` tree, minutes apart in one session:

```
posts=240  allow=206  deny=34      (first walk)
posts=241  allow=207  deny=34      (second walk, same session)
```

Round 2 measured 236, then 237, 239, 240 over one afternoon. So a count taken at 0a
has moved by Phase 3, which is a cross-repo ship later. This is why 0a's deliverable
is a file, not a number.

### Today's shipped guard against the pinned snapshot

```
snapshot rows-0a.json  posts=241  md5=4c70205d279a87ad19c8f73159bf5e07
posts=241  allow=207  deny=34
  TARGET=8  artifact=17  multi-statement=9  other=0
     8  [target] no typed turn in the last 3 asked for a Slac
     6  [artifact] the body file /tmp/claude-1000/-home-saidler
     5  [multi-statement] this command carries 2 Slack posting stateme
     3  [artifact] the body file $S/blocks.json is unreadable,
     2  [multi-statement] this command carries 4 Slack posting stateme
     2  [artifact] the body file $f is unreadable, so the text
     1  [artifact] the body file $TMPDIR/upstream-sec.txt is un
     1  [multi-statement] this command carries 3 Slack posting stateme
     1  [multi-statement] this command carries 5 Slack posting stateme
     1  [artifact] the body file $TMPDIR/slack-drafts.md is unr
     1  [artifact] the body file $S/prec.json is unreadable, so
     1  [artifact] the body file $S/fixed.json is unreadable, s
     1  [artifact] the body file $S/bad.json is unreadable, so
     1  [artifact] the body file $S/$f.json is unreadable, so t
```

**Phase 3's baseline is TARGET=8.** The 17/8/9 split reproduces the round-2 measurement
exactly. `rowsFinal.json`'s `216/26/9/0` is chunk D's record and is NOT the target: the
guard gained the multi-statement rule after that file was cut.

### The gate: replays deterministically, twice, to the same counts

```
replaying rows-0a.json  posts=241  md5=4c70205d279a87ad19c8f73159bf5e07
posts=241  allow=207  deny=34
  TARGET=8  artifact=17  multi-statement=9  other=0        (replay 1)

replaying rows-0a.json  posts=241  md5=4c70205d279a87ad19c8f73159bf5e07
posts=241  allow=207  deny=34
  TARGET=8  artifact=17  multi-statement=9  other=0        (replay 2)
```

Stronger than the gate asks: the scored rows are byte-identical across both replays
(`f23c42e6230549396f4c62495d52f0b1`) and byte-identical to the walk that produced the
snapshot. `cmp` returns clean on both pairs.

### The live ledger was never opened

10 entries before the first run, 10 after four full runs (two walks, two replays). The
scratch-`HOME` isolation holds; `REPLAY_LEDGER` stays buried.

### The snapshot is the payloads, not the scored rows

`rows-0a.json` stores each post's full `tool_input` and its verbatim prompt window. The
scored rows clip `target` to 60 and `text` to 90 chars for reading, so they are a summary
and could never be replayed: the guard would be handed a different body. Posts are sorted
by `(session, tool_name, tool_input)` because `rglob` order is filesystem order, which is
what makes the byte-comparison above possible.
