# Phase 3 evidence: measure the TARGET variants

Run 2026-09-17 on desk.lan. Design doc: `docs/design/2026-09-17-dm-resolution-and-pipeline-glue.md`.

Every block below is an observed command output pasted verbatim, with one
documented exception: a single em-dash inside a quoted prompt window is written
as `[emdash]`, because this file is on `.otto.yml`'s em-dash lint list. The
corpus itself is unmodified.

**Verdict: neither candidate variant clears the bar. Phase 4 is dropped, measured.**

## The prerequisite, confirmed before anything ran

```
$ slack --version
slack v0.14.0

$ jq '{dms: (.dms|length), schema, legacyD: ([.users // {} | keys[] | select(startswith("D"))] | length), users: (.users|length), handles: (.handles|length)}' ~/.cache/slack/ids.json
{
  "dms": 232,
  "schema": 2,
  "legacyD": 18,
  "users": 120,
  "handles": 402
}
```

`dms` is live at 232 edges, `schema` is still 2, the 18 legacy `D…` keys under
`.users` are untouched. This is the first Phase 3 run that could resolve a `D…`
to a person.

## The three arms

`derive.py` builds them from the guard ON DISK. Variant A is a byte copy:

```
$ md5sum HOME/.claude/hooks/slack-post-guard.sh phase3/variant-a.sh
576fad060ac0197ae788217068f9a5d4  HOME/.claude/hooks/slack-post-guard.sh
576fad060ac0197ae788217068f9a5d4  docs/design/.../phase3/variant-a.sh
```

The harvested `phase0/replay/variantA.sh` is NOT the baseline arm. Its
`posting_intent` greps the raw prompt (`variantA.sh:354-356`); the shipped guard
pipes through `sed 's/<[^>]*>/ /g'` first (`slack-post-guard.sh:396-405`) to
strip harness tags. Scoring a post-fix variant against a pre-fix baseline would
measure the tag fix rather than the TARGET rule.

B and C both carry Phase 4's `resolve_names` change (the `dms` map replaces the
`.users` DM branch in BOTH jq programs) and differ only in the TARGET loop. B
adds `is_dm_spelling` and keeps `posting_intent` as the fallback for channels; C
drops `posting_intent` from TARGET entirely.

### The `dms` clause resolves a DM the shipped guard cannot

A post to Garrison LeRock's DM, prompt "ask Garrison LeRock about the valet
rollout", which carries no posting word:

```
--- variant a
slack-post-guard: no typed turn in the last 3 asked for a Slack post, and nothing in them names `D0C1NCDPES2`. A post goes where Scott asked for it. Ask him, or post to #clipboard.
--- variant b
ALLOW
--- variant c
ALLOW
```

## The measurement

Corpus `phase0/replay/rows-0a.json`, 241 posts, md5
`4c70205d279a87ad19c8f73159bf5e07`, through
`phase0/replay/slackrecall.py --from-rows`.

```
$ tally.py rows-a.json rows-b.json rows-c.json
rows-a: posts=241 allow=207 deny=34 TARGET=8  artifact=17 multi-statement=9 other=0
rows-b: posts=241 allow=201 deny=40 TARGET=14 artifact=17 multi-statement=9 other=0
rows-c: posts=241 allow=190 deny=51 TARGET=25 artifact=17 multi-statement=9 other=0
```

`tally.py` widens the TARGET class to cover both deny texts: the shipped "no
typed turn in the last ..." and the variants' "nothing in the last 3 typed turns
names ...". Both are the TARGET rule firing. The class is widened here rather
than by editing `phase0/replay/slackrecall.py`, which is a prior phase's
committed artifact.

**Bar: TARGET <= 8. B is 14, C is 25. Neither clears.**

### Variant A reproduces Phase 0a byte for byte

```
variant a: replay 2 byte-identical to replay 1  md5=f23c42e6230549396f4c62495d52f0b1
variant b: replay 2 byte-identical to replay 1  md5=7a13fe6d233f888d3978747daa80f6ff
variant c: replay 2 byte-identical to replay 1  md5=3fd5dbaabdad786cd9f0e3b2986f4cb7
```

`f23c42e6230549396f4c62495d52f0b1` is the md5 Phase 0a recorded for the shipped
guard's scored rows. The baseline arm is the shipped rule, confirmed twice: by
the file hash and by the replay hash.

### The live ledger was never opened

