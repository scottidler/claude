# Design Document: Intent guards for outward and irreversible actions

**Author:** Scott Idler
**Date:** 2026-09-15
**Status:** Draft
**Review Passes Completed:** 5/5, then a research fold-in, then panel round 1

> Panel round 1 ran 2026-09-15 against the pre-fold snapshot (`/tmp/review-panel/GOX7yywR/`): 10 must-fix, 7 cheap wins, 2 defers, 8 findings rejected with measurements. All folded below. Five of the must-fix were re-verified in this session before folding, because each one changes a predicate: the commit half of PUBLIC-REPO reading an index that does not exist yet, `realpath -m` dereferencing an existing link, `stmts` splitting the ingest out of its loop, `flag_value` returning empty for `-XDELETE`, and `~/.claude/hooks/*` being per-file symlinks so a hook is live on save. The round also refuted one claim the research fold-in had just introduced (the `last-prompt` ordering), and produced two more measured item-1 predicates, both worse. Minutes: `docs/design/2026-09-15-intent-guards-review-log.md`.
>
> Passes 1 to 5 ran, then a `design-research` dig came back and corrected six things: item 8's `Environment=` target is measurably wrong, the `Read` deny has an unproven interaction with `Read(**)` in `permissions.allow`, the "active allowlisted skill" clause in the audit's prescription is not implementable, chunk B handed this chunk an open secret-guard hole that the draft missed entirely, the two exempt Slack ids cannot be resolved from the cache, and the write fence on `settings.json` is Bash-only rather than absolute. All six are folded in below. The panel's round 1 was dispatched against the pre-fold text, so its findings are reconciled against this version.

## Summary

Chunk D of the setup-audit program (`docs/design/2026-09-13-setup-audit-program.md`), covering audit item 6: the actions that reach outside this machine or cannot be undone, and the secret-leak vectors the echo guard does not cover.

The audit prescribes eight guards. Measured against the corpus before designing anything: four hold as specified (`gh api` writes, public-repo leak, secret vectors, Slack posts), three need a different predicate than the verb they name (outward deletes, symlink cycle, vault ingest), and one is refused. The refused one is the `git commit` intent guard: it would have denied 590 legitimate commits to catch 2 of 5 known incidents, and it cannot run at all in the subagents that make 31% of commits. What replaces it is a blanket-staging deny that infers no intent.

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

- Every action class in the table is denied by a hook or a permission entry, not discouraged by a sentence.
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
- **Item 1, the unrequested-commit class, ships with no mechanical coverage.** This is the chunk's one scope reduction and it is Scott's to overturn. Four predicates were derived and measured, all against 5 known incidents out of 2,832 commit statements: prompt-word over the last 3 prompts, 590 denies / 2 of 5; the same over a session-wide window, 318 / 1 of 5; docs-only staged set, 351 / precision 1.4%; subagent-type allowlist, 569 of 882 subagent commits / **0** of 5, since all five incidents are main-thread and `agentType` is free-text dispatcher naming across ~190 values; path provenance (a staged basename never named in any prompt), 820 / 4 of 5. The base rate is 0.18%, so any predicate coarser than "exactly this commit" lands under 2% precision. The STAGING rule is **not** a substitute, for the causal-closure reason given at that rule. One caveat on the docs-only figure: it classifies by the `git add` arguments in the same call plus file extension, so it is a proxy for the staged set, not the staged set.
- **Any "an allowlisted skill is active" clause.** The audit's prescription for item 1 and its "no live posts during a `/cli-shakedown`" clause for item 2 both depend on a guard knowing which skill is running. No measured `PreToolUse` payload carries a skill field (full 2.1.272 key set at `docs/design/2026-09-14-panel-round-cap-phase0/evidence.md:16-41`). The only available signal is the newest `Skill` tool_use record in the transcript, which has **no end marker**, so "active" is unbounded and the inference is wrong in exactly the long-running sessions where it matters. Both clauses are refused. TEST-TEXT covers the shakedown case textually instead, and item 1's skill allowlist is moot because item 1 is refused on its own numbers.
- **Mode-0664 credential files on this machine.** `/run/user/1000/{borg,cortex,sb-harvest}.env` hold roughly 40 live credentials and are readable by any local process. Found while measuring item 8. It is a configuration fix in the daemons that write them, not a guard, and not in this repo.
- **Redacting secrets already in a transcript.** A `PostToolUse` hook cannot unwrite the transcript. The audit says so and the fix lives in `clyde`'s indexer, which already redacts.

## Proposed Solution

### Overview

