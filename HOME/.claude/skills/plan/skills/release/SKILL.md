---
name: release
description: 'Ship a release, routed by `bump --gates`. Ungated repos release inline with `bump release`; gated repos hand the arc to the plan:release-driver agent, ENTRY release from a feature branch or ENTRY finish once the PR merged. Use when the user says "ship it", "shipit", "release this", "push this out", "cut a release and install", "bump", "bump the version", "bump version", "cut a tag", "create a tag", "tag a release", "tag a new version", "release", or asks to increment or ship a new version, even without naming Rust or saying "bump"; prefer firing over asking. Also fires on the post-merge arc: "the PR merged, finish the bump", "finish the release", "tag it now that it''s merged", "it merged, ship it".'
argument-hint: "[-m|--minor|-M|--major] [repo-path]"
---

# Plan Release

One entry for a release. `bump --gates` reads GitHub (classic protection AND
repo/org rulesets) and its verdict picks the path. Never infer the gates
yourself, and never let the path drift from the verdict: protected goes to
`plan:release-driver`, not protected runs inline (`~/repos/.claude/refs/release-rulings.md`,
2026-10-02 (a)).

Both verbs that cut a release are bare `bump` subcommands, `bump release` and
`bump finish`. They own the version line, the CI wait, the tag and the push, so
every `~/HALL-OF-SHAME.md` failure at a tag/push decision sits in the binary, not
in a sequence you have to remember.

## Step 0: target and level

- **REPO**: the repo-path argument, else the current directory. Resolve it to an
  absolute path with `git -C <path> rev-parse --show-toplevel`. Not a git repo:
  stop and say so.
- **LEVEL**: patch by default; `-m` / `--minor` is minor; `-M` / `--major` is
  major, and major is confirmed with the user before anything runs.

Nothing in this step writes anything.

## Step 1: read the gate verdict

Run it bare, as its own Bash call, with the absolute repo path:

```bash
bump --gates <REPO>
```

`bump --gates` exits 0 on every verdict, including `UNKNOWN`
(`report_gates` in `scottidler/bump` `src/main.rs`). **The exit code is not the
signal. Parse the text.** Find the one line that starts with `Gates:`:

| `Gates:` line | Verdict |
|---|---|
| `Gates:  none (ungated)` | ungated: Branch 4 check, then Branch 1 |
| `Gates:  <rules> (gated)` (e.g. `classic_protection, workflows (gated)`) | gated: Branch 2 or 3 |
| `Gates:  UNKNOWN (could not verify: <reason>)` | Branch 5 |
| no `Gates:` line, more than one, a non-zero exit, or any other text | Branch 5 |

Match the whole line, not a substring: `ungated` appearing elsewhere in the
output is not a verdict. Until Step 1 has produced a parsed ungated or gated
verdict, nothing is committed, branched, pushed, or dispatched.

## Branch 5: verdict UNKNOWN or unparseable

Stop. Do not commit, branch, push, run `bump release` / `bump finish`, or
dispatch any agent. Report:

- the repo path
- the raw `bump --gates` output, verbatim, in a code block
- which row of the table it hit (`UNKNOWN`, or what made it unparseable)
- the fix it names, when it names one (offline or unauthenticated: re-run once
  online; no GitHub remote: there is no gate to read and nowhere to release to)

Then end the turn. A missing verdict is never treated as ungated: `bump release`
itself fails closed on an unknown gate, and so does this skill.

## Branch 4: ungated verdict on a repo Scott treats as protected

Check this on every ungated verdict, before Branch 1. It applies when any of
these hold:

- Scott said, in this session, that this change ships as a PR or "on a branch"
  (2026-10-07 (a): if he was told "on a branch", it ships as a PR, and changing
  the path needs his OK first)
- Scott has called this repo protected or PR-only in this session
- the repo's own `CLAUDE.md` or `AGENTS.md` says changes land by PR

Then stop and ask (2026-10-07 (d): when the check says unprotected on a repo
Scott treats as protected, stop and ask; do not ship). Nothing is committed or
pushed before the answer. Ask in the shape `rules/interaction.md` gives: the
problem (the verdict line verbatim, and the signal that says protected), the
decision, A: ship ungated inline / B: ship as a PR through the gated path, and a
`Rec:`.

None of them hold: go to Branch 1.

## Branch 1: ungated, inline, no agent

The main session runs it; no agent is dispatched.

1. **Pre-flight.** `git -C <REPO> status --porcelain` and
   `git -C <REPO> log --oneline @{u}..HEAD`. No changes and nothing unpushed:
   say so and stop. Detached HEAD: warn and stop.
2. **Get the work onto the default branch as a commit.** Stage the real changed
   files by explicit path, never `git add -A` / `git add .` (that is how scratch
   assets got swept into release commits). Never stage anything secret-looking
   (`.env`, keys, tokens); flag it instead. Commit message: concise, from the diff.
   - **On the default branch, origin not `tatari-tv`:** commit there.
   - **On the default branch, `tatari-tv` origin:** the commit-on-main hook fires
     even on an ungated repo (2026-10-03 (c)). Commit on a temp branch
     (`git switch -c <slug>`, carrying the working tree), then `git switch <default>`,
     `git merge --ff-only <slug>`, `git branch -d <slug>`.
   - **Work on a feature branch:** commit there, then fast-forward the default
     branch to it locally (`git switch <default>`, `git merge --ff-only <branch>`)
     (2026-10-05 (d)). An ff refusal means the branches diverged: stop and report.
   - **Tree already clean, unpushed commits on the default branch:** no new commit.
