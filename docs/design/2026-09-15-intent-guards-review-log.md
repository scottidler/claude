# Chunk D review log: intent guards

Minutes for `docs/design/2026-09-15-intent-guards.md`. Rounds are capped at 3 by `panel-round-guard.sh`.

## Pre-panel: `design-research` fold-in, 2026-09-15

Dispatched before the panel; reported after round 1 was already running, so the seats reviewed the pre-fold snapshot. Six corrections folded:

1. Item 8's `Environment=` vector is the wrong artifact. No unit file under `~/.config/systemd/user/` holds a secret value; the only names are `PATH` and `SCCACHE_*`. The credentials ride `EnvironmentFile=` into mode-0664 `/run/user/1000/{borg,cortex,sb-harvest}.env`, plus `~/.config/eratosthenes/digest.env`, `~/.cache/okta/tokens.json` and `~/.cache/slack/token.json` (singular).
2. The `Read` deny's interaction with `Read(**)` in `permissions.allow` is unproven, so it became a Phase 0 gate instead of an assumption.
3. "An allowlisted skill is active" is not implementable: no payload field, and the only transcript signal has no end marker. Refused in both places it appeared.
4. Chunk B handed this chunk an open hole the draft missed entirely: `'echo' $GH_TOKEN` allows while `"echo" $GH_TOKEN` denies, because `mask_squote` erases the verb before an unanchored regex sees it. Now Phase 1, ahead of every new rule.
5. The two exempt Slack ids cannot be resolved from the cache (`#clipboard` is a private single-member channel, absent from the 823 `channels`), so both are hardcoded.
6. The write fence on `settings.json`, `agents/`, `skills/` is Bash-only; the Edit tool reaches them, proven by `f257ddb` and `ca3bfe8` inside this program.

One thing the dig got wrong, refuted by the panel in the same round: the `last-prompt` ordering claim, generalized from a session with one typed prompt. See M10.

## Round 1, 2026-09-15

Run dir `/tmp/review-panel/GOX7yywR/`. Architect (gemini-3.1-pro-preview) rc=0. Staff engineer (codex gpt-6-astra) rc=124 at the 10m cap mid-exploration, re-dispatched once at 18m, rc=0. 10 must-fix, 7 cheap wins, 2 defers, 8 rejected with measurements.

Five must-fix were re-verified in this session before folding, because each changes a predicate:

| finding | verification |
|---|---|
| M1 PUBLIC-REPO's commit half is inert on its founding incident | the incident is one Bash call, `git add ... && git commit`, so the index is empty at hook time |
| M3 LN denies its own legitimate shape | `realpath -m` on an existing link and on its target return the identical path |
| M4 INGEST misses the incident's shape | ran `stmts` on the loop body: the `$( )` ingest splits out with no loop keyword |
| M5 GH-WRITE's parser allows `-XDELETE` | `flag_value -X` returns empty for the attached form, `DELETE` for the separated one; `gh` parses both |
| M8 hooks go live on save | `~/.claude/hooks/*` are per-file symlinks into the working tree |

Folded without argument: M1, M2, M3, M4, M5, M6, M7, M8, M9, M10, C1 through C7. Nothing was dropped or deferred against a reviewer's wishes.

Two findings changed a decision rather than a predicate:

- **M6** is the sharpest of the round. `--broadcast`, `dm_mentioned` and `follow_ups` each reach recipients past the named target, so the Slack exemption became a bound on the full recipient set.
- **The STAGING Rec was attacked successfully on justification, not volume.** The deny's own recovery instruction (`git add docs/design && git commit`) permits the identical violation, so the rule cannot claim item 1. It narrowed to `-A`/`.`/`--all` justified purely as phantom prevention, and item 1 moved to Non-Goals with five measured predicates.

## Findings rejected in round 1, with the measurement

Recorded so round 2 does not re-derive them.

- **Architect's subagent-type predicate for item 1.** 569 denies of 882 subagent commits, 0 of 5 incidents; `agentType` is free-text across ~190 values and every incident is main-thread. Asserted without measurement.
- **The panel's own path-provenance predicate.** 820 denies, 4 of 5 incidents, precision ~0.5%.
- **Architect's claim that LN's cycle direction is backwards.** Wrong: target-ancestor-of-link is the cycle, and its counterexample (`ln -s .. parent_dir`) creates exactly the infinite path that froze the workstation.
- **Architect's DELETE-OUT expansion.** `gh issue delete` 0, `acli bitbucket` 0, `gh pr close` 28 but a closed PR reopens.
- **Architect's "extend PUBLIC-REPO to `~/repos/*/*`".** No repo outside `scottidler/` has an origin remote Scott owns.
- **Architect's "the `~/Claude` symlink deny is unrequested".** It is in `CLAUDE.md`; both seats found traceability.
- **Staff's "INGEST loses loop context" as a general claim.** The `for` and `xargs` forms each emit one statement carrying both the loop and the ingest; only the command-substitution shape is affected.

## Process notes for later chunks

- **Do not dispatch the panel while a research fold-in is still outstanding.** The live doc moved 194 lines while round 1 ran, both seats reviewed the snapshot, and one of the round's findings exists only because the fold introduced a claim mid-review. Land every fold-in first, then snapshot, then dispatch.
- **A predicate written from a man page is not measured.** M3 and M5 would both have been caught by running the command once. The doc's own rule says every predicate is measured before it ships; the draft applied that to fire counts and not to the predicate's own mechanics.