One new Bash hook carrying the statement-level rules, one new hook on the Slack write surfaces, and an extension of the guard that already owns secrets. Plus permission-deny entries as a second layer where a literal verb exists.

```
PreToolUse(Bash)                 -> intent-guard.sh      rules: GH-WRITE, DELETE-OUT, INGEST, LN, PUBLIC-REPO, STAGING
PreToolUse(Bash | mcp__slack__*) -> slack-post-guard.sh   rules: TARGET, TEST-TEXT, RESEND
PreToolUse(Bash | Read)          -> secret-echo-guard.sh  extended: 5 statement vectors + credential-path Read deny
permissions.deny                 -> acli deletes, gh repo edit
```

### Why one hook and not six

Measured on this machine, 2026-09-15: the ten hooks registered on the `PreToolUse` Bash matcher cost 689 ms when run one after another over a trivial payload (`git status --porcelain`), individual times 18 to 137 ms. Every Bash call in every session pays that. Six new scripts would add roughly half again as much, and all six rules need the same `lib.sh` parse of the same command string, so parsing once is strictly cheaper than parsing six times.

`prose.sh` is the in-house precedent: one script, three rules, one payload read, `--self-test` on the side. `intent-guard.sh` copies that shape.

(Whether the harness runs the hooks in one matcher list serially or in parallel is not established. The 689 ms is a sum of individual runs, and Phase 0 measures what the harness charges per call. One hook is the right shape either way.)

### Implementation contract every rule follows

Not restated per rule below:

- **Sourcing:** `. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }` (`lib.sh:5`).
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

**The attached form is a `lib.sh` gap, and it is fixed in `lib.sh`, not worked around here.** Verified 2026-09-15 against the shipped parser and the installed `gh`:

```
printf 'gh api -XDELETE repos/o/r'  | flag_value -X value  ->  ''        (empty)
printf 'gh api -X DELETE repos/o/r' | flag_value -X value  ->  'DELETE'
gh api -XDELETE   ->  "accepts 1 arg(s), received 0"        (gh parsed the flag)
gh api -QDELETE   ->  "unknown shorthand flag: 'Q'"         (control)
```

So `gh api -XDELETE repos/tatari-tv/valet/branches/main/protection/enforce_admins` runs fine and reads as no method at all to the guard. This is chunk B's prefix-regex class again: reads complete, silently allows a subset. The hole is in `lib.sh`'s `flag_value` (`:357-368`), which every future guard will consume, so `flag_value` learns the attached short-option form and the fix lands with the existing `lib-test.sh` matrix extended. A per-guard workaround would leave the same hole open for the next guard.

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

How well the predicate discriminates is **partly unmeasured, and Phase 3 closes that**: of 100 absolute two-arg `ln -s` pairs in the window, 3 are ancestor-shaped and all 3 are deliberate loop-repro probes under `/tmp`, so zero legitimate instances. But 97 of the 100 use relative paths and cannot be classified without the cwd each ran in. So Phase 3 replays all ~112 corpus statements **with their recorded cwd** and asserts zero denies. That replay is exactly the measurement that would have caught the `realpath -m` defect before it was written into a doc.

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

At hook time the index holds none of those paths. So the commit half's path set is the **union of three sources**: the arguments of any `git add` statement in this same command, the arguments of `git commit <paths>` (which commits working-tree content and bypasses the index entirely), and the current index. The 1 MB check measures the blob that will be committed, not whatever currently occupies the path.

**The push half has no index at all, and `@{u}..HEAD` is the wrong question.** Three defects in the draft:

- **Refspec and non-HEAD sources.** `@{u}..HEAD` describes HEAD, not the ref being pushed. 32 refspec-form push statements in the window, including **this chunk's own landing command** (`git push origin intent-guards:main`), plus `git push origin 472114f:refs/heads/bump-v0.2.0` and a push from a different HEAD. The rule parses the source ref out of the refspec and diffs that, and **fails closed** when it cannot resolve one. `@{u}` errors with "no upstream configured" on a fresh branch, which is the normal state for this repo's landing flow.
- **An endpoint diff hides add-then-remove.** `git diff A..B` compares two trees, so a sensitive file added and then removed inside the pushed range diffs to nothing while its bytes are published in history. The rule walks the commits (`git log --name-only A..B`), not the endpoints.
- **Cases to model:** a new branch with no upstream, force-push, detached HEAD, tag push, and `--all` or multiple refspecs. `--no-verify` is **not** one of them and is recorded here so it is not re-raised: it bypasses git's own pre-push hook and never a Claude `PreToolUse` hook.

