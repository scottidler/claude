# Design Document: Intent guards for outward and irreversible actions

**Author:** Scott Idler
**Date:** 2026-09-15
**Status:** Draft
**Review Passes Completed:** 5/5, then a research fold-in

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
  - write = a method of `PATCH`, `PUT`, `POST` or `DELETE` from `-X`/`--method` (case-insensitive), **or** any of `-f`, `-F`, `--raw-field`, `--input`, because `gh api` switches to POST on its own as soon as a body field is present and no `-X` is needed
- `repo edit`

Fires in the window: **10** `gh api` statements out of 173 explicit writes plus 792 implicit ones, made of 6 with an explicit method on a guarded path (1 protection, 2 rulesets, 3 repo root) and 4 with only body fields on a guarded path. Plus 3 `gh repo edit`. Two are the incidents; the rest were Scott-directed, and a deny is the correct outcome for those too because he re-ran them himself with `!`.

The implicit-write clause is what pass 4 found: without it the rule reads as covering writes and misses 4 of the 10, which is the same shape as chunk B's prefix-regex defect (a rule that looks complete and silently allows a subset).

Deny text: `repo/org settings are Scott's to change (rules/git.md). Report the blocker; do not change the setting.`

#### DELETE-OUT: outward deletes

Deny `acli` statements carrying a `delete` subcommand (`jira workitem delete`, `confluence page delete`), except with `--help`. Fires in the window: 2 statements, one of them the SEC-2997 incident.

Gmail delete/trash is a Non-Goal (zero observed vectors).

One note on precision, observed live during this session's own measurement: a naive `acli.*delete` pattern matched `scan5.py`'s regex **text**, inside a quoted heredoc, at 2026-09-15T19:41. That is the exact class chunk B's `lib.sh` exists to kill. Every rule in this hook matches on `stmts` output from the masked copy, never on the raw command.

#### LN: no symlink cycle, and nothing symlinked into `~/Claude`

Two independent denies on a statement whose command word is `ln` with `-s`:

- **cycle**: `realpath -m` the link path and the target; deny when they resolve to the same path, or when the resolved target is an ancestor of the resolved link. This is the shape that froze the workstation on 2026-07-03: `ln -s ~/repos/scottidler/claude/HOME/Claude/writing/voice ~/Claude/writing/voice` where `~/Claude` already resolved into that same tree, so the link pointed at itself.
- **`~/Claude` is symlink-free by policy**: deny any link path under `~/Claude/`. `CLAUDE.md` states it: "~/Claude is the Cowork/Syncthing space, so no symlinks there". A flat path rule, no inference.

Why the predicate and not the verb: 112 `ln -s` statements in the window, nearly all installing hook and config symlinks. A verb matcher is 112 denies for one incident; the cycle predicate is designed to fire only on self-resolution.

#### INGEST: bulk vault ingest

Deny a statement that contains an `sb borg ingest`, `reingest` or `reingest-failed` occurrence together with any of: a loop keyword (`while`, `for`, `select`), `xargs`, a redirect reading a file, or two or more ingest occurrences in the same command. A single-URL ingest passes. `sb borg log` and `sb borg audit` always pass.

Note the wording: not "bulk". A loop body is one statement regardless of how many times it runs, so "bulk" is not statically countable and a rule phrased that way cannot be implemented. What is countable is the loop, the `xargs`, the file redirect, and the repeat count inside one command.

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

On `git commit` and `git push` under `~/repos/scottidler/*`, when the remote is public, deny if the staged set (`git diff --cached --name-only`) contains a path matching `personal/`, `excluded/`, `voice/`, `secrets?/`, `\.env$`, `\.age$`, or a file over 1 MB.

Standing on this: **119 of Scott's 136 personal repos are public, including `scottidler/claude` itself**, the repo that holds his rules, `WHOAMI.md` and every design doc in this program. `scottidler/keep`, where the `.age` secrets live, is private, so the `.age` pattern costs nothing there.

Observed on main, 2026-09-15: `git ls-files | grep -E '<pattern>'` returns 0 matches in this repo, and no tracked file exceeds 1 MB. The guard has zero standing false positives against the current tree.

Visibility is read once per repo with `gh repo view --json visibility` and cached under `~/.cache/`, because a `gh` call on every commit is not acceptable at 689 ms of existing hook latency.

