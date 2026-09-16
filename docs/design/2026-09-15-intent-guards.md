# Design Document: Intent guards for outward and irreversible actions

**Author:** Scott Idler
**Date:** 2026-09-15
**Status:** Implemented, with two acceptance criteria failing. All eight phases are built, committed and live; the two failures are rule-tuning decisions Scott owns, recorded under "Acceptance criteria: results" with the evidence and the options.
**Review Passes Completed:** 5/5, then a research fold-in, then panel rounds 1, 2, 3 and 4

> Panel round 4 ran 2026-09-15, ordered by Scott past the 3-round cap (`PANEL_ROUNDS_ORDERED_BY_SCOTT=4`) to review the round-3 fold, which no reviewer had read. Both seats returned "not ready to build". 8 must-fix, 3 cheap wins, 3 rejected, all folded below. Five of round 3's nine fixes verified clean; four needed another pass. Two of the findings are **live bypasses executed against the real endpoint**: `gh api -XDELETE -p -XGET /rate_limit` and `gh api -XDELETE --header "-XGET: x" /rate_limit` both send DELETE while the round-3 parse resolves GET and allows, because the hand-listed skip list omitted `--header`, `-p`/`--preview` and `--cache`. The skip list is now the complete `gh api --help` flag specification. The round also found LN's raw-paren fallback denying a legitimate corpus command (8 of 51 `ln -s` commands carry a paren, only 3 carry a structural `$(`), INGEST's step 2 short-circuiting the whole command, the `BULK_INGEST_ORDERED_BY_SCOTT` ceiling that was never compared, a `jq 'has(...)'` allowlist that admits arbitrary expressions, and the `git commit -i` row repeating the index omission the `-am` row had just been fixed for. Drift during the round: **0 lines**, the second clean round running. Minutes: `docs/design/2026-09-15-intent-guards-review-log.md`.
>
> Panel round 1 ran 2026-09-15 against the pre-fold snapshot (`/tmp/review-panel/GOX7yywR/`): 10 must-fix, 7 cheap wins, 2 defers, 8 findings rejected with measurements. All folded below. Five of the must-fix were re-verified in this session before folding, because each one changes a predicate: the commit half of PUBLIC-REPO reading an index that does not exist yet, `realpath -m` dereferencing an existing link, `stmts` splitting the ingest out of its loop, `flag_value` returning empty for `-XDELETE`, and `~/.claude/hooks/*` being per-file symlinks so a hook is live on save. The round also refuted one claim the research fold-in had just introduced (the `last-prompt` ordering), and produced two more measured item-1 predicates, both worse. Minutes: `docs/design/2026-09-15-intent-guards-review-log.md`.
>
> Passes 1 to 5 ran, then a `design-research` dig came back and corrected six things: item 8's `Environment=` target is measurably wrong, the `Read` deny has an unproven interaction with `Read(**)` in `permissions.allow`, the "active allowlisted skill" clause in the audit's prescription is not implementable, chunk B handed this chunk an open secret-guard hole that the draft missed entirely, the two exempt Slack ids cannot be resolved from the cache, and the write fence on `settings.json` is Bash-only rather than absolute. All six are folded in below. The panel's round 1 was dispatched against the pre-fold text, so its findings are reconciled against this version.

## Summary

Chunk D of the setup-audit program (`docs/design/2026-09-13-setup-audit-program.md`), covering audit item 6: the actions that reach outside this machine or cannot be undone, and the secret-leak vectors the echo guard does not cover.

The audit prescribes eight guards. Measured against the corpus before designing anything, **seven ship and one does not**: four hold as specified (`gh api` writes, public-repo leak, secret vectors, Slack posts), three need a different predicate than the verb they name (outward deletes, symlink cycle, vault ingest), and item 1, the unrequested-commit guard, ships nothing at all. Five predicates were derived for it and the best costs 820 denials to catch 4 of 5 known incidents against a 0.18% base rate. Scott ruled on 2026-09-15 to accept that gap. The blanket-staging rule proposed as a partial substitute is also dropped, because git already refuses to stage the only class it would have closed.

The chunk also carries one thing the audit did not list: a live bypass of `secret-echo-guard.sh` that chunk B handed over and the draft missed.

## Problem Statement

### Background

Chunks A through C built the enforcement layer: sandbox config, prose hooks, the `rm` rewrite (A), a shared quote-aware command parser and guard precision fixes (B), the panel round cap (C). Every guard so far protects the working tree or the release flow, both of which are recoverable.

Item 6 is the first chunk about actions that are not recoverable: a Jira key burned on a shared tracker, a Slack message read by a coworker, 163 notes in the vault, a branch-protection rule deleted on a work repo, personal material on a public GitHub remote, a token in a transcript.

### Problem

Eight action classes, measured over `~/.claude/projects` (2026-06-01 through 2026-09-12, 2,782 main-thread plus 2,077 subagent session files), each with prose coverage and no mechanical coverage:

| # | Class | Prescribed mechanism | Statements in window | Incidents |
|---|---|---|---|---|
| 1 | unrequested `git commit` | prompt-word match over the last 3 prompts | 2,832 commits, 590 residual denies | 5 explicit reactions |
| 2 | unasked Slack post | resolve target, block test text and resends | 64 posts through the two current MCP write tools; 12 residual denies | 2 confirmed, plus a 24-post burst |
| 3 | bulk vault ingest | deny looped or multi-URL `sb borg ingest` | 11 ingest statements | 1 (164 URLs -> 163 notes) |
| 4 | `gh api` repo/org writes | deny PATCH/PUT/DELETE on protection, rulesets, repo root, `gh repo edit` | 173 `gh api` writes, 6 on guarded surfaces | 2 |
| 5 | outward deletes | deny `acli ... delete`, confluence page delete, gmail delete/trash | 2 `acli delete`, 0 gmail deletes | 1 (SEC-2997) |
| 6 | symlink cycle | deny a link whose target resolves inside the link's parent | 112 `ln -s` statements | 1 (workstation froze) |
| 7 | public-repo leak | deny commits adding sensitive paths to a public remote | no coverage of any kind | 1 (history rewrite) |
| 8 | secret-leak vectors | extend `secret-echo-guard.sh`, add a `Read` matcher | 4 plausible live tokens after the guard shipped | 4 |

Source counts for the incidents: audit findings post, lens `incidents` sections 6 through 12. Statement counts re-derived in this session (method below), not inherited.

And none of these verbs merely lacks a guard: `permissions.allow` **pre-approves every one of them**, so today each runs without even a classifier prompt. `Bash(gh:*)` (`HOME/.claude/settings.json:203`), `Bash(ln:*)` (:601), `Bash(gws gmail *)` (:668), `Bash(git commit:*)` (:94), `Bash(git add:*)` (:93), `Bash(sb:*)` (:19), `Read(**)` (:379). A deny hook is the only layer left above them.

### Evidence: re-derived, and it changes the design

Every count in the table above was measured in this session by walking the corpus directly (`scratchpad/intent-scan.py`, `scan2.py`, `scan3.py`, `scan4.py`, `scan5.py`). Three results contradict the audit's prescription.

**1. The commit intent guard denies 590 and catches 2 of 5.**

The prescribed guard denies `git commit` unless one of the last 3 human prompts carries a commit-shaped word (`commit|ship|push|land|merge|pr|release|phase|execute`) or an allowlisted skill is active.

```
git commit statements, 2026-06..09:          2,832
  from subagents:                              880  (31%)
  no commit-word in the last 3 prompts:      1,520
    main-thread:                               640
    residual after a skill allowlist:          590
  same, authorization window = whole session:  318
```

Against the five sessions where Scott reacted with an explicit "I never said commit":

| session | commits | denied, last-3 window | denied, session-wide |
|---|---|---|---|
| `b908b4db` marquee 06-23 | 1 | no | no |
| `0cf83e1b` dotfiles 06-27 | 2 | no | no |
| `4f83442d` eratosthenes 09-04 | 2 | no | no |
| `2a4d6300` tmp 09-09 | 15 | 3 | 3 |
| `e2ca5bb5` otto 09-01 | 12 | 4 | 0 |

590 denials, 2 of 5 incidents. The mechanism fails four separate ways, and each one is visible in the transcripts:

- **The ask was to commit something else.** `0cf83e1b` 19:35, Scott: "commit this write a /handoff doc directly into manifest/docs/". Claude committed the `.age` file (asked) and then at 19:38 committed the handoff doc (not asked). Scott: "I did not ask you to commit the fucking design doc". A prompt-word guard sees "commit" and allows both.
- **The prompt is not from a human.** `4f83442d`'s three preceding "prompts" are `<teammate-message>` and `<task-notification>` records, which arrive as user-role turns. Any guard reading user turns treats machine traffic as human authorization.
- **Incidental vocabulary authorizes.** `b908b4db`'s preceding prompts are about building `/spaces` and `/users` endpoints and carry no commit ask; the word list matched anyway.
- **Subagents have no human prompt at all.** 880 commit statements come from subagent transcripts. `phase-implementer`'s contract is exactly one commit per phase. A prompt-intent guard denies every one of them, which breaks `/how-to-execute-a-plan` outright.

The measured failure is not "committed without being asked to commit". It is "committed an artifact that was not part of the ask". That is a path problem, not an intent problem, which is why item 1 is redesigned rather than built.

**2. The ingest guard as prescribed would not have caught the ingest.**

The 164-URL incident (`000985e0`, 2026-09-08) did not run `sb borg ingest` in a loop. At 00:32:22 Claude wrote a script with a heredoc, then at 00:32:40 ran it:

```
cat > "$S/ingest.sh" <<'EOF'
while IFS= read -r url; do
  out=$(sb borg ingest --tags claude anthropic data -- "$url" 2>&1); rc=$?
...
"$S/ingest.sh" "$S/batch1-rest.txt" "$S/batch1-ingest.log"
```

A `PreToolUse` guard matching `sb borg ingest` sees the command word `$S/ingest.sh` and allows it. Worse, chunk B's shared parser strips heredoc bodies on purpose (the manifest guard was firing on prose, 9 of 9), so the guard is blind to the script's creation too. The one visible statement is the single-URL test at 00:32:30, whose URL (`code.claude.com/docs/en/sessions`) does not appear in any Scott prompt: that clause, and only that clause, stops the sequence at step one.

**3. Guard-surface volume splits the eight items into two very different groups.**

```
gh api writes, 173 total:  pulls/issues 148 | other 19 | repo root 3 | rulesets 2 | protection 1
gh repo edit:                3
acli ... delete:             2 (one --help, one the SEC-2997 incident)
gws ... delete|trash:       10, all Drive, zero Gmail
ln -s:                     112, nearly all hook and config symlink installs
git add -A | add . :       454 (main 319, sub 135), flat: 108 / 129 / 115 / 102 by month
git commit -a:              65
git add -u:                 15
```

Items 4, 5, and 7 guard surfaces that fire a handful of times in four months, which is what a high-precision guard looks like. Items 1, 2, 3, and 6 guard surfaces with hundreds of legitimate statements, and each one needs a predicate sharper than the verb.

One live demonstration of that, from this session: the naive `acli.*delete` pattern matched `scan5.py`'s own regex text at 2026-09-15T19:41, inside a heredoc. Chunk B's parser exists for exactly this, and chunk D's guards source it or repeat the mistake.

### Goals