Standing on this: **119 of Scott's 136 personal repos are public, including `scottidler/claude` itself**, the repo that holds his rules, `WHOAMI.md` and every design doc in this program. `scottidler/keep`, where the `.age` secrets live, is private, so the `.age` pattern costs nothing there.

Observed on main, 2026-09-15: `git ls-files | grep -E '<pattern>'` returns 0 matches in this repo, and no tracked file exceeds 1 MB. The guard has zero standing false positives against the current tree.

Visibility is read once per repo with `gh repo view --json visibility` and cached under `~/.cache/`, because a `gh` call on every commit is not acceptable at 689 ms of existing hook latency. An unknown or unreadable cache entry is treated as **public**, so a repo that flips to public between refreshes fails closed.

Scope stays `~/repos/scottidler/*`: no repository outside it has an origin remote Scott owns, third-party clones are not pushable, and `tatari-tv` is a different threat model.

#### STAGING: no blanket staging

Deny `git add -A`, `git add --all`, and `git add .` when they carry **no path operand**. `git add -A <path>` is path-scoped and does not match. `git add -u` and `git commit -a`/`-am` are **not** covered, and the reason is below. Deny text names the mechanical fix: stage the paths `git status --porcelain` lists, and verify that list outside the sandbox namespace, because `git status` is itself phantom-contaminated inside it (`CLAUDE.md`).

Fires in the window: 454 statements of `add -A`/`add .`, flat month over month (108 / 129 / 115 / 102), 135 of them from subagents.

**This rule does not address item 1, and claiming it did was the draft's mistake.** The argument against it is the strongest thing either reviewer produced: the deny's own recovery instruction permits the identical violation, because `git add docs/design && git commit` satisfies the rule and commits the same unrequested artifacts. By the standard in `rules/taste.md` ("every fix carries causal closure"), that is not a fix for the unrequested-commit class. Item 1 is therefore uncovered, recorded in Non-Goals with all four measured predicates.

What the 454 does buy, and the only thing it buys, is **phantom-file prevention plus staging discipline**. The sandbox leaks char devices and stubs named `.bashrc`, `.zshrc`, `.profile`, `.gitconfig`, `.mcp.json` into the working tree (`CLAUDE.md`), none of them tracked and none of them gitignored in this repo (verified: `git ls-files` returns none of them, `git check-ignore` reports NOT ignored for each). A blanket stage is the only way they reach a commit. The audit's subagent lens counts 96 phases that ran `git add -A`.

That justification covers `-A`, `.` and `--all` and stops there: `git add -u` stages only already-tracked files and `git commit -a` only already-tracked modifications, so neither can pick up an untracked phantom. Keeping them would be 20 statements with no argument behind them, so they are out.

#### SLACK: a post goes where Scott named, once, and not as a test

`slack-post-guard.sh`, registered on both the Slack MCP write tools and the Bash matcher. Both surfaces post: the audit's `hooks-sandbox` F8.12 counts 73 MCP `chat_post_message`/`chat_update` calls plus 85 CLI `slack write`/`slackify` calls, and its `mcp-usage` F8 counts 120 posts across all paths including two retired tools. Re-derived here over main-thread transcripts for the two MCP tools that still exist: 64 posts, `tool_input` carrying `channel`, `text`, and optionally `thread_ts`, `raw`, `no_mentions`. Three denies:

- **TARGET**: allow unconditionally when the **full recipient set** is inside `#clipboard` (`C0ANJQAJC7N`) and Scott's own DM (`D01G4Q7AWLV`, from the cache's `self.dm`). Both ids are **hardcoded in the hook**, not resolved: `#clipboard` is a private channel Scott is the only member of and does not appear in the cache's 823 `channels` at all. For every other target, require that the channel id, the `#name`, or the DM user's display or first name appears in a typed human prompt of the current transcript, resolved through `~/.cache/slack/ids.json` (208 KB, mode 0600, schema 2, holding `channels` 823, `users` 120, `handles`, `profiles`, `subteams`, `self`, last synced 2026-09-14).
- **TEST-TEXT**: deny when the first line matches test/testing/verify/verifying and the target is not one of the two exempt ids. This is the 2026-07-10 class: five live posts and an MCP write test into a coworker DM during a shakedown whose prompt was "merged #10, tag v0.2.0 and run the shakedown". The rule is purely textual on purpose: the audit's phrasing of it ("no live posts during a `/cli-shakedown`") is not implementable, see Non-Goals.
- **RESEND**: deny a repost of the same body to the same target. This is the 2026-06-09 class: "having you spam multiple versions of shit into our DMs is NOT what I asked you to do", one post asked, two sent.

  The draft's "one `last-post` record, first 40 characters, 120 seconds" does not survive contact: an A then B then A sequence loses A's entry, two concurrent sessions can both pass before either writes, recording at `PreToolUse` suppresses a legitimate retry after a **failed** send or after another hook's deny, and first-40-chars matching would block correcting a typo. So the state is keyed on `(target, body-hash, confirmed-sent)` with an entry per target rather than one global record, only a confirmed send counts, and **`chat_update` is exempt** because editing an existing message is the opposite of a resend.