#### STAGING: no blanket staging

Deny `git add -A`, `git add --all`, `git add .`, `git add -u`, and `git commit -a`/`-am`/`--all`. **`git commit --amend` is not blanket staging and must not match.** Deny text names the mechanical fix: stage the paths `git status --porcelain` lists.

Fires in the window: **474** statements (454 `add -A`/`add .`, 15 `add -u`, 5 `commit -a`), the `add` family flat month over month (108 / 129 / 115 / 102), 153 of them from subagents.

The 5 is a correction made in pass 4. A first pass measured 65 `commit -a` with the pattern `git commit (-\S*a\S*|--all)`, which also matches `--amend`: there are 110 `--amend` statements in the window and they are not blanket staging. A rule shipped with that pattern would have denied every amend in the tree. Recorded because the same regex shape is the natural thing to write again. It catches exactly one of the five commit incidents: `2a4d6300` at 2026-09-09T00:49:24, `git add -A docs/design && git commit`, the one Scott answered with "uncommit all of this bullshit. I never said create markdown files, i never said commit them. unstage them but dont delete".

Its independent justification is stronger than that one incident: `CLAUDE.md` already forbids `git add`-ing the sandbox phantom files that appear in every working tree in this repo, and a blanket stage is the only way they get in. The audit's subagent lens counts 96 phases that ran `git add -A`.

This rule is the one Scott has to price: 534 denies over four months (about 4 a day), each costing one extra round trip, against a class of unrequested commits that prose has not moved in three rules and four months. See the decision below.

#### SLACK: a post goes where Scott named, once, and not as a test

`slack-post-guard.sh`, registered on both the Slack MCP write tools and the Bash matcher. Both surfaces post: the audit's `hooks-sandbox` F8.12 counts 73 MCP `chat_post_message`/`chat_update` calls plus 85 CLI `slack write`/`slackify` calls, and its `mcp-usage` F8 counts 120 posts across all paths including two retired tools. Re-derived here over main-thread transcripts for the two MCP tools that still exist: 64 posts, `tool_input` carrying `channel`, `text`, and optionally `thread_ts`, `raw`, `no_mentions`. Three denies:

- **TARGET**: allow unconditionally when the target is `#clipboard` (`C0ANJQAJC7N`) or Scott's own DM (`D01G4Q7AWLV`, from the cache's `self.dm`). Both ids are **hardcoded in the hook**, not resolved: `#clipboard` is a private channel Scott is the only member of and does not appear in the cache's 823 `channels` at all. For every other target, require that the channel id, the `#name`, or the DM user's display or first name appears in a typed human prompt of the current transcript, resolved through `~/.cache/slack/ids.json` (208 KB, mode 0600, schema 2, holding `channels` 823, `users` 120, `handles`, `profiles`, `subteams`, `self`, last synced 2026-09-14).
- **TEST-TEXT**: deny when the first line matches test/testing/verify/verifying and the target is not one of the two exempt ids. This is the 2026-07-10 class: five live posts and an MCP write test into a coworker DM during a shakedown whose prompt was "merged #10, tag v0.2.0 and run the shakedown". The rule is purely textual on purpose: the audit's phrasing of it ("no live posts during a `/cli-shakedown`") is not implementable, see Non-Goals.
- **RESEND**: deny a second post to the same target within 120 seconds whose first 40 characters match the previous one. This is the 2026-06-09 class: "having you spam multiple versions of shit into our DMs is NOT what I asked you to do", one post asked, two sent.

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

The pattern list is built from that measurement, not from the audit's globs: `/run/user/*/*.env`, `~/.config/*/*.env`, `**/tokens.json`, `**/token.json`, plus the two history files. Each new deny gets a near-miss allow fixture beside it: `aws secretsmanager get-secret-value --query SecretString` allows, `rg -n TOKEN /run/user/1000/borg.env` denies.

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