```
$ find ~/.cache/slack/sent-ledger -newermt '2026-09-17T16:00:00' | wc -l
0
```

Six full replays (1,446 guard invocations) plus the probes, and not one entry
was written. Newest live entry predates the run. The scratch-`HOME` isolation
holds, and `REPLAY_LEDGER` stays buried.

## What variant B introduces: 6 denies, 0 bought back

```
== rows-b: 6 TARGET denies introduced vs baseline, 0 baseline denies bought back
  [1] target='D01VB7QMKJ7'
      text='hey brian, need an approval from you as the `@tatari-tv/fe` codeowner on the tatari-skills'
      window='audit promote.py for those codex sub-claims\ncommit the desig || lets merge all of these one by one, including 285 || actually lets hold off merging the 285 and instead lets ping'
      session=71390a78-b72b-4204-b61d-7222a96dee65.jsonl
  [2] target='D03G74VF2T1'
      text='hey lin, need a `@tatari-tv/data-science` approval on the tatari-skills stack. `plugins/da'
      window=(same as [1])
      session=71390a78-b72b-4204-b61d-7222a96dee65.jsonl
  [3] target='D08UME8GC82'
      text='tantum, closing the loop: the access you gave worked. Daily Budgets Tech Spec has its head'
      window='Loose ends\n- 3 Tech Specs reviewed in Slack, never labelled\n || if was off || can you fix all of these'
      session=c640cd94-4d7c-44c5-addb-5dd5663400df.jsonl
  [4] target='D042EB42T1C'
      text='doing a tech spec cleanup: getting every TS labelled `eng-tech-spec` so they all list in o'
      window="yes update the doc || lets send a slack to each group of owners as DMs or Group DM || if you cant send multiple, send to the page's author"
      session=dbda303f-84a1-4b28-a18e-674990f96f3d.jsonl
  [5] target='D08UME8GC82'  (same body, window and session as [4])
  [6] target='D0B36NE6VFA'  (same body, window and session as [4])
```

Every one of the five distinct ids resolves through `dms` today:

```
D01VB7QMKJ7 -> UCM4U8327    brian            Brian Feldman
D03G74VF2T1 -> U5M9EJT6X    lin              Lin O'Driscoll
D08UME8GC82 -> U02E3K62PD1  tantum           Tantum Nilkaew
D042EB42T1C -> U02D81L6U1E  kyle.zou         Kyle Zou
D0B36NE6VFA -> U0B04QRHG0L  david.ontiveros  David Ontiveros
D0C0W882C93 -> U03839QPB4L  roman.pavlushkov Roman Pavlushkov   (already denied by the shipped rule)
```

So none of the six is a resolution failure, and `dms` bought back nothing. The
reason is structural: resolution only helps where the prompt NAMES the person
and the id failed to resolve, and `posting_intent` already allowed every one of
those. What a name-mandatory rule hits instead is the collective ask, "lets send
a slack to each group of owners as DMs or Group DM", which names nobody by
construction. Items 4, 5 and 6 are one such instruction fanned out to three
recipients.

**Variant B behaves identically under the harvested `variantB.sh` shape** (name
mandatory only when the cache resolves the recipient to more than its own
spelling), because all five ids resolve. The variant shape is not what produces
the 14.

## What variant C introduces: 17 denies

Six are B's. The eleven additional, each read:

```
  [1]  C0C11ND3SAV  mpdm-scott.idler--vlad.belik--andrii.bashuk-1
       window names "Vlad Belik" [emdash] the recipient spelling is the mpdm channel, never typed
  [2]  C0C11NDHZSM  mpdm with vlad, roman, dmitriy, serhii; same window
  [3]  C0C0ZGUP273  mpdm with vlad and roman; tech-spec-cleanup window
  [4]  '#ai-foundry' via `slack write '#ai-foundry' --edit`; window "yes, edit it to lead with slack-cli"
  [5]  C0AUBBY21S6  #ai-helpdesk; window says "send the announcement to #engineering" (a DIFFERENT channel)
  [6]  C0ACWPXHLPK  #ai-foundry; window ends "lets ping"
  [7]  C0AA8UBU5MX  #tech-spec-reviews; window "drop the quick missive to Mike in that thread"
  [8]  C0ACWPXHLPK  #ai-foundry; window "i didnt ask for a draft. I asked you to send it"
  [9]  json         from `slack write --at 7d --output json '#clipboard'`
  [10] json         from `... slack --version; slack write ... --output json ...`
  [11] json         from `... slack write --at ... --output json ...`