**The exemption is not a bound on recipients, and that is the sharpest finding of round 1.** One call to the Slack client can reach people other than the named target, confirmed in the client source:

- `--broadcast`, repeatable, crossposts the same body to additional channels (`tatari-tv/slack-cli/src/cli.rs:278-287`)
- `dm_mentioned`, which after posting DMs the permalink to everyone the body mentions, with usergroups expanded (`src/mcp/request.rs:102-112`)
- `follow_ups`, additional bodies threaded under the parent (`src/mcp/request.rs:113-122`)

So a post whose primary target is `#clipboard` can still land in a coworker's channel or DM. The guard resolves the full recipient set (primary target, every `--broadcast`, every mention when `dm_mentioned` is set) **before** granting either exemption, and TEST-TEXT applies to every `follow_ups` body as well as the primary one. A body read from a file is checked as the text that will be sent, not as the filename.

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

**The path deny list is priced.** Bash statements in the window touching the listed paths: `~/.cache/slack/token.json` 77 (40 literal, 37 via `${XDG_CACHE_HOME:-...}`), `~/.cache/okta/tokens.json` 50, `~/.config/eratosthenes/digest.env` 37, `~/.config/fabric/.env` 30, `/run/user/1000/{borg,cortex}.env` 21, `~/.config/marquee/tokens.json` 9. Over 200 occurrences, and the routine shape is **auth debugging**, not a leak: `jq .expires_at`, `jq 'has("access_token")'`, a mode check. So each path pattern ships with a near-miss allow fixture for the projections that cannot carry a token, and the deny fires on the shapes that print the whole file. Without that split the rule is 200 denials against 4 leaks and it reads like `manifest-scope-guard`'s 9-of-9 prose problem.

**3. The `Read` matcher.** The `.env` leak came through the Read tool, which no hook in this repo has ever matched. Two things are unproven and both are Phase 0 criteria: whether a `"matcher": "Read"` block fires at all, and whether its deny survives `Read(**)` sitting in `permissions.allow`. Chunk A's spike proved only that a `Write|Edit|MultiEdit|NotebookEdit` matcher does **not** fire on Read (`docs/design/2026-09-13-enforcement-core-phase0/evidence.md:90-104`), which is a different claim. `rewrite-cd-read.py:5-9` documents the adjacent asymmetry, that allow and deny evaluation runs regardless of what a hook returns, which is exactly why this needs a measurement and not an argument.

Residual hole, named rather than patched blind: `Grep` and `Glob` over a credential path are not covered, and a `Grep` result can carry a matching line. No instance appears in the corpus.

**Handed to Scott, not fixed here:** `/run/user/1000/{borg,cortex,sb-harvest}.env` are mode 0664, so roughly 40 live credentials are readable by any local process on this machine. That is a configuration finding for the daemons that write those files, outside this chunk and outside this repo.

### Edge cases each rule has to survive

Found in pass 4, each one pinned as a matrix fixture in its phase:

