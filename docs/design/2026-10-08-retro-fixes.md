# Design Document: Retro fixes, the month of 2026-09-08 to 2026-10-08

**Author:** Scott Idler
**Date:** 2026-10-08
**Status:** Ready to build (both open questions closed by Scott 2026-10-08; panel round 1 folded; no disputes). Awaiting Scott's go.
**Review Passes Completed:** 5/5, then panel round 1 folded (7 must-fix, 8 cheap wins, 2 demoted; synthesis `/tmp/review-panel/GZsuYMOh/synthesis.md`)

> Panel round 1 ran 2026-10-08 (Architect after one sandbox-network retry, Staff Engineer clean). Verdict: not ready, on three things: Gate F inherited Gate B's refspec extraction, which strips the destination and would ALLOW `git push origin feat:main`; OQ1's "undeclared tatari-tv is shipit" contradicted hall 10-07 (c), the managed PR policy, and the live commit-on-main gate; and Phase 6 could not unload `cli.md`/`logging.md` by removing `alwaysApply` (a rule with no frontmatter still loads). All folded. The seats also showed the fix-6 measurement is provisional: rails treats a `bash -c` payload that contains an excluded head as exempt, so whether `bash -c 'cargo build'` ran in-sandbox is unknown until Phase 0 runs a single-stage marker. OQ1 gained a third option (default by org); Scott closed it the other way: GitHub is the truth, marquee gets protected.
>
> Passes 2 to 5 ran 2026-10-08 on the same draft. Pass 2 dropped the per-day gate cache, named the `UNKNOWN` fallback, added the Gate E door, and listed the `git` subcommands fix 4 exempts. Pass 3 added the phase count, the blast radius, and the ship order to the Overview. Pass 4 added the subagent shape updates to Phase 11 and replaced AC5's instrument with a one-liner (nothing under `docs/` may be a script). Pass 5 fixed the Phase 5 criterion (`rg` without `--hidden` skips `HOME/.claude` and reports zero hits today) and ran the voice lint.

## Summary

A `/retro` over the month's 1,511 sessions ($7,935, 102K tool calls, 5,114 tool errors) produced 14 fixes to the Claude Code environment. Scott chose on 2026-10-08 to carry all 14 in one doc, a one-time override of the baton's one-chunk-per-doc rule (`docs/design/2026-09-13-setup-audit-program.md:22-26`), the way D2 and E shared a doc on 2026-09-17.

The month's lesson in one line: every win came from a hook; the prose-only rules did not move. So 11 of the 14 fixes are hooks, settings, or file moves, and the 3 prose fixes are one line each or a lift of rulings already written.

Three premises in the retro were wrong and are corrected here from the research dig: the title guard's slashed-branch text already shipped on 2026-09-14 (fix 11 becomes a verification fixture); rails already treats a trailing `| tail` / `2>&1` as transparent (fix 7 becomes a better deny text); and GitHub said `tatari-tv/marquee` is ungated while Scott treated it as protected. Scott ruled 2026-10-08: GitHub is always where the gating truth lives, and marquee's exemption goes (he protects its main). Fixes 1 and 2 key on `bump --gates` alone.

## Problem Statement

### Background

- Chunks A through F2 of the setup-audit program built the enforcement layer: sandbox config, prose hooks, the shared parser, release gates A-D, intent guards, recall and handoff hooks.
- The month after: 22 sessions of explicit anger about release and tagging, 10 about GUI navigation from memory, 12 about dithering; 25 `~/HALL-OF-SHAME.md` entries dated in the month (`:1457-2010`), all but two about release, push, or tag.
- Tool-error rate climbed week over week: 3.3% -> 4.4% -> 5.2% -> 7.5%.
- Measured over the month's transcripts (`~/.claude/projects/*/*.jsonl`, 1,559 top-level files, 2,562 error results; subagent files push the clyde count to 5,114):

| error class | count | sessions |
|---|---|---|
| rails "would run unsandboxed because X is in excludedCommands" | 534 | 181 |
| auto-mode classifier denials (26 Self-Modification on the config repo) | 160 | |
| oversized MCP results ("exceeds maximum allowed tokens") | 100 | 61 |
| "Linux sandbox HTTP bridge socket is missing" | 55 | 8 |
| "not a git repository" | 45 | 30 |
| em-dash denials (working as designed) | 41 | |
| branch-pr-title guard | 36 | 24 |
| security-guidance StructuredOutput schema failure | 30 | 30 |
| `bwrap: Can't find source path /tmp/review-panel/.mcp.json` | 14 | |
| `pkill -f` exit 144 (killed its own shell) | 18 | 8 |

- rails denials by excluded head: cargo 134, git 114, otto 74, bump 63, slack 42, systemctl 37, journalctl 37, ssh 22, aws-vault 8. By stage pair (research dig, 1,570 results incl. duplicates): `git` because `git` 166, `git` because `cargo` 128, `sed` because `cargo` 112, `tail` because `otto` 91 (all `otto ci > log; tail log`), `git` because `bump` 66.

### Problem

Release flow, the biggest cluster, has a gate for everything except the three moves that recurred: a PR on an ungated repo, a push to a gated main, and a sandbox-off push from a subagent. The rulings that govern those moves live in a 2,027-line, 157 KB narrative file that the agent is told to grep and does not.

Below that, five mechanical costs the agent pays dozens of times a week with no hook to stop them (compound commands against excluded heads, dead sandbox bridge retried 17 times, a phantom mount, self-killing `pkill`, a plugin that fails its own schema), and 1,144 lines of always-on steering of which the implementation agent needs a fraction.

### Goals

- G1: the three unhooked release moves get a deny each, keyed on one gating source of truth that `bump`, the hooks, and release-driver all read (Scott, retro fixes 1-3).
- G2: a `git`/`bump` call outside a repo is denied with the legal shape named (fix 4).
- G3: the release rulings are a 30-line ref, the hall stays the ledger (fix 5).
- G4: excluded heads that work in-sandbox leave `excludedCommands`; the remaining denials carry the exact two-call rewrite (fixes 6, 7).
- G5: the three sandbox infra failures stop costing retries (fixes 8, 9, 10).
- G6: the title guard's slashed-branch path has a pinned fixture; the security-guidance plugin is off (fixes 11, 12).
- G7: the three oversized-result tools return rows that fit (fix 13).
- G8: always-on steering drops by at least the bytes of `tools.md`, `cli.md`, `logging.md` (fix 14).

### Non-Goals

- The auto-mode classifier's 160 denials: server-side, no local lever.
- GUI navigation from memory and dithering: prose rules exist (`rules/interaction.md`), no hook can see a wrong button name. Excluded.
- The 84 flat-branch title mismatches: the guard's intended text; not a defect.
- `pgrep`: nobody asked; the rule covers `pkill -f` only.
- A `pkill -f` rewrite for patterns outside the supported subset (an alternation `a|b`, a leading metachar): denied with the bracketed form named, never rewritten half-right.
- `systemctl *` stays excluded: measured 2026-10-08 in-sandbox, `systemctl --user status` -> "Failed to connect to user scope bus via local transport", rc=1.
- A declaration layer for gating (`gated:` in `bump.yml`, an org default): rejected by Scott 2026-10-08, see Alternatives 2 and 7. Settled, not parked.
- `taste.md` as a whole: only the review-only sections move (fix 14); the architecture, security, and naming sections stay always-on. Parked: revisit if the implementation audit shows an implementer needing a moved section.
- A `git -C <repo> push` shape for subagents: rails `excludedAs` (`index.ts:576-583`) and intent-guard `gitnet_bare_simple` (`:473-479`) both anchor on `^git push`, so an interior `*` can never match. Dropped; the subagent shape is `bump <verb> <repo>` (Phase 9), and no agent in this setup hand-pushes a release.

## Proposed Solution

### Overview

Fourteen fixes in four groups, 17 phases plus a close, each its own phase and commit. Blast radius: four repos (`scottidler/claude`, `scottidler/bump`, `tatari-tv/clyde`, `tatari-tv/marquee`) plus two pointer bumps in `tatari-tv/tatari-skills`. Ship order forced: bump before the two sandbox-off/gate hook phases; clyde and marquee last.