- **Answered, not re-spiked.** The `PreToolUse` payload carries `transcript_path` **and** `prompt_id` (verbatim 2.1.272 payload at `docs/design/2026-09-14-panel-round-cap-phase0/evidence.md:16-41`). In a completed transcript the typed prompt lands as both a `type=="user"` string record and a `type=="last-prompt"` record **before** the turn's first `tool_use` record (measured on `~/.claude/projects/-home-saidler-repos-scottidler-claude/0aa23bbf-*.jsonl`: user at line 5, `last-prompt` at 21, first assistant `tool_use` at 28). So no `UserPromptSubmit` recorder is needed and Alternative 4 stays an alternative.
- **Still unproven, and this is the gate.** Whether the record is flushed at the instant a hook fires cannot be read off a completed file. A scratch `PreToolUse` Bash hook dumps what it can see, for three cases: a plain prompt, a slash-command prompt, and a turn whose first tool call is the guarded one.
- **Also unproven.** Whether a `"matcher": "Read"` block fires at all, and whether its deny blocks the call with `Read(**)` still in `permissions.allow`.
- **Free measurement while the harness is up.** Whether `prompt_id` is constant across every tool call in one turn. If it is, it replaces `prose.sh`'s ordering heuristic with an exact staleness key.
- **Extractor miss rate.** Run the extractor over at least 40 turns from `~/.claude/projects`, counting false authorizations by class: teammate relays and `<command-*>` wrappers. Two defects are already known in `prose.sh:131-153` and get fixed rather than measured: the relay filter `startswith("Another Claude session sent a message:")` is applied only on the `last-prompt` branch (`:137`) and not the `user` fallback (`:139-143`), and the `startswith("<")` clause silently discards slash-command turns whose shape is `<command-message>...</command-message>` plus `<command-name>` plus `<command-args>`.
- **Success criteria:** `docs/design/2026-09-15-intent-guards-phase0/evidence.md` answers all five, each with its command and output. If the `Read` matcher does not fire or its deny loses to `Read(**)`, the SECRET Read half has no seam and this doc reopens rather than the phase improvising. If the current turn's prompt is not reliably readable, the SLACK TARGET rule degrades to the exempt-id allowlist plus TEST-TEXT plus RESEND, and the doc is amended before Phase 5.

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
- Cycle predicate over `realpath -m` of link and target; `~/Claude` link-path deny
- Matrix includes the 2026-07-03 command verbatim, plus the 112-statement legitimate shapes (hook installs under `HOME/.claude/hooks/`, `ln -sf` config installs) asserted allowed
- **Success criteria:** the incident command is denied; a hook-install `ln -sf` into `~/.claude/hooks/` is allowed; a link whose target is its own resolved parent is denied

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
- Five statement vectors in `secret-echo-guard.sh`; `Read` matcher registration and path deny list
- **Success criteria:** each of the five vector commands is denied, each in all `WRAPPER_SHAPES`; `Read` on `~/.config/fabric/.env` is denied and on `.env.example` is allowed; the existing 37 + 31 denial fixtures still pass

#### Phase 7: PUBLIC-REPO
**Model:** opus
- Visibility cache, staged-path classification, size check, on `git commit` and `git push` under `~/repos/scottidler/*`
- **Success criteria:** a staged `HOME/Claude/writing/voice/x.md` in this repo is denied; the same path in `scottidler/keep` (private) is allowed; `git ls-files | grep -E '<pattern>'` still returns 0 in this repo after the phase

#### Phase 8: STAGING
**Model:** sonnet
- The blanket-staging deny, pending the decision below
- **Success criteria:** `git add -A && git commit -m x` is denied with the `git status --porcelain` instruction; `git add a.rs b.rs && git commit -m x` is allowed; denial holds in all `WRAPPER_SHAPES`

## Blast radius and ship order