- **GH-WRITE**: a leading slash (`gh api /repos/o/r`), gh's own `{owner}`/`{repo}` template placeholders, a method after the path rather than before it, and the implicit-POST form above.
- **DELETE-OUT**: `--help` passes; `--yes` does not change the verdict; the deny covers `acli jira workitem delete` and `acli confluence page delete` and nothing else in `acli`.
- **LN**: the one-argument form (`ln -s target`, link name inferred from the basename in the cwd), a relative target, combined short flags (`-sfn`), the long form (`--symbolic`), and a `cd` prefix, which the rule resolves with `lib.sh`'s `cd_target`/`cd_at` rather than trusting `$PWD`.
- **INGEST**: `sb borg reingest` and a bare `borg ingest` both count. The `BULK_INGEST_ORDERED_BY_SCOTT` door can be typed by the model as easily as by Scott, exactly like chunk C's `PANEL_ROUNDS_ORDERED_BY_SCOTT`. The mitigation is the same and it is not cryptographic: the variable name makes an agent-authored override plainly visible in the transcript and in `clyde permit log`.
- **PUBLIC-REPO**: `git commit` reads the index (`git diff --cached --name-only`); `git push` has no index to read and must query the outgoing commits instead (`git diff --name-only @{u}..HEAD`, falling back to the range against `origin/<default>` when there is no upstream). Treating push like commit would make the push half inert. Bare-container worktrees put the tree under `/main/`, so the rule resolves the repo root with `git rev-parse --show-toplevel` and never by string-matching the cwd.
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
~/.cache/intent-guard/visibility/<owner>-<repo>    public|private, one line, refreshed weekly
~/.cache/slack/ids.json                            channels, users, handles (existing)
~/.cache/slack/last-post                           target + first 40 chars + epoch, for RESEND
```

No state is kept for GH-WRITE, DELETE-OUT, LN, INGEST or STAGING: all five are pure functions of the command string.

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
- **Still unproven, and this is the gate.** Whether the record is flushed at the instant a hook fires cannot be read off a completed file. A scratch `PreToolUse` Bash hook dumps what it can see, for three cases: a plain prompt, a slash-command prompt, and a turn whose first tool call is the guarded one.
- **Also unproven.** Whether a `"matcher": "Read"` block fires at all, and whether its deny blocks the call with `Read(**)` still in `permissions.allow`.
- **Free measurement while the harness is up.** Whether `prompt_id` is constant across every tool call in one turn. If it is, it replaces `prose.sh`'s ordering heuristic with an exact staleness key.
- **The latency measurement needs a budget, not just a number.** Pass is added hook cost under 150 ms per Bash call for the one new hook; over that, the design reopens on rule-count-per-hook. A measurement with no threshold is evidence collection, not a gate.
- **Extractor miss rate.** Run the extractor over at least 40 turns from `~/.claude/projects`, counting false authorizations by class: teammate relays and `<command-*>` wrappers. Two defects are already known in `prose.sh:131-153` and get fixed rather than measured: the relay filter `startswith("Another Claude session sent a message:")` is applied only on the `last-prompt` branch (`:137`) and not the `user` fallback (`:139-143`), and the `startswith("<")` clause silently discards slash-command turns whose shape is `<command-message>...</command-message>` plus `<command-name>` plus `<command-args>`.
- **Success criteria:** `docs/design/2026-09-15-intent-guards-phase0/evidence.md` answers all six, each with its command and output. If the `Read` matcher does not fire or its deny loses to `Read(**)`, the SECRET Read half has no seam and this doc reopens rather than the phase improvising. If the current turn's prompt is not reliably readable, the SLACK TARGET rule degrades to the exempt-id allowlist plus TEST-TEXT plus RESEND, and the doc is amended before Phase 5.

#### Phase 1: close chunk B's secret-guard hole
**Model:** opus
- `secret-echo-guard.sh`'s echo/printf check gated with `cmdword_is` per statement, payload matched on the squote-masked copy, the verb regex deleted from the Python matcher
- **Success criteria:** `'echo' $GH_TOKEN` denies; `echo '$GH_TOKEN'` still allows; both ride all 18 `wrap_shapes` spellings green; the existing 39 assertions in `secret-echo-guard-test.sh` pass unchanged

#### Phase 2: `intent-guard.sh` skeleton, GH-WRITE and DELETE-OUT
**Model:** opus
- New hook sourcing `lib.sh`, `--help` and `--self-test` like `prose.sh`, registered on the Bash matcher, symlink verified by `hooks-preflight.sh` in this phase
- GH-WRITE and DELETE-OUT rules; matching on `stmts` output only, never the raw string
- `intent-guard-test.sh` matrix, every deny fixture re-run through `shapes.sh`'s `WRAPPER_SHAPES`
- permission-deny entries for `acli jira workitem delete`, `acli confluence page delete`, `gh repo edit`
- `.otto.yml` lint `FILES` list grown with every file this phase touches
- **Success criteria:** `otto ci` exits 0; the matrix denies the two incident commands verbatim (`gh api -X DELETE repos/tatari-tv/valet/branches/main/protection/enforce_admins`, `acli jira workitem delete --key SEC-2997 --yes`) in all `WRAPPER_SHAPES`; `gh api repos/tatari-tv/philo/pulls/1 -X PATCH -f body=x` is allowed

#### Phase 3: LN and the `~/Claude` policy
**Model:** opus
- Prospective-link-entry predicate (`dirname` resolved, basename never dereferenced); `~/Claude` link-path deny; the four operand forms (directory destination, `-t DIR`, relative target, `-n`/`-T`)
- **Corpus replay**: all ~112 `ln -s` statements from the window replayed with their recorded cwd
- **Success criteria:** the 2026-07-03 command is denied verbatim; `ln -sf <repo>/HOME/.claude/hooks/x.sh ~/.claude/hooks/x.sh` over an existing link is allowed; the corpus replay produces zero denies

#### Phase 4: INGEST
**Model:** opus
- Heredoc-reading rule, the `BULK_INGEST_ORDERED_BY_SCOTT` door, `rules/interaction.md:110` amended to name the hook
- Matrix includes the incident's `cat > ingest.sh <<'EOF' ... EOF` statement verbatim and the single-URL form
- **Success criteria:** the script-creation statement is denied; `sb borg ingest --tags x -- https://one.url` is allowed; the 5-URL 2026-06-21 form is denied without the door and allowed with it