- Every action class in the table **except item 1** is denied by a hook or a permission entry, not discouraged by a sentence. Item 1 is uncovered by Scott's 2026-09-15 ruling, on measured precision; see Non-Goals.
- Each guard's predicate is measured against the corpus before it ships: fires, and which known incidents it catches.
- No guard infers human intent from word-matching a prompt. Where authorization matters, it is a named target or a named path, not a verb.
- Guards work in subagents, which originate 31% of commits and 40% of `rm -r`, except where the subagent is structurally the wrong place to deny.
- Every deny message names the allowed next action, so it cannot induce a retry loop (chunk B's `branch-pr-title-guard` lesson).
- Prose that a guard makes mechanical is deleted in the same phase that ships the guard.

### Non-Goals

- **`gh pr merge --admin`.** 37 statements, no incident attached, and the audit itself calls it rule material rather than hook material ("Rule material (Scott's own repos vs tatari-tv), not a hook", lens `hooks-sandbox` F8.7). Not in item 6's scope line either.
- **Gmail delete/trash.** 10 `gws` delete-shaped statements in the window, all against Drive, all exploratory `--help` or requested. Zero Gmail deletes and zero incidents. Named in the audit's change list; refused here for lack of any observed vector. Revisit condition: the first Gmail delete statement in the corpus.
- **`git reset --hard` / `git clean -f` tightening.** The audit ranks it 12 of 12 and it belongs to the release/working-tree family that chunk B owns, not to outward actions.
- **Agent-definition hard-constraints blocks.** The audit's incidents lens proposes a safety block in `phase-implementer.md`, `release-driver.md`, `review-panel.md`, `design-research.md`. That is audit item 12, chunk G.
- **`spec-review`'s independent round cap.** Handed on from chunk C; belongs to whichever chunk owns skill hygiene.
- **Item 1, the unrequested-commit class, ships with no mechanical coverage. Scott ruled this on 2026-09-15: accept the gap.** Four predicates were derived and measured, all against 5 known incidents out of 2,832 commit statements: prompt-word over the last 3 prompts, 590 denies / 2 of 5; the same over a session-wide window, 318 / 1 of 5; docs-only staged set, 351 / precision 1.4%; subagent-type allowlist, 569 of 882 subagent commits / **0** of 5, since all five incidents are main-thread and `agentType` is free-text dispatcher naming across ~190 values; path provenance (a staged basename never named in any prompt), 820 / 4 of 5. The base rate is 0.18%, so any predicate coarser than "exactly this commit" lands under 2% precision. The blanket-staging rule is **not** a substitute and is not built either (Alternative 5). One caveat on the docs-only figure: it classifies by the `git add` arguments in the same call plus file extension, so it is a proxy for the staged set, not the staged set.
- **Blanket staging.** See Alternative 5: no item-1 claim, no surviving phantom claim, and zero of five incidents.
- **Any "an allowlisted skill is active" clause.** The audit's prescription for item 1 and its "no live posts during a `/cli-shakedown`" clause for item 2 both depend on a guard knowing which skill is running. No measured `PreToolUse` payload carries a skill field (full 2.1.272 key set at `docs/design/2026-09-14-panel-round-cap-phase0/evidence.md:16-41`). The only available signal is the newest `Skill` tool_use record in the transcript, which has **no end marker**, so "active" is unbounded and the inference is wrong in exactly the long-running sessions where it matters. Both clauses are refused. TEST-TEXT covers the shakedown case textually instead, and item 1's skill allowlist is moot because item 1 is refused on its own numbers.
- **Mode-0664 credential files on this machine.** `/run/user/1000/{borg,cortex,sb-harvest}.env` hold roughly 40 live credentials and are readable by any local process. Found while measuring item 8. It is a configuration fix in the daemons that write them, not a guard, and not in this repo.
- **Redacting secrets already in a transcript.** A `PostToolUse` hook cannot unwrite the transcript. The audit says so and the fix lives in `clyde`'s indexer, which already redacts.

## Proposed Solution

### Overview

One new Bash hook carrying the statement-level rules, one new hook on the Slack write surfaces, and an extension of the guard that already owns secrets. Plus permission-deny entries as a second layer where a literal verb exists.

```
PreToolUse(Bash)                 -> intent-guard.sh      rules: GH-WRITE, DELETE-OUT, INGEST, LN, PUBLIC-REPO
PreToolUse(Bash | mcp__slack__*) -> slack-post-guard.sh   rules: TARGET, TEST-TEXT, RESEND
PreToolUse(Bash | Read)          -> secret-echo-guard.sh  extended: 5 statement vectors + credential-path Read deny
permissions.deny                 -> acli deletes, gh repo edit
```

### Why one hook and not six

Measured on this machine, 2026-09-15: the ten hooks registered on the `PreToolUse` Bash matcher cost 689 ms when run one after another over a trivial payload (`git status --porcelain`), individual times 18 to 137 ms. Every Bash call in every session pays that. Five new scripts would add roughly 300 to 400 ms more, and all five rules need the same `lib.sh` parse of the same command string, so parsing once is strictly cheaper than parsing five times.

`prose.sh` is the in-house precedent: one script, three rules, one payload read, `--self-test` on the side. `intent-guard.sh` copies that shape.

(Whether the harness runs the hooks in one matcher list serially or in parallel is not established. The 689 ms is a sum of individual runs, and Phase 0 measures what the harness charges per call. One hook is the right shape either way.)

### Implementation contract every rule follows

Not restated per rule below:

- **Sourcing, and the fail-open snippet is NOT the one a fail-closed rule uses.** The tree's line is `. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }` (`lib.sh:5`), which **fails open**: it emits an allow and exits before any rule evaluates. That is right for the existing guards and wrong for an authorization gate. Round 3 asserted that SLACK and PUBLIC-REPO "deny when `lib.sh` is unreadable" while prescribing this exact line, so the doc named a requirement and handed the implementer a snippet that forecloses it.

  A hook carrying a fail-closed rule records the failure and keeps going instead of exiting:

  ```
  LIB_OK=1
  . "$(dirname "$0")/lib.sh" 2>/dev/null || LIB_OK=0
  ```

  With `LIB_OK=0` the fail-closed rules (SLACK, PUBLIC-REPO) **deny** with text naming `lib.sh` as unreadable, and every rule that needs a `lib.sh` helper it cannot call is skipped rather than evaluated against a missing function. The fail-open rules keep the tree's behavior. `hooks-preflight.sh` already asserts `lib.sh` is readable at session start, so this path is the second line of defense, not the first.
- **Deny:** `jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'` then `exit 0`. Allow is `echo '{}'; exit 0`. Copied from `manifest-scope-guard.sh:24-27`.
- **The command-word test, and the one way to get it wrong:** `cmdword_is <verb>` only, which consumes chunk B's structural `cmdword_index` walk (`lib.sh:396-423`, the fix for the prefix regex that let `{ git reset --hard; }`, `timeout 5 git push --tags` and `\git tag -d v1` through). Run it on a copy masked with `mask_heredoc | mask_comment` **only**. Quote-masking the command-word test makes the verb read as no verb at all, which is audit finding CW1, cited in `manifest-scope-guard.sh:29-43`. Flag values come from `flag_value`, never a substring match, so `--method=PATCH` is caught as well as `--method PATCH`.
- **Matrices are wired by glob:** `.otto.yml`'s `test` task runs every `HOME/.claude/hooks/*-test.sh`, so a new matrix needs no `.otto.yml` edit. The `lint` task's `FILES=()` array is explicit and every new file must be added to it, or the em-dash gate does not cover the file (chunk A audit finding M3, five files shipped with em-dashes for exactly this reason).
- **Wrapper sweep:** `shapes.sh` exports `WRAPPER_SHAPES` (16 printf formats) and `wrap_shapes <cmd>` (18 spellings including `\cmd` and `"verb" rest`). Five matrices source it today. Every irreversible deny fixture in this chunk runs through it.
- **Registration:** a new `PreToolUse` block in `settings.json` goes in through the **Edit tool**. Bash writes to that path are denied from a session whose config this repo is, while the Edit path works (proven by `f257ddb`, which registered `panel-round-guard`). `hooks-preflight.sh` warns on a hook registered before it is linked, so `manifest -l` runs in the same phase that adds the file.

### The rules

#### GH-WRITE: repo and org settings are Scott's

Deny a statement whose command word is `gh` when either holds:

- `api` against a **guarded path** and carrying a **write**, where
  - guarded path = `repos/*/branches/*/protection*`, `repos/*/rulesets*`, `orgs/*/rulesets*`, or a bare `repos/<owner>/<repo>` with nothing after it, with or without a leading `/`
  - **effective method** is computed first, then the path is classified. Method comes from `-X`/`--method` in all three spellings: separated (`-X DELETE`), attached (`-XDELETE`), and equals (`--method=DELETE`). With no method flag, the presence of any of `-f`, `-F`, `--field`, `--raw-field`, `--input` makes it a POST, because `gh api` switches on its own as soon as a body field is present. An **explicit** `--method GET` with body fields is a GET and is not a write.
  - write = effective method in `PATCH`, `PUT`, `POST`, `DELETE`

**The method is parsed by the guard itself, not by `flag_value`.** Round 1 decided the opposite and round 2 reversed it with two measurements.

First, `flag_value` cannot see the attached form:

```
printf 'gh api -XDELETE repos/o/r'  | flag_value -X value  ->  ''        (empty)
printf 'gh api -X DELETE repos/o/r' | flag_value -X value  ->  'DELETE'
gh api -XDELETE   ->  "accepts 1 arg(s), received 0"        (gh parsed the flag)
gh api -QDELETE   ->  "unknown shorthand flag: 'Q'"         (control)
```

Second, and worse, `flag_value` returns on its **first** match while `gh` honours the **last**. Verified 2026-09-15:

```
printf 'gh api repos/o/r -X GET -X DELETE' | flag_value '' '-X'  ->  GET
gh api -X POST -X GET /rate_limit  ->  {"resources":{"core":{"limit":5000,...
```

That second line is the proof of last-wins: a POST to `/rate_limit` would not return rate-limit data. So `gh api repos/tatari-tv/valet/branches/main/protection -X GET -X DELETE` reads as a GET to the guard and executes as a DELETE.

**Teaching `flag_value` the attached form is not the fix, because it corrupts three shipped guards.** Reproduced against a patched copy under `$TMPDIR`, never in the tree:

| payload | shipped | with a naive attached-form fix |
|---|---|---|
| `gh api -XDELETE repos/o/r` (`-X`) | `` (the gap) | `DELETE` (fixed) |
| `gh pr create --body -testing --title "feat: right"` (`-t`) | `feat: right` | **`esting`** |
| `gh pr create --body -Hbad/name --head right` (`-H`) | `right` | **`bad/name`** |
| `gh api -H "-XGET: x" -XDELETE repos/o/r` (`-X`) | `` | **`GET: x`** |
| `gh pr create --title=add-viewport-support` (`-t`) | unchanged | unchanged |

Rows 2 and 3 are allow-to-deny flips in `branch-pr-title-guard.sh:145,146,154` and `branch-name-guard.sh:172`. Row 4 is a fresh bypass the fix itself creates. `bash lib-test.sh` against the patched copy returns **pass=135 fail=0**, so the matrix does not protect the change.

The root cause is that `flag_value` has no per-flag arity table, so it cannot tell an attached value from a value that merely begins with a dash. That is not fixable generically without giving the parser a flag spec, which is a chunk-B-sized change to a dependency three live guards share.

**So: `flag_value` is left alone**, its limitation is documented at its definition, and the five rows above are added to `lib-test.sh` as characterization fixtures that pin current behavior. GH-WRITE gets a **local** effective-method parse over the `gh api` token list. Four spellings, `-X V`, `-XV`, `-X=V` and `--method[= ]V`, **last occurrence wins**, compared **case-insensitively**. Every part of that was probed, and two of them were bypasses in the round-2 text:

```
gh api -X get  /rate_limit  ->  {"resources":{"core":{"limit":5000,...   (lowercase accepted)
gh api -X=GET  /rate_limit  ->  {"resources":{"core":{"limit":5000,...   (equals form accepted)
```

So an uppercase-only test misses `-X delete`, and a parse that does not strip the `=` reads `-X=DELETE` as the value `=DELETE`, matches no method, and allows.

The third requirement is **operand consumption**, and it is the subtle one. `gh` accepts a dash-leading header value, and `args` reports the tokens flat:

```
printf 'gh api -XDELETE -H "-XGET: x" repos/o/r' | args
  ->  -XDELETE | -H | -XGET: x | repos/o/r
```

A naive last-wins scan for anything shaped like `-X...` picks up `-XGET: x`, which is the **operand of `-H`**, resolves the method to `GET`, and allows the DELETE. So the parse walks the token list left to right and skips the operand of every value-taking flag before deciding whether a token is a method flag at all.

**The skip list is the complete `gh api` flag specification, short and long alias for each, derived from `gh api --help` on the installed `gh`.** Round 3 hand-listed a subset and round 4 executed two live bypasses straight through the gaps:

```
$ gh api -XDELETE -p -XGET /rate_limit --verbose 2>&1 | sed -n 3p
> DELETE /rate_limit HTTP/1.1
$ gh api -XDELETE --header "-XGET: x" /rate_limit --verbose 2>&1 | sed -n 3p
> DELETE /rate_limit HTTP/1.1
```

Both send DELETE against the live endpoint while a parse over the round-3 list resolves GET and allows. The three misses were `--header` (the long alias of `-H`, which round 3 fixed only in its short form), `-p`/`--preview`, and `--cache`.

| value-taking flag | aliases |
|---|---|
| cache | `--cache` |
| field | `-F`, `--field` |
| header | `-H`, `--header` |
| hostname | `--hostname` |
| input | `--input` |
| jq | `-q`, `--jq` |
| method | `-X`, `--method` |
| preview | `-p`, `--preview` |
| raw-field | `-f`, `--raw-field` |
| template | `-t`, `--template` |

`-X`/`--method` is on the list because it takes a value: the parse consumes its own operand as the method rather than skipping past it. The four boolean flags (`-i`/`--include`, `--paginate`, `--silent`, `--verbose`) take no operand and are never skipped over. `gh api`'s `-i` is `--include` for response headers and is unrelated to `git commit -i` in PUBLIC-REPO below.

`--cache` is on the list for completeness, not because it is a vector: `gh api --cache -XGET /rate_limit` fails with `invalid argument "-XGET" for "--cache" flag: time: invalid duration "-XGET"` and nothing executes. Round 4's architect seat claimed it as a critical bypass without running it; the staff seat ran it and the claim is recorded as rejected in the review log.

The list is a snapshot of one binary's surface, so a flag the installed `gh` grows later is a hole by construction. Phase 2 carries one fixture per value-taking flag so a missing alias fails the matrix rather than passing silently.

A repeated method flag is honoured as last-wins rather than denied, because that is what `gh` does. None of this touches `flag_value`.

Also corrected from the draft: `-F` and `--field` are the same flag (`gh api --help`), and the draft listed only `-F`, so `gh api repos/o/r --field description=x` was an implicit POST outside the predicate.
- `repo edit`

Fires in the window: **10** `gh api` statements out of 173 explicit writes plus 792 implicit ones, made of 6 with an explicit method on a guarded path (1 protection, 2 rulesets, 3 repo root) and 4 with only body fields on a guarded path. Plus 3 `gh repo edit`. Two are the incidents; the rest were Scott-directed, and a deny is the correct outcome for those too because he re-ran them himself with `!`.

The implicit-write clause is what pass 4 found: without it the rule reads as covering writes and misses 4 of the 10.

**GraphQL is a named hole, not a phase.** Measured over the window: 716 `gh api graphql` statements, 170 carrying a mutation verb, and **zero** naming a protection, ruleset or repo-settings mutation (they are all `addPullRequestReviewThreadReply`, `updatePullRequestReviewComment`, `updatePullRequest`, `updatePullRequestReview`). No observed vector, so it sits in the residual-holes list beside `Grep`/`Glob` rather than in a rule.

Deny text: `repo/org settings are Scott's to change (rules/git.md). Report the blocker; do not change the setting.`

#### DELETE-OUT: outward deletes

Deny `acli` statements carrying a `delete` subcommand (`jira workitem delete`, `confluence page delete`), except with `--help`. Fires in the window: 2 statements, one of them the SEC-2997 incident.

The `--help` carve-out lives in the hook and **not** in the `permissions.deny` entries this phase also adds, which have no carve-out and are evaluated independently of what a hook returns. So the combined behavior of `acli jira workitem delete --help` is a **fixture**, not an assumption: whichever layer wins, the matrix records it.

Not expanded, with the measurement: `gh issue delete` 0 statements, `acli bitbucket` 0, `gh release delete` 4 (already in `permissions.deny`), `gh pr close` 28 and a closed PR reopens, so it is not an outward irreversible delete.

Gmail delete/trash is a Non-Goal (zero observed vectors).

One note on precision, observed live during this session's own measurement: a naive `acli.*delete` pattern matched `scan5.py`'s regex **text**, inside a quoted heredoc, at 2026-09-15T19:41. That is the exact class chunk B's `lib.sh` exists to kill. Every rule in this hook matches on `stmts` output from the masked copy, never on the raw command.

#### LN: no symlink cycle, and nothing symlinked into `~/Claude`

Two independent denies on a statement whose command word is `ln` with `-s`:

- **cycle**: deny when the resolved target is an ancestor of, or identical to, the **prospective link entry**. This is the shape that froze the workstation on 2026-07-03, and the cycle direction is target-ancestor-of-link, not the reverse.

  **The predicate must never dereference the link's final component**, which the draft got wrong. Verified 2026-09-15:

  ```
  realpath -m ~/.claude/hooks/lib.sh
    -> /home/saidler/repos/scottidler/claude/HOME/.claude/hooks/lib.sh
  realpath -m /home/saidler/repos/scottidler/claude/HOME/.claude/hooks/lib.sh
    -> /home/saidler/repos/scottidler/claude/HOME/.claude/hooks/lib.sh      # identical
  ```

  `realpath -m` follows an existing link, so for any `ln -sf` **reinstall** of a live symlink the link and the target resolve to the same file and the equality clause fires. That is the dominant legitimate shape in the window and Phase 3's own criteria require it to pass. The guard instead resolves `dirname` of the link path and appends the basename unresolved, which gives the entry the link will occupy: for a hook reinstall that is `~/.claude/hooks/x.sh` against a target in the repo (allow), and for the incident it is `.../HOME/Claude/writing/voice` against the same resolved target (deny).

  Operand forms the predicate has to model, each confirmed against the installed `ln --help`: a **directory destination** (the entry is `dir/basename(target)`), `-t DIR` with multiple sources, a **relative target** resolving against the link's parent, and `-n`/`-T` changing how an existing destination is read. Combined short flags (`-sfn`) and `--symbolic` are spellings of the same thing.
- **`~/Claude` is symlink-free by policy**: deny any link path under `~/Claude/`. `CLAUDE.md` states it: "~/Claude is the Cowork/Syncthing space, so no symlinks there". A flat path rule, no inference.

Why the predicate and not the verb: 112 `ln -s` statements in the window, nearly all installing hook and config symlinks. A verb matcher is 112 denies for one incident.

How well the predicate discriminates is **partly unmeasured, and Phase 3 closes that**: of 100 absolute two-arg `ln -s` pairs in the window, 3 are ancestor-shaped and all 3 are deliberate loop-repro probes under `/tmp`, so zero legitimate instances. But 97 of the 100 use relative paths and cannot be classified without the cwd each ran in. So Phase 3 replays all ~112 corpus statements **with their recorded cwd** and asserts **zero denies outside the 3 known loop-repro probes, which must deny**. Asserting zero across all 112 would be unsatisfiable, because 3 of them are the exact shape the rule exists to catch.

Resolving those cwds needs more than the shipped helpers: `cd_last` (`lib.sh:371-381`) and `cd_at` (`:635-645`) return the **last** `cd` operand and replace rather than accumulate, so `cd ~/repos/scottidler/claude && cd HOME && ln -s ...` yields the relative `HOME`. 97 of the 100 measured absolute-pair statements use relative paths, so the rule accumulates the cwd across the command's `cd` chain itself, starting from the payload's `cwd` field. That accumulation is LN-local and does not touch `lib.sh`.

It also needs a scope boundary, which round 3 found missing, because a `cd` inside a subshell does not escape it and `stmts` cannot see that it was one:

```
printf '(cd /tmp); pwd' | stmts   ->   cd /tmp | pwd
```

Naive accumulation concludes `pwd` runs in `/tmp`, which is wrong. Rather than teach the rule subshell scoping, it **stops accumulating** at a structural paren and falls back to the payload's `cwd`.

**The test runs against the MASKED command, not the raw one.** Round 3 wrote it against the raw string and round 4 measured what that costs: of 51 `ln -s` commands in the corpus, 8 carry a `(` and only **3** carry a structural `$(`. The other 5 carry it in a comment or a quoted string, where it means nothing. The decisive false deny:

```
mkdir -p /tmp/otto-p1/nopy && cd /tmp/otto-p1/nopy && for b in bash sh echo cat env ln rm mkdir; do ln -sf $(command -v $b) . 2>/dev/null; done
```

Link path is `.`, relative; the cwd it needs came from the `cd` that a raw-paren check forbids the rule to use; it is not one of the 3 loop-repro probes. Under round 3's text it denies, which makes Phase 3's "exactly 3 denies" criterion unsatisfiable.

Masking separates the two cases at no cost, because `lib.sh:68` already classifies a command-substitution body as class `P`, "which no masker may erase, because the shell runs it". A paren inside a comment or a quoted string is erased by `mask_comment` / quote masking; a structural `$(`, `` ` ``, `<(` or `>(` survives. So the rule tests for a paren on the masked copy.

Then the fallback resolves, and the two outcomes are **distinguished rather than collapsed**:

- The payload's `cwd` is present and the link path resolves against it: **allow or deny on the resolved path**, like any other statement.
- The link path is relative and the cwd is genuinely unknown, so no absolute link path can be formed: **deny**. Fail-closed, and this is the narrow case round 3 meant.

The command above lands in the first bucket and allows. It goes in Phase 3's matrix as an allow fixture.

That replay is exactly the measurement that would have caught the `realpath -m` defect before it was written into a doc.

#### INGEST: bulk vault ingest

Deny when an `sb borg ingest`, `reingest` or `reingest-failed` occurrence appears **anywhere in the command** together with any of: a loop keyword (`while`, `for`, `select`), `xargs`, a redirect reading a file, or two or more ingest occurrences. A single literal-URL ingest passes. `sb borg log` and `sb borg audit` always pass.

**The scope is the whole command, not the statement, and that is a deliberate exception to the implementation contract above.** Verified by running the shipped `stmts` on the incident's own loop body:

```
input : while IFS= read -r url; do
          out=$(sb borg ingest --tags x -- "$url" 2>&1); rc=$?
        done < urls.txt
stmts : while IFS= read -r url | do | out=$() | rc=$? | done < urls.txt
        sb borg ingest --tags x -- "$url" 2> | 1
```

The command substitution is split out into its own statement, which carries the ingest but **no loop keyword, no second URL and no file redirect**. A per-statement predicate does not fire on the shape that actually happened. The plain forms are fine: `for url in a b; do sb borg ingest -- "$url"; done` and `cat urls.txt | xargs -n1 sb borg ingest --` each emit one statement holding both the loop construct and the ingest, verified. So the exception is narrow and it is named here rather than left as a silent inconsistency with the contract.

Second predicate, and the sharper one for this shape: **deny an ingest whose URL operand is not a literal `http(s)://` token.** The incident's operand is `"$url"`. A variable operand means the target is not in the command, so it cannot be the thing a human named.

**The three verbs do not share an operand shape, and one of them has a built-in bulk door the draft never named.** From `scottidler/second-brain/main/sb/src/cli/borg.rs`:

| verb | operands | verdict |
|---|---|---|
| `ingest` (`:36-46`) | optional URL, `--clipboard`, **`--file <path>`** | `--file` is the CLI's own bulk path and is denied outright without the door; a single literal URL passes |
| `reingest` (`:75-91`) | **no URL operand**; `--all` and filters | `--all` is denied without the door; a filtered reingest passes |
| `reingest-failed` (`:96-100`) | **no URL operand** | read-only forms (`--dry-run`) always pass |

So the literal-URL clause applies to `ingest` **only**. Applied to the other two it would deny every `reingest-failed --dry-run`, and `reingest --all` trips none of the loop, xargs or repeat triggers while being the largest bulk action available.

**Precedence, in this exact order**, because the round-2 text evaluated the deny clauses first and thereby made its own door unreachable.

**Each step names the unit it decides on**, which round 3 left implicit and round 4 found to be the defect underneath steps 2 and 3. The rule head above scopes the loop, xargs, redirect and repeat triggers to the whole **command**; the door and the read-only exclusion are per **statement**, which `stmts` already separates. Where a step decides per statement, its verdict binds that statement only, and the command's verdict is any-deny-wins over the statements that remain in scope.

1. **The door.** `BULK_INGEST_ORDERED_BY_SCOTT=<n>` as a leading environment assignment on the ingest statement, where `<n>` is the maximum number of ingest occurrences permitted. **`<n>` is a ceiling and it is compared**, which round 3's text asserted and then never did: it said "present and well-formed, the statement is allowed" with no count anywhere, so `=0` allowed and `=1` allowed five ingests. The counted unit is the number of `ingest` / `reingest` / `reingest-failed` occurrences in the statement, after step 2's read-only exclusion. Count `<= n` allows the statement and nothing below runs. Count `> n` **denies**, with deny text naming the count and the ceiling. `n = 0` denies any ingest, which is the degenerate case and is correct. Malformed, non-numeric or negative denies. This matches the cited precedent: `panel-round-guard.sh` treats its value as a ceiling, so `=5` grants five and still denies six. Anchored as a leading assignment on the statement so it cannot be smuggled in from a heredoc body or a comment, and the matrix pins the fenced self-reference case per chunk C's rule.
2. **Read-only verbs are EXCLUDED from the operation list, they do not grant a command-wide allow.** `sb borg log`, `sb borg audit`, and any `reingest`/`reingest-failed` carrying `--dry-run` are dropped from the set of operations the deny clauses are evaluated over. They do not return a verdict for the command. Round 3 wrote this step as "always allow" with no scope stated, and round 4 found what that costs: `sb borg log; sb borg ingest --file urls.txt` hits step 2, returns allow for the whole command, and never reaches step 3. Both seats found it independently.
3. **The deny clauses**, evaluated over the operations that survive step 2, **any-deny-wins**: a loop keyword, `xargs`, a file-reading redirect, two or more ingest occurrences, `ingest --file`, `reingest --all`, or an `ingest` whose URL operand is not a literal `http(s)://` token.
4. **Otherwise allow.** A live `reingest-failed` with no `--dry-run` reaches here and is allowed: it retries what the daemon already recorded as failed, so it introduces no new source.

`echo while; sb borg ingest -- https://one.url` reaches step 3, matches the loop-keyword clause, and denies.

**The raw-text scan needs a bound, and this document proves it.** The INGEST section above contains both `while IFS= read -r url; do` and `sb borg ingest`, so writing this design doc through a heredoc would deny under an unbounded command-scope raw scan. That is chunk C's self-reference class exactly. The bound: a heredoc body is scanned **only when its redirect target ends in `.sh`**. Nothing more clever than that. Round 2's text added "or a target the same command marks executable", which asks the implementer to invent static analysis over a `chmod` in a sibling statement; it is deleted. The incident's target is `"$S/ingest.sh"` and is caught; this doc's target is a `.md` path and is not. Both shapes are pinned as fixtures, the deny and the allow. A script written to an extensionless path and chmodded is a named residual hole, not a silent one.

Note the wording: not "bulk". A loop body is one statement regardless of how many times it runs, so "bulk" is not statically countable and a rule phrased that way cannot be implemented. What is countable is the loop, the `xargs`, the file redirect, the repeat count, and whether the operand is a literal.

This rule reads heredoc bodies, which is a deliberate departure from every other rule in the hook, and the reason is the measured vector. The 164-URL incident did not loop `sb borg ingest`; at 00:32:22 it wrote a script with a quoted heredoc and at 00:32:40 ran it:

```
cat > "$S/ingest.sh" <<'EOF'
while IFS= read -r url; do
  out=$(sb borg ingest --tags claude anthropic data -- "$url" 2>&1); rc=$?
...
"$S/ingest.sh" "$S/batch1-rest.txt" "$S/batch1-ingest.log"
```

The run statement's command word is `$S/ingest.sh`, so no verb matcher sees it, and the delimiter is quoted, so `heredoc_expanded` does not emit it either. Denying at **creation** is what stops the sequence, and creation is only visible in the heredoc body. The false-positive cost of reading heredocs is bounded here by the surface: 11 `sb borg ingest` statements in four months.

Door for a legitimate bulk ingest, copying chunk C's pattern: `BULK_INGEST_ORDERED_BY_SCOTT=<n>` in the command. Needed because one requested bulk ingest (2026-06-21, 5 URLs, "then sb borg ingest them") would otherwise be denied and re-denied, which is the retry loop chunk B's `branch-pr-title-guard` taught us to design out.

#### PUBLIC-REPO: nothing sensitive on a public remote

On `git commit` and `git push` under `~/repos/scottidler/*`, when the remote is public, deny if the path set contains `personal/`, `excluded/`, `voice/`, `secrets?/`, `.env`, `.age`, or a blob over 1 MB.

**The commit half cannot read the index, and the draft's version would have allowed the leak it is named after.** `PreToolUse` fires before the whole Bash call, so `git diff --cached` sees the index as it stands **before** the statement's own `git add` runs. The founding incident is exactly that shape, verbatim from the transcript:

```
cd ~/repos/scottidler/claude && git add .gitignore HOME/Claude/writing/voice \
  HOME/repos/.claude/rules/voice.md && git commit -m "add voice corpus ..."
```

At hook time the index holds none of those paths. So the commit half's path set is computed per commit form, not as one blanket union:

| commit form | path set |
|---|---|
| plain `git commit` | current index, plus the arguments of any `git add` statement in this same command |
| `git commit <paths>` | those paths only (working-tree content, index bypassed) |
| `git commit --only <paths>` | those paths only. Unioning the whole index here produces false denies |
| `git commit -a` / `-am` / `--all` | current index, **plus** the arguments of any `git add` in the same command, plus every tracked modification. `git add x && git commit -am msg` must not drop `x`, which the round-2 table did |
| `git commit -i <paths>` / `--include <paths>` | current index, **plus** the arguments of any `git add` in the same command, plus those paths. Same pre-hook index omission the `-a`/`-am` row above fixes, and round 3 fixed that row and not this one |

The `-i`/`--include` row is the same defect one row down, and it was measured rather than argued. `git add secrets/new.txt && git commit --include README.md -m update` in a scratch repo: `git diff --cached --name-only` is empty at hook time, and the resulting commit contains `README.md` and `secrets/new.txt`. `--include` adds its paths to whatever is already staged, so a path staged by an earlier statement in the same command rides along and a path set computed from the pre-hook index misses it.

`git commit -a` was missing from the draft, and the doc's own evidence counts 65 such statements in the window. Its severity is bounded: `-a` reaches **tracked** files only, and there are zero tracked sensitive paths in this repo today, so it is a completeness gap rather than a live leak. It is in the set regardless.

Directory operands (`git add .`, `git add docs/`) are **expanded by asking git**, with `git ls-files -co --exclude-standard -- <operand>`, never by globbing the filesystem. A glob walks ignored files and would deny on a gitignored `.env` that git is never going to stage. The 1 MB check measures the blob that will be committed, not whatever currently occupies the path.

**The push half has no index at all, and `@{u}..HEAD` is the wrong question.** Three defects in the draft:

- **Refspec and non-HEAD sources.** `@{u}..HEAD` describes HEAD, not the ref being pushed. 32 refspec-form push statements in the window, including **this chunk's own landing command** (`git push origin intent-guards:main`), plus `git push origin 472114f:refs/heads/bump-v0.2.0` and a push from a different HEAD. The rule parses the source ref out of the refspec and diffs that, and **fails closed** when it cannot resolve one.
- **The destination boundary is read from the remote, on the push path only.** `@{u}` errors with "no upstream configured" on a fresh branch, the normal state for this repo's landing flow, and a remote-tracking ref can be arbitrarily stale. So the guard resolves the destination with one `git ls-remote <remote> <dest-ref>`: a push is already a network operation, so one extra round trip is not the hot path, and an absent destination ref means the whole source history is in range.

Three outcomes, because "unresolvable denies" left the middle one out:

| `ls-remote` | the object locally | verdict |
|---|---|---|
| no such ref | n/a | the whole source history is the range, evaluate it |
| resolves | present (`git cat-file -e` rc=0) | that SHA is the range boundary |
| resolves | **absent** (rc non-zero, so `rev-list` cannot run) | **deny**: the range cannot be computed |

The third row is the case a pushed-to branch the local clone never fetched produces, and the round-2 text would have fallen through it.
- **An endpoint diff hides add-then-remove, and a plain commit walk hides merge-introduced content.** Neither single method is sufficient, measured 2026-09-15 on a synthetic repo whose merge **resolution** added `.env`:

  ```
  git log --format= --name-only BASE..HEAD                            ->  a.txt  s.txt
  git log --format= --name-only --diff-merges=first-parent BASE..HEAD ->  a.txt  .env  s.txt
  ```

  `git log --name-only` shows no diff for a merge commit by default, so bytes published through a merge resolution are invisible to the walk the draft prescribed. `--diff-merges=first-parent` catches both classes: it lists per-commit names, so an add-then-remove pair still surfaces the filename, and it attributes the merge's own resolution.
- **Blob size is measured over the range, not on disk.** A filename cannot distinguish a currently-small file from a 4 MB blob earlier in the pushed history, so the size check runs `git rev-list --objects` over the range into `git cat-file --batch-check`.
- **Cases to model:** a new branch with no upstream, force-push, detached HEAD, tag push, and `--all` or multiple refspecs. `--no-verify` is **not** one of them and is recorded here so it is not re-raised: it bypasses git's own pre-push hook and never a Claude `PreToolUse` hook.

Standing on this: **119 of Scott's 136 personal repos are public, including `scottidler/claude` itself**, the repo that holds his rules, `WHOAMI.md` and every design doc in this program. `scottidler/keep`, where the `.age` secrets live, is private, so the `.age` pattern costs nothing there.

Observed on main, 2026-09-15: `git ls-files | grep -E '<pattern>'` returns 0 matches in this repo, and no tracked file exceeds 1 MB. The guard has zero standing false positives against the current tree.

Visibility is read once per repo with `gh repo view --json visibility` and cached under `~/.cache/`, because a `gh` call on every commit is not acceptable at 689 ms of existing hook latency. The cache entry is `visibility` plus the epoch it was read, with a one-week life.

Two cases, and the draft only handled the easy one:

- **Unknown, missing or unreadable** reads as **public**, so the guard is on rather than off when it has no answer.
- **A cached `private` that has since gone public** is the case that matters, and unknown-reads-as-public does nothing for it: a stale `private` entry stays private for the rest of its week. So a cached `private` is **revalidated with `gh` before the guard allows a sensitive path**, and only then. The revalidation is on the deny-candidate path, not the hot path: a commit with no sensitive path never triggers it, which is every commit in this repo today. If the revalidation cannot run, the guard denies.

The refresher is the guard itself, on read, with no background job.

Scope stays `~/repos/scottidler/*`: no repository outside it has an origin remote Scott owns, third-party clones are not pushable, and `tatari-tv` is a different threat model.

#### STAGING: dropped, and the measurement that dropped it

The draft carried a blanket-staging deny (`git add -A` / `.` / `--all`) as item 1's replacement. Panel round 1 took its item-1 justification away, and a measurement in this session took the remaining one. It is not built. Full reasoning in Alternative 5, kept so it is not re-proposed.

#### SLACK: a post goes where Scott named, once, and not as a test

`slack-post-guard.sh`, registered on both the Slack MCP write tools and the Bash matcher. Both surfaces post: the audit's `hooks-sandbox` F8.12 counts 73 MCP `chat_post_message`/`chat_update` calls plus 85 CLI `slack write`/`slackify` calls, and its `mcp-usage` F8 counts 120 posts across all paths including two retired tools. Re-derived here over main-thread transcripts for the two MCP tools that still exist: 64 posts, `tool_input` carrying `channel`, `text`, and optionally `thread_ts`, `raw`, `no_mentions`. Three denies:

- **TARGET**: allow unconditionally when the **full recipient set** is inside `#clipboard` (`C0ANJQAJC7N`) and Scott's own DM (`D01G4Q7AWLV`, from the cache's `self.dm`). Both ids are **hardcoded in the hook**, not resolved: `#clipboard` is a private channel Scott is the only member of and does not appear in the cache's 823 `channels` at all. For every other target, require that the channel id, the `#name`, or the DM user's display or first name appears in a typed human prompt of the current transcript, resolved through `~/.cache/slack/ids.json` (208 KB, mode 0600, schema 2, holding `channels` 823, `users` 120, `handles`, `profiles`, `subteams`, `self`, last synced 2026-09-14).
- **TEST-TEXT**: deny when the first line matches test/testing/verify/verifying and the target is not one of the two exempt ids. This is the 2026-07-10 class: five live posts and an MCP write test into a coworker DM during a shakedown whose prompt was "merged #10, tag v0.2.0 and run the shakedown". The rule is purely textual on purpose: the audit's phrasing of it ("no live posts during a `/cli-shakedown`") is not implementable, see Non-Goals.
- **RESEND**: deny a repost of the same body to the same target. This is the 2026-06-09 class: "having you spam multiple versions of shit into our DMs is NOT what I asked you to do", one post asked, two sent.

  The draft's "one `last-post` record, first 40 characters, 120 seconds" does not survive contact: an A then B then A sequence loses A's entry, two concurrent sessions can both pass before either writes, recording at `PreToolUse` suppresses a legitimate retry after a **failed** send or after another hook's deny, and first-40-chars matching would block correcting a typo. So the state is keyed on `(target, body-hash)` with an entry per pair rather than one global record.

  **A `PreToolUse` hook cannot write that state**, which round 2 caught and which made the round-1 rewrite inert: the hook never sees a send result. So `slack-post-guard.sh` is registered on **`PostToolUse`** as well, and the two registrations split the work.

  **Not with `flock`, which round 3 correctly called false.** A `PreToolUse` process exits before the tool runs, so a lock it holds covers the hook and not the send, and two sessions still interleave. The ledger is a **directory of entry files** and the mutual exclusion is the filesystem's:

  - `PreToolUse` creates `<ledger>/<target>-<body-hash>` with `O_EXCL`. A successful create is the reservation and the call proceeds. A create that fails because the entry exists is a **deny**, whatever state that entry is in.
  - `PostToolUse` marks the entry `sent`.
  - Two concurrent sessions posting the same body to the same target: exactly one `O_EXCL` create wins, the other denies. The exclusion spans processes because the create does, which a hook-held lock cannot.

  **A failed call does not mean nothing was sent, and the guard cannot learn which recipients landed.** Verified in the client: `post_chunks` can fail after the parent message has landed, and follow-ups post after it (`tatari-tv/slack-cli/src/mcp/helpers.rs:300-320`). And verified in the installed harness (2.1.273): a tool error arrives as **`PostToolUseFailure`**, a distinct event whose payload carries `error` as a string, with no `tool_response` key at all, so there is nothing per-recipient to read on that path.

  Phase 0 added one more fact to this, and it narrows what the failure path ever sees: **a tool that reports "not found" in its RESULT is a successful call and raises no failure event.** Measured with `mcp__oracle__note_read` against a nonexistent path, which returned `{"found":false}` through the ordinary `PostToolUse` path. So `PostToolUseFailure` fires on transport and schema failures only, never on a semantic one. That does not change the fail-closed ruling, which turns on the parent possibly having landed rather than on the error's kind; it means the event is rarer than the rule's wording implies, and the ordinary `PostToolUse` mark is what runs almost always.

  So the ruling is fail-closed and blunt: **a failure leaves the entry in place.** A retry of the same body to the same target denies, because the parent may well have landed. The cost is that a genuinely failed send cannot be retried until the entry expires, so the entry's life is one hour and the deny text names the exact file to remove. That is the honest trade: a duplicate post to a coworker is worse than a one-hour wait or one `rm` Scott can run.

  **Reclamation is exclusive, and the reaper is named.** The entry's one-hour life needs a process that ends it, and round 4 found none specified: two `PreToolUse` processes can both observe the same expired entry, both unlink it, and both `O_EXCL` create, which loses the exclusion the `O_EXCL` fix exists to provide. So expiry is never unlink-then-create. No separate reaper daemon, no sweep: the next guard to touch an expired entry is its reaper. The `O_EXCL` create itself is unchanged and is not in dispute; this closes the boundary around it.

  **Amended in Phase 5, because the mechanism this paragraph prescribed cannot meet its own criterion.** It read: the guard "reclaims it with a single atomic `rename` of a freshly created temp entry over the old path, and a losing racer sees the winner's entry and denies." That rename is atomic and it is not a compare-and-swap. `mv temp path` succeeds whether or not the path still holds the entry the process measured, so every racer that read the same expired mtime renames and proceeds, and the criterion below (two concurrent reclaims leave exactly one allowed) fails by construction. Renaming the expired entry AWAY, to a name only one process can take, IS a compare-and-swap and was the first implementation; measured at 8 concurrent racers it still allowed two, 1 round in 30, because a file that turns out to be a racer's fresh reservation has to be put back and the path is empty for the length of that restore, which a third process's plain `O_EXCL` create walks into. Any scheme that removes a live entry even briefly has that window. The shipped mechanism never moves the entry: reclamation takes a separate `O_EXCL` lock at `<entry>.reclaim`, and the holder re-reads the expiry while holding it. A lock older than a minute is swept and that call denies, so a dead process cannot wedge the pair; removing the entry by hand, which the deny text asks for, bypasses the lock entirely. Measured at 120 rounds of 8 concurrent racers against one expired entry: zero rounds with more than one allowed.

  Phase 0 gains one criterion from this: dump a `PostToolUseFailure` payload from a deliberately failed MCP tool call and record what it carries.

  **`chat_update` is exempt**, because editing an existing message is the opposite of a resend, and checked so it is not re-raised: `ChatUpdateRequest` carries no `dm_mentioned` and no `follow_ups` (`slack-cli/src/mcp/request.rs`), so an edit cannot fan out and the exemption opens no recipient hole.

  Cleanup: a ledger entry expires after an hour, and an unreadable or unwritable ledger **denies** on the `PreToolUse` side, consistent with the rest of this rule.

**The exemption is not a bound on recipients, and that is the sharpest finding of round 1.** One call to the Slack client can reach people other than the named target, confirmed in the client source:

- `--broadcast`, repeatable, crossposts the same body to additional channels (`tatari-tv/slack-cli/src/cli.rs:278-287`)
- `dm_mentioned`, which after posting DMs the permalink to everyone the body mentions, with usergroups expanded (`src/mcp/request.rs:102-112`)
- `follow_ups`, additional bodies threaded under the parent (`src/mcp/request.rs:113-122`)

So a post whose primary target is `#clipboard` can still land in a coworker's channel or DM. The guard resolves the full recipient set (primary target, every `--broadcast`, every mention when `dm_mentioned` is set) **before** granting either exemption, and TEST-TEXT applies to every `follow_ups` body as well as the primary one. A body read from a file is checked as the text that will be sent, not as the filename.

**The guard's recipient set can be smaller than the client's, and that decides the exemption.** Verified in the client: `write::fanout_recipients` calls `ensure_users_fresh()` then `ensure_usergroups_fresh()` and **refreshes a stale cache from the API before expanding recipients** (`tatari-tv/slack-cli/src/command/write.rs:785-787`, impl at `src/slack/mention.rs:906`). The guard reads `~/.cache/slack/ids.json` as it stands, so a cache older than the client's staleness window authorizes a smaller set than the client then sends to.

The ruling: **the client's set is authoritative, and the guard never grants an exemption on a set it cannot vouch for.** Concretely, an exemption requires the cache's `users_synced_at` and `usergroups_synced_at` to be inside the client's own staleness window. Outside it, or with any mention the cache cannot resolve, there is no exemption and the post needs a named target in the prompt. The two exempt ids themselves are literals and never need the cache, so a post to `#clipboard` with no mentions and no `--broadcast` passes regardless of cache age.

Why name resolution and not a literal channel id: for 86 of 120 posts in the window Scott names the target by person or `#name` only ("message russ", "slackify this to Reno"). A guard requiring the literal id in the prompt blocks 72% of legitimate posts.

And the flip side, which is part of item 6 and not a separate ask: Scott's 2026-09-11 ruling, "change that to NOT do that when the fucking target is my own DM or #clipboard! THATS A FUCKING PRIVATE CHANNEL THAT ONLY I AM IN. FUCK OFF WITH THE CONFIRMATION". Half of that is already prose in the right place: `HOME/.claude/skills/slack-clipboard/SKILL.md:21` reads "**Do NOT ask for confirmation.** The target is always Scott's own private channel, so the invocation IS the authorization", and `:30` adds "No confirmation gate, no preview, no egress warning. Post on the first ask." What exists nowhere is the other half, the confirmation requirement for every target that is **not** one of those two. This phase writes that, and the guard is silent for the exempt pair.

Surface notes that shape the registration:

- Matchers: `mcp__slack__chat_post_message`, `chat_update`, and `chat_schedule_message`. All three are the same egress with a different verb. `chat_post_message` is already matched today, by `emdash.sh` and only `emdash.sh` (`settings.json:883-889`), which scans string values for content and never reads the channel: zero authorization coverage.
- `tool_input.channel` is the field, documented as "Channel id (or DM id) to post to" in `tatari-tv/slack-cli/src/mcp/request.rs:78-123`.
- The Bash surface is the raw `slack` binary (`~/.cargo/bin/slack`, write verbs `write`, `delete`, `repost`, `scheduled deliver`). There is **no `Bash(slack:*)` entry in `permissions.allow`**, so those calls fall to the auto-classifier today. The plugin's own write skills are `off` in `skillOverrides` (`settings.json:756-763`), so the CLI and the MCP tool are the two live paths.
- `slackify` does not post: it converts markdown to rich text on the local clipboard, no network.

This rule reads the transcript, which is the only remaining prompt-reading guard in the chunk and carries the risk named under Phase 0. When the transcript is unreadable it fails **closed**, and the two exempt ids still pass, because their ids are literals in the hook and need no cache and no prompt.

#### SECRET: the vectors, the measured artifacts, and one hole chunk B handed over

Three separate pieces of work, and the first one is not in the audit's list at all.

**1. The command-word anchor hole, handed to this chunk by chunk B** (`docs/design/2026-09-13-guard-precision.md:542`). Reproduced live 2026-09-15:

```
'echo' $GH_TOKEN   -> allow
"echo" $GH_TOKEN   -> deny
```

`mask_squote` erases the single-quoted verb before the guard's echo/printf regex at `secret-echo-guard.sh:95` can see it, and that check has no command-word anchor. The fix is available and verified: `cmdword_is echo` matches all three quoting forms, and `mask_squote` still correctly inerts the one case that must stay allowed (`echo '$GH_TOKEN'`). So the verb gate becomes `cmdword_is` per statement, the payload match runs on the squote-masked copy, and the verb regex leaves the Python matcher. This is a live bypass of a shipped guard, so it goes first.

**2. New statement vectors.** The audit names five. One is aimed at the wrong artifact, measured:

| vector | evidence | status |
|---|---|---|
| `aws secretsmanager get-secret-value` without `--query` | `xoxb-` bot token printed twice, 06-23 and 06-25, marquee | as prescribed |
| `systemctl [--user] show-environment` | Anthropic key, 110 chars, 07-30, in a **subagent**, after the guard existed | as prescribed |
| history files read by `cat`/`sed`/`strings`/`grep`/`rg`/`head`/`tail` | `xoxp-` user token, 78 chars, 09-07, keep | as prescribed |
| a `*.service` file carrying `Environment=` | none found | **wrong target, corrected below** |
| `.env` files | `sk-ant-`, 108 chars, 06-16, via the **Read tool** | correct, glob incomplete |

Measured across `~/.config/systemd/user/*.service`: **no unit file carries a secret value in `Environment=`.** The only names present are `PATH` and `SCCACHE_*`. The secrets ride `EnvironmentFile=` into plaintext, mode-0664 files the prescribed globs miss entirely:

```
/run/user/1000/borg.env          3.8k each, ~40 vars, including ANTHROPIC_API_ADMIN_KEY,
/run/user/1000/cortex.env        ATLASSIAN_API_KEY, CLAUDE_COST_SLACK_BOT_TOKEN
/run/user/1000/sb-harvest.env
~/.config/eratosthenes/digest.env    ERATOSTHENES_SLACK_USER_TOKEN
~/.cache/okta/tokens.json
~/.cache/slack/token.json            singular, not tokens.json
~/.config/{marquee,persona,loki,verify}/tokens.json
```

The pattern list is built from that measurement, not from the audit's globs: `/run/user/*/*.env`, `~/.config/*/*.env`, `**/tokens.json`, `**/token.json`, plus the two history files. Each new deny gets a near-miss allow fixture beside it. **But not the draft's fixture, which baked in the leak**: `--query SecretString` selects the decrypted value and is exactly the output of the 06-23 and 06-25 `xoxb-` leak, so the presence of `--query` is not a safety predicate at all. Corrected: allow only projections that cannot carry a value (`ARN`, `Name`, `VersionId`, `CreatedDate`) and deny any `--query` selecting `SecretString` or `SecretBinary`.

**The path deny list is priced.** Bash statements in the window touching the listed paths: `~/.cache/slack/token.json` 77 (40 literal, 37 via `${XDG_CACHE_HOME:-...}`), `~/.cache/okta/tokens.json` 50, `~/.config/eratosthenes/digest.env` 37, `~/.config/fabric/.env` 30, `/run/user/1000/{borg,cortex}.env` 21, `~/.config/marquee/tokens.json` 9. Over 200 occurrences, and the routine shape is **auth debugging**, not a leak: `jq .expires_at`, `jq 'has("access_token")'`, a mode check. Without a split the rule is 200 denials against 4 leaks and it reads like `manifest-scope-guard`'s 9-of-9 prose problem. But "the shapes that print the whole file" is not an algorithm, and the pricing paragraph above holds its own counterexample: `jq 'has("access_token")'` must allow and `jq .access_token` must deny, and **neither one prints the whole file**. So the split is stated as a rule, fail-closed:

- **Readers that cannot project** (`cat`, `strings`, `head`, `tail`, `less`, `more`, `xxd`, `base64`) against a listed path: always **deny**. There is no safe form.
- **`jq` and `yq`** against a listed path: **the WHOLE filter string is matched against an allowlist**, never a substring or a pattern the filter merely contains. The allowed forms are `has("<literal>")` with a literal double-quoted string argument and nothing else in the filter, `keys`, `keys_unsorted`, `type`, `length`, `paths`, and a dotted path into an allowlisted non-secret key (`.expires_at`, `.created_at`, `.scope`, `.token_type`, `.account`). **Any other filter denies**, including a bare `.`, `.[]`, `to_entries` and every key not on the list. An unrecognized filter is a deny, not an allow.

  Round 3 wrote this as `has(...)`, which is a substring pattern, and `has` takes an arbitrary expression as its argument. Round 4 reproduced the leak:

  ```
  $ printf '%s\n' '{"example":"visible"}' | jq 'has(.example | debug)'
  ["DEBUG:","visible"]
  false
  ```

  The outer filter returns a boolean and the argument prints the selected value to stderr. A credential key in that position leaks exactly the same way, past a rule whose whole purpose is that the value never prints. So the grammar is explicit: a literal string argument, no embedded pipeline, no expression, no suffix after the closing paren.
- **`grep`/`rg`** against a listed path: **deny**, because a match prints the matching line. `grep -c` and `grep -q` allow, since a count and an exit code carry no value.
- **`stat`, `ls`, `test`, `wc`**: allow. They read metadata.

That is the algorithm the ~200 measured occurrences ride on, and each bullet gets a deny fixture and its near-miss allow.

**3. The `Read` matcher.** The `.env` leak came through the Read tool, which no hook in this repo has ever matched. Two things are unproven and both are Phase 0 criteria: whether a `"matcher": "Read"` block fires at all, and whether its deny survives `Read(**)` sitting in `permissions.allow`. Chunk A's spike proved only that a `Write|Edit|MultiEdit|NotebookEdit` matcher does **not** fire on Read (`docs/design/2026-09-13-enforcement-core-phase0/evidence.md:90-104`), which is a different claim. `rewrite-cd-read.py:5-9` documents the adjacent asymmetry, that allow and deny evaluation runs regardless of what a hook returns, which is exactly why this needs a measurement and not an argument.

Residual holes, named rather than patched blind:

- `Grep` and `Glob` over a credential path are not covered, and a `Grep` result can carry a matching line. No instance appears in the corpus.
- Slack message **deletes** (`mcp__slack__chat_delete`, `chat_delete_scheduled_message`, CLI `slack delete`) are uncovered. Audit item 6's Slack scope is the unasked post, and round 1 rejected DELETE-OUT expansions on measured grounds, so this is deferred rather than refused. The MCP already fails closed on messages the agent did not author.
- `gh api graphql` mutations: 716 statements, 170 mutations, zero on a guarded surface.

**Handed to Scott, not fixed here:** `/run/user/1000/{borg,cortex,sb-harvest}.env` are mode 0664, so roughly 40 live credentials are readable by any local process on this machine. That is a configuration finding for the daemons that write those files, outside this chunk and outside this repo.

### Edge cases each rule has to survive

Found in pass 4, each one pinned as a matrix fixture in its phase:

- **GH-WRITE**: a leading slash (`gh api /repos/o/r`), gh's own `{owner}`/`{repo}` template placeholders, a method after the path rather than before it, and the implicit-POST form above.
- **DELETE-OUT**: `--help` passes; `--yes` does not change the verdict; the deny covers `acli jira workitem delete` and `acli confluence page delete` and nothing else in `acli`.
- **LN**: the one-argument form (`ln -s target`, link name inferred from the basename in the cwd), a relative target, combined short flags (`-sfn`), the long form (`--symbolic`), and a `cd` prefix, which the rule resolves with its own LN-local accumulation over the command's `cd` chain, starting from the payload's `cwd`. **Not** `lib.sh`'s `cd_target`/`cd_at`: the LN rule explicitly rejects them because they replace rather than accumulate, so `cd ~/repos/scottidler/claude && cd HOME && ln -s ...` yields the relative `HOME`. This bullet still prescribed them after round 3; it is the same fold-propagation miss as the `-i` commit row.
- **INGEST**: `sb borg reingest` and a bare `borg ingest` both count. The `BULK_INGEST_ORDERED_BY_SCOTT` door can be typed by the model as easily as by Scott, exactly like chunk C's `PANEL_ROUNDS_ORDERED_BY_SCOTT`. The mitigation is the same and it is not cryptographic: the variable name makes an agent-authored override plainly visible in the transcript and in `clyde permit log`.
- **PUBLIC-REPO**: the path sets are specified at the rule, per commit form and per push form; neither is `git diff --cached` alone and neither is an endpoint diff. Bare-container worktrees put the tree under `/main/`, so the rule resolves the repo root with `git rev-parse --show-toplevel` and never by string-matching the cwd.
- **SLACK**: a missing or unreadable `~/.cache/slack/ids.json` fails **closed** with a deny that names the refresh command, rather than failing open into an inert guard. `#clipboard` and Scott's own DM stay allowed in that state, because their ids are literals in the hook and need no cache.
- **SECRET**: the `Read` deny covers `Read` only. `Grep` and `Glob` over a credential path are not covered, and a `Grep` result can carry a matching line. Named as a residual hole rather than patched blind, because no instance of it appears in the corpus.

### Prose narrowed, not deleted

Chunk D's program rule is enforcement before prose. Checked line by line, neither prose target is a deletable sentence: both are clauses inside a rule that covers more than this chunk's guards.

- `HOME/repos/.claude/rules/git.md:62` is a push-rejection rule that ends "do not change repo settings (merge methods, protection, rulesets). Report the exact rejection to the user." The bullet's subject is a rejected push to main, not repo settings. GH-WRITE makes the parenthetical mechanical, so it becomes a pointer at the guard; the bullet stays.
- `HOME/repos/.claude/rules/interaction.md:110` reads "Research results go in the response, not auto-filed into the vault or elsewhere". INGEST covers the vault half only. The "or elsewhere" half has no guard, so the sentence stays and gains the hook name.
- The confirm-first prose in the Slack skills is rewritten to Scott's 09-11 two-target split, not deleted.

Net prose deleted by this chunk: none. An independent grep over all 19 `rules/*.md` and 7 `refs/*.md` found no duplicate prose at all for items 1 through 7, and the one hit for item 8 (`rules/secrets.md:8`, "NEVER print, echo, log, or commit a decrypted value") is broader than any hook and stays. So the program's "delete the duplicate rule text" rule is satisfied by vacuity here, and the two clauses above are narrowed rather than removed. That is a departure from chunks A through C, and it is the honest reading of the files rather than a deletion invented to satisfy the rule.

Nothing changes in a rule before the guard that replaces it is live and its matrix is green. Chunk B's lesson applies: the phase that adds a file another live hook depends on runs the link step in the SAME phase.

## Data Model

```
~/.cache/intent-guard/visibility/<owner>-<repo>    visibility + epoch read, one week life,
                                                   a cached `private` revalidated before an allow
~/.cache/slack/ids.json                            channels, users, handles, *_synced_at (existing)
~/.cache/slack/sent-ledger/<target>-<body-hash>    one file per pair, one hour life. Created with
                                                   O_EXCL by the PreToolUse half (the create IS the
                                                   mutual exclusion), marked sent by PostToolUse,
                                                   left in place on a failure
```

GH-WRITE, DELETE-OUT and INGEST keep no state: all three are pure functions of the command string. **LN is not**: it needs the cwd the statement runs in and the filesystem state of the link's parent, which is why its corpus replay has to carry the recorded cwd.

## Implementation Plan

#### Phase 0: prove what is left unproven, zero code
**Model:** opus
Two of the three questions the draft asked are already answered by chunk C's own spike, so this phase is narrower than it was:

- **Answered, not re-spiked: `transcript_path` reaches `PreToolUse`.** Two independent grounds: the verbatim 2.1.272 payload at `docs/design/2026-09-14-panel-round-cap-phase0/evidence.md:16-41`, and `PreToolUseHookInput` inheriting `transcript_path: str` in `claude_agent_sdk/types.py:282,312`. `prompt_id` is present too.
- **Answered, and the research fold-in had it backwards: the guard must read `user` records, not `last-prompt`.** The fold-in claimed the `last-prompt` record lands before the turn's first `tool_use`, generalizing from a session that contains exactly one typed prompt. Measured by the panel over the 400 most recently modified transcripts, 1,122 typed-prompt turns followed by a tool call:

  | turn | `last-prompt` before first `tool_use` | only after | absent |
  |---|---|---|---|
  | session's first typed prompt | 298 / 386 (77.2%) | 72 (18.7%) | 16 (4.1%) |
  | every later typed prompt | 46 / 736 (6.2%) | 568 (77.2%) | 122 (16.6%) |
  | all turns | 345 / 1,122 (32.0%) | 640 (59.4%) | 92 (8.5%) |

  A `PreToolUse` guard keyed on `last-prompt` is wrong 93.8% of the time on a later turn. The `type=="user"` string record is earlier in append order in 1,122 of 1,122 cases, so that is the source. This **inverts `prose.sh`'s precedence** for a mid-turn guard: `:137` tries `last-prompt` first and falls back to `user` at `:139-143`; for this use the fallback is the primary. It also means Alternative 4's recorder is not the only remaining option if the flush answer is bad: reading `user` records is.
- **Still unproven, and this is the gate.** Whether the record is flushed at the instant a hook fires cannot be read off a completed file. A scratch `PreToolUse` Bash hook dumps what it can see, for three cases: a plain prompt, a slash-command prompt, and a turn whose first tool call is the guarded one. The `TAIL_CAP` question this criterion was going to carry is **already closed** by a static reconstruction over 7,203 tool calls: a 200K tail reaches the prompt record 51.673% of the time and 4 MB reaches 99.944%, so the cap stays and the scan is gated instead.
- **Also unproven.** Whether a `"matcher": "Read"` block fires at all, and whether its deny blocks the call with `Read(**)` still in `permissions.allow`.
- **What a `PostToolUseFailure` payload carries**, dumped from a deliberately failed MCP tool call. RESEND's failure path depends on it, and the installed 2.1.273 appears to deliver `error` rather than a tool result, which is why the rule fails closed on a failure rather than trying to read per-recipient outcomes. Confirm or correct that before Phase 5.
- **Free measurement while the harness is up.** Whether `prompt_id` is constant across every tool call in one turn. If it is, it replaces `prose.sh`'s ordering heuristic with an exact staleness key.
- **The latency measurement needs a budget, not just a number.** Pass is **total** added cost under 250 ms per Bash call across everything this chunk registers, not 150 ms for one hook: the chunk adds `intent-guard.sh`, `slack-post-guard.sh` (which scans a transcript and reads `ids.json`) and a `Read` matcher. Measured against the named payload classes: a small command, a command in a repo with a cold visibility cache, and a session with a large transcript. Over budget, the design reopens on rule-count-per-hook. A re-measure after the last phase is part of the final sweep.

  **Measured 2026-09-15, and it FAILS.** Full numbers and per-hook table: `docs/design/2026-09-15-intent-guards-phase0/evidence.md`.

  | component | cost |
  |---|---|
  | transcript scan at `prose.sh:95`'s `TAIL_CAP=4000000`, 8.7M transcript | 230 ms |
  | `intent-guard.sh` floor (bash + source `lib.sh` + read stdin) plus `stmts` | 32 ms |
  | `slack-post-guard.sh` reading `ids.json` (204K) | 12 ms |
  | **total, before the `Read` matcher** | **274 ms** |

  Over the 250 ms budget on the large-transcript class, which is 83 of 5,052 transcripts today (1.6%, and the largest is 15.8 MB). Not a random 1.6%: a session reaches that size by running long, which is the session doing outward work worth guarding. For scale, the existing Bash chain already costs 510 to 549 ms per call across its ten hooks plus `clyde permit log`, so this budget is being added on top of half a second.

  **The `TAIL_CAP` lever is dead, measured and closed.** Cutting 4 MB to 200K would take the scan to 18 ms, but it costs the TARGET rule the thing it exists to read. Reconstructed over 7,203 tool calls in 250 transcripts, measuring how far back the turn's typed-prompt `user` record sits from the transcript's end at the instant the hook fires:

  | tail cap | tool calls whose prompt record is inside it |
  |---|---|
  | 200K | 51.673% |
  | 500K | 72.900% |
  | 1 MB | 85.700% |
  | 4 MB | **99.944%** |

  p50 is 187 KB, p90 is 1.41 MB, p99 is 3.27 MB. A 200K cap blinds the rule on nearly half of all tool calls, so `TAIL_CAP=4000000` is right-sized and stays.

  **The fix is to gate the scan, and it is not rule-count-per-hook either.** The 230 ms was only ever a per-Bash-call cost because the round-3 text put `slack-post-guard.sh` on the Bash matcher scanning unconditionally. The TARGET rule needs the prompt only when a Slack post is actually happening. So the hook runs a **cheap predicate on the command first and reads the transcript only on a Slack-posting command**. Measured against the same 8.7M transcript:

  | shape | plain Bash command | Slack-posting command |
  |---|---|---|
  | ungated (round 3's text) | 230 ms | 230 ms |
  | **gated (this fix)** | **27 ms** | 269 ms |

  Chunk total on a generic Bash call becomes `intent-guard.sh` 32 ms plus `slack-post-guard.sh` 27 ms = **59 ms**, inside the 250 ms budget on every session regardless of transcript size. The 269 ms is paid only on a Slack post, which is not a per-Bash-call cost and is not what the budget measures.

  **Criterion 7 PASSES in the gated shape and FAILS in the ungated one**, so the gate is a requirement on Phase 5 rather than an optimization. The scan cost is linear in bytes read (`scan_ms = 0.061 * KB + 11.8`, fitted over six sizes from 102K to 3.9M), and the ungated shape crosses the budget at 3.13 MB read, which 189 of 5,048 transcripts (3.74%) exceed. That is the failure this gate removes rather than tolerates.
- **Extractor miss rate, with a threshold.** Run the extractor over at least 40 turns from `~/.claude/projects`, counting false authorizations by class: teammate relays and `<command-*>` wrappers. Pass is **zero** false authorizations of either class, because a single one is a guard that treats machine traffic as Scott's instruction. A miss that returns *no* prompt is a different outcome and is measured separately: over 20% of turns and the TARGET rule degrades per the fallback below. Two defects are already known in `prose.sh:131-153` and get fixed rather than measured: the relay filter `startswith("Another Claude session sent a message:")` is applied only on the `last-prompt` branch (`:137`) and not the `user` fallback (`:139-143`), and the `startswith("<")` clause silently discards slash-command turns whose shape is `<command-message>...</command-message>` plus `<command-name>` plus `<command-args>`.
- **Success criteria:** `docs/design/2026-09-15-intent-guards-phase0/evidence.md` answers all eight, each with its command and output. **COMPLETE as of 2026-09-15.** The extractor criterion PASSES (0 false authorizations of either class over 1,237 turns, against 272 = 22.0% for the current extractor, so both `prose.sh` fixes are load-bearing). The latency criterion PASSES in the gated shape recorded above after failing in the ungated one. The three live-probe criteria were measured by registering scratch probes, exercising them, and removing them in the same session:

  - **The turn's record IS readable at hook time.** The transcript grew 28,038 bytes between two calls in one turn and the most recent `user` record sat 1,263 bytes from EOF. No `UserPromptSubmit` recorder is needed and Alternative 4 stays an alternative.
  - **`prompt_id` is identical across every tool call in a turn**, confirmed live, so it is the exact staleness key and `promptId`'s provisional status is closed.
  - **A `Read` matcher fires and its deny BEATS `Read(**)` in `permissions.allow`.** Phase 6 has its seam and this doc does not reopen.
  - **`PostToolUseFailure` carries `error` as a string and no `tool_response` key**, which confirms round 3's fail-closed RESEND ruling rather than merely permitting it. A tool that reports "not found" in its result is a SUCCESSFUL call and does not raise this event, which matters for any rule keyed on it.
  - **`fits_200k=no` on the measuring session itself**, with the typed prompt 1.36 MB from EOF: live confirmation of the `TAIL_CAP` result above. If the `Read` matcher does not fire or its deny loses to `Read(**)`, the SECRET Read half has no seam and this doc reopens rather than the phase improvising. If the current turn's prompt is not reliably readable, the fallback is the `UserPromptSubmit` recorder in Alternative 4, and the SLACK TARGET rule degrades to the exempt-id allowlist plus TEST-TEXT plus RESEND only if the recorder is also unavailable. Round 2 flagged that Phase 0 and Alternative 4 disagreed on this; the recorder is first, the degrade is second, and the doc is amended before Phase 5 either way.

#### Phase 1: close chunk B's secret-guard hole
**Model:** opus
- `secret-echo-guard.sh`'s echo/printf check gated with `cmdword_is` per statement, payload matched on the squote-masked copy, the verb regex deleted from the Python matcher
- **Success criteria:** `'echo' $GH_TOKEN` denies and `echo '$GH_TOKEN'` still allows, both asserted **directly**; the unquoted `echo $GH_TOKEN` rides all 18 `wrap_shapes` spellings green; the existing 39 assertions in `secret-echo-guard-test.sh` pass unchanged

> Why the split: `shapes.sh:45-46` states that "a command carrying a single quote or a newline cannot ride the quoted shapes, so fixtures fed to this are the plain ones." Two of the 18 spellings are `eval '%s'` and `bash -lc '%s'`, which a single-quoted fixture cannot survive. Every chunk-D fixture was checked against this: the `gh api -XDELETE`, `acli ... delete`, `ln -s` and `aws secretsmanager` fixtures are quote-free and ride the full sweep; the two single-quoted secret fixtures are asserted directly.

#### Phase 2: `intent-guard.sh` skeleton, GH-WRITE and DELETE-OUT
**Model:** opus
- New hook sourcing `lib.sh`, `--help` and `--self-test` like `prose.sh`, registered on the Bash matcher, symlink verified by `hooks-preflight.sh` in this phase
- GH-WRITE and DELETE-OUT rules; matching on `stmts` output only, never the raw string
- `intent-guard-test.sh` matrix, every deny fixture re-run through `shapes.sh`'s `WRAPPER_SHAPES`
- permission-deny entries for `acli jira workitem delete`, `acli confluence page delete`, `gh repo edit`
- `.otto.yml` lint `FILES` list grown with every file this phase touches
- **Success criteria:** `otto ci` exits 0; the matrix denies the two incident commands verbatim (`gh api -X DELETE repos/tatari-tv/valet/branches/main/protection/enforce_admins`, `acli jira workitem delete --key SEC-2997 --yes`) in all 18 `wrap_shapes` spellings; `gh api repos/tatari-tv/philo/pulls/1 -X PATCH -f body=x` is allowed
- **Method-parse criteria, one fixture each, because these are what the phase exists to get right:** `-XDELETE`, `--method=DELETE`, `-X delete` (lowercase), `-X GET -X DELETE` (last wins, denies), `--method GET -f x=1` on a guarded path (explicit GET with fields, allows), `--field x=1` with no method (implicit POST, denies), a leading slash (`/repos/o/r`), and gh's `{owner}`/`{repo}` placeholders
- **Both round-4 bypass regressions, asserted directly:** `gh api -XDELETE -p -XGET /rate_limit` denies, and `gh api -XDELETE --header "-XGET: x" /rate_limit` denies. Plus one operand-skip fixture per value-taking flag in the table above, so a missing alias fails the matrix
- The five `flag_value` characterization fixtures added to `lib-test.sh`, pinning current behavior without changing the parser

#### Phase 3: LN and the `~/Claude` policy
**Model:** opus
- Prospective-link-entry predicate (`dirname` resolved, basename never dereferenced); `~/Claude` link-path deny; the four operand forms (directory destination, `-t DIR`, relative target, `-n`/`-T`)
- **Corpus replay**: all ~112 `ln -s` statements from the window replayed with their recorded cwd
- **Success criteria, amended 2026-09-15 after the replay ran.** The 2026-07-03 command is denied verbatim; `ln -sf <repo>/HOME/.claude/hooks/x.sh ~/.claude/hooks/x.sh` over an existing link is allowed; the `for b in ... ln -sf $(command -v $b) .` command is asserted as an **allow**; a relative link path whose cwd cannot be resolved at all denies. The corpus replay over **163** `ln -s` statements with their recorded cwd denies **exactly 9**, and every one is accounted for:

  | count | rule | what they are |
  |---|---|---|
  | 3 | cycle | the known loop-repro probes (`/tmp/loopprobe`, `/tmp/lp2`, `/tmp/manifest-repro`) |
  | 3 | `~/Claude` policy | the voice-corpus links into `~/Claude/writing/voice` |
  | 1 | cycle | `ln -s . 5626` |
  | 1 | fail-closed | `(cd "$S" && ln -sf .../otto/target target)`, a subshell before a relative link path |
  | 154 | allow | everything else |

  **Why the old criterion ("exactly the 3 known loop-repro probes and nothing else, out of 51") was a doc defect, independent of the implementation.** Three reasons, each checkable without running the guard:

  - **The corpus is 163 statements, not 51 or 112.** Those counts came from `rg -o '"command":"[^"]{0,600}ln -s[^"]{0,600}"'`, which caps each match at 600 characters and so drops every long command. Walking the transcript JSON properly yields 163 unique (command, cwd) pairs, all with a recorded cwd.
  - **The criterion counted one rule and the replay exercises two.** The `~/Claude` policy is the LN rule's second half and it correctly denies 3 corpus commands. "Nothing else" could never have been true while that half shipped.
  - **`ln -s . 5626` is ancestor-shaped by inspection.** It yields `5626/5626/5626` without bound, which is the class the rule exists to catch. It was deliberate (a URL prefix), and a deny is still the correct outcome: Scott re-runs it with `!`, the same disposition GH-WRITE takes for his own protection changes.

#### Phase 4: INGEST
**Model:** opus
- Heredoc-reading rule, the `BULK_INGEST_ORDERED_BY_SCOTT` door, `rules/interaction.md:110` amended to name the hook
- Matrix includes the incident's `cat > ingest.sh <<'EOF' ... EOF` statement verbatim and the single-URL form
- **Success criteria:** the script-creation statement is denied and the same heredoc written to a `.md` target is allowed; `sb borg ingest --tags x -- https://one.url` is allowed; `ingest --file`, `reingest --all` and a variable URL operand each deny; `reingest-failed --dry-run` allows; the 5-URL 2026-06-21 form is denied without the door and allowed with `BULK_INGEST_ORDERED_BY_SCOTT=5` as a leading assignment, while the same marker inside a fenced block in a heredoc body does not open it

#### Phase 5: SLACK
**Model:** opus
- `slack-post-guard.sh` on the MCP write tools and the Bash matcher for `PreToolUse`, **and on `PostToolUse`** to record confirmed sends; three rules; the `~/.cache/slack/sent-ledger/` entry directory with `O_EXCL` creates
- **The transcript scan is gated behind a cheap command predicate and never runs on a non-Slack Bash call.** This is a latency requirement, not an optimization: Phase 0 measured the ungated shape at 230 ms on a large transcript against a 250 ms whole-chunk budget, and the gated shape at 27 ms. The predicate runs before `lib.sh` work of any weight
- The two-target confirmation split written into the Slack skills
- **Success criteria:** the hook exits without reading the transcript for a non-Slack Bash command, asserted by measuring against a transcript over 4 MB and requiring the call to stay under 50 ms; a post to `#clipboard` with no mentions and no `--broadcast` passes with no confirmation and no cache read; a post to an unnamed channel is denied; a `**MCP write test**` first line to a DM is denied; a repost of the same body to the same target after a recorded send is denied, and **also denied after a recorded failure**, with the deny text naming the entry file to remove; two concurrent `O_EXCL` creates for the same (target, body-hash) leave exactly one allowed; two concurrent reclaims of the same **expired** entry also leave exactly one allowed, asserted against the atomic-replace path and not just the fresh-create path; a `#clipboard` post carrying `--broadcast <other-channel>` is denied

#### Phase 6: SECRET vectors and the Read deny
**Model:** opus
- The corrected statement vectors in `secret-echo-guard.sh`; `Read` matcher registration and the measured path list
- Gated on Phase 0's `Read`-matcher criterion; developed against a copy before the live file is written (see Blast radius)
- **Success criteria:** each vector command is denied in all 18 `wrap_shapes` spellings; `--query SecretString` is denied and `--query ARN` is allowed; `jq .expires_at ~/.cache/slack/token.json` is allowed while `cat` of the same file is denied; the three jq-grammar assertions, `has("access_token")` allows, `.access_token` denies, and `has(.access_token | debug)` denies; the existing assertions in `secret-echo-guard-test.sh` pass unchanged

  **Amended in Phase 6: the count is 77, not 39.** Phase 1 of this chunk added the wrapper sweep and the single-quoted-verb fixtures to that matrix, so the number this criterion was written against was already out of date when the phase started. Measured by running the committed matrix at `e2cb587` against the committed guard, then against the Phase 6 guard:

  ```
  original test against original guard   pass=77 fail=0
  original test against the NEW guard    pass=77 fail=0
  ```

  The criterion's substance (no existing assertion regresses) holds; only its count was wrong

#### Phase 7: PUBLIC-REPO
**Model:** opus
- Visibility cache (unknown reads as public), the three-source path set for commit, refspec parsing plus commit-walking for push, blob-size check
- **Success criteria:** the founding incident's `git add ... && git commit` one-liner is denied with an empty index; `git push origin intent-guards:main` on a public repo with a sensitive path in the outgoing commits is denied, and an unresolvable refspec is denied rather than allowed; the same paths in `scottidler/keep` (private) are allowed
- **Commit-form criteria, one fixture each, all against an EMPTY pre-hook index:** `git add <sensitive> && git commit -am msg` denies, `git add <sensitive> && git commit --include README.md -m msg` denies (the round-4 miss), `git commit --only README.md` with a sensitive path staged allows, and `git add docs/` expands through `git ls-files -co --exclude-standard -- docs/` rather than a filesystem glob
- **Push-destination criteria, one per outcome:** the destination resolves locally and the commit walk runs; it resolves at `ls-remote` but `git cat-file -e` returns 1, so the walk cannot run and the push denies; the refspec does not resolve at all and denies

## Blast radius and ship order

- **Single repo.** Every file this chunk touches is in `scottidler/claude`: `HOME/.claude/hooks/*`, `HOME/.claude/settings.json`, `HOME/repos/.claude/rules/{git,interaction}.md`, the Slack skills, `.otto.yml`. No other repo changes.
- **The write fence is Bash-only, not absolute.** Verified 2026-09-15 with touch probes from this session: writable via Bash are `HOME/.claude/hooks/`, `HOME/repos/.claude/rules/`, `bin/`, `docs/design/` and `.otto.yml`; denied via Bash are `HOME/.claude/agents/`, `HOME/.claude/skills/`, `HOME/.claude/output-styles/`, `HOME/.claude/settings.json` and `HOME/.claude/CLAUDE.md`. The **Edit tool reaches the denied set**, proven inside this program by `f257ddb` (registered `panel-round-guard` in `settings.json`) and `ca3bfe8` (edited `HOME/.claude/agents/review-panel.md`). So the chunk is not blocked: new hook files land in a Bash-writable directory, and the `settings.json` registrations go through Edit. What is forbidden is a Bash redirect or heredoc into the denied set.
- **Hooks go live on SAVE, not on commit.** `~/.claude/hooks/` holds **per-file** symlinks into the working tree (verified 2026-09-15: `allow-help.sh -> /home/saidler/repos/scottidler/claude/HOME/.claude/hooks/allow-help.sh`, and the same for every entry). So an already-linked script is live the instant the file is written, before `otto ci` and before the commit. "Matrix green before the commit" isolates nothing for an **edited** hook. Only a **new** file waits, and it waits for its `manifest -l` link plus its `settings.json` registration, not for the commit.
- **Copy-before-live applies to every already-live script and every shared dependency, not just the two phases that edit `secret-echo-guard.sh`.** The candidate predicate is developed and exercised against a **copy** under a scratch name, the matrix runs against the copy, and only then is the live file written. That covers Phase 1 and Phase 6 on `secret-echo-guard.sh`, and it also covers `intent-guard.sh` in Phases 3, 4 and 7, because Phase 2 registers it and every later edit lands on a live hook. `lib.sh` is in the same position (`~/.claude/hooks/lib.sh` is a symlink into the working tree and three shipped guards source it), which is one of the reasons this chunk no longer edits it.
- **Recovery path for a guard that denies its own repair.** `secret-echo-guard.sh` is registered on Bash, so a broken version can deny the very `sed`/`python3` call that would fix it. The escape is the Edit tool, which is not on the Bash matcher, and the fallback is Scott running the repair with `!`. Named because Phase 1 edits that exact guard.
- **The rails plugin loads once per session**, so nothing in this chunk may depend on a rails change taking effect in the session that lands it. Chunk D adds no rails hooks, so this only matters if the Open Question resolves to option B.
- **Ship order: Phase 0, then Phase 1, then free.** Phase 1 closes a live bypass of a shipped guard and outranks every new rule. After that the rules are independent: no rule reads another's state, and the only shared file is the hook skeleton Phase 2 creates. Phases 3, 4 and 7 depend on that skeleton; Phases 5 and 6 are separate files and can land in any order. Eight phases, 0 through 7.
- **Landing.** `git push origin intent-guards:main`, per the program hazard: `git checkout <branch>` fails in this repo from a session whose own config it is, and a partial checkout leaves the working tree half-reverted.

## Requirement traceability

Every rule here traces to audit item 6, which traces to a measured incident with Scott's own reaction quoted in the findings post. The two additions beyond the audit's change list, and who asked:

- **The `~/Claude` symlink-free deny** (part of LN): Scott's own `CLAUDE.md`, "~/Claude is the Cowork/Syncthing space, so no symlinks there".
- **The Slack two-target confirmation split**: Scott, 2026-09-11, quoted in full above.

Nothing else in this doc was added on the author's initiative. The audit's Gmail delete item and the prescribed prompt-word commit guard are the only two prescriptions not built, both recorded with numbers.

## Technical Considerations

### Dependencies
- `lib.sh` (chunk B) for statement splitting and masking; `shapes.sh` (chunk C's audit) for the wrapper-mutation sweep; `hooks-preflight.sh` (chunk B) for registration.
- `jq` for the deny payload, `realpath -m` for LN, `gh` for one cached visibility read per repo.
- No new binary, no new package, no network call on the hot path.

### Performance
Ten Bash `PreToolUse` guards already cost 689 ms as a sum of individual runs (measured 2026-09-15, trivial payload). Chunk D adds one Bash hook, not six, and one `Read` matcher registration on a guard that already exists. PUBLIC-REPO's visibility lookup is cached to a file because a `gh` call per commit would dominate everything else.

### Security
This chunk is the security work. Two notes on not making it worse:
- The SECRET rules match on masked statements and never echo the matched value. The existing guard's contract already forbids printing a secret in its own deny text, and the new vectors inherit it.
- The `Read` deny list names credential paths, so the list itself is a map of where credentials live. It contains only path patterns already documented in `rules/secrets.md` and `rules/marquee.md`, nothing new.

### Testing Strategy
- One `*-test.sh` matrix per new or extended hook, run by `otto ci`, sitting next to the hook as the existing ten do.
- Every irreversible-deny fixture re-run through `shapes.sh`'s `WRAPPER_SHAPES`. Chunk C's audit found 22 deny-to-allow flips from exactly the gap this closes.
- Break-the-code evidence per rule: the rule is disabled, the matrix is re-run, and the failing assertion count is recorded in the implementation notes. Green matrices over an untested predicate is how chunks B and C both shipped a broken core.
- **Chunk C's process rule applies directly here**: a guard that parses a document or a script body must be tested in the form the artifact actually uses. INGEST reads heredoc bodies, so its matrix pins the incident's quoted-delimiter heredoc verbatim, not an inline-backtick paraphrase.

### Rollout Plan
Phase by phase, each its own commit, `otto ci` green before the commit, pushed to `main` with `git push origin intent-guards:main`. No flag and no staged rollout, and note what that means precisely: a shell hook is live the moment its file is **written**, not when it is committed (see Blast radius). The commit records it; the save deploys it. After the last phase, a round-1 implementation audit dispatched under the guards it is auditing, then the acceptance criteria re-run against the live setup and recorded.

## Acceptance Criteria

Every criterion below was executed against `main` at 53f2904 on 2026-09-15 and the output recorded. Where a criterion cannot pass until a phase ships, it says which phase.

- [ ] Every rule in this doc has a deny fixture in a `*-test.sh` matrix, quote-free fixtures riding the full `wrap_shapes` sweep, and `otto ci` exits 0.
  **Observed on main:** `WRAPPER_SHAPES` holds 16 entries (`HOME/.claude/hooks/shapes.sh:21-37`) and `wrap_shapes "git tag -d v1" | wc -l` returns **18** (the 16 wrappers plus `\cmd` and `"verb" rest`). 11 `*-test.sh` matrices exist; 5 of them source `shapes.sh`. `HOME/.claude/hooks/intent-guard-test.sh`: "No such file or directory". Cannot pass before Phase 2.
  **Observed on branch `intent-guards` 2026-09-15 (Phases 0-4, 7 committed; Phase 5 in the tree; Phase 6 unbuilt):** `otto ci` exits 0 ("All CI checks passed!"). Matrices green: `intent-guard-test.sh` 131/0, `slack-post-guard-test.sh` 108/0, `secret-echo-guard-test.sh` 77/0, `lib-test.sh` 140/0; `intent-guard-test.sh` sources `shapes.sh`. **Still fails** on "every rule": SECRET has no fixtures until Phase 6.
- [ ] Every incident command quoted verbatim in this doc is denied by the shipped guards, **except the unrequested-commit incident** (`git add .gitignore HOME/Claude/writing/voice && git commit`), which item 1's 2026-09-15 ruling leaves uncovered and which must therefore stay **allowed**. Nine of ten deny; the tenth is asserted as an allow.
  **Observed on main:** all ten fed through the live nine-guard Bash chain, every one **allowed**:

  ```
  allow  gh api -X DELETE repos/tatari-tv/valet/branches/main/protection/enforce_admins
  allow  gh api -XDELETE  repos/tatari-tv/valet/branches/main/protection/enforce_admins
  allow  acli jira workitem delete --key SEC-2997 --yes
  allow  ln -s ~/repos/scottidler/claude/HOME/Claude/writing/voice ~/Claude/writing/voice
  allow  cd ~/repos/scottidler/claude && git add .gitignore HOME/Claude/writing/voice && git commit -m x
  allow  aws secretsmanager get-secret-value --secret-id x
  allow  systemctl --user show-environment
  allow  cat /run/user/1000/borg.env
  allow  'echo' $GH_TOKEN
  allow  gh repo edit tatari-tv/mcp-io-rs --visibility public
  ```

  The ninth line is chunk B's open hole reproduced through the live chain, not a synthetic case.

  **Observed on branch `intent-guards` 2026-09-15 (Phases 0-4, 7 committed; Phase 5 in the tree; Phase 6 unbuilt):** **six of ten deny** through the live twelve-guard chain. Denied: both `gh api` protection forms, `acli jira workitem delete`, the `~/Claude` symlink, `'echo' $GH_TOKEN` (Phase 1 closed chunk B's hole), `gh repo edit --visibility public`. Allowed: `aws secretsmanager get-secret-value`, `systemctl --user show-environment`, `cat /run/user/1000/borg.env`, all three Phase 6; plus the commit line, which is the asserted allow above.
- [ ] The `ln -s` corpus replay over the **163-statement** corpus denies only the ancestor-shaped and fail-closed statements Phase 3 enumerated (the loop-repro probes, `ln -s . 5626`, and the one unresolvable `$S` cwd), with no other deny; and the `secret-echo-guard` path list's ~200 measured auth-debugging occurrences produce **zero** denies. The earlier "exactly 3 out of ~112" form was wrong on all three counts: the ~112 came from an `rg -o` pattern capping each match at 600 characters, the replay exercises the `~/Claude` half as well as the cycle half, and `ln -s . 5626` is ancestor-shaped by inspection. Corrected 2026-09-15 from Phase 3's replay, same amendment the per-phase criterion already took.
  **Observed on main:** no guard denies any of them today. That trivially satisfies the `secret-echo-guard` half (zero denies is what it asks for) and **fails** the `ln` half, which requires exactly 3. Both become meaningful only after Phases 3 and 6. The `ln` half is deliberately not "zero denies": three of the corpus statements are the exact ancestor shape the rule exists to catch, so a zero-denies assertion would be unsatisfiable. That was round 2's finding and it reached the rule text but neither criterion until now.
  **Observed on branch `intent-guards` 2026-09-15 (Phases 0-4, 7 committed; Phase 5 in the tree; Phase 6 unbuilt):** the `ln` half is exercised by the 18 committed Phase 3 fixtures in the matrix rather than by a hermetic test, per Phase 3's note that a replay reading `~/.claude/projects` cannot be hermetic. The `secret-echo-guard` half stays unmeasurable until Phase 6 adds the path list.
- [ ] `hooks-preflight.sh` reports every new hook as resolving and executable at session start.
  **Observed on main:** registered at `HOME/.claude/settings.json:973`; run directly it emits no warning and exits 0. It proves registration, not behavior: it has caught zero misses since it shipped.
  **Observed on branch `intent-guards` 2026-09-15 (Phases 0-4, 7 committed; Phase 5 in the tree; Phase 6 unbuilt):** **passes.** `hooks-preflight.sh` exits 0 with no warning, and `intent-guard.sh`, `slack-post-guard.sh` and `shapes.sh` all resolve through the live `~/.claude/hooks` symlinks.
- [ ] `git ls-files | grep -cE 'personal/|excluded/|voice/|secrets?/|\.env$|\.age$'` returns 0 in `scottidler/claude`, and no tracked file exceeds 1 MB.
  **Observed on main:** `0` and `0`.
  **Observed on branch `intent-guards` 2026-09-15 (Phases 0-4, 7 committed; Phase 5 in the tree; Phase 6 unbuilt):** **passes.** `0` and `0`.
- [ ] `rules/git.md:62` and `rules/interaction.md:112` each name the guard that now enforces the clause. (Phase 4's edit landed the `intent-guard.sh` pointer at 112; the criterion's original `:110` predated it.)
  **Observed on main:** `git.md:62` is the push-rejection bullet ending "do not change repo settings (merge methods, protection, rulesets)", no hook named; `interaction.md:110` reads "auto-filed into the vault or elsewhere", no hook named.
  **Observed on branch `intent-guards` 2026-09-15 (Phases 0-4, 7 committed; Phase 5 in the tree; Phase 6 unbuilt):** `interaction.md:112` names `intent-guard.sh`, so that half **passes** at the corrected line. `git.md` names no guard anywhere, so the GH-WRITE pointer that "Prose narrowed, not deleted" prescribes is **still owed**, and GH-WRITE being live and green satisfies its stated precondition.

## Acceptance criteria: results

Walked 2026-09-15 against the shipped code, after Phase 6. Four pass, two fail, and both failures are decisions rather than unbuilt work.

### 1. Deny fixtures, the wrapper sweep, and green CI: FAIL

`otto ci` exits 0 and every rule has a deny fixture. The sweep is the gap. GH-WRITE, DELETE-OUT, SLACK and SECRET ride `wrap_shapes`; the acceptance walk added LN, which holds 18 of 18 on both `ln -s . 5626` and `ln -s /tmp /tmp/loop`. INGEST and PUBLIC-REPO still do not ride it, and running the sweep by hand says why it matters:

```
ln -s . 5626              deny=18 allow=0
ln -s /tmp /tmp/loop      deny=18 allow=0
sb borg reingest --all    deny=15 allow=3
  ALLOW: eval "sb borg reingest --all"
  ALLOW: eval 'sb borg reingest --all'
  ALLOW: bash -c "sb borg reingest --all"
```

**INGEST has a live bypass in 3 of 18 spellings.** The rule is command-scoped by design (the doc settles that: `stmts` splits the incident's loop body apart), so it matches on the fully masked copy, and masking double quotes erases the payload of `eval "..."` and `bash -c "..."`. That is the deny-to-allow class chunk C's audit counted 22 of. Not fixed here: it is a change to Phase 4's rule scope and it needs its own decision.

PUBLIC-REPO's fixtures are repo-state, not textual (a real scratch repo, `ls-remote`, `rev-list`), so wrapping them asserts nothing.

### 2. Every incident command denied, except the commit one: PASS

All ten fed through the live 12-hook `PreToolUse` Bash chain, in registration order, first deny wins:

```
deny   intent-guard.sh       gh api -X DELETE repos/tatari-tv/valet/branches/main/protection/enforce_admins
deny   intent-guard.sh       gh api -XDELETE  repos/tatari-tv/valet/branches/main/protection/enforce_admins
deny   intent-guard.sh       acli jira workitem delete --key SEC-2997 --yes
deny   intent-guard.sh       ln -s ~/repos/scottidler/claude/HOME/Claude/writing/voice ~/Claude/writing/voice
allow                        cd ~/repos/scottidler/claude && git add .gitignore HOME/Claude/writing/voice && git commit -m x
deny   secret-echo-guard.sh  aws secretsmanager get-secret-value --secret-id x
deny   secret-echo-guard.sh  systemctl --user show-environment
deny   secret-echo-guard.sh  cat /run/user/1000/borg.env
deny   secret-echo-guard.sh  'echo' $GH_TOKEN
deny   intent-guard.sh       gh repo edit tatari-tv/mcp-io-rs --visibility public
mismatches=0  chain=12 hooks
```

The ninth line is chunk B's hole, closed by Phase 1. The fifth is the allow the 2026-09-15 ruling requires.

### 3a. The `ln -s` corpus replay: PASS

163 statements, 11 denies, every one accounted for:

- 5 cycle-rule: `ln -s . 5626` twice, and the `/tmp/loopprobe`, `/tmp/lp2` and `/tmp/manifest-repro` loop probes.
- 1 LN fail-closed: the relative link whose cwd cannot be resolved (the `$S` case).
- 3 `~/Claude` policy, all genuine: two are literally `ln -sfn <repo>/HOME/Claude/writing/voice ~/Claude/writing/voice`, the founding incident.
- 2 INGEST, a different rule, on commands that genuinely carry an ingest statement. Confirmed not a heredoc false positive: a heredoc body naming the verb and three URLs written to a `.md` target allows, and the same body written to a `.sh` target denies.

### 3b. Zero denies over the credential-path corpus: FAIL

Rebuilt the corpus rather than trusting the count: 5,076 transcripts walked, every Bash `tool_use` command naming `token.json`, `tokens.json`, `/run/user/*/*.env`, `~/.config/*/*.env` or a shell history file. **300 unique commands**, which is the "over 200 occurrences" the pricing paragraph measured.

Against the shipped guard: **84 of 300 deny.** The first pass denied 108; the acceptance walk fixed 24 of those as unambiguous false positives (a statement with no command word, a path appearing only as a redirect target, a credential filename quoted inside `echo` prose, `grep`'s PATTERN operand read as a file, `[` and `source` and `:` and `tee`). What is left is the rule working as this doc specifies it:

```
  38  jq with a filter that is not on the allowlist   (22 of them captured into a variable)
  17  cat of a .env or token file
  14  grep or rg against a history or token file
   4  strings, 3 awk, 2 head, 1 tail, 1 sed
   2  the pre-existing env-var rule, not this chunk
   ~2 residual false positives (a case-arm fragment, one unknown verb)
```

**The criterion and the rule text contradict each other**, and that is the finding. The rule text says a reader that cannot project denies against these paths and any jq filter off the allowlist denies. The corpus contains those shapes in volume. The criterion's premise, that the measured traffic is `jq .expires_at` / `jq has(...)` / mode checks, is what the measurement refutes: the dominant idiom is `TOKEN=$(jq -r .value "$C")` feeding a `curl`, 22 commands, where the value goes into a shell variable and never reaches the transcript.

Open decision, for Scott: leave the rule as specified and amend the criterion, or carve out a captured-into-a-variable form (`X=$(jq -r .key <file>)` allows, a bare `jq .key <file>` still denies). Not decided here.

### 4. `hooks-preflight.sh` reports every new hook resolving: PASS

Run directly against the current `settings.json`: exit 0, no warning. `slack-post-guard.sh` and `slack-post-guard-test.sh` are linked into `~/.claude/hooks/`.

### 5. No sensitive tracked path, no tracked file over 1 MB: PASS

```
git ls-files | grep -cE 'personal/|excluded/|voice/|secrets?/|\.env$|\.age$'   ->  0
tracked files over 1 MB                                                        ->  0
```

### 6. The two prose clauses name their guard: PASS

`rules/git.md:62` now ends "do not change repo settings (merge methods, protection, rulesets); `intent-guard.sh`'s GH-WRITE rule denies the `gh api` and `gh repo edit` forms mechanically." `rules/interaction.md:112` names `intent-guard.sh` for the ingest clause.


## Resolved Decisions

- **2026-09-15: the prompt-word commit guard is not built.** Measured 590 denials against 2 of 5 incidents, and structurally unavailable in subagents. Superseded by Scott's 2026-09-15 ruling, which accepted the gap outright. Recorded as Alternative 1 so it is not re-proposed.
- **2026-09-15: Gmail delete/trash is not guarded.** Zero observed vectors across 10 `gws` delete-shaped statements, all Drive, all requested or `--help`. Revisit condition stated in Non-Goals.
- **2026-09-15: one hook, not five.** 689 ms of measured Bash-hook latency and five rules over one command string.
- **2026-09-15: LN guards the predicate, not the verb.** 112 legitimate `ln -s` statements in the window make a verb matcher unshippable.
- **2026-09-15: INGEST reads heredoc bodies**, against the general rule that guards match on the masked copy. The measured vector lives only in a heredoc body and the surface is 11 statements in four months.
- **2026-09-15: no `UserPromptSubmit` recorder, *provisionally*.** Settled: the `PreToolUse` payload carries `transcript_path` and `prompt_id`, and the source is the `type=="user"` string records, not `last-prompt` (panel round 1 measured the ordering over 1,122 turns). **Not settled, and it is Phase 0's gate:** whether the current turn's `user` record is visible at the instant a hook fires. Alternative 4 stays live against that result, and Phase 0 owns the fallback for both outcomes.
- **2026-09-15: skill-activity inference is refused outright**, not deferred. No payload field, and the transcript signal has no end marker. See Non-Goals.
- **2026-09-15: item 8's `Environment=` vector is replaced by the measured `EnvironmentFile=` targets.** Zero secret values in any unit file's `Environment=`; the credentials are in `/run/user/1000/*.env` and `*/token*.json`.
- **2026-09-15: chunk B's single-quoted-verb hole is chunk D's Phase 1**, ahead of every new rule, because it is a live bypass of a guard that is already shipped and already trusted.
- **2026-09-15, Scott's ruling: item 1 ships with no guard.** Asked as an A/B with five measured predicates; answer was A, accept the gap. Not a deferral: the class is uncovered and recorded as such in Non-Goals.
- **2026-09-15: the blanket-staging deny is dropped entirely**, after panel round 1 removed its item-1 claim and a measurement removed its phantom claim. Author's call on the evidence in Alternative 5, reversing the draft's own Rec.
- **2026-09-15 (panel round 2, reversing round 1): `flag_value` is NOT changed.** Round 1 decided the attached-short-option gap belonged in `lib.sh`. Round 2 measured the obvious fix flipping two shipped guards from allow to deny (`-t` yields `esting`, `-H` yields `bad/name`) and creating a fresh `-X` bypass, with `lib-test.sh` passing 135/0 over the patched copy. Root cause: `flag_value` has no per-flag arity table, so it cannot tell an attached value from a value beginning with a dash. GH-WRITE parses the method locally, last-wins and case-insensitive; the five measured rows become characterization fixtures in `lib-test.sh`.
- **2026-09-15 (panel round 2): PUBLIC-REPO's push half reads the destination from the remote** with one `git ls-remote`, and walks the range with `--diff-merges=first-parent`. A plain walk misses a file introduced by a merge resolution, measured; an endpoint diff misses add-then-remove, measured in round 1. The first-parent walk covers both.
- **2026-09-15 (panel round 2): a cached `private` visibility is revalidated before an allow**, not merely on a cold read. Unknown-reads-as-public does nothing for a stale `private` entry, which is the case that leaks.
- **2026-09-15 (panel round 2): `slack-post-guard.sh` also registers on `PostToolUse`.** A `PreToolUse` hook cannot observe a send result, so the round-1 RESEND state was unwritable and the rule was inert.
- **2026-09-15 (panel round 2): the client's recipient set is authoritative.** No exemption is granted on a cache staler than the client's own staleness window, because the client refreshes before expanding and the guard does not.
- **2026-09-15 (panel round 3): RESEND's exclusion is an `O_EXCL` entry create, not `flock`.** A `PreToolUse` process exits before the tool runs, so a lock it holds cannot span the send. The create does, because the filesystem outlives the process.
- **2026-09-15 (panel round 3): a failed Slack send leaves its ledger entry in place.** `PostToolUseFailure` carries `error`, not a result, so the guard cannot learn which recipients landed and the parent may have. A duplicate post to a coworker is worse than a one-hour wait, so it fails closed and the deny names the file to remove.
- **2026-09-15 (panel round 3): the INGEST door is evaluated first**, ahead of every deny clause, because evaluating denies first made the door unreachable. Read-only verbs come second, denies third.
- **2026-09-15 (panel round 3): `jq` against a credential path is allowed only on an allowlist of value-free filters.** "Shapes that print the whole file" was not an algorithm, and the two cases the pricing paragraph rests on (`has("access_token")` allows, `.access_token` denies) both print one line.
- **2026-09-15 (panel round 3): LN stops accumulating cwd at the first `(` or `$(` and denies an unresolvable relative link path.** `stmts` erases subshell boundaries, measured, so the alternative was teaching the rule shell scoping.
- **2026-09-15 (panel round 2): the INGEST raw-text scan is bounded to heredocs whose redirect target is a shell script.** Unbounded, it denies the writing of this design doc, which contains both a loop keyword and the ingest verb.
- **2026-09-15 (panel round 1): INGEST evaluates at command scope**, a named exception to the "match on `stmts` output" contract, because the measured shape puts the ingest in a statement stripped of its loop.
- **2026-09-15 (panel round 1): the Slack exemption is a bound on the full recipient set**, not on the primary target. `--broadcast`, `dm_mentioned` and `follow_ups` each reach past it.
- **2026-09-15: the `~/Claude` symlink deny rides in this chunk.** It is not in the audit's change list; it is in Scott's `CLAUDE.md`, and the LN rule is the only place it can be enforced.

## Alternatives Considered

### Alternative 1: the prompt-word commit guard as prescribed
- **Description:** deny `git commit` unless a commit-shaped word appears in the last 3 human prompts or an allowlisted skill is active.
- **Why not chosen:** measured at 590 denials and 2 of 5 incidents, defeated four ways (ask-was-something-else, machine prompts counted as human, incidental vocabulary, and no human prompt at all in subagents). Full numbers above. Kept here so it is not re-proposed.

### Alternative 2: a docs-only commit deny
- **Description:** four of the five incidents committed a design doc, handoff doc or implementation-notes file with an explicit path, so deny a commit whose staged set is documentation and no code.
- **Why not chosen:** 351 docs-only commits in the window (341 main-thread), about 3 a day, against 5 incidents. Precision 1.4%. It also fires on this program's own workflow, since every chunk commits its design doc.

### Alternative 2b: the two predicates panel round 1 derived
- **Subagent-type allowlist** (deny a subagent `git commit` unless the agent type is `phase-implementer` or `release-driver`): 569 denies of 882 subagent commits, **0 of 5** incidents. `agentType` is the free-text name the dispatcher typed, spread over ~190 values (`phase-implementer` 295, `release-driver` 18, then `phase1` 43, `phase3` 39, `w3p1`, `auditfix`, `wtfix`). More denials than the predicate it was proposed to replace, and every incident is main-thread.
- **Path provenance** (deny a commit whose staged paths include a basename that never appears in any typed prompt of the session): 1,348 in-scope statements, 820 denies, 4 of 5 incidents, precision ~0.5%. Best recall of the five, worst volume.
- **Why neither is chosen:** both are worse than what they replace. Recorded so round 2 does not re-derive them.

### Alternative 5: the blanket-staging deny
- **Description:** deny `git add -A`, `git add .`, `git add --all` with no path operand. 454 statements in the window, flat month over month, 135 from subagents.
- **Why not chosen, first reason (panel round 1):** it cannot claim item 1. Its own deny text instructs the model to stage explicit paths, and `git add docs/design && git commit` satisfies the rule while committing the same unrequested artifacts. `rules/taste.md` calls that a fix with no causal closure.
- **Why not chosen, second reason (measured 2026-09-15):** the phantom-prevention justification does not hold. Every sandbox phantom in this working tree is a **character special file, size 0, mode 666** (`.bash_profile`, `.bashrc`, `.zshrc`, `.profile`, `.mcp.json`, `.ripgreprc`, `.zprofile`, `.gitmodules`), and git refuses to add one:

```
$ git add -A --dry-run
error: .bash_profile: can only add regular files, symbolic links or git-directories
fatal: adding files failed
```

  The abort is all-or-nothing, so a blanket stage in a phantom-contaminated tree stages nothing. Git already fails closed on the only class the rule would have closed. `git status --porcelain` reported zero regular-file phantoms at the time of measurement.
- **Why not chosen, third reason:** the one incident it was credited with, `2a4d6300` at 2026-09-09T00:49:24, is `git add -A docs/design && git commit`. That is `-A` **with** a path operand, which cheap win C2 correctly requires the rule to allow. So the narrowed rule catches zero of the five incidents.
- **Revisit condition:** a phantom that appears as a 0-byte **regular** file rather than a char device. `CLAUDE.md` describes both shapes; only the char-device shape was present when this was measured. A regular-file phantom is addable, and then `git add -A` does commit it.

### Alternative 3: one hook per verb, the tree's current pattern
- **Description:** a separate `gh-write-guard.sh`, `ln-guard.sh`, `ingest-guard.sh`, `public-repo-guard.sh`, each with its own matrix. This is how the existing ten guards are organized, and the research dig recommended it for `rules/general.md` naming and legible per-guard matrices.
- **Why not chosen:** ten Bash `PreToolUse` guards already cost 689 ms as a sum of individual runs, 18 to 137 ms each. Four more would add roughly 300 ms to **every Bash call in every session**, and all four rules parse the same command string, so the parse would be repeated four times for one answer. `prose.sh` is the counter-precedent in the same tree: one script, three rules, one payload read, one `--self-test`.
- **What the pushback concedes:** matrix legibility. `intent-guard-test.sh` is sectioned one block per rule, in the order the rules appear in this doc, so a reader looking for the LN fixtures finds them without reading the GH-WRITE ones. The naming objection is answered by the one-word name `intent`.
- **Open on one fact:** if Phase 0 finds the harness runs a matcher list in parallel, the latency argument weakens and per-verb hooks become defensible. The parse-once argument stands either way.

### Alternative 4: a `UserPromptSubmit` recorder writing `~/.claude/state/last-prompt`
- **Description:** the audit's prescribed mechanism for carrying prompt context to a `PreToolUse` guard.
- **Why not chosen, provisionally:** the transcript already carries the answer, so a recorder would be a second source of truth for the same fact. Corrected by panel round 1: the source is the `type=="user"` string records (earlier in append order in 1,122 of 1,122 measured turns), not the `last-prompt` records `prose.sh` prefers. Phase 0 decides whether that is enough: if the current turn's `user` record is not yet visible when a `PreToolUse` hook runs, the recorder is the only way and this alternative becomes the design.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A guard reads a stale prompt and denies a legitimate post | Med | Med | Phase 0 measures the flush; TARGET falls back to allowlist plus TEST-TEXT plus RESEND |
| Denial induces a retry loop | Med | Med | Every deny text names the allowed next action; INGEST carries an explicit door |
| The heredoc-reading INGEST rule fires on prose | Low | Low | Surface is 11 statements in four months; matrix pins the prose case |
| Added hook latency | High | Low | One hook, one parse; Phase 0 measures the per-call cost the harness charges |
| A guard passes CI and is broken live | High | High | Chunks B and C both shipped this exact way. Round-1 implementation audit is mandatory, dispatched under the guards it audits |

## Open Questions

None. The two that survived panel round 1 are both closed:

- **Does item 1 stay uncovered?** Scott ruled A on 2026-09-15: accept the gap. Recorded in Non-Goals with all five measured predicates.
- **Is phantom prevention worth 454 denials?** Closed by measurement, not by ruling: git refuses to add a character-special file and aborts the whole `git add -A`, so there is no phantom class left for the rule to close. The rule is dropped (Alternative 5).

Round 2 nominated four for this section. All four are decisions rather than unknowns, so they are decided here rather than parked, which is what `rules/taste.md` requires of an author:

- **PUBLIC-REPO's outgoing-object set.** Destination boundary: one `git ls-remote` on the push path, unresolvable denies. Merge handling: `--diff-merges=first-parent`. Blob identity: `git rev-list --objects` into `git cat-file --batch-check` over the range.
- **The stale-private visibility window.** Not accepted: a cached `private` is revalidated before the guard allows a sensitive path, and a failed revalidation denies. The call is on the deny-candidate path only, so it is not in the hot path.
- **RESEND's lifecycle.** A `PostToolUse` registration records confirmed sends and an `O_EXCL` entry create serializes concurrent sessions, because a lock held inside a `PreToolUse` process cannot span the send (round 3). A failure leaves the entry in place, since `PostToolUseFailure` carries no per-recipient outcome and the parent may have landed. Entries expire after an hour and an unreadable ledger denies.
- **Which recipient set is authoritative.** The client's. No exemption on a cache staler than the client's staleness window, or on a mention the cache cannot resolve.

Closed earlier, recorded so they are not reopened:

- **Fail-open or fail-closed when the transcript is unreadable.** Only SLACK reads prompts now, and it fails **closed** with the two exempt ids still passing on hardcoded literals. `panel-round-guard.sh:50-57` fails open behind a measured 97.4% hit rate, which is right for a round counter and wrong for an authorization gate.
- **Item 1's repo scope** (every repo, or only repos with a remote). Moot: item 1 is uncovered.
- **Item 7's visibility source.** Cached per repo with a TTL; unknown or unreadable reads as **public**, so a repo that flips between refreshes fails closed.
- **PUBLIC-REPO's scope.** Stays `~/repos/scottidler/*`. No repo outside it has an origin remote Scott owns.
- **Whether the `~/Claude` symlink deny is unrequested scope.** It is in `CLAUDE.md`; both seats found traceability for it, the 1 MB threshold and the Slack confirmation split.
- **GraphQL writes.** 716 `gh api graphql` statements, 170 mutations, zero on a guarded surface. Named as a residual hole.

## References

- Program baton: `docs/design/2026-09-13-setup-audit-program.md`
- Audit, ranked: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/ (item 6)
- Audit, raw findings: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-audit-findings-2026-09-12/ (lens `incidents` 6-12, lens `hooks-sandbox` F8-F9, lens `mcp-usage` F7-F8)
- Chunk A: `docs/design/2026-09-13-enforcement-core.md`
- Chunk B: `docs/design/2026-09-13-guard-precision.md`
- Chunk C: `docs/design/2026-09-14-panel-round-cap.md`
- Measurement scripts for every count in this doc: the session scratchpad's `intent-scan.py`, `scan2.py` through `scan6.py`, `why.py`, `why2.py`