- **Single repo.** Every file this chunk touches is in `scottidler/claude`: `HOME/.claude/hooks/*`, `HOME/.claude/settings.json`, `HOME/repos/.claude/rules/{git,interaction}.md`, the Slack skills, `.otto.yml`. No other repo changes.
- **The write fence is Bash-only, not absolute.** Verified 2026-09-15 with touch probes from this session: writable via Bash are `HOME/.claude/hooks/`, `HOME/repos/.claude/rules/`, `bin/`, `docs/design/` and `.otto.yml`; denied via Bash are `HOME/.claude/agents/`, `HOME/.claude/skills/`, `HOME/.claude/output-styles/`, `HOME/.claude/settings.json` and `HOME/.claude/CLAUDE.md`. The **Edit tool reaches the denied set**, proven inside this program by `f257ddb` (registered `panel-round-guard` in `settings.json`) and `ca3bfe8` (edited `HOME/.claude/agents/review-panel.md`). So the chunk is not blocked: new hook files land in a Bash-writable directory, and the `settings.json` registrations go through Edit. What is forbidden is a Bash redirect or heredoc into the denied set.
- **Shell hooks go live on commit**, because `~/.claude/hooks` symlinks into this repo. There is no install step and no way to stage a hook: the commit is the deploy. A broken guard is broken for every session on this machine immediately, which is why each phase's matrix is green before its commit.
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
- [ ] Every incident command quoted verbatim in this doc is denied by the shipped guards. **Observed on main, 2026-09-15:** all of them are allowed; no registered hook matches any of them (`settings.json` hooks block has matchers for Bash, `Write|Edit|MultiEdit|NotebookEdit`, the Slack MCP writes, `mcp__multi-account-github__create_pr`, `AskUserQuestion` and `Agent`, and none of the ten Bash guards covers these verbs).
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
- **2026-09-15: the `~/Claude` symlink deny rides in this chunk.** It is not in the audit's change list; it is in Scott's `CLAUDE.md`, and the LN rule is the only place it can be enforced.

## Alternatives Considered

### Alternative 1: the prompt-word commit guard as prescribed
- **Description:** deny `git commit` unless a commit-shaped word appears in the last 3 human prompts or an allowlisted skill is active.
- **Why not chosen:** measured at 590 denials and 2 of 5 incidents, defeated four ways (ask-was-something-else, machine prompts counted as human, incidental vocabulary, and no human prompt at all in subagents). Full numbers above. Kept here so it is not re-proposed.

### Alternative 2: a docs-only commit deny
- **Description:** four of the five incidents committed a design doc, handoff doc or implementation-notes file with an explicit path, so deny a commit whose staged set is documentation and no code.
- **Why not chosen:** 351 docs-only commits in the window (341 main-thread), about 3 a day, against 5 incidents. Precision 1.4%. It also fires on this program's own workflow, since every chunk commits its design doc.

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

- [ ] **STAGING's price.** The blanket-staging deny fires 474 times over four months to catch 1 of 5 commit incidents, and its independent justification is the phantom-file rule plus the 96 subagent phases that ran `git add -A`. Options: (A) ship it as Phase 7; (B) ship it plus a non-blocking rails context line on commits with no prompt ask (roughly 590 injections, no denials, efficacy unmeasured); (C) drop item 1 entirely and record it as a Non-Goal with the precision numbers. **Rec: A.** It is the only mechanism in the set that infers nothing, and B adds a second unmeasured prose-shaped thing of exactly the kind the audit says does not work.

Closed during the research fold-in, recorded here so it is not reopened:

- **Fail-open or fail-closed when the transcript is unreadable.** This was an open question while three rules read prompts. After the fold-in only SLACK does, and it fails **closed** with the two exempt ids still passing on hardcoded literals. `panel-round-guard.sh:50-57` fails open behind a measured 97.4% hit rate, which is right for a round counter and wrong for an authorization gate: a gate that fails open permits exactly the action it exists to stop.
- **Item 1's repo scope** (every repo, or only repos with a remote). Moot: item 1 is refused.
- **Item 7's visibility source.** Cached per repo with a TTL, and an unknown or unreadable cache entry is treated as **public**, so a repo that flips to public between refreshes fails closed rather than silently losing the guard.

## References

- Program baton: `docs/design/2026-09-13-setup-audit-program.md`
- Audit, ranked: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/ (item 6)
- Audit, raw findings: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-audit-findings-2026-09-12/ (lens `incidents` 6-12, lens `hooks-sandbox` F8-F9, lens `mcp-usage` F7-F8)
- Chunk A: `docs/design/2026-09-13-enforcement-core.md`
- Chunk B: `docs/design/2026-09-13-guard-precision.md`
- Chunk C: `docs/design/2026-09-14-panel-round-cap.md`
- Measurement scripts for every count in this doc: the session scratchpad's `intent-scan.py`, `scan2.py` through `scan6.py`, `why.py`, `why2.py`