#### Phase 5: SLACK
**Model:** opus
- `slack-post-guard.sh` on both matchers, three rules, `~/.cache/slack/last-post` for RESEND
- The two-target confirmation split written into the Slack skills
- **Success criteria:** a post to `#clipboard` passes with no confirmation; a post to an unnamed channel is denied; a `**MCP write test**` first line to a DM is denied; a same-text repost inside 120 s is denied

#### Phase 6: SECRET vectors and the Read deny
**Model:** opus
- The corrected statement vectors in `secret-echo-guard.sh`; `Read` matcher registration and the measured path list
- Gated on Phase 0's `Read`-matcher criterion; developed against a copy before the live file is written (see Blast radius)
- **Success criteria:** each vector command is denied in all 18 `wrap_shapes` spellings; `--query SecretString` is denied and `--query ARN` is allowed; `jq .expires_at ~/.cache/slack/token.json` is allowed while `cat` of the same file is denied; the existing 39 assertions in `secret-echo-guard-test.sh` pass unchanged

#### Phase 7: PUBLIC-REPO
**Model:** opus
- Visibility cache (unknown reads as public), the three-source path set for commit, refspec parsing plus commit-walking for push, blob-size check
- **Success criteria:** the founding incident's `git add ... && git commit` one-liner is denied with an empty index; `git push origin intent-guards:main` on a public repo with a sensitive path in the outgoing commits is denied, and an unresolvable refspec is denied rather than allowed; the same paths in `scottidler/keep` (private) are allowed

#### Phase 8: STAGING
**Model:** sonnet
- The blanket-staging deny for `-A` / `.` / `--all` with no path operand, pending the decision below
- **Success criteria:** `git add -A && git commit -m x` is denied; `git add -A docs/design` (path-scoped) and `git add -u` are both allowed; denial holds in all 18 `wrap_shapes` spellings

## Blast radius and ship order

- **Single repo.** Every file this chunk touches is in `scottidler/claude`: `HOME/.claude/hooks/*`, `HOME/.claude/settings.json`, `HOME/repos/.claude/rules/{git,interaction}.md`, the Slack skills, `.otto.yml`. No other repo changes.
- **The write fence is Bash-only, not absolute.** Verified 2026-09-15 with touch probes from this session: writable via Bash are `HOME/.claude/hooks/`, `HOME/repos/.claude/rules/`, `bin/`, `docs/design/` and `.otto.yml`; denied via Bash are `HOME/.claude/agents/`, `HOME/.claude/skills/`, `HOME/.claude/output-styles/`, `HOME/.claude/settings.json` and `HOME/.claude/CLAUDE.md`. The **Edit tool reaches the denied set**, proven inside this program by `f257ddb` (registered `panel-round-guard` in `settings.json`) and `ca3bfe8` (edited `HOME/.claude/agents/review-panel.md`). So the chunk is not blocked: new hook files land in a Bash-writable directory, and the `settings.json` registrations go through Edit. What is forbidden is a Bash redirect or heredoc into the denied set.
- **Hooks go live on SAVE, not on commit.** `~/.claude/hooks/` holds **per-file** symlinks into the working tree (verified 2026-09-15: `allow-help.sh -> /home/saidler/repos/scottidler/claude/HOME/.claude/hooks/allow-help.sh`, and the same for every entry). So an already-linked script is live the instant the file is written, before `otto ci` and before the commit. "Matrix green before the commit" isolates nothing for an **edited** hook. Only a **new** file waits, and it waits for its `manifest -l` link plus its `settings.json` registration, not for the commit.
- **Consequence for the two phases that edit a live guard** (Phase 1 and Phase 6, both on `secret-echo-guard.sh`): the candidate predicate is developed and exercised against a **copy** under a scratch name, the matrix is run against the copy, and only then is the live file written. Writing first and testing after means every session on this machine runs the untested predicate in between.
- **Recovery path for a guard that denies its own repair.** `secret-echo-guard.sh` is registered on Bash, so a broken version can deny the very `sed`/`python3` call that would fix it. The escape is the Edit tool, which is not on the Bash matcher, and the fallback is Scott running the repair with `!`. Named because Phase 1 edits that exact guard.
- **The rails plugin loads once per session**, so nothing in this chunk may depend on a rails change taking effect in the session that lands it. Chunk D adds no rails hooks, so this only matters if the Open Question resolves to option B.
- **Ship order: Phase 0, then Phase 1, then free.** Phase 1 closes a live bypass of a shipped guard and outranks every new rule. After that the rules are independent: no rule reads another's state, and the only shared file is the hook skeleton Phase 2 creates. Phases 3, 4, 7 and 8 depend on that skeleton; Phases 5 and 6 are separate files and can land in any order.
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
Phase by phase, each its own commit, `otto ci` green before the commit, pushed to `main` with `git push origin intent-guards:main`. No flag, no staged rollout: a shell hook is live the moment it is committed. After the last phase, a round-1 implementation audit dispatched under the guards it is auditing, then the acceptance criteria re-run against the live setup and recorded.