```
prose/settings (1,2,3,4,5,6,7,8)  ->  bump (9)  ->  shell hooks (10,11,12)  ->  rails (13,14)  ->  clyde (15) | marquee (16)
```

### Architecture

**Gating source of truth (fixes 1, 2, 3).** GitHub is always where the gating truth lives (Scott, 2026-10-08). One verdict, three readers, no declaration layer.

- `bump --gates` is the verdict (`bump/src/main.rs:316-346`): `Gates:  none (ungated)` | `Gates:  <rules> (gated)` | `Gates:  UNKNOWN (could not verify: <reason>)`, always rc=0. Test seam: `BUMP_GATES_PROBE=ungated|gated|gated:t1,t2|unknown:reason` (`github.rs:48-51,101-121`).
- The one repo where the verdict and Scott disagreed, `tatari-tv/marquee` (API: protection 404, rulesets `[]`, `.protected` false; hall `:1652`, `:1996-2003`, `:2021-2026`), stops being an exception: Scott protects `main` in GitHub (operator step, a `pull_request` ruleset, recorded in Phase 0 with the settings as applied), and marquee's `bump --no-tag -m` door (`marquee/AGENTS.md:206-221`, hall `:1687`) is rewritten to the standard gated flow in Phase 16. The snapshot step survives as a second commit on the release PR: `bump release -m` on the branch opens the PR with the version commit, then `otto snapshot`, commit, push; CI goes green on the head, the merge needs green on the head, `bump finish` after.
- Readers: `git-release-guard.sh` gains `gate_verdict <dir>` (calls `bump --gates <dir>` with an inner deadline shorter than the hook's, parses the `Gates:` line on stdout; no cache, the probe runs only on `gh pr create` and `git push ... main` statements, a few per day). Gate E: `gh pr create` on `ungated` -> deny, text cites `refs/release-rulings.md`. Gate F: `git push` whose refspec DESTINATION resolves to `main`/`master` on `gated` -> deny; `git push origin main`, `git push origin feat:main`, `git push origin HEAD:main`, `git push` with no refspec on main all resolve to main. `UNKNOWN`, a probe timeout, a missing `bump`, a non-zero exit, or an unparseable line -> deny both, text carries the reason and says run `bump --gates` and report; fail loudly, fail closed.
- Gate E door, same shape as Gate D's body line: a PR body carrying `PR on ungated: ordered by Scott - <his words>` passes. Never invented; the words come from this session.
- Consequence: an ungated tatari-tv repo is shipit (hall 10-02 (a), 10-03 (c)); hall 10-07 (b) (squash-merge heuristic) and (c) ("org policy beats tool output") are superseded, because the tool output IS the policy once the policy is in GitHub.
- Hook env: a PreToolUse hook inherits the Claude process env. `bump` has its own token chain (`github.rs:291-350`), so Phase 0 runs `bump --gates` itself from a throwaway hook against a home-private and a work repo, not `gh api user`. If a home-private repo reads `UNKNOWN`, Phase 12 picks the token by slug inside the hook (`github-pat-home` for `scottidler/*` via the decrypt path in `rules/secrets.md`, value never printed, never a TTY or passphrase prompt) rather than treating the miss as a verdict.

**Sandbox-off on excluded verbs (fix 3).** `intent-guard.sh:467-470` already reads `.tool_input.dangerouslyDisableSandbox` into `sandbox_off`; today it turns GIT-NET's shape rule (`:1714`) and SSH-SHAPE (`:1721`) into allows, with fixtures asserting that (`intent-guard-test.sh:675-677,697`). This fix inverts them: `sandbox_off=1` on `git push|pull|fetch|ls-remote|clone`, `ssh`, or `bump` -> deny, text: "these run unsandboxed by `excludedCommands` already; the flag is only ever a bypass; run the bare command". Scott-visible reversal of three shipped fixtures, recorded under Resolved Decisions.

- The subagent problem the five 2026-10-03 hall entries share (`:1697`, `:1766`): the harness resets the shell cwd to a working directory whenever a `cd` lands outside the session's working directories (measured 2026-10-08: `cd <scratchpad>; pwd` printed the scratchpad, then "Shell cwd was reset to /home/saidler/repos/tatari-tv/tatari-skills"; a `cd` under `~/repos`, an additional working dir here, sticks). A subagent whose working dirs do not include the repo loses every `cd`, so "cd in its own call, then bare `bump release`" cannot work from release-driver when the parent sits outside the repo. Denying the sandbox-off escape without a legal shape strands release-driver. The legal shape is `bump release <dir>` / `bump finish <dir>`: today `DIRECTORIES` is a top-level positional (`cli.rs:82-84`), `ReleaseArgs`/`FinishArgs` take no directory, and `dispatch_command` hardwires `env::current_dir()` (`main.rs:866-869`). Phase 9 adds an optional `[DIR]` positional to both verbs. A bare `bump release /path` is still a simple command, so every allow rule and the `bump *` exclusion match unchanged.

**Not a repo (fix 4).** New gate in `git-release-guard.sh` before the tag gates: `cmdword_is git` or `cmdword_is bump`, with `git -C "$stmt_dir" rev-parse --git-dir` failing -> deny. Exempt, because each is legal outside a repo: `git clone`, `git init`, `git --version`, `git help`, `git config --global|--system`, `git ls-remote <url>`, `git -C <dir>` and `git --git-dir` (resolved via the `dash_c_tree` precedent in `branch-pr-title-guard.sh:107-123`), and `bump <verb> <dir>` (resolved to `<dir>`). Deny text: "`<cwd>` is not a git repository; `cd <repo>` in its own call, or `bump <verb> <repo>`". Today `:149,168` swallow the failed rev-parse and every gate self-skips.

**Release rulings ref (fix 5).** `HOME/repos/.claude/refs/release-rulings.md`, one bullet per ruling with its hall line: THE RULING `:484-540` (two flows, decided by `bump --gates`), 09-26 one release command (`git-release-guard.sh:106-111`), 10-02 (a) protected -> release-driver, not protected -> shipit `:1740`, 10-03 (c) tatari-tv ungated shape `:1744`, 10-03 lint-unused "ungated: never push by hand, `bump release` is the push" `:1756`, 10-05 (d) `:1974`, 10-07 (a), (d), (e) `:2021-2026`, and the 2026-10-08 ruling itself: GitHub is always where the gating truth lives. `rules/git.md` "Tagging / releases" gets the pointer; `CLAUDE.md` References gets the entry. NOT lifted, superseded by the 10-08 ruling: 10-07 (b) (squash-merge heuristic), 10-07 (c) (org policy beats tool output), 09-29 (a) and 09-30 (b) (marquee's door, `:1652`, `:1687`); each gets one line under a "superseded" heading so the next agent does not re-derive them.

**excludedCommands (fix 6).** Measured 2026-10-08 inside this session, first via `bash -c` (provisional, the panel asked for a marker), then PROVEN with a marker: a probe crate whose program opens `~/HALL-OF-SHAME.md` for append without writing (home root is outside the write allowlist, so in-sandbox that is EROFS) and prints `SANDBOX_RUNTIME`, an env var the sandbox sets to `1`. Controls: bare `cargo run -q` in the probe dir printed `append-open: OK` and `SANDBOX_RUNTIME=unset` (unsandboxed, the exclusion working); `bash -c 'cargo run -q'`, `otto ci | tail` (whose task is `cargo run -q`), and `S=...; cargo run -q --manifest-path $S/...` all printed `Read-only file system (os error 30)` and `SANDBOX_RUNTIME=1` and still built and ran the crate with the sccache wrapper active (`~/.cargo/config.toml:2`).

| head | command | result |
|---|---|---|
| cargo | `bash -c 'cd ~/repos/scottidler/bump && cargo build'`; marker runs above | compiled, rc=0; marker: sandboxed and built |
| otto | `bash -c 'cd ~/repos/scottidler/bump && otto ci'`; `otto ci \| tail` on the probe | `All CI checks passed!`, rc=0; marker: `[ci] SANDBOX_RUNTIME=1`, built, ran |
| journalctl | `bash -c 'journalctl --user -n1 --no-pager'` | one line, rc=0 |
| systemctl | `bash -c 'systemctl --user status --no-pager'` | "Failed to connect to user scope bus", rc=1 |

`cargo *`, `otto *`, `journalctl *` leave the list; `systemctl *` stays. Scott, 2026-10-08: "so then remove them, but you better fucking test that it works as you claim it does since 9/20"; the marker runs above are that test, and Phase 4 re-runs them in a fresh session after the edit. That is 245 of the 534 denials (46%). The case rests on the heads no longer needing exclusion: `cargo *`/`otto *` were excluded on 2026-06-09 for the sccache socket (`enforcement-core.md:28`), `allowAllUnixSockets: true` removed that reason on 2026-09-20 (`refs/sccache-sandbox.md:52`), and `journalctl` needs no bus. The 09-13 option D ruling (`enforcement-core.md:357`) kept all ten because reverting the five NEW bare words would lose five fixes, and it said in so many words that hatch count is not the variable; it did not weigh heads whose reason had expired. Scott confirmed the supersession on 2026-10-08 (OQ2 closed).

**rails deny text (fix 7).** The strip premise is dead: `index.ts:530-536,612-621,630` already pass a trailing `| tail`, `| head`, `2>&1`, and redirects (`:148`). The survivors are acting stages (`git fetch && git rev-list`, `sed -i && cargo check`, `otto ci > log; tail log`). The rails header's premise is dead too: `index.ts:509-520` says an excluded stage anywhere exempts the whole compound (measured 2026-09-13), and on 2.1.295 the marker shows the opposite: a compound (`;`, `&&`, `|`, a `VAR=x;` prefix, `bash -c '...'`) runs fully SANDBOXED whatever heads it contains; only a bare simple command matching the glob is exempt (`cargo run -q` unsandboxed, `S=x; cargo run -q ...` sandboxed, `otto ci | tail` sandboxed, `ssh ripr.lan ls /tmp` bare unsandboxed). That matches `intent-guard.sh:453-457` (2026-09-24) and means the mixed-compound hatch the 09-13 ruling closed is closed by the harness itself. The rails deny stays for the heads that FAIL sandboxed (git net verbs, `bump`, `ssh`, `slack`, `systemctl`, `aws-vault`, `crontab`): it prevents a confusing in-sandbox failure, and it keeps the hatch shut if a later harness version exempts compounds again. `excludedDeny` (`index.ts:646-652`) gets the truthful text: "`<excluded stage>` would run INSIDE the sandbox here (a compound is never exempt) and cannot authenticate/reach the host; run `<excluded stage>` alone, then `<rest>`". The header comment at `:509-520` records the 2026-10-08 measurement beside the 2026-09-13 one. After fix 6 the `cargo`/`otto`/`journalctl` pairs stop being mixed, so 245 of 534 denials go; the remaining 286 are correct denials with a text that now tells the truth.

**Bridge socket (fix 8).** One bullet in `CLAUDE.md:46-57` beside the phantom-files bullets: the exact string means the sandbox bridge is dead for the rest of the session; nothing recovers it; stop and tell Scott to restart. No hook can see it before the call.

**Review-panel run dir (fix 9).** `/tmp/review-panel` is tmpfs and named in `settings.json:742` (`additionalDirectories`), `:1123` (`allowWrite`, redundant: `/tmp` is at `:1121`), `:1140` (`allowRead`, a no-op: no read-deny covers it). The `.mcp.json` deny-mount leaves a `nobody`-owned stub there (the phantom from `CLAUDE.md:46-54`); after a reboot the parent is gone until `review-panel.md:87-88` runs `mkdir -p`, and bwrap then fails to mount the stub on every Bash call. Move the run dir to `~/.cache/review-panel/runs/` (precedent: `panel-round-guard.sh:27-29,92` already uses `~/.cache/review-panel/rounds` and records "/tmp was rejected"; `~/.cache` is in `allowWrite`). Delete the three settings entries; update `review-panel.md:87-91` (which also claims a `Read(/tmp/review-panel/**)` permission that no longer exists), rails `SCRATCH`/`RM_DENY` (`index.ts:281,303`), both seat scripts (`architect/script.sh:16-20,66`, `staff-engineer/script.sh:16-21,66`), `architect/limitations.md`, `docs/sandbox-filesystem-allowlist.md`. rails `SCRATCH` gets `runs/` only, in both the tilde and the absolute form (rails compares literal prefixes, `index.ts:428-432`); the `rounds/` counters stay outside scratch so a wrapper `rm` cannot reset the cap. No sweep exists for `rounds/` and none is added for `runs/` by a timer: `review-panel.md` Step 0 prunes `runs/` entries older than 14 days with plain `rm -rf` (scratch, regenerable) before minting a new one.

**pkill (fix 10).** Nothing handles `pkill` today (zero hits across hooks, rails, rules). A fourth rails `tool.call` rule beside the rm rule (`index.ts:733-749`): `pkill -f <pat>` where `<pat>` is in the supported subset (first character a literal, no `|` anywhere, not already bracketed) -> bracket the first character (`quartz.*4173` -> `[q]uartz.*4173`); `-x`, no `-f`, or already bracketed -> untouched; outside the subset -> deny with the bracketed form of each alternative named. Returned via `updatedInput` + `withContext` like the gh-persona rewrite (`:727-730`).

**Title guard (fix 11).** Already shipped: `branch-pr-title-guard.sh:85-90` (commit `0907a90`, 2026-09-14) says `rename the BRANCH: git branch -m <slug>` for any branch containing `/` or `.`. Session `a2823139` (2026-09-12) predates it. This phase adds the pinning fixture only.

**security-guidance (fix 12).** `settings.json:1069` -> `false`. The plugin's review subagent emits `{"findings": {"findings": []}}` against a schema that wants an array (`review_api.py:125-152` in the 2.0.11 cache), 30 of 30 reviews this month. Feedback filed; flip back when a release fixes it.

**Tool budget (fix 13).**
- clyde `sessions_ls` (`sessions/src/mcp.rs:244-275`) serializes the whole `SessionRecord` (`model.rs:11-56`): `first_prompt` up to 2,000 chars, `cwd`, `project_dir`, `transcript_path`. Default row drops those four; a `verbose: true` request field restores them. `limit` stays (default 50, max 200).
- marquee has two MCP surfaces that return a post body: the local `cli/src/mcp.rs:268-277,476-510` and the remote `mcp/src/lib.rs:170-208` (`ReadInput`/`ReadOutput`, `deny_unknown_fields`). Both gain `max_bytes` (default 60,000; `0` = no cap) and `truncated: bool`; truncation cuts on a UTF-8 char boundary. The CLI `read` stays byte-exact (stdout is for files). A new wire field is a minor bump, which triggers marquee's snapshot step.
- `refs/jira.md` gains a JQL section: `searchJiraIssuesUsingJql` always with `fields` and `maxResults` (<= 25). Parameter names verified via ToolSearch before the phase writes them.

**Steering load (fix 14).** Always-on today: 889 rule lines (12 `alwaysApply: true` files plus `voice.md`, which has no frontmatter and so loads unconditionally) + `CLAUDE.md` 132 + `WHOAMI.md` 46 + `tools.md` 52 + `repos/CLAUDE.md` 25 = 1,144 lines, 67,903 bytes.
- Delete `tools.md` (3,349 bytes, a `--help` cache last regenerated 2026-07-02, two entries already junk) and its include at `CLAUDE.md:86`.
- `cli.md` (2,932) and `logging.md` (1,472) MOVE out of `rules/` to `refs/cli.md` and `refs/logging.md` (removing `alwaysApply` alone leaves a rule always-on, see `voice.md`); `agents/phase-implementer.md:33` and `agents/review-panel.md:307` gain the pointer (both already read `taste.md`).
- `taste.md`: "The pipeline is the process", "The design doc is the source of truth", "Phasing", "Evidence standards" move to `refs/process-taste.md`, pointed at from `create-design-doc`, `how-to-execute-a-plan`, `review-panel.md`. "Quality bar", "Architecture instincts", "Security instincts" stay always-on.
- `voice.md` gains `alwaysApply: true` so its status is declared, not accidental.
- Floor: 7,753 bytes (the three deleted/moved files), measured.

### Data Model

- `sessions_ls` request: `verbose: Option<bool>`.
- `marquee_read` request (both MCPs): `max_bytes: Option<usize>`; response: `truncated: bool`.

### API Design

- `bump release [FLAGS] [DIR]`, `bump finish [DIR]`: one optional directory on each verb's own args; absent -> cwd.
- Hook deny texts (all cite the ref):
  - Gate E: "release-rulings.md: `<slug>` is ungated; ungated repos do not take PRs. `bump release` on main is the push (hall 10-02 (a), 10-03 lint-unused). Scott's order goes in the body as `PR on ungated: ordered by Scott - <words>`."
  - Gate F: "release-rulings.md: `<slug>` is gated; main takes PRs only. Branch, `bump release` on the branch, merge, `bump finish`."
  - Gate E/F on `UNKNOWN`: "could not verify gating: `<reason>`. Run `bump --gates` and report."
  - sandbox-off: "`<verb>` already runs unsandboxed via excludedCommands; `dangerouslyDisableSandbox` is only a bypass here. Run the bare command (from a subagent: `bump <verb> <repo>`)."
  - not-a-repo: "`<cwd>` is not a git repository. `cd <repo>` in its own call, or `bump <verb> <repo>`."

### Implementation Plan

Each phase: one commit, `otto ci` green, acceptance recorded. Config-repo phases land on main with `git push origin <branch>:main` (hazard `setup-audit-program.md:129`). Shell hooks go live on commit; rails only in a fresh session.

#### Phase 0: Spike, zero code
**Model:** opus

Each row names what each result changes.

| measurement | how | if yes | if no |
|---|---|---|---|
| cold `cargo fetch` | `CARGO_HOME=$TMPDIR/ch cargo fetch` in bump, sandboxed | network path proven | add the missing host to `allowedDomains` or keep `cargo *` |
| otto in clyde | `bash -c 'cd ~/repos/tatari-tv/clyde && otto ci'` (its tasks install `cargo-mutants`) | nothing new | add the failing task's host to `allowedDomains` or keep `otto *` |
| excludedCommands matching on 2.1.295 | DONE 2026-10-08 with the probe marker: bare `cargo run -q` UNSANDBOXED; `S=x; cargo run -q --manifest-path ...` SANDBOXED; `otto ci \| tail` SANDBOXED; `otto -C <abs> ci \| tail` SANDBOXED; `bash -c 'cargo run -q'` SANDBOXED; bare `ssh ripr.lan ls /tmp` UNSANDBOXED | one statement: only a bare simple command matching the glob is exempt; every compound runs sandboxed. rails header `:509-520` is wrong on 2.1.295, intent-guard `:453-457` is right | n/a |
| sandbox marker | DONE 2026-10-08: append-open on `~/HALL-OF-SHAME.md` (EROFS in-sandbox) plus `SANDBOX_RUNTIME` (`1` in-sandbox, unset outside); `~/.ssh` is NOT a marker (`agent`, `allowed_signers`, `identities` are allowWithinDeny and show both ways) | valid | n/a |
| cargo, otto, journalctl in-sandbox | DONE 2026-10-08, see fix 6 | drop all three in Phase 4 | n/a |
| marquee protected | Scott applies a `pull_request` ruleset to `tatari-tv/marquee` main; `bump --gates` in the marquee checkout | prints `(gated)`; record the ruleset settings here | Gates E/F would deny the marquee PR and allow a marquee push; Phase 12 waits |
| `bump --gates` from a hook | throwaway PreToolUse hook runs `bump --gates` in `~/repos/scottidler/bump` (home, private?) and `~/repos/tatari-tv/marquee`; also with a 2s inner `timeout` and with `bump` off PATH | verdicts clean on stdout; Phase 12 as designed | Phase 12 adds the by-slug token pick; any failure mode that is not a clean `UNKNOWN` line gets its own deny text |
| `BUMP_GATES_PROBE=gated bump --gates` | run it | prints `Gates:  pull_request (gated)`; Phase 12 fixtures use it | find the seam |
| rails -> shell hook order | a rails `updatedInput` on a command `git-release-guard.sh` would deny; which one the shell hook sees (`guard-precision-review-log.md:32`) | Phases 13/14 rewrite freely | rewrites must stay deny-equivalent |
| fresh-session rule loading | in a session started after a scratch commit that moves `cli.md` to `refs/`, `/context` or the system prompt shows it absent | Phase 6 as designed | find what loads it |

**Phase 0 results, run 2026-10-09 on Claude Code 2.1.295.** One block per remaining row: how it ran, the exact stdout, the branch taken.

*Cold `cargo fetch`.* `cd ~/repos/scottidler/bump` in its own call, then `CARGO_HOME=$TMPDIR/ch cargo fetch; echo "rc=$?"; echo "SANDBOX_RUNTIME=${SANDBOX_RUNTIME:-unset}"` (a compound, so sandboxed). Output opened with `Updating crates.io index`, three `Updating git repository` lines (`https://github.com/tatari-tv/mcp-io-rs`, `.../okta-auth-rs.git`, `.../renew`), then `Downloading crates ...` and every `Downloaded` line, and closed:
```
  Downloaded aws-lc-sys v0.45.0
rc=0
SANDBOX_RUNTIME=1
```
Branch: **if yes**, the network path is proven from an empty `CARGO_HOME` (crates.io index, crate downloads, and git deps on github.com), no `allowedDomains` change.

*otto in clyde.* `bash -c 'cd ~/repos/tatari-tv/clyde && otto ci > $TMPDIR/otto-clyde.log 2>&1; echo "rc=$?"; echo "SANDBOX_RUNTIME=${SANDBOX_RUNTIME:-unset}"'` printed:
```
rc=0
SANDBOX_RUNTIME=1
```
The log (2,313 lines) ends `[ci] ✅ All CI checks passed!`; the tasks that ran were `lint`, `bloat`, `check`, `test`, `ci`. The row's premise was off: clyde's `mutants` task (the one that runs `cargo install cargo-mutants`) is NOT a `before:` of `ci` (`clyde/.otto.yml:146-153`, "NOT part of ci"), so `otto ci` never installs anything. A `cargo install` reaches the same crates.io hosts the cold-fetch row just proved. Branch: **if yes**, nothing new; `otto *` can leave the list.

*marquee protected.* Orchestrator run at 00:08, re-run by the Phase 0 implementer in `~/repos/tatari-tv/marquee`, bare `bump --gates`:
```
Repo:   tatari-tv/marquee
Branch: main
Gates:  none (ungated)

Ungated flow:
  bump release [-m|-M]       # on main: version commit, push, CI wait, tag, push tag
```
Scott has not applied the ruleset yet. Branch: **if no**. Gates E/F would deny the marquee PR and allow a marquee push; Phase 12 waits on Scott's operator step, and the ruleset settings get recorded here when it lands.

*`bump --gates` from a hook.* Live hooks and `settings.json` were not touched. A PreToolUse hook is a child of the Claude process, unsandboxed, with the Claude process env, so the probe ran from a scratch script under the Bash tool (which inherits that env) twice: once sandboxed, once with the sandbox off as a hook runs. Both runs gave the same verdict for every case. Modes: `env` (as inherited), `nopersona` (`env -u GITHUB_PAT_HOME -u GITHUB_PAT_WORK`), `timeout` (`timeout 2`), `nopath` (`PATH=/usr/local/bin:/usr/bin:/bin`, no `~/.cargo/bin`). `~/repos/scottidler/bump` turned out to be PUBLIC (`gh api repos/scottidler/bump --jq .visibility` -> `public`), so `~/repos/scottidler/obsidian` (`private`) is the home-private case. Unsandboxed run, filtered to the `===`, `Gates:`, `rc=`, `stderr` lines (the scratchpad path in `stderr` shortened to `...`):
```
=== /home/saidler/repos/scottidler/bump [env]
Gates:  none (ungated)
rc=0 elapsed=.623880549s SANDBOX_RUNTIME=unset
=== /home/saidler/repos/scottidler/bump [nopersona]
Gates:  none (ungated)
rc=0 elapsed=.656478484s SANDBOX_RUNTIME=unset
=== /home/saidler/repos/scottidler/bump [timeout]
Gates:  none (ungated)
rc=0 elapsed=.654104859s SANDBOX_RUNTIME=unset
=== /home/saidler/repos/scottidler/bump [nopath]
rc=127 elapsed=.005473318s SANDBOX_RUNTIME=unset
stderr: .../hook-sim.sh: line 17: bump: command not found
=== /home/saidler/repos/scottidler/obsidian [env]
Gates:  UNKNOWN (could not verify: classic-protection probe failed: gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403))
rc=0 elapsed=.422944900s SANDBOX_RUNTIME=unset
=== /home/saidler/repos/scottidler/obsidian [nopersona]
Gates:  UNKNOWN (could not verify: ruleset probe failed: gh: Not Found (HTTP 404))
rc=0 elapsed=.777825812s SANDBOX_RUNTIME=unset
=== /home/saidler/repos/scottidler/obsidian [timeout]
Gates:  UNKNOWN (could not verify: classic-protection probe failed: gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403))
rc=0 elapsed=.409218354s SANDBOX_RUNTIME=unset
=== /home/saidler/repos/scottidler/obsidian [nopath]
rc=127 elapsed=.006192373s SANDBOX_RUNTIME=unset
stderr: .../hook-sim.sh: line 17: bump: command not found
=== /home/saidler/repos/tatari-tv/marquee [env]
Gates:  none (ungated)
rc=0 elapsed=.769105154s SANDBOX_RUNTIME=unset
=== /home/saidler/repos/tatari-tv/marquee [nopersona]
Gates:  none (ungated)
rc=0 elapsed=.898622779s SANDBOX_RUNTIME=unset
=== /home/saidler/repos/tatari-tv/marquee [timeout]
Gates:  none (ungated)
rc=0 elapsed=.748479066s SANDBOX_RUNTIME=unset
=== /home/saidler/repos/tatari-tv/marquee [nopath]
rc=127 elapsed=.006260397s SANDBOX_RUNTIME=unset
stderr: .../hook-sim.sh: line 17: bump: command not found
```
A forced expiry, `timeout 0.05 bump --gates` in marquee, printed nothing on stdout and exited `rc=124`. Every real probe finished in under 0.9s, inside a 2s deadline.

Branch: **if no, and for a different reason than the row anticipated.** The home-private repo reads `UNKNOWN` WITH the right token: GitHub's classic-protection endpoint answers HTTP 403 "Upgrade to GitHub Pro or make this repository public" for a private repo on a free personal plan, whoever asks. The rulesets endpoint gives the same answer with the home token (`gh api repos/scottidler/obsidian/rules/branches/main` -> `gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)`), so on this plan GitHub can enforce neither layer and the repo is ungated in fact. The by-slug token pick cannot fix that, because the token is already right (bump's chain at `github.rs:291-350` finds `GITHUB_PAT_HOME` in the inherited env). Four things Phase 12 now has to handle, each with evidence above:
- `UNKNOWN` exits `rc=0`. A non-zero exit cannot be the failure signal; the `Gates:` line is the only verdict, so parse it, and treat a missing line as failure.
- `bump` off PATH is `rc=127` with empty stdout; a timeout is `rc=124` with empty stdout. Both fall into "no `Gates:` line", each needs its own reason text.
- With the persona vars absent (`nopersona`), bump falls back to the ambient work `GH_TOKEN`, the classic probe on the private home repo reads 404 as clear, and the ruleset probe 404s to `UNKNOWN`. Still `UNKNOWN`, never a false `ungated`, so it fails closed.
- Every private `scottidler/*` repo (obsidian, keep) reads `UNKNOWN` permanently, so Gates E/F as designed would deny every `gh pr create` and every `git push ... main` there. That needs a decision before Phase 12 (Open questions in the implementation notes).

*`BUMP_GATES_PROBE=gated bump --gates`.* Bare, in `~/repos/tatari-tv/marquee`:
```
Repo:   tatari-tv/marquee
Branch: main
Gates:  pull_request (gated)

Gated flow:
  bump release [-m|-M]       # on the feature branch: version commit, push, PR
  <merge the PR>
  bump finish                # CI wait on the merged main, tag, push tag
```
Branch: **if yes**, Phase 12 fixtures use it. The other accepted forms, from `parse_probe_override` (`bump/src/github.rs:102-122`): `ungated`, `gated:type1,type2`, `unknown:<reason>`; anything else becomes `UNKNOWN (invalid BUMP_GATES_PROBE: ...)`.

*rails -> shell hook order.* No scratch hook was registered. Measured with the live pair instead: rails's `tool.call` injects `GH_PERSONA` via `updatedInput` on every `gh` call, and `rewrite-cd-read.py` (a PreToolUse shell hook on the same Bash event as `git-release-guard.sh`) logs the command text it receives on every invocation that has a `cd`. Call: `cd /home/saidler/repos/scottidler/claude && gh api user --jq .login`. Rails reported `rails: GH_PERSONA injected (work, cwd under /repos/tatari-tv)`; the shell hook's log line (`~/.cache/claude/rewrite-cd-read.log:39411`):
```
2026-10-09T00:15:01	BAIL	GH_PERSONA=work	cd /home/saidler/repos/scottidler/claude && GH_PERSONA=work gh api user --jq .login
```
The shell hook saw `GH_PERSONA=work`, a token only rails adds. Rails runs first and the shell hooks receive its rewritten `tool_input`. Branch: **if yes**, Phases 13/14 rewrite freely, because `git-release-guard.sh` judges the command rails produced, not the one the model typed. (Separate from rails, shell hooks still do not compose with each other: 2026-09-14 spike 0e, `2026-09-13-guard-precision.md:425`.) Side observation, not in scope here: rails picks the persona from the hook's `cwd`, not from a `cd` inside the command, which is why a `cd` into `scottidler/claude` still got `work`.

*Fresh-session rule loading.* The live tree was not touched (`~/repos/.claude/rules/` is per-file symlinks into this repo, laid by the manifest's recursive `link:`, `manifest.yml:1-3`; moving the real file changes every session). Instead, three scratch project dirs outside `~/repos` (so the live rules do not load), each with a copy of `otto.md` in `.claude/rules/` as the positive control: `rl-yes` (`cli.md` in `rules/`), `rl-no` (`cli.md` in `refs/` only), `rl-dangle` (`cli.md` in `refs/` plus a dangling `rules/cli.md` symlink, the state a `git mv` leaves behind). Each ran `claude -p --no-session-persistence --tools "" --model haiku` asking whether the headings `List-valued flags: no comma separation` and `Never touch otto's files` are in its loaded instructions:
Stdout per run, verbatim (the label lines are added here):
```
# rl-yes
CLI=yes
OTTO=yes
rc=0
# rl-no
CLI=no
OTTO=yes
rc=0
# rl-dangle
CLI=no
OTTO=yes
rc=0
```
Branch: **if yes**, Phase 6 as designed: a file under `.claude/refs/` does not load, and nothing else loads it. One step the phase does not list yet: after `git mv`, the live `~/repos/.claude/rules/cli.md` and `logging.md` symlinks dangle (harmless per `rl-dangle`, but dead), and `refs/cli.md` / `refs/logging.md` get no live link until a scoped manifest apply. Phase 6's operator step should name both.

- **Success criteria:** every row has an exact stdout in this doc and the chosen branch named (five rows done above, six remain: cold fetch, otto in clyde, marquee protected, hook token chain, `BUMP_GATES_PROBE`, rails order, fresh-session loading).

#### Phase 1: Release rulings ref (fix 5)
**Model:** sonnet
- Write `HOME/repos/.claude/refs/release-rulings.md` (<= 40 lines, one ruling per bullet with its hall line).
- Pointer line in `rules/git.md` "Tagging / releases"; References entry in `CLAUDE.md`.
- **Success criteria:** `wc -l < HOME/repos/.claude/refs/release-rulings.md` <= 40; `rg -n release-rulings HOME/repos/.claude/rules/git.md HOME/.claude/CLAUDE.md | wc -l` = 2; `otto ci` rc=0.

#### Phase 2: Bridge-socket line (fix 8)
**Model:** sonnet
- One bullet in `CLAUDE.md:46-57`.
- **Success criteria:** `rg -c 'HTTP bridge socket' HOME/.claude/CLAUDE.md` = 1.

#### Phase 3: security-guidance off (fix 12)
**Model:** sonnet
- `settings.json:1069` -> `false`.
- **Success criteria:** `jq '.enabledPlugins["security-guidance@claude-plugins-official"]' HOME/.claude/settings.json` = `false`; `hooks-preflight.sh` rc=0.

#### Phase 4: excludedCommands shrink (fix 6)
**Model:** sonnet
- Remove the heads Phase 0 confirmed (`cargo *`, `otto *`, `journalctl *` expected) from `settings.json:1150-1167`; `review-panel.md:90-91` and `docs/sandbox-filesystem-allowlist.md` restate the list, update both; record the supersession of `enforcement-core.md:357` under Resolved Decisions.
- **Success criteria:** `! jq -r '.sandbox.excludedCommands[]' HOME/.claude/settings.json | rg -q '^(cargo|otto|journalctl) '` exits 0; in a fresh session `cargo --version && git status` is not denied and `otto ci` in `~/repos/scottidler/bump` rc=0 with the Phase 0 marker reporting sandboxed.

#### Phase 5: Review-panel run dir (fix 9)
**Model:** sonnet
- Run dir -> `~/.cache/review-panel/runs/`; delete `settings.json:742,1123,1140`; update `review-panel.md:87-91` (plus the Step 0 prune), rails `SCRATCH`/`RM_DENY` (`runs/` only, tilde and absolute), both seat scripts, `architect/limitations.md`, `docs/sandbox-filesystem-allowlist.md`.
- **Success criteria:** `jq '[.. | strings | select(test("/tmp/review-panel"))] | length' HOME/.claude/settings.json` = 0; `rg --hidden -l '/tmp/review-panel' HOME --glob '!**/docs/**' --glob '!*.bak' --glob '!**/fixtures/**'` prints nothing (`.claude` is a hidden dir, so plain `rg` reports zero today and lies; today with `--hidden`: `settings.json`, `agents/review-panel.md`, `skills/rails/hooks/index.ts`, `skills/architect/script.sh`, `skills/architect/limitations.md`, `skills/staff-engineer/script.sh`, plus `settings.json.bak` and `hooks/fixtures/inline-token/fixtures.json`, which the globs exclude: a backup and a replay fixture are history, not config); `bun test HOME/.claude/skills/rails/hooks` passes with a case asserting `rm -rf ~/.cache/review-panel/rounds/x` is NOT scratch and `rm -rf ~/.cache/review-panel/runs/x` is.

#### Phase 6: Steering trim (fix 14)
**Model:** sonnet
- Delete `tools.md` and `CLAUDE.md:86`; `git mv` `rules/cli.md` and `rules/logging.md` to `refs/`, strip their frontmatter, add pointers to `phase-implementer.md` and `review-panel.md`; four `taste.md` sections -> `refs/process-taste.md` with pointers from the three process skills; `voice.md` gains `alwaysApply: true`.
- **Success criteria:** `test ! -e HOME/.claude/tools.md && test ! -e HOME/repos/.claude/rules/cli.md && test ! -e HOME/repos/.claude/rules/logging.md`; always-on byte total (sum of `wc -c` over `alwaysApply`/no-frontmatter rules + `CLAUDE.md`, `WHOAMI.md`, `repos/CLAUDE.md`) <= 60,150 (67,903 - 7,753); `rg -n 'refs/(cli|logging)\.md' HOME/.claude/agents/phase-implementer.md | wc -l` >= 1; the Phase 0 fresh-session row re-run shows `cli.md` absent.

#### Phase 7: JQL line (fix 13c)
**Model:** sonnet
- `refs/jira.md` JQL section; parameter names checked with ToolSearch in-session first.
- **Success criteria:** `rg -c 'maxResults' HOME/repos/.claude/refs/jira.md` >= 1 and `rg -c '\bfields\b' HOME/repos/.claude/refs/jira.md` >= 1 and `rg -q '<= 25|at most 25' HOME/repos/.claude/refs/jira.md`.

#### Phase 8: Title-guard fixture (fix 11)
**Model:** sonnet
- Fixture: branch `chore/retire-general-plugin`, any title -> reason contains `git branch -m chore-retire-general-plugin`.
- **Success criteria:** `bash HOME/.claude/hooks/branch-pr-title-guard-test.sh | tail -1` reports `fail=0` with the new fixture counted.

#### Phase 9: bump honors a directory (scottidler/bump)
**Model:** sonnet
- `ReleaseArgs` and `FinishArgs` each gain an optional `[DIR]` positional; `dispatch_release`/`dispatch_finish` take it, else cwd. The top-level `DIRECTORIES` positional is untouched.
- The bump repo itself is ungated: this phase lands with `bump release` on its main.
- **Success criteria:** from `/tmp`, `bump release -n ~/repos/scottidler/bump` prints the dry-run for that repo (rc=0); `bump finish -n ~/repos/scottidler/bump` likewise; `cargo test` passes with a test for each verb.

#### Phase 10: Not-a-repo gate (fix 4)
**Model:** opus
- New gate in `git-release-guard.sh` as designed; fixtures via `runcwd`.
- **Success criteria:** `runcwd deny /tmp /tmp 'bump finish'` and `runcwd deny /tmp /tmp 'git status'` fail against `git show HEAD~1:HOME/.claude/hooks/git-release-guard.sh` and pass after; `run allow main 'git clone x'`, `run allow main 'git -C "$REPO" status'`, `run allow main 'git --version'`, `runcwd allow /tmp /tmp 'git config --global user.name'`, `runcwd allow /tmp /tmp "bump finish $REPO"` hold; `--self-test` fail=0.

#### Phase 11: Sandbox-off deny (fix 3)
**Model:** opus
- `intent-guard.sh:1714-1726`: `sandbox_off=1` + excluded net verb, `ssh`, or `bump` -> deny; flip `intent-guard-test.sh:675-677,697` from allow to deny.
- `release-driver.md:63` and `rules/git.md:55` stop prescribing "its own Bash call after a separate `cd <repo>`" and prescribe `bump release <repo>` / `bump finish <repo>` (Phase 9), which a subagent can run from any cwd.
- **Success criteria:** `runsb deny` for each of `git push origin main`, `git pull`, `git fetch`, `git ls-remote origin`, `git clone x`, `ssh host ls`, `bump release`, `cd ~/repos/x && git push origin main`; `runsb allow 'ls'`; the three old allow fixtures fail against the new hook; `--self-test` fail=0.

#### Phase 12: Gates E and F (fixes 1, 2)
**Model:** opus
- `gate_verdict <dir>` helper (inner `timeout`, stdout parse, every failure -> `UNKNOWN`-shaped deny); Gate E before Gate D (`git-release-guard.sh:516-579`) with the body-line door; Gate F beside the force-push gate (`:415-436`) with its OWN refspec extraction that keeps the DESTINATION side (Gate B's at `:490` keeps the source, `${gateb_ref%%:*}`, and is wrong for this purpose).
- **Success criteria:** with `runwith`, the seven denies fail against `HEAD~1` and pass after: `deny feat-real BUMP_GATES_PROBE=ungated 'gh pr create --title x --body "Release: none - y"'`; `deny main BUMP_GATES_PROBE=gated 'git push origin main'`; `deny main BUMP_GATES_PROBE=gated 'git push origin feat:main'`; `deny main BUMP_GATES_PROBE=gated 'git push origin HEAD:main'`; `deny main BUMP_GATES_PROBE=gated 'git push'`; `deny main BUMP_GATES_PROBE=unknown:x 'git push origin main'`; `deny feat-real BUMP_GATES_PROBE=unknown:x 'gh pr create --title x --body "Release: none - y"'`. Allows hold: `allow feat-real BUMP_GATES_PROBE=gated 'gh pr create ... "Release: none - y"'`; `allow feat-real BUMP_GATES_PROBE=ungated 'gh pr create ... "Release: none - y\nPR on ungated: ordered by Scott - do it"'`; `allow main BUMP_GATES_PROBE=ungated 'git push origin main'`; `allow feat-real BUMP_GATES_PROBE=gated 'git push origin feat-real'`. `--self-test` fail=0.

#### Phase 13: rails deny text (fix 7)
**Model:** opus
- `excludedDeny` names both stages and the two-call rewrite.
- The header comment at `index.ts:509-520` gains the 2026-10-08 measurement (compound = sandboxed on 2.1.295).
- **Success criteria:** `bun test` case asserting the reason for `git fetch -q origin && git rev-list --count HEAD` contains both stage texts and the words `INSIDE the sandbox`; `excludedDeny('git fetch -q origin 2>&1 | tail -5', EXCLUDED)` is null before and after (regression guard on a head that stays excluded); `rg -c '2026-10-08' HOME/.claude/skills/rails/hooks/index.ts` >= 1.

#### Phase 14: pkill rewrite (fix 10)
**Model:** opus
- Fourth rails rule as designed, `pkill -f` only.
- **Success criteria:** `bun test` cases: `pkill -f "quartz.*4173"` -> `pkill -f "[q]uartz.*4173"`; `pkill -f '[b]ump'` unchanged; `pkill -x foo` unchanged; `pkill foo` unchanged; `pkill -f 'foo|bar'` denied naming `[f]oo|[b]ar`; `pkill -f '.*x'` denied; in a fresh session `pkill -f sleep-marker` exits 1, not 144.

#### Phase 15: clyde `sessions_ls` slim rows (tatari-tv/clyde, gated, PR)
**Model:** sonnet
- Default row drops `first_prompt`, `cwd`, `project_dir`, `transcript_path`; `verbose: true` restores; README + `plugin/` skill updated (`rules/fleet-plugins.md`: CLI, MCP, plugin, README agree before a tag).
- **Success criteria:** `cargo test -p clyde-sessions` passes with a test asserting the default JSON row has none of the four keys (`first-prompt`, `cwd`, `project-dir`, `transcript-path`) and the verbose row has all four; a test asserting a 200-row default response serializes to < 100,000 bytes on a fixture whose `first_prompt` fields are 2,000 chars each; `rg -n first-prompt plugin/ README.md` matches the new text.

#### Phase 16: marquee `marquee_read` cap and the door rewrite (tatari-tv/marquee, gated, PR, minor bump with snapshot)
**Model:** sonnet
- `max_bytes` (default 60,000; 0 = no cap) + `truncated` on both MCP surfaces, UTF-8 boundary; CLI `read` unchanged; plugin skill notes the field.
- `AGENTS.md:206-221` loses the `bump --no-tag -m` door and reads: `bump release -m` on the branch (version commit, push, PR), then `otto snapshot`, commit, push to the same branch, `otto ci` green on the head, merge, `bump finish`. This PR is the first to ship that way and proves it.
- **Success criteria:** a test per surface with a 1 MB multibyte body returns `truncated: true`, valid UTF-8, and a serialized response < 70,000 bytes; `max_bytes: 0` returns the whole body with `truncated: false`; `marquee read` on a fixture is byte-identical before and after; `rg -c 'bump --no-tag' AGENTS.md` prints nothing or 0; the PR itself carried the snapshot as a second commit and merged green.

#### Close
**Model:** sonnet
- Baton rows: H (12, 14) and I (10, 13) marked done-here with the override note; new row for the release gates; doc Status; acceptance re-run against the live setup: installed `bump --version`, `clyde --version`, `marquee --version` show the released tags; the clyde and marquee MCP processes restarted (`clyde mcp` and the marquee server) and `sessions_ls`/`marquee_read` exercised once each; `tatari-skills` pointer-refs PR merged for both pins.

## Acceptance Criteria

- [ ] AC1: `git-release-guard.sh --self-test` and `intent-guard.sh --self-test` both report `fail=0`, and every new deny fixture in Phases 10-12 fails when run against the hook as of the previous commit.
  Observed on main: `pass=289 fail=0` and `pass=599 fail=0`; no gate reads `bump --gates` (`rg -n 'bump --gates' git-release-guard.sh` non-comment hits = 0); no gate checks the work tree (`rg -n 'rev-parse --git-dir' git-release-guard.sh` = 0).
- [ ] AC2: `jq` over `HOME/.claude/settings.json`: `excludedCommands` has none of the heads Phase 0 cleared; zero strings match `/tmp/review-panel`; `security-guidance@claude-plugins-official` is `false`.
  Observed on main: list has `cargo *`, `otto *`, `journalctl *`; 3 strings match; plugin `true`.
- [ ] AC3: always-on steering bytes <= 60,150 and `tools.md`, `rules/cli.md`, `rules/logging.md` are gone.
  Observed on main: 67,903 bytes; all three present.
- [ ] AC4: from `/tmp`, `bump release -n ~/repos/scottidler/bump` acts on that repo.
  Observed on main: cannot run; `dispatch_command` reads `env::current_dir()` (`main.rs:866`) and the verbs take no directory.
- [ ] AC5: rails "would run unsandboxed" deny events in the 14 days after Phase 4 and Phase 13 land number < 60% of the 14 days before, counted as deduplicated `is_error` tool results by event timestamp:
  `fd -e jsonl . ~/.claude/projects -x jq -r --arg a <start> --arg b <end> 'select(.type=="user" and .timestamp>=$a and .timestamp<$b) | .message.content[]? | select(.type=="tool_result" and .is_error==true) | select((.content|tostring)|test("would run unsandboxed because")) | .tool_use_id' | sort -u | wc -l`
  Observed on main: cannot run until the phases land; baseline 534 results / 30 days, 181 sessions (the retro's text-shape count, which this instrument replaces).

## Resolved Decisions

- 2026-10-08, Scott: all 14 fixes ride one doc (option B over "release gates only"), a one-time override of the baton's one-chunk rule. H's items 12 and 14 and I's items 10 and 13 are folded in here; the baton rows say so.
- 2026-10-08, author: fix 7 is a deny-text change, not a strip. rails already passes `| tail`, `| head`, `2>&1`, redirects (`index.ts:530-536,612-621,630,148`); the measured survivors are acting stages.
- 2026-10-08, author: fix 11 is a verification fixture. The rename text shipped in `0907a90` on 2026-09-14; the cited session predates it.
- 2026-10-08, author: `systemctl *` stays excluded (measured: user bus unreachable in-sandbox).
- 2026-10-08, Scott (closes OQ1): "github is always where the gating truth lives", and marquee's exemption goes: he protects its main. Gates E and F key on `bump --gates` alone; no `bump.yml` fact, no org default (Alternatives 2 and 7). Hall 10-07 (b) and (c) and marquee's door (09-29 (a), 09-30 (b)) are superseded.
- 2026-10-08, panel round 1, folded: Gate F gets its own destination-side refspec extraction; `cli.md`/`logging.md` move to `refs/` instead of losing a frontmatter key; Phase 9 adds `[DIR]` to each verb's args (the shared resolver the panel asked for went with Alternative 2); rails `SCRATCH` covers `runs/` only in both path forms; the `git -C * push *` row is dropped (unmatchable by both rails and intent-guard); `pgrep` is out of scope; the pkill rule has a defined subset; both marquee MCP surfaces are capped; the fix-6 measurement is provisional until the Phase 0 marker; the fix-6 argument rests on expired reasons, not hatch count.
- 2026-10-08, Scott (closes OQ2): drop `cargo *`, `otto *`, `journalctl *`, on the condition that the in-sandbox claim is tested; tested the same day with the marker (fix 6). The 09-13 option D literal ("all ten entries stay") is superseded for those three; its reasoning (reverting the five new bare words loses five fixes) is untouched.
- 2026-10-09, Phase 4: `docs/design/2026-09-13-enforcement-core.md:357` (option D, "all ten entries stay") is superseded for `cargo *`, `otto *`, `journalctl *`, removed from `settings.json` `sandbox.excludedCommands`; `systemctl *` and the other entries stay. The `review-panel.md:90-91` restatement the plan names does not exist (those lines scope `/tmp/review-panel`, no list); the list was restated only in `docs/sandbox-filesystem-allowlist.md`, updated.
- 2026-10-08, author, from the marker: the rails header's "any excluded stage exempts the whole compound" is false on 2.1.295; the rails mixed deny stays for the heads that fail sandboxed, with truthful text (fix 7).
- 2026-10-08, panel round 1, demoted: "Phase 0's criterion is only documentation" (recording results is a zero-code spike's deliverable); "B is bypassable by an adversary" (the threat model is the agent's own drift; the committed-tree read closes it either way).

## Alternatives Considered

### Alternative 1 (CHOSEN): Key Gates E and F on `bump --gates` alone
- **Description:** no policy override; the API verdict is the law.
- **Pros:** zero new config; one probe.
- **Cons:** as drafted, it denied the marquee PR Scott wanted and never fired on a marquee push to main; the three marquee hall entries are exactly this disagreement.
- **Why chosen:** Scott, 2026-10-08 (closes OQ1): GitHub is always where the gating truth lives. The con goes away because marquee's main gets protected (Phase 0 row), so the verdict and Scott agree.

### Alternative 2: A `gated:` fact in the repo-root `bump.yml`
- **Description:** `bump --gates` reads a declaration from the committed `origin/<default>` tree before the API probe, through one shared resolver for its three call sites.
- **Pros:** repo-local, versioned, reviewed; covers a repo whose GitHub settings cannot be changed.
- **Cons:** a second signal for one meaning; drifts from GitHub the moment someone changes a ruleset; needs a bump change and a probe of the committed tree.
- **Why not chosen:** Scott, 2026-10-08: GitHub is always where the gating truth lives. The one disagreeing repo gets protected instead.

### Alternative 3: rails splits a compound into sequential calls
- **Description:** rewrite `cd x && cargo test` into two tool calls.
- **Cons:** a PreToolUse hook returns one `updatedInput`, not two calls; impossible at this seam.
- **Why not chosen:** cannot be built.

### Alternative 4: Fix 6 by deleting all of `excludedCommands`
- **Cons:** `git push`, `bump`, `ssh`, `slack`, `systemctl` measurably need the host (keys, agent, user bus, allowlisted hosts).
- **Why not chosen:** measured; four of the heads fail in-sandbox.

### Alternative 5: A prose rule for `pkill -f`
- **Why not chosen:** the month's evidence; prose did not move the compound-command habit either.

### Alternative 6: `git -C * push *` as an excludedCommands entry for subagents
- **Why not chosen:** rails and intent-guard both anchor on `^git push`; an interior glob matches nothing. `bump <verb> <repo>` is the shape.

### Alternative 7: Default by org (tatari-tv gated unless declared, scottidler per GitHub)
- **Description:** the panel's third option; the managed PR policy made mechanical, with Alternative 2 as the declaration.
- **Pros:** matches hall 10-07 (c) and the live tatari-tv commit-on-main deny.
- **Cons:** every ungated tatari-tv repo Scott ships by shipit needs a committed `gated: false`; a policy that lives in a hook and a YAML key instead of the repo's own settings.
- **Why not chosen:** same ruling as Alternative 2. A tatari-tv repo that should take PRs gets a ruleset, and then the API says so.

### Alternative 8: Keep marquee's door and a `bump` pre-push hook for the snapshot
- **Why not chosen:** the snapshot rides the release PR as a second commit; `bump release` on a gated repo stops after opening the PR, so nothing has to run between the version commit and the push.

## Technical Considerations

### Dependencies
- `bump` (scottidler, ungated: shipit) ships Phase 9 before Phase 11 lands, or release-driver has no legal shape.
- Scott protects `tatari-tv/marquee` main (Phase 0 row) before Phase 12 lands, or Gate E denies the marquee PR and Gate F allows a marquee push.
- clyde and marquee phases are PRs on gated fleet repos, `bump release` on the branch, `bump finish` after merge, then `pointer-refs.yaml` in tatari-skills bumps the plugin pins (operator review). marquee's is a minor bump, so `otto snapshot` rides the PR per `marquee/AGENTS.md:206-221`.
- rails changes (Phases 5, 13, 14) are only observable in a session started after they land.

### Performance
- Gate probe: two `gh api` calls per `gh pr create` or `git push ... main` statement, nothing else pays it; no cache, so a main protected an hour ago is seen an hour ago. Inner deadline shorter than the hook's, so a hung probe denies instead of silently allowing.

### Security
- Fix 6 removes heads whose host-side reason expired; each excluded head is also an unsandboxed path, so the list only shrinks.
- Fix 3 closes the sandbox-off bypass the classifier was catching by luck.
- Nothing here widens a read or write allowlist; fix 9 narrows one.

### Testing Strategy
- Shell hooks: fixtures in the `*-test.sh` beside each hook; every new deny has a break-the-code assertion against `HEAD~1`; `shapes.sh` wrapper-mutation sweep on any parser touch.
- rails: `bun test`.
- bump, clyde, marquee: `cargo test`, `otto ci`.
- Live: fresh session after Phases 4, 13, 14 for the rails-visible behavior, with the Phase 0 marker re-run.

### Rollout Plan
- Config repo: 13 commits on main in phase order.
- bump: one `bump release` (minor: two new positionals).
- clyde: one PR, patch. marquee: one PR, minor, with snapshot.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `bump --gates` from a hook reads `UNKNOWN` on private home repos (token chain) | Med | High | Phase 0 measures; if so, Phase 12 picks the token by slug in the hook; `UNKNOWN` stays a loud deny |
| A later Claude Code version exempts compounds again, reopening the hatch for the heads still excluded | Low | Med | the rails mixed deny stays for those heads; Phase 0's marker is the re-check |
| Dropping `cargo *` breaks a network path (cold fetch, `cargo install`) | Low | Med | Phase 0 cold-fetch row; add the missing host or keep the head |
| Fix 3 strands release-driver before Phase 9 ships | Med | High | ship order forced: 9 before 11 |
| `~/.cache/review-panel/runs` fills | Low | Low | Step 0 prune, 14 days |
| Moving `taste.md` sections hides a rule an implementer needed | Low | Med | parked non-goal; implementation audit checks |
| marquee gets protected but a second repo turns up in the same state later | Low | Med | same answer: protect it; the door line in Gate E covers the day between |

## Open Questions

- none. OQ1 and OQ2 closed by Scott 2026-10-08; OQ3's measurements are Phase 0 rows with their outcomes mapped.

## References

- `docs/design/2026-09-13-setup-audit-program.md` (baton)
- `docs/design/2026-09-13-enforcement-core.md:357` (excludedCommands ruling)
- `docs/design/2026-09-13-guard-precision.md`, `docs/design/2026-09-15-intent-guards.md` (hook phasing and test precedent)
- `~/HALL-OF-SHAME.md:484-540, 1457-2027`
- `HOME/repos/.claude/refs/sccache-sandbox.md:52`
- `/tmp/review-panel/GZsuYMOh/synthesis.md` (panel round 1)
- Retro instrument: the transcript scan over `~/.claude/projects/*/*.jsonl` counting `is_error` tool results by text shape (session d17fecb6, 2026-10-08)