3. **Release.** The `<repo>` positional on `bump release` ships only once
   `bump release --help` shows `[DIR]` (scottidler/bump commit eba0468). Until
   then, `cd <REPO>` in its own Bash call, confirm with `pwd`, then run the verb
   bare, with `run_in_background` (the CI wait runs up to `--ci-timeout`, default
   1800s, past the 600s foreground cap):
   ```bash
   bump release [-m|-M] [--install "<cmd>"|--no-install]
   ```
   No `&&`, no env prefix, no wrapper, no `dangerouslyDisableSandbox`: a bare
   `bump ...` matches the `Bash(bump:*)` allow rule and already runs unsandboxed.
   INSTALL comes from the repo's `CLAUDE.md` (root, then `.claude/CLAUDE.md`:
   Quick Reference, Install, Build & Install, including any daemon restart);
   else `cargo install --path .` for a Rust crate; else `--no-install`.
4. **Wait for the completion notification.** Do not poll. Read the result:
   - `Released vX.Y.Z on <default>`: shipped. Go to step 5.
   - A refusal: do the one exact command it names (see Refusals), then re-run.
     A re-run after red CI reuses the pending version; it never bumps past it.
5. **Prove the new version is live.** Green CI and a tag are not done.
   - **CLI:** `command -v <binary>` (catches an older copy earlier on PATH), then
     `<binary> --version`, which must report the vX.Y.Z `bump` cut. Then run the
     acceptance commands for the change and report each exit status with output.
   - **Deployed service:** `sdv probe <deploy-url>` until it reports vX.Y.Z,
     as a `run_in_background` terminating `until` loop that keeps each probe's
     output (`| tee -a`), then paste the final probe. Still old when you stop
     waiting: report NOT LIVE with the last output.
   - Then fire `/cli-shakedown` yourself if the release wants one.

## Branch 2: gated, work on a feature branch

Dispatch the agent; do not run the release inline.

- **Uncommitted work on the default branch:** `git switch -c <slug>` first (the
  working tree comes with it; branch names are lowercase, hyphenated, no slash),
  then dispatch from that branch.
- **Local commits on the default branch that are not on origin:** stop and
  report. That is the stranded case: `bump release` prints the literal rescue
  commands and never auto-rescues, and neither does this skill.

Dispatch `subagent_type: "plan:release-driver"` with:

- **REPO**: the absolute repo path
- **ENTRY**: `release`
- **LEVEL**: patch / minor / major
- **MESSAGE**: a concise commit message derived from the diff (you have the
  working context; pass it so the agent does not re-infer it)
- **INSTALL**: per Branch 1 step 3
- **KIND**: `cli` or `service`
- **DEPLOY-URL** (service): what `sdv probe` hits until the new version is live
- **ACCEPTANCE** (cli): the commands that exercise the installed binary

The agent commits the real files, runs `bump release` (which commits the
version, pushes the branch and opens the PR with `Release: rides this PR
(vX.Y.Z)`), watches the PR to merge, runs `bump finish`, verifies the tag is on
`origin/<default>`, installs, and proves the version live. Relay its report. It
returns "installed at vX.Y.Z, shakedown not run" on purpose (its tools are
`Bash, Read, Grep, Glob`, no `Skill`): fire `/cli-shakedown` yourself if the
release wants one.

## Branch 3: gated, the PR already merged

Not a fresh release and never a hand-rolled tag. Applies when the user says it
merged, or `gh pr view <branch> --json state` reads `MERGED`. Dispatch
`subagent_type: "plan:release-driver"` with **ENTRY** `finish`, **MERGED-PR**
(the merged PR url, required), REPO, INSTALL, KIND, and DEPLOY-URL or ACCEPTANCE.
It runs `bump finish`, which tags the merged tip when the bump rode the PR and
refuses when it did not. On that refusal: STOP and report. The default is to fold
the bump into the next feature PR.

## Refusals: read them, do what they name

Every `bump` refusal names its one exact next command.

- **Bump-only branch** (diff empty or version lines only): never create one. The
  bump belongs INSIDE the feature PR.
- **Standalone door**: if Scott already ordered a version-only release in this
  session, re-run with `bump release --standalone "<his exact words>"`; the words
  are quoted into the PR. Otherwise STOP and report. Never invent the order, never
  re-ask one he gave.
- **Branch name not its own slug**: run the `git branch -m <slug>` it prints.
- **Behind / diverged**: run the `git pull --ff-only` or `git pull --rebase` it
  prints, then re-run.
- **CI red, truncated, or never registered**: no tag exists. Fix and re-run; a
  repo whose workflows never run on push declares `ci: none` in a committed
  `bump.yml`. Never reach for `--no-ci-gate`; that flag is for Scott at a terminal.

## Rules that never bend

- **Never** tag a branch, run a tag-creating `bump` off the default branch, or
  create, move, or delete a tag by hand.
- **Never** `git push --tags` / `--follow-tags`, and never push by hand on an
  ungated repo: `bump release` is the push.
- **Never** hand-edit a `version =` line: `bump` owns it.
- **Never** create a bump-only release branch.
- **Never** wrap, chain, or env-prefix the two verbs.
- **Push rejected after a tag exists locally?** STOP: do not push the tag, do not
  retry variations, do not change repo settings. Report the exact state (the
  okta-auth-rs orphan vector).
- **Install fails:** report it, and do not roll back the push: the code shipped.

## `bump` reference

```bash
bump --gates <REPO>   # the verdict this skill routes on; exit 0 on every verdict
bump release [-m|-M] [-n] [--install "<cmd>"|--no-install] [--standalone "<words>"] [--ci-timeout SECS]
bump finish  [-n] [--install "<cmd>"|--no-install] [--ci-timeout SECS]
```

For Rust projects on `/rust-cli-coder` conventions, the version `bump` sets is
picked up by `build.rs` and exposed via `GIT_DESCRIBE` for clap's `--version`.