## Acceptance Criteria

- [ ] Every rule in this doc has a deny fixture in a `*-test.sh` matrix that also runs through `shapes.sh`'s `WRAPPER_SHAPES`, and `otto ci` exits 0. **Observed on main:** `shapes.sh` exists with the `WRAPPER_SHAPES` array (`HOME/.claude/hooks/shapes.sh:21`); matrices today are `lib-test.sh`, `panel-round-guard-test.sh`, `rewrite-cd-read-test.sh`, `branch-pr-title-guard-test.sh` and six more; `intent-guard-test.sh` does not exist yet, so this criterion cannot pass before Phase 1.
- [ ] Every incident command quoted verbatim in this doc is denied by the shipped guards, each in all 18 `wrap_shapes` spellings. **Observed on main, 2026-09-15:** all of them are allowed; no registered hook matches any of them (`settings.json` hooks block has matchers for Bash, `Write|Edit|MultiEdit|NotebookEdit`, the Slack MCP writes, `mcp__multi-account-github__create_pr`, `AskUserQuestion` and `Agent`, and none of the ten Bash guards covers these verbs).
- [ ] The `ln -s` corpus replay (all ~112 statements with their recorded cwd) produces zero denies, and the `secret-echo-guard` path list's ~200 measured auth-debugging occurrences produce zero denies. **Observed on main, 2026-09-15:** no guard exists to deny them, so the criterion is trivially true today and becomes meaningful only after Phases 3 and 6.
- [ ] `hooks-preflight.sh` reports every new hook as resolving and executable at session start. **Observed on main:** preflight is registered on SessionStart (`settings.json` hooks block) and green; it has caught zero misses, so it proves registration, not behavior.
- [ ] `git ls-files | grep -E 'personal/|excluded/|voice/|secrets?/|\.env$|\.age$'` returns 0 matches in `scottidler/claude`, and no tracked file exceeds 1 MB. **Observed on main, 2026-09-15:** 0 matches, 0 files over 1 MB.
- [ ] `rules/git.md:62` and `rules/interaction.md:110` each name the guard that now enforces the clause. **Observed on main, 2026-09-15:** `git.md:62` reads "do not change repo settings (merge methods, protection, rulesets)" with no hook named; `interaction.md:110` reads "not auto-filed into the vault or elsewhere" with no hook named.

## Resolved Decisions

- **2026-09-15: the prompt-word commit guard is not built.** Measured 590 denials against 2 of 5 incidents, and structurally unavailable in subagents. Author's call on the numbers above, not a deferral: item 1 ships as the STAGING rule, which infers nothing. Recorded as Alternative 1 so it is not re-proposed.
- **2026-09-15: Gmail delete/trash is not guarded.** Zero observed vectors across 10 `gws` delete-shaped statements, all Drive, all requested or `--help`. Revisit condition stated in Non-Goals.
- **2026-09-15: one hook, not six.** 689 ms of measured Bash-hook latency and six rules over one command string.
- **2026-09-15: LN guards the predicate, not the verb.** 112 legitimate `ln -s` statements in the window make a verb matcher unshippable.
- **2026-09-15: INGEST reads heredoc bodies**, against the general rule that guards match on the masked copy. The measured vector lives only in a heredoc body and the surface is 11 statements in four months.
- **2026-09-15: no `UserPromptSubmit` recorder.** The `PreToolUse` payload already carries `transcript_path` and `prompt_id`, and the prompt record lands before the turn's first tool call. A recorder would be a second source of truth for the same fact. Kept as Alternative 4 against Phase 0's flush-timing result.
- **2026-09-15: skill-activity inference is refused outright**, not deferred. No payload field, and the transcript signal has no end marker. See Non-Goals.
- **2026-09-15: item 8's `Environment=` vector is replaced by the measured `EnvironmentFile=` targets.** Zero secret values in any unit file's `Environment=`; the credentials are in `/run/user/1000/*.env` and `*/token*.json`.
- **2026-09-15: chunk B's single-quoted-verb hole is chunk D's Phase 1**, ahead of every new rule, because it is a live bypass of a guard that is already shipped and already trusted.
- **2026-09-15 (panel round 1): STAGING narrows to `-A` / `.` / `--all` with no path operand**, justified only as phantom-file prevention and staging discipline. The item-1 framing is deleted because the deny's own recovery instruction permits the identical violation. `-u` and `-a` are dropped: neither can stage an untracked file, so the phantom argument does not reach them.
- **2026-09-15 (panel round 1): the `flag_value` attached-short-option gap is fixed in `lib.sh`, not worked around in the guard.** Every future guard consumes the same parser, so a local workaround would leave the class open.
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