```

[7] and [8] are fixtures the shipped matrix asserts must ALLOW. [9], [10] and
[11] are a parser gap, not a rule: `WRITE_VALUE_FLAGS` (`slack-post-guard.sh:191`)
omits `--output`, so its operand `json` is read as the target and the actual
target `#clipboard`, which is exempt, never gets looked at.

## Corroboration: the shipped matrix, run against each arm

`slack-post-guard-test.sh` with the arm dropped in as `slack-post-guard.sh`:

```
=== variant a ===  pass=129 fail=0
=== variant b ===  pass=124 fail=5
=== variant c ===  pass=117 fail=12
```

Variant A at 129/0 is the third confirmation that the baseline arm is the
shipped guard. Variant B's five failures are one fixture-shape artifact (the
matrix cache predates `dms` and holds the legacy `.users` DM keys, which B no
longer reads) plus four DM ids the fixture cache deliberately cannot resolve.
Variant C additionally fails "a missive to Mike in a channel the prompt does not
name", "post it, where the target was named an earlier turn" and "I asked you to
send it", which are the corpus posts the first cut denied and the second
sufficient condition exists to allow.

## The three must-still-deny cases

The replay cannot answer this criterion. The corpus copy of the
`**MCP write test**` post went to `D01G4Q7AWLV`, which is `EXEMPT_DM`
(`slack-post-guard.sh:111`), so it allows by design, and the driver wipes the
ledger per post so no RESEND deny can ever appear. `must-deny.sh` asserts them
directly on a fixture HOME whose cache carries `dms`, so the recipient resolves
and TARGET passes: a deny that landed because the id no longer resolved would
prove nothing about whether TEST-TEXT and RESEND still bite.

```
$ ./must-deny.sh
  PASS  variant-a    MCP write test marker into a named DM
           slack-post-guard: the first line of a body reads as a test, and the recipients are not just #cli
  PASS  variant-a    2026-07-10 shakedown turn
           slack-post-guard: no typed turn in the last 3 asked for a Slack post, and nothing in them names
  PASS  variant-a    /cli-shakedown command wrapper
           slack-post-guard: no typed turn in the last 3 asked for a Slack post, and nothing in them names
  PASS  variant-a    duplicate body within the hour
           slack-post-guard: this exact body has already been sent to `D02020W2872` in the last hour, or a
  PASS  variant-b    MCP write test marker into a named DM
  PASS  variant-b    2026-07-10 shakedown turn
  PASS  variant-b    /cli-shakedown command wrapper
  PASS  variant-b    duplicate body within the hour
  PASS  variant-c    MCP write test marker into a named DM
  PASS  variant-c    2026-07-10 shakedown turn
  PASS  variant-c    /cli-shakedown command wrapper
  PASS  variant-c    duplicate body within the hour

12 passed, 0 failed
```

(Variants b and c print the same reason lines; they are elided above and
reproduce by running the script.)

## Reproducing

The scored rows are committed beside this file (`rows-a.json`, `rows-b.json`,
`rows-c.json`, md5s as listed above), so every count and every named deny
re-derives in a second without a replay:

```
python3 tally.py rows-a.json rows-b.json rows-c.json
```

They are NOT on the em-dash lint list, and deliberately: they quote the corpus
verbatim and the corpus contains em-dashes. Same reason `phase0/replay/rows-0a.json`
is off the list.

The full replay, from the guard on disk:

```
cd docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase3
python3 derive.py
cd ../2026-09-17-dm-resolution-and-pipeline-glue-phase0/replay
for v in a b c; do
  python3 slackrecall.py "$TMPDIR/rows-$v.json" \
    --guard ../../2026-09-17-dm-resolution-and-pipeline-glue-phase3/variant-$v.sh \
    --from-rows rows-0a.json
done
python3 ../../2026-09-17-dm-resolution-and-pipeline-glue-phase3/tally.py \
  "$TMPDIR"/rows-{a,b,c}.json
```

`derive.py` re-derives the arms from whatever `slack-post-guard.sh` says today,
so a later guard edit moves the baseline honestly instead of silently comparing
against a stale copy. The three counts above are pinned to the guard at
`576fad060ac0197ae788217068f9a5d4`.