### Alternative 3: one hook per verb, the tree's current pattern
- **Description:** a separate `gh-write-guard.sh`, `ln-guard.sh`, `ingest-guard.sh`, `public-repo-guard.sh`, `staging-guard.sh`, each with its own matrix. This is how the existing ten guards are organized, and the research dig recommended it for `rules/general.md` naming and legible per-guard matrices.
- **Why not chosen:** ten Bash `PreToolUse` guards already cost 689 ms as a sum of individual runs, 18 to 137 ms each. Five more would add roughly 400 ms to **every Bash call in every session**, and all five rules parse the same command string, so the parse would be repeated five times for one answer. `prose.sh` is the counter-precedent in the same tree: one script, three rules, one payload read, one `--self-test`.
- **What the pushback concedes:** matrix legibility. `intent-guard-test.sh` is sectioned one block per rule, in the order the rules appear in this doc, so a reader looking for the LN fixtures finds them without reading the GH-WRITE ones. The naming objection is answered by the one-word name `intent`.
- **Open on one fact:** if Phase 0 finds the harness runs a matcher list in parallel, the latency argument weakens and per-verb hooks become defensible. The parse-once argument stands either way.

### Alternative 4: a `UserPromptSubmit` recorder writing `~/.claude/state/last-prompt`
- **Description:** the audit's prescribed mechanism for carrying prompt context to a `PreToolUse` guard.
- **Why not chosen, provisionally:** `prose.sh` already extracts the last typed prompt from the transcript's `last-prompt` records, so a second mechanism would be a second source of truth for the same fact. Phase 0 decides it: if the current turn's record is not flushed when a `PreToolUse` hook runs, the recorder is the only way and this alternative becomes the design.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A guard reads a stale prompt and denies a legitimate post | Med | Med | Phase 0 measures the flush; TARGET falls back to allowlist plus TEST-TEXT plus RESEND |
| Denial induces a retry loop | Med | Med | Every deny text names the allowed next action; INGEST carries an explicit door |
| The heredoc-reading INGEST rule fires on prose | Low | Low | Surface is 11 statements in four months; matrix pins the prose case |
| Added hook latency | High | Low | One hook, one parse; Phase 0 measures the per-call cost the harness charges |
| A guard passes CI and is broken live | High | High | Chunks B and C both shipped this exact way. Round-1 implementation audit is mandatory, dispatched under the guards it audits |

## Open Questions

- [ ] **Does item 1 stay uncovered?** Chunk D ships no guard for the unrequested-commit class. Five predicates were derived and measured against 5 incidents in 2,832 commit statements, and the best of them is 820 denials for 4 of 5 (full table in Non-Goals). The base rate is 0.18%. Options: (A) accept the gap, ship the other seven rules, and leave the class to prose; (B) order one of the five predicates anyway, naming which; (C) leave the class open and revisit when a sixth incident gives a sharper shape. **Rec: A.** Every measured predicate costs between 318 and 820 interruptions to catch between 1 and 4 events, and the one with the best recall has 0.5% precision. This is the only scope reduction in the chunk and it is yours to overturn.
- [ ] **Is phantom prevention worth 454 denials?** STAGING's only surviving justification is that a blanket stage is the single way a sandbox phantom file reaches a commit, and none of them is tracked or gitignored here. That costs 454 denials over four months, about 3.7 a day, each recoverable by staging explicit paths. Options: (A) ship it as Phase 8; (B) drop it and record the phantom class as uncovered too. **Rec: A**, because it closes a class completely rather than partially, which is what the item-1 refusal could not do.

Closed during the research fold-in and panel round 1, recorded so they are not reopened:

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
