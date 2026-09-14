# Design Document: Guard Precision (dead-hook preflight, shared parser, the git gaps)

**Author:** Scott Idler
**Date:** 2026-09-13
**Status:** Building (Phase 0 ran 2026-09-14; its evidence is in `2026-09-13-guard-precision-phase0/evidence.md` and its plan changes are marked `Phase 0 outcome` inline below)
**Review Passes Completed:** 5/5 author passes; review panel 3 of 3 rounds
**Program:** chunk B of `docs/design/2026-09-13-setup-audit-program.md` (audit item 5)

## Summary

Seven fixes to the nine PreToolUse hooks that already exist in this repo. The hooks work; their parsers do not. They match prose inside heredocs, deny commands no rule forbids, miss three git operations the rules do forbid, and can sit registered in `settings.json` for days without a file on disk. This chunk gives every bash guard one shared, tested command parser, closes the measured gaps in `git-release-guard.sh`, turns the `git -C` deny into a silent rewrite, adds a branch-name guard, and makes a dead hook impossible to merge and visible at session start. No new layer: every change lands in the PreToolUse shell hooks that already exist.

## Problem Statement

### Background

- The 2026-09-12 audit (14 lenses, every session Jun 1 to Sep 12) put this at item 5: the enforcement layer that already exists is imprecise. Items 1 to 3 (chunk A, `docs/design/2026-09-13-enforcement-core.md`) build new hooks. This chunk fixes the ones already live.
- All nine hooks are PreToolUse on Bash plus two on an MCP `create_pr`, one on `AskUserQuestion`, two on SessionStart. Four of the bash guards split a command into statements with the same `sed -E 's/&&/\n/g; ...'` line; only one of the four strips heredoc bodies first.
- Sources: ranked report item 5 https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/ ; raw findings https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-audit-findings-2026-09-12/ (lenses `hooks-sandbox` F1 to F10, `tool-errors` F2/F8/F10/F11, `config-audit` fix list 1/2/5, `incidents` proposals 2/5/12).

### Problem

Seven measured defects. Every one reproduced against `main` on 2026-09-13; four of them reproduced by firing on this session's own probe commands.

**1. A registered hook can have no file, and the one hook that warns cannot be heard.** Seven hooks ran as `/bin/sh: 1: /home/saidler/.claude/hooks/<x>: not found` no-ops for windows of one minute to seven days: `manifest-scope-guard.sh` 831 fires on 2026-09-08, `block-question-picker.sh` inert 07-29 to 08-05 while 13 `AskUserQuestion` calls went through unblocked. Cause: `manifest.yml:1-7` links `HOME/.claude/{skills,agents,output-styles}` as directories but every hook individually, so a settings edit is instant and a new hook file is not. Nothing verifies the two agree.

The same item has a second half. `ssh-agent-check.sh:10` warns with a bare `echo` and `exit 0`. The 2.1.270 binary documents a SessionStart hook's plain stdout as shown in transcript mode (ctrl+o), NOT as model context; the context field is `hookSpecificOutput.additionalContext`. That is why the audit found zero WARN lines in any transcript: the warning has never reached a model in the first place. Any preflight that warns the same way would be equally inaudible, which is what spike 0a exists to settle before Phase 7 is written.

**Phase 0 outcome (0a, 2026-09-14): the causal claim above is withdrawn.** In an interactive session BOTH channels reach the model: plain stdout arrives as a `hook_success` attachment rendered `SessionStart:startup hook success: <text>`, and `additionalContext` as a `hook_additional_context` attachment rendered `SessionStart hook additional context: <text>`; a nested session quoted both probe strings verbatim. The zero-WARN finding has a plainer cause: in the 9 transcripts under this project that carry an `ssh-agent-check.sh` attachment, its recorded stdout is empty, because the key was readable and an agent key was loaded. The condition never tripped. Separately, SessionStart does not fire at all under `claude -p`, from `--settings` or from a project settings file, with matcher `*`, empty, or `startup`. Phase 7 emits `additionalContext`.

**2a. A quoted `<<EOF` hides every following command from every gate.** `strip_heredocs` at `git-release-guard.sh:342-377` is not quote-aware: its opener regex matches `<<WORD` anywhere on a line, including inside a string. Verified 2026-09-13 by piping two lines through the function as it exists today:

```
input:   echo "<<EOF"          output:  echo "<<EOF"
         git push --tags
```

The second line was consumed as heredoc body and never reached `check_stmt`. Confirmed end to end against the live hook with a destructive command rather than a flag: on a 17-entry dirty tree, `git reset --hard` alone returns DENY, while `echo "<<EOF"` on one line followed by `git reset --hard` on the next returns ALLOW. This is a deny BYPASS, not a false positive, and it is live in the one guard that carries the irreversible gates. It is also why the Phase 1 plan says the function is lifted AND made quote-aware rather than lifted verbatim.

**2b. The bash guards match prose.** `manifest-scope-guard.sh:21-24` and `branch-pr-title-guard.sh:71` split on `&& || ; |` and newlines with no heredoc strip, so every physical line of a heredoc body is handed to the matcher as a statement. `secret-echo-guard.sh:34` uses `_PAT` as a secret-name token, which matches `_PATH` and `_PATTERN`. `git-release-guard.sh:176` matches `--tags` without masking `$(...)`.
  - manifest-scope-guard: 9 of 9 fires were prose, a `grep` pattern, or a heredoc. Zero true positives.
  - secret-echo-guard: 72 denials, 44 true; 13 were `_PATH` vars, 5 were prose in heredocs, 8 were presence checks that print nothing.
  - git-release-guard `--tags` gate: 38 of 53 blocks had no `git push ... --tags` statement at all.

**3. `git -C <cwd>` is denied where nothing is wrong.** 249 denials, 235 with the `-C` target equal to the session cwd, zero cross-repo saves, every single one immediately reissued as the same command without the flag. 67% came from subagents, whose own system text tells them to use absolute paths. The hook costs one round trip per fire and buys nothing. Scott asked for this exact comparison on 2026-09-03 (session `ae59ec0b`): "go research if updatedInput actually works also I have a similar pertool hook that prevents git -C usage. compare and contrast".

**4. The PR-title guard demands the impossible.** `branch-pr-title-guard.sh:32-37` slugifies the title and `:46` compares it to the raw branch. A branch containing `/` or `.` can never be matched, because slugify collapses both to `-`. 24 of 43 denials were that shape, two sessions burned four consecutive retries, and five branches were renamed after the block, which `general.md` forbids once a PR is open. The guard also reads `git branch --show-current` from the session cwd, so a `cd`-into-another-worktree command was evaluated against the wrong repo three times. Branch CREATION is guarded only for release-shaped names: Gate C at `git-release-guard.sh:189` matches `checkout -b`, `switch -c|--create` and `branch <name>`, but only when the name STARTS with `bump` or `release`. Nothing rejects a slash, so twelve slashed branches were created Jun 26 to Sep 12; the 2026-09-12 rule commit `af61e71` is prose written to compensate for a hook that was never updated.

**5. `git-release-guard.sh` has three gaps and one over-reach.**
  - Over-reach: `:329` denies `git checkout -- <path>` and `git restore <path>` whenever the tree is dirty, with no distinction between a named path and the whole tree. 66 denials were path-scoped single-file reverts; the model dodged 12 of them with `git show HEAD:f > f`, which destroys the same bytes and is unguarded.
  - Gap: there is no `git tag` CREATION matcher at all, on any branch. `:173` covers only `-d|--delete`, `:176` push `--tags`, `:179-180` remote tag deletion. So `git tag -f` (a tag move, three of them unblocked on 2026-07-11) and off-main annotated tag creation (17 of them, which `git.md` forbids absolutely) both pass. Both verified allow on `main` 2026-09-13.
  - Gap: Gate C at `:189` anchors `(bump|release)` at the START of the new branch name, so `chore/bump-0.9.0` slips it. Five HALL-OF-SHAME recurrences after the 2026-07-10 hardening, one of them a commit straight to a gated `main`.
  - Bug: the destructive-op gate at `:329` tests `$porcelain`, captured once at `:98` against the SESSION cwd, while the bump gates test `$bump_porcelain`, captured at `:115` against the `cd`-resolved worktree. A `cd <other worktree> && git checkout -- <file>` is therefore judged against the wrong tree's dirtiness, in either direction.
  - Friction: `--body-file` paths containing `$TMPDIR` are refused by `:300` because the hook reads the raw command text. `$TMPDIR` is the harness-mandated temp dir.

**6. Three files describe a release flow nothing runs.** `rules/git.md:73`, `agents/release-driver.md:36` and `git-release-guard.sh:19` all say the ungated flow tags local HEAD first. `~/.claude/bin/release:11-14` and `bump/SKILL.md:19-30` do the opposite: version commit first, push main, wait for green CI on that SHA, then `bump --tag-only`. The reason is in the script's own comment: a tag created before CI has run can only be repaired by a second tag, so one release burns two version numbers (otto v2.0.2/v2.0.3, v2.0.4/v2.0.5). Three sources of truth for the one irreversible operation, and the two stale ones describe the behavior that caused the incident.

**7. Four always-on rules leak their own frontmatter.** `cli.md`, `general.md`, `interaction.md` and `taste.md` open with a three-line `<!-- WORKAROUND ... issues/26868 -->` HTML comment ABOVE the `---` block, so the frontmatter is not parsed and the literal `---` / `alwaysApply: true` / `---` renders into the system prompt on every turn. `git.md` has no comment and is parsed correctly. The workaround is also inert: the issue it cites is about `paths:` arrays, which `comments.md`, `js-ts.md` and `terraform.md` now use successfully.

### Goals

- One shared, tested command parser under every bash guard: heredoc bodies, quoted strings and comments are data, and a match must be in command position.
- Close the three `git-release-guard.sh` gaps that let an irreversible operation through, and drop the one over-reach that taught the model a worse workaround.
- Replace a deny that never saved anything (`git -C <cwd>`) with a rewrite that costs nothing.
- Make the branch-name rule mechanical at creation time, and make the PR-title denial always satisfiable.
- Make a dead hook impossible to merge and visible at session start.
- One source of truth for the release flow.

### Non-Goals

- The `pr-open` helper that auto-injects the `Release:` line (82 denials). Chunk E owns it. This chunk only documents the two accepted forms in `rules/pr.md`.
- Porting `rewrite-cd-read.py` or the search rules (`find` to `fd`, `grep -r` to `rg`) onto rails. Chunk I.
- New intent guards (commit, Slack, vault ingest, `gh api` writes, `ln`, public repo). Chunk D.
- Stripping em-dashes repo-wide. This chunk strips them only from the files it touches and extends the `.otto.yml` lint list, same rule chunk A set.
- `voice.md` has no frontmatter at all (`config-audit.md:98`). It is always-on by default, so the rendered prompt is already correct. Parked with a revisit condition: chunk H owns the always-on prefix and can normalize all twelve files at once.

## Proposed Solution

### Overview

- One new sourced library, `HOME/.claude/hooks/lib.sh`, carrying the parser primitives. `git-release-guard.sh:342-377` already contains a heredoc stripper that handles `<<-`, quoted delimiters, `<<<` herestrings and multiple openers per line; its structure is the starting point, but it is NOT copied as-is, because it is not quote-aware and that gap is a live deny bypass (problem 2a). It is joined by four more maskers, a quote-aware statement splitter, a command-word test, an in-awk flag-value extractor, and the `cd <dir>` resolvers from `:108-113`. Harvest the proven in-house structure, fix the hole in it, then share it.
- Six guards source it: `manifest-scope-guard.sh`, `secret-echo-guard.sh`, `branch-pr-title-guard.sh`, `git-release-guard.sh`, plus the new `branch-name-guard.sh` and the converted `git-no-dash-c.sh`. **Phase 0 outcome (0e):** five, not six. `git-no-dash-c.sh` is deleted rather than converted; its job moves into `rewrite-cd-read.py`, which is Python and does not source `lib.sh`.
- One new guard, `branch-name-guard.sh`, denying `/`, uppercase and `_` in a branch being CREATED.
- One new SessionStart hook, `hooks-preflight.sh`, plus a CI check that refuses a `settings.json` naming a hook not in the repo.
- `git-no-dash-c.sh` converted in place from a deny to an `updatedInput` rewrite. It stays a shell hook and keeps its name. **Phase 0 outcome (0e):** superseded. Two `updatedInput` hooks on one Bash call do not compose (each is handed the original `tool_input`, one edit survives), so the `-C` strip folds into `rewrite-cd-read.py` and `git-no-dash-c.sh` is deleted and unregistered. This is the fallback the Rollout Plan pre-committed to.
- Text fixes: three stale release-flow descriptions, four leaked frontmatter blocks, the `Release:` line documented in `rules/pr.md`.

### Architecture

```
Bash tool call
  -> settings PreToolUse (matcher "Bash")
       secret-echo-guard.sh   \
       manifest-scope-guard.sh > all source hooks/lib.sh
       branch-pr-title-guard.sh|
       git-release-guard.sh   /
       branch-name-guard.sh  (new, also sources lib.sh)
       rewrite-cd-read.py    (existing updatedInput hook; Phase 0 outcome: gains the git -C strip,
                              git-no-dash-c.sh is deleted)
session start
  -> settings SessionStart -> hooks-preflight.sh -> additionalContext | stderr WARN
otto ci
  -> lint: em-dash list, rules frontmatter starts at line 1
  -> test: every hooks/*-test.sh, bin/hooks-resolve (plus chunk A's bun test, if A landed first)
```

### Data Model

`hooks/lib.sh` is one file of shell functions wrapping a single embedded `awk` program, the same shape `git-release-guard.sh` already uses for its heredoc stripper. No `python3`: four more guards paying a Python startup on every Bash tool call is a cost the repo does not need, and `awk` is what the working code already uses.

The contract has one rule that drives everything else: **a guard matches on a MASKED copy and extracts values from the ORIGINAL, and the slice never leaves `awk`.** Masking replaces selected spans with a run of `\x01` of the same byte length, so offsets are identical in both strings. Bash is never handed an offset: `grep -b -o` reports BYTE offsets while `${var:off:len}` counts CHARACTERS, and the two diverge the moment a command carries a multibyte character. Verified 2026-09-13: a string whose first character is a 4-byte emoji reports the following `b` at byte 5, and `${V:5:1}` on that string returns empty. So the masking, the match and the slice all happen inside one `awk` program, and `lib.sh` exposes `flag_value <long> <short>` which returns the ORIGINAL text of a flag's value directly. No guard ever computes an offset.

That works because awk's `index` and `substr` share one index space, whatever that space is. Verified 2026-09-13 on the system awk (mawk 1.3.4) against a string whose first character is a 4-byte emoji: `index` reported 14 and `substr($0, i+1, 11)` returned `hello world` correctly, under both a UTF-8 locale and `LC_ALL=C`. The awk program pins `LC_ALL=C` anyway, so the behavior does not depend on which awk or which locale a machine has. The bash-side failure is not that offsets are hard, it is that `grep` and `${var:off:len}` disagree about what an offset means; keeping both operations in one tool removes the disagreement rather than working around it.

**There is no single `mask`.** Masking the wrong span class is how a false-positive fix becomes a deny bypass, so the maskers are separate and each gate names the ones it uses:

| masker | neutralizes | exists because |
|---|---|---|
| `mask_heredoc` | heredoc bodies and terminators, quote-aware | prose in a `cat <<EOF` body is not a command |
| (no masker) | subshell bodies, backticks, `-c` arguments | NOT maskable: these execute. `stmts` yields them as nested statements instead, see the rule below |
| `mask_squote` | single-quoted spans that are NOT a `-c` argument, and a backslash-escaped `$` | bash performs no expansion in `'...'`, but `bash -c '...'` hands the span to a child shell that does |
| `mask_dquote` | double-quoted span contents | the word is data, not a command word |
| `mask_comment` | an unquoted `#` that starts a word | a comment is not a command |
| `mask_optarg` | the VALUE token of a message-carrying flag: `-m`, `--message`, `-F`, `--file`, `--reuse-message`, `--reedit-message` | `git tag -a v1 -m "added --force"` is a tag annotation that mentions a flag, not a command that uses one. Long forms only for the reuse flags: `-C` is deliberately ABSENT, because git overloads it as `git -C <dir>`, `git commit -C <commit>` and `git switch -C <branch>`, and masking its value would hide a branch name from `branch-name-guard.sh` and the directory from `git-no-dash-c.sh` |


**The rule every masker obeys, and the one that took three rounds to find: a masker may only erase a span the shell will never execute.** Heredoc bodies redirected to a file, single-quoted data that stays in this shell, and comments are inert, so erasing them is safe. Subshell bodies, backtick bodies, and the argument of `bash -c` / `sh -c` / `zsh -c` are NOT inert: they are nested statements, and the shell runs them. Erasing those hides commands from the gates.

That is why `stmts` yields nested statements rather than leaving them to a masker. For each `$( ... )`, backtick span, or `-c` argument it finds, it emits the body as its own statement AND neutralizes that span in the enclosing statement. Both halves are needed:

| command | outer statement sees | nested statement | verdict |
|---|---|---|---|
| `git push origin "$(git describe --tags)"` | the subshell span neutralized, so no `--tags` | `git describe --tags` (verb `describe`, not `push`) | allow, which is the measured false positive fixed |
| `echo "$(git push origin --tags)"` | `echo` with the span neutralized | `git push origin --tags` (verb `push`) | DENY, and the deny comes from the nested statement |
| `bash -c 'echo $SOME_TOKEN'` | `bash -c` with the span neutralized | `echo $SOME_TOKEN` | DENY, the secret guard sees the nested statement |

Both of the last two are live DENIES on `main` today, verified 2026-09-13 by feeding the hooks their JSON. An earlier draft of this design masked subshell bodies and single-quoted spans outright, which would have turned both into ALLOWS while the shell still executed them. That is the same defect as the round-1 double-quote finding, in two more span classes, and it is the reason the rule above is stated as a rule instead of a list of cases.

The rule that decides which to use: **option detection never masks quotes.** In shell, `git push origin "--tags"` passes `--tags` to git exactly as the bare form does, so a gate that masked double quotes would allow the bulk tag push it exists to stop. Both reviewers caught this independently and they are right. What actually removes the measured false positives for the option gates is not masking but the command-word anchor, which is a different tool:

| measured false positive | what fixes it |
|---|---|
| `echo "=== manifest refs ==="` and heredoc prose, against `manifest-scope-guard.sh` | `mask_heredoc` and `mask_dquote` (the same heredoc against `git-release-guard.sh` already allows today: it grew `strip_heredocs` on 2026-09-01, verified 2026-09-13) |
| `grep -n "git push origin --tags\|git push.*--tags" <file>` | `cmdword_is git` (the command word is `grep`) |
| `git-release-guard.sh --help` | `cmdword_is git` (the command word is the hook) |
| `git push origin "$(git describe --tags --abbrev=0)"` | `stmts` yields the subshell as a nested statement whose verb is `describe` |

All four classes fall to `mask_heredoc` + nested-statement yielding + `cmdword_is`, with double quotes left intact, so `git push origin "--tags"` still denies.

Leaving quotes intact does open one hole in the other direction, which round 2 caught: `git tag -a v1 -m "added --force"` would trip the new tag-force gate on a word inside a commit-style message. `mask_optarg` is the answer, and it is the right shape rather than a patch, because it encodes the actual distinction. A flag in flag position is an option; the same text sitting in the VALUE of `-m` is prose that git will never parse as an option. Masking by quote character cannot tell those apart, since both `git push origin "--tags"` (a real option) and `git tag -m "--force"` (prose) are double-quoted. Masking by argument role can. Known limit, stated rather than papered over: a subshell whose OUTPUT is a flag, `git push origin $(echo "--tags")`, is invisible to any static matcher, this one included. Evaluating it would mean running it.

Functions:

- `mask_heredoc` (stdin to stdout): the existing `git-release-guard.sh:342-377` logic, kept for its `<<-`, quoted-delimiter, `<<<` and multiple-opener-per-line handling, PLUS the quote awareness it lacks today (problem 2a). Runs first, because it is the only line-level pass.
- `mask_heredoc`, `mask_squote`, `mask_dquote`, `mask_comment`, `mask_optarg` (stdin to stdout, composable): the offset-preserving maskers in the table above. `mask_heredoc` replaces `git-release-guard.sh:342-377` and is quote-aware, which that function is not (see problem 2a).
- `flag_value <long> <short>` (stdin, two arguments): finds the flag on a masked copy and returns the ORIGINAL text of its value, handling `--flag x`, `--flag=x`, and single- or double-quoted values. It ALWAYS returns the raw text, including a value holding an unexpanded `$`.

  What to do with an unexpandable value is the CALLER's decision, not the library's, and the two callers need opposite things:
  - `branch-pr-title-guard.sh` treats an unexpandable `--title` as unknowable and passes through, so `gh pr create --title $(gen-title)` is not denied for slugifying to `-gen-title-`.
  - `git-release-guard.sh` needs the raw `--body-file` text precisely BECAUSE it contains `$TMPDIR`, so it can expand the four known spellings and read the file. A library that returned empty here would hand Gate D an empty path, Gate D would find no `Release:` line, and the command would be DENIED. That is the exact `$TMPDIR` friction this chunk is fixing, reintroduced through a fail-open that fails closed one layer up. Round 2 caught this; it is the reason the rule lives in the callers.
- `stmts` (stdin to stdout, NUL-delimited): splits into statements on `&& || ; | &` and newlines, computing separator positions on a quote-aware pass and emitting the ORIGINAL slices. It also yields NESTED statements: the body of every `$( ... )`, backtick span, and `bash -c` / `sh -c` / `zsh -c` argument is emitted as its own statement, and that span is neutralized in the enclosing one. See the rule below for why this is `stmts`'s job and not a masker's. This is a behavior change from today's `sed` splitter, and a deliberate one: a `;` or `|` inside a quoted argument currently splits a statement in two, which is its own false-positive source.
- `cmdword_is <word>` (argument plus stdin, exit status): true when the masked statement's command word is `<word>`, allowing leading env assignments, `command|builtin|exec|sudo|env` prefixes, and a path prefix. This is `block-draft-pr.sh:42`'s `cmdword_create` regex (the canonical copy, with the reasoning in its comment at `:38-41`; `branch-pr-title-guard.sh:72` carries a duplicate) and `git-release-guard.sh:207`'s bump anchor, generalized to one place.
- `cd_target` (stdin to stdout): the LAST `cd <dir>` in the chain, quotes stripped, empty when none. Lifted from `git-release-guard.sh:108-113`.
- `cd_at <n>` (stdin, statement index): the `cd` in effect at statement `n`, meaning the last `cd` that appears BEFORE it. New, and the reason is below.

The ordering note, because it is a trap this design walked into once. `cd_target` at `git-release-guard.sh:108-113` takes the LAST `cd` in the whole command, wherever it sits. That is correct for the bump gates: `cd <main worktree> && bump` puts the `cd` first, and the gate cares about where `bump` lands. It is WRONG for the destructive-op gate, because `git checkout -- f && cd /somewhere-clean` would resolve to the clean directory and allow a revert that discards work in the dirty one. So the destructive gate uses `cd_at <n>`, the `cd` in effect at that statement, which is well defined because `stmts` already yields statements in order. The bump gates keep `cd_target` and their existing behavior. This is the one place where "which worktree" has two different right answers in one file, and conflating them is how a deny quietly becomes an allow.

`stmts` emits NUL-delimited records, which needs `read -r -d ''`, which is a bashism. `manifest-scope-guard.sh:1` is `#!/bin/sh` today and becomes `#!/bin/bash` in Phase 2. Every other guard is already bash. NUL is the right delimiter because a statement can legitimately contain a newline.

Per-gate masker sets, stated once so no guard has to re-derive them:

| gate | maskers | why |
|---|---|---|
| option gates (`--tags`, `--force`, tag flags) | heredoc, comment, optarg, plus `cmdword_is git`, applied to EVERY statement `stmts` yields including nested ones | a quoted flag is a real flag, a flag inside a `-m` value is prose, and a flag inside a subshell is a real flag of the INNER command |
| bare-word gates (`manifest`) | heredoc, subshell, squote, dquote, comment, plus `cmdword_is` | the word is only a command in command position |
| value extraction (`--title`, `--body-file`) | heredoc, comment, via `flag_value` | the value IS the quoted text |
| `secret-echo-guard.sh` | heredoc, comment, squote (and escaped `$`), NOT dquote, applied to every statement including nested ones | expansion happens in double quotes and not in single, but a single-quoted `bash -c` argument is a nested statement and is scanned as one |
| destructive-op and `git clean` gates | heredoc, subshell, comment, optarg, plus `cmdword_is git` | same reasoning as the option gates; the path arguments are read from the ORIGINAL via `flag_value`-style extraction, not from the mask |
| commit-on-main gate | heredoc, subshell, comment, optarg, plus `cmdword_is git` | `git commit -m "push to main"` is a message, not a push |
| `branch-name-guard.sh` | heredoc, subshell, comment, plus `cmdword_is git`, NO optarg | the branch name is the thing being judged, and `git switch -C <branch>` puts it where optarg masking would hide it |
| `branch-pr-title-guard.sh` | heredoc, subshell, comment, plus `cmdword_is gh`; the title comes from `flag_value --title -t` | the title is data to slugify, so it is extracted rather than matched |
| `git-no-dash-c.sh` | heredoc, subshell, comment, plus `cmdword_is git`, NO optarg | reading the `-C` target IS the job; optarg masking would erase it. **Phase 0 outcome (0e):** row retired; the strip lives in `rewrite-cd-read.py`, whose own tokenizer already handles quotes and heredocs, and the file is deleted |

`cmdword_is git` applies to EVERY gate in `git-release-guard.sh` that matches a git operation, not only the `--tags` gate named in the table. The gates are written today as `\bgit[[:space:]]+tag`-style regexes that match anywhere in the statement, so without the anchor `echo "git tag -f v1"` trips the new tag-force gate. The anchor is what makes "the statement's command word is git" a precondition rather than a coincidence.

Two deliberate exceptions to everything above:

- Gate D in `git-release-guard.sh:285` reads the `Release:` line out of the FULL, unstripped command, because PR bodies are multi-line and arrive by heredoc. Unchanged.
- `secret-echo-guard.sh` masks single quotes but NOT double quotes. Bash expands `$VAR` inside `"` and not inside `'`, so that split is exactly the shell's own semantics: the double-quoted form is the vector the guard exists to catch, and the single-quoted and backslash-escaped forms cannot leak anything and are false positives today. Staff review found three live examples of the second kind. This is the one place a guard deviates from the standard set, and it is stated in both file headers.


### The payload carries `cwd`, and three guards ignore it

Every guard that reads git state today reads it from the HOOK PROCESS's working directory: `git-release-guard.sh:97-98` runs `git rev-parse` and `git status` bare, `branch-pr-title-guard.sh:79` runs `git branch --show-current` bare, `git-no-dash-c.sh:9` compares against `realpath "$PWD"`. All three are assuming the hook process cwd equals the session cwd.

It does not have to be assumed. The PreToolUse payload carries a top-level `cwd` field, and `rewrite-cd-read.py:911` has been reading it (`payload.get("cwd")`) since 2026-09-03 across 8,904 logged invocations. Every guard in this chunk switches to it, falling back to `$PWD` when the field is absent, which is the same fail-open shape `rewrite-cd-read.py:912-914` uses.

This is the shared root of three separately-reported defects: the PR-title guard's three wrong-repo denials, the `git -C` comparison, and the destructive-op gate's tree reading. Fixing the input fixes all three, which is why it is stated once here rather than three times in the plan.

`lib.sh` is sourced as `. "$(dirname "$0")/lib.sh"`. `$0` is the symlink path `~/.claude/hooks/<x>.sh`, so `dirname` is `~/.claude/hooks` and `lib.sh` must be linked there too. The same unquoted-glob link step covers it. A guard whose `lib.sh` is missing prints one line to stderr and exits 0 (pass through): a parser library that is absent must not deny every Bash call in the session, and `hooks-preflight.sh` checks `lib.sh` by name so the gap is visible at the next session start.

Two guards print nothing on their pass path: `git-no-dash-c.sh` ends at `:21` inside its `if`, and `secret-echo-guard.sh` ends at `:68` inside its. The other five all end with `echo '{}'` then `exit 0`. Both are fixed in their phases. An empty stdout happens to be treated as a pass today, but every other hook in the tree states the pass explicitly, and a guard whose silence is load-bearing is one refactor away from a silent failure that looks exactly like the dead-hook class item 1 exists to kill.

`hooks-preflight.sh` (SessionStart): reads `jq -r '.hooks[][].hooks[] | select(.type=="command") | .command'` from `~/.claude/settings.json`, takes the first token of each command, and resolves it two ways: a token containing `/` is a path, so it is `~`-expanded and checked with `test -x`; a bare token is a PATH lookup via `command -v`. That covers both live shapes today, `bash '/home/saidler/.claude/hooks/herdr-agent-state.sh' session` (a path in argument position, so the FIRST token `bash` resolves and the hook script itself would be missed) and `clyde permit log` (a bare name). For the `bash <path>` shape the checker takes the first argument that looks like a path instead. Anything unresolved is reported by name. It additionally checks `~/.claude/hooks/lib.sh` is readable. Output goes through whichever channel Phase 0a proves reaches the model.

`git-no-dash-c.sh` stops denying and starts rewriting, via `updatedInput`. This is the answer to Scott's own 2026-09-03 question, which named both halves in one breath: "go research if updatedInput actually works also I have a similar pertool hook that prevents git -C usage. compare and contrast". It works, and it is already in this repo: `rewrite-cd-read.py:927-949` has emitted `updatedInput` since 2026-09-03, with 8,904 logged invocations and 786 rewrites as of 2026-09-13.

Two things carry over from that file and are not optional:

- **`updatedInput` REPLACES `tool_input` wholesale; it is not merged** (`rewrite-cd-read.py:920-926`). Emitting only `command` silently discarded every sibling field, most damagingly `dangerouslyDisableSandbox`, so a `git push` the model asked to run unsandboxed ran sandboxed and died on an unreadable `~/.ssh`. The rewrite must emit `{**tool_input, "command": rewritten}`. This is scar tissue with a name, and the new hook carries the same comment.
- The rewrite emits `permissionDecisionReason` and NO `permissionDecision`, the same shape as that file's REWRITE branch (`:940-948`): the command is still judged by the normal permission rules, and the reason is what makes the rewrite visible instead of magic.

The match itself is deliberately conservative: strip `-C <arg>` when `<arg>`, after trimming a trailing `/`, string-equals the payload's `cwd`, or is `.` or the literal `$PWD`. No `realpath` (the current hook's `realpath` at `:8-9` resolves symlinks and can therefore disagree with the path the model typed), no filesystem access. A miss leaves the command exactly as the model wrote it, and `git -C <cwd>` runs correctly anyway, so a miss costs nothing. That asymmetry is the whole argument for a string match here.

The current matcher is also narrower than its own denial count suggests. `git-no-dash-c.sh:5` is `grep -oP '(?<=git -C )\S+'`, a fixed-width lookbehind on the literal `git -C ` with exactly one space on each side. Probed live 2026-09-13 with cwd at the repo root: `git -C <cwd> status` denies, `git -C "$PWD" status` ALLOWS (the literal `"$PWD"` is captured and `realpath` fails on it), and `git  -C  <cwd>  status` with doubled spaces ALLOWS. So the hook today misses two shapes of the exact thing it exists to catch. Scanning with `lib.sh` rather than a lookbehind closes both, and because the outcome is a rewrite rather than a deny, closing them costs nothing if the scan is over-eager.

### API Design

`settings.json` changes:

```json
"PreToolUse": [
  { "matcher": "Bash", "hooks": [
      { "type": "command", "command": "~/.claude/hooks/secret-echo-guard.sh" },
      { "type": "command", "command": "~/.claude/hooks/allow-help.sh" },
      { "type": "command", "command": "~/.claude/hooks/rewrite-cd-read.py" },
      { "type": "command", "command": "~/.claude/hooks/git-release-guard.sh" },
      { "type": "command", "command": "~/.claude/hooks/block-draft-pr.sh" },
      { "type": "command", "command": "~/.claude/hooks/branch-pr-title-guard.sh" },
      { "type": "command", "command": "~/.claude/hooks/branch-name-guard.sh" },
      { "type": "command", "command": "~/.claude/hooks/codex-stdin-guard.sh" },
      { "type": "command", "command": "~/.claude/hooks/manifest-scope-guard.sh" }
  ]}
],
"SessionStart": [ { "matcher": "*", "hooks": [ ..., { "type": "command", "command": "~/.claude/hooks/hooks-preflight.sh" } ] } ]
```

The order of the `Bash` array above is the order as it stands today plus `branch-name-guard.sh` appended. Spike 0f decides whether that order is load-bearing: if the reason a model sees is chosen by registration order, `branch-name-guard.sh` moves to wherever its advice beats Gate C's for a command that trips both. The array is not settled until 0f runs.

**Phase 0 outcome (0f):** the order is NOT load-bearing and cannot be made so. Across seven runs (both registration orders, a lexically-reversed command path, a lexically-reversed reason, and a 3-second sleep on the first hook in two of them) the reason the model receives is the one from the LAST hook to COMPLETE. Every hook fires; one reason surfaces; with equal-cost hooks it is a race the later-registered one usually wins but did not always. So the array above stands as written, `branch-name-guard.sh` appended, and Phase 5 makes each deny text sufficient on its own instead of relying on a slot.

**Phase 0 outcome (0e):** `git-no-dash-c.sh` is removed from the array above (already reflected) and deleted from the repo. Its symlink at `~/.claude/hooks/git-no-dash-c.sh` goes dangling, so the operator step for this chunk gains `rm ~/.claude/hooks/git-no-dash-c.sh` alongside the `lib.sh` link. `branch-name-guard.sh` is added.

`git-release-guard.sh` gate changes, each with its new deny text:

| change | at | new behavior |
|---|---|---|
| effective-worktree dirtiness | `:98-99,:108-113,:326,:329` | BOTH the destructive-op gate (`:329`) and the `git clean -f` gate (`:326`) stop reading `$porcelain` / `$untracked`, captured once at `:98-99` from the hook process cwd, and read the worktree in effect AT THAT STATEMENT instead; the variables are renamed to say which tree they describe. This is not a cosmetic correction: measured against the live guard, session-clean plus target-dirty ALLOWS a `git reset --hard` against a dirty tree today. See the ordering note below: it is NOT simply a switch to `$bump_porcelain` |
| path-scoped revert | `:329` | allow plain `git checkout -- <path>...` and plain worktree `git restore <path>...` when every non-flag argument is an explicit LITERAL path; keep denying `.`, `./`, `:/`, `*`, any argument carrying an unexpanded `$` or backtick (the hook cannot know what it resolves to, and `git checkout -- "$(pwd)"` is tree-wide), every `reset --hard` on a dirty tree, and `git restore` carrying `--staged` or `--source=` (those discard the index as well as the worktree, which is strictly more loss than the form the 66 denials were about) |
| tag force | new, beside `:173` | deny `git tag` carrying `-f` or `--force`, including combined short flags (`-fa`, `-af`): "git.md: NEVER move a tag. If a tag must move, ask Scott to do it himself." |
| off-main tag | new, beside `:173` | deny tag CREATION (`git tag [-a|-s|-m] <name>` with no `-d|-l|--list|-v|--verify`) when the effective worktree branch is not `main` or `master`: "git.md: tags are cut on main only. A tag on a branch is burnt: squash-merge rewrites the SHA." |
| Gate C name | `:189` | regex `(^\|/)(bump\|release)[-/]` against the EXTRACTED new branch name, never against the whole statement, so `chore/bump-0.9.0` matches and `git commit -m 'mention bump-1.0.0'` does not |
| commit on gated main | new | deny `git commit` when the effective worktree is on `main`/`master` AND its `origin` URL names `tatari-tv`: "git.md: `tatari-tv/*` main is PR-gated. Branch first." |
| `--tags` mask | `:176` | the gate requires `cmdword_is git` and matches on heredoc + subshell + comment maskers, with double quotes LEFT INTACT, so `git push origin "--tags"` still denies while the `grep`, `--help`, heredoc and `$(git describe --tags)` false positives all fall |
| `--body-file` expansion | `:296-310` | expand a leading `$TMPDIR`, `${TMPDIR}`, `$HOME`, `${HOME}` by literal string replacement against the hook's own environment, NEVER `eval` (an `eval` here would execute attacker-controlled text from a tool call); refuse only on what remains. Tests cover all four spellings plus the `--body-file=$TMPDIR/body.md` equals form |

`branch-name-guard.sh` denies a NEW branch name matching `[/_]`, `[A-Z]`, or a leading/trailing `-`, on:

- `git checkout -b <name>` / `git checkout -B <name>`
- `git switch -c <name>` / `git switch -C <name>`
- `git branch <name>` (name in the position Gate C at `git-release-guard.sh:189` already anchors, so `git branch -d x` and `git branch --list 'x*'` pass)
- `git branch -m <new>` and `git branch -m <old> <new>` (the NEW name only): a rename is the sanctioned fix for a bad branch name, so the guard must judge where it lands, not refuse the move
- `git worktree add <path> -b <name>` and `git worktree add -b <name> <path>` (both flag orders)
- `gh pr create --head <name>` when `<name>` is not an existing local branch; an `owner:branch` form is split on the last `:` first, the same as `branch-pr-title-guard.sh:65` does

Known limit, stated rather than papered over: Scott drives worktrees through the `worktree` CLI, not `git worktree add`. A hook matching on the command text cannot see the branch name that CLI passes to git internally, so a slashed branch created that way is out of reach of this guard. The audit's twelve slashed branches were all `git checkout -b` / `gh pr create --head` shapes, so the guard covers the measured cases; if a `worktree`-created slashed branch ever appears, the fix belongs in that CLI.

Deny text names the fix, because the measured failure was the model not knowing what to do: "Branch names are a flat lowercase slug: no `/`, no `_`, no uppercase. Use `<slug>`. The conventional-commit type goes in the PR TITLE, never the branch (rules/git.md)." `<slug>` is the offered name run through the same slugifier.

`branch-pr-title-guard.sh` denial text, by case:

- branch contains `/` or `.`: "Branch '<b>' can never match a title: slugifying collapses `/` and `.` to `-`. No PR exists yet, so rename the BRANCH: `git branch -m <slug>`, push it, then retry with title 'type(scope): <words>'."
- branch is `main`/`master`: "You are on <b>. Create a feature branch first: `git checkout -b <slug>`."
- plain mismatch: today's text, unchanged.

The branch is resolved in the effective worktree: `--head`, then `--repo`, then `cd_target`, then `git -C`, then the session cwd.

`git-no-dash-c.sh` output shape, on a strip (otherwise `{}`):

```json
{"hookSpecificOutput": {
  "hookEventName": "PreToolUse",
  "updatedInput": { "...every field of tool_input...": "...", "command": "git status" },
  "permissionDecisionReason": "Dropped `-C <cwd>`; the flag pointed at the directory git already runs in (rules/git.md)"
}}
```

### Implementation Plan

Operator notes, stated once:

- A NEW hook file (`lib.sh`, `branch-name-guard.sh`, `hooks-preflight.sh`) is inert until `manifest -l HOME/.claude/hooks/* | bash` runs from the repo root with the glob UNQUOTED. Verified 2026-09-13 in chunk A's session: the quoted form emits an empty link list and exits 0. Editing an already-linked file is live.
- `HOME/.claude/settings.json` is sandbox deny-write in this repo, and settings/hook edits trip the auto-mode `[Self-Modification]` classifier (11 blocks in the audit). Phases 5, 6 and 7 run with auto mode off; the settings edits run with the sandbox disabled.
- `.otto.yml` does not exist on `main` today. Chunk A's Phase 4 creates it. If A has landed, Phase 1 extends it; if not, Phase 1 creates it with A's `lint` and `test` tasks plus this chunk's additions, and A's phase becomes an extension instead. Either order works; whichever lands second extends.

#### Phase 0: prove the harness assumptions (zero code)
**Model:** fable
Ten phases, 0 through 9. The count grew by one in review: the `git-release-guard.sh` work is two phases, a parser swap that changes no verdicts and then the gate changes, because a regression net cannot validate a refactor whose assertions move in the same commit. Each spike below runs against a scratch `--settings` file carrying throwaway hooks, and records its evidence under `docs/design/2026-09-13-guard-precision-phase0/`.
- 0a SessionStart output reaches the model. A scratch SessionStart hook prints a WARN line to stdout, and a second variant emits `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"probe"}}`. Ask the new session what it saw. This is genuinely unknown: `ssh-agent-check.sh` has printed a bare WARN line since 2026-09-08 and the audit found zero WARN lines in any transcript.
- 0b `updatedInput` actually reaches the tool. A scratch hook that rewrites `echo original` to `echo rewritten`; run it and record which word comes back. `rewrite-cd-read.py` has 786 logged rewrites, so the mechanism is exercised daily, but "the hook emitted it" and "the shell ran it" are two different claims and only one of them is in that log.
- 0c The same rewrite in a SUBAGENT. 67% of the `git -C` denials came from subagents, so a rewrite that only works on the main thread fixes a third of the problem.
- 0d `lib.sh` resolves through the symlink. `. "$(dirname "$0")/lib.sh"` from a scratch hook invoked at its `~/.claude/hooks/` symlink path.
- 0e Two `updatedInput` hooks on one event. After Phase 6 both `rewrite-cd-read.py` and `git-no-dash-c.sh` can rewrite the same Bash call. Register two scratch hooks that each rewrite a distinct marker (`echo one` to `echo ONE`, `echo two` to `echo TWO`) and run a command containing both; record whether the shell receives both edits, one, or neither, and whether the second hook was handed the original or the rewritten `tool_input`. Then run a rewrite-then-deny chain and record whether the deny cancels the rewrite. If rewrites do not compose, Phase 6 folds the `-C` strip into `rewrite-cd-read.py` (already an `updatedInput` hook, already the only one) instead of converting a second hook, and the doc records that as the outcome.
- 0f Which denying hook supplies the reason. Two probes on 2026-09-13 tripped two live guards with one command and disagreed about which reason surfaced: `git -C <cwd> ... && manifest` showed the manifest guard (registered 9th) over `git-no-dash-c` (4th), while a secret-var echo plus `manifest` showed `secret-echo-guard` (1st). Registration order, file order, and return order are all still live hypotheses and none is confirmed. Settle it with a scratch settings file carrying two trivially-identifiable deny hooks, run both orderings, and record which reason the model receives.
- **Success criteria:** 0a records which channel, if either, reached the model, verbatim. 0b the shell printed `rewritten`, not `original`. 0c the same, from inside an Agent call. 0d the scratch hook sourced the library and printed a function's output. 0e the composition rule is stated as a rule (both edits land, or last-writer-wins, or first-wins) with the observed shell output behind it, and the rewrite-then-deny outcome is recorded. 0f both orderings run, and the rule for which reason surfaces is stated as a rule, not a single observation.

#### Phase 1: `hooks/lib.sh` and its tests
**Model:** opus
- New `HOME/.claude/hooks/lib.sh` with the functions in the Data Model. `mask_heredoc` starts from `git-release-guard.sh:342-377` and MUST add the quote awareness that function lacks: copying it as-is would carry the problem-2a bypass into `lib.sh` and from there into all six guards that source it, which is the opposite of the point. `cd_target` comes from `:108-113`; `cd_at` is new.
- New `HOME/.claude/hooks/lib-test.sh` in the `git-release-guard-test.sh` shape: a `run <expect> <input>` matrix, `--self-test` entry point on `lib.sh`.
- No guard changes yet. This phase is the library alone, so a regression in a later phase is bisectable to the guard, not the parser.
- Create (or extend, see the operator note) `.otto.yml` and wire `lib-test.sh` into its `test` task IN THIS PHASE. Every phase below does the same for the test file it introduces. A test that only reaches CI in a later phase does not gate the commit that added the code it tests, which breaks the one-commit-per-phase-green rule for every phase in between.
- **Success criteria:** `bash HOME/.claude/hooks/lib-test.sh` exits 0 with at least one positive and one negative case per function, including: the problem-2a regression, `echo "<<EOF"` on one line followed by `git push --tags` on the next, where the second line MUST survive (today's function eats it); `<<-` with an indented terminator; two openers on one line; every masker's output is byte-for-byte the same LENGTH as its input; `mask_comment` leaves a `#` inside a quoted span alone and does not treat `a#b` as a comment; `mask_dquote` neutralizes `echo "manifest"` so the bare-word gate does not see the word, while leaving the same word bare in `manifest -l x` visible; `mask_optarg` hides `--force` in `git tag -m "--force"` and leaves the `-C` target of `git -C /tmp status` untouched; `stmts` does not split on a `;` inside quotes but does on a bare one; `flag_value` recovers a quoted `--title` verbatim, recovers a `--title=x` equals form, and returns the RAW text including the `$` for `--body-file "$TMPDIR/b.md"` (the library never decides fail-open; its callers do); `flag_value` recovers the correct value from a command whose earlier text contains a multibyte character (the byte-versus-character case that keeps offsets inside awk); `cd_target` picks the last of three; `cd_at` returns the SECOND of three when asked about a statement sitting between the second and third.

#### Phase 2: port `manifest-scope-guard.sh` and `secret-echo-guard.sh`
**Model:** opus
- Both source `lib.sh`. `manifest-scope-guard.sh` takes the bare-word set (heredoc, subshell, squote, dquote, comment) plus `cmdword_is manifest`. `secret-echo-guard.sh` takes heredoc, comment and squote ONLY, never dquote, per the Data Model exception.
- `secret-echo-guard.sh`: change the `_PAT` token to `_PAT(?![A-Za-z])` so `_PATH` and `_PATTERN` stop matching while `GITHUB_PAT` and `GITHUB_PAT_HOME` still do. This guard matches in PYTHON (`:26` pipes the command into a `python3` heredoc and uses `re.search`), not in `grep -E`, so a negative lookahead is valid here; verified 2026-09-13 against all five names. The trailing `[A-Za-z0-9_]*` in `NAME` at `:35` is what lets `_PAT` swallow the `H` today, and `re.IGNORECASE` at `:40,:50,:53` means lowercase `_path` matches too. `:44-46` already strips the safe `${NAME:+...}` form before the print check, so it is the existing place to hang the exemption. Also mask single-quoted spans and backslash-escaped `$` before matching, which kills three false positives staff review found live (`echo '$SOME_TOKEN'`, `printf '%s\n' '\$SOME_TOKEN'`, `echo \$SOME_TOKEN`): none of those expand anything. Double quotes stay unmasked. Add the explicit `echo '{}'` pass path it lacks at `:68`, and add `${#NAME}` and `[ -n "$NAME" ]` / `[ -z "$NAME" ]` to the safe forms alongside the existing `${NAME:+...}`.
- New `manifest-scope-guard-test.sh` and `secret-echo-guard-test.sh`, each carrying the audit's false positives as allow cases and the true positives as deny cases.
- Wire both new `-test.sh` files into `.otto.yml`.
- **Success criteria:** both `-test.sh` files exit 0 and `otto ci` runs them. The two live false positives this design reproduced (a heredoc body containing the word `manifest`; an `echo` of a `*_CONFIG_PATH` var) return `{}`. The true positives still deny, including the two nested-statement cases: `bash -c 'echo $SOME_TOKEN'` and a single-quoted secret passed to `sh -c`. Plus bare `manifest` as the command word, `echo "$ANTHROPIC_API_KEY"`, `${GH_TOKEN:-x}`.

#### Phase 3: `git-release-guard.sh` parser swap, zero verdict change
**Model:** opus
- Source `lib.sh`. Replace the local `strip_heredocs` and the `sed` splitter with the shared quote-aware `mask_heredoc` and `stmts`, and route every gate's matching through the maskers its row in the Data Model table names. Switch `:97-98` from bare `git` to `git -C <payload cwd>`. Gate D keeps reading the unstripped `$cmd`, as it does today.
- **No gate logic changes in this phase.** Not one expected outcome in `git-release-guard-test.sh` moves.
- This split is the whole point: the existing 54-case matrix can only serve as a regression net for the parser swap if the expected outcomes are untouched while it runs. Combining the swap with the gate changes would mean editing the very assertions that are supposed to prove the swap changed nothing, which proves nothing. Round 2 named this and it is correct.
- Two cases are EXPECTED to change verdict in this phase, and only two, because they are parser bugs rather than gate policy: the problem-2a bypass (`echo "<<EOF"` followed by `git reset --hard` must now DENY, where it allows today) and the `$(git describe --tags)` false positive (must now ALLOW, where it denies today). Both are added to the matrix here with their new expectations and a comment naming them as parser fixes.
- **Success criteria:** `git-release-guard.sh --self-test` exits 0 with all 54 pre-existing cases passing UNCHANGED, plus the two named parser-fix cases. A fixture whose payload `cwd` differs from the hook process cwd is judged against the payload.

#### Phase 4: `git-release-guard.sh` gaps and over-reach
**Model:** opus
- The gate changes in the API Design table, on top of the parser from Phase 3.
- Fix the stale flow comment at `:19-24` as part of this phase, since it is the same file (the other two stale places are Phase 8).
- Extend `git-release-guard-test.sh` with the new cases: `git tag -f -a v1` deny; the combined short form `git tag -fa v1 -m moved` deny; annotated tag creation on a feature branch deny, on main allow; `git tag -d` still deny; `git tag -l 'v*'` allow; `git tag -a v1 -m "added --force"` ALLOW (the `mask_optarg` case: a flag named inside a message is prose); `echo "git tag -f v1"` allow (the `cmdword_is git` anchor); `echo "$(git push origin --tags)"` DENY, from the nested statement, not the outer one; `git tag -a v1 -m "fix the -d flag"` deny as a tag creation off main and NOT read as a deletion (the `mask_optarg` case for the exclusion list); `git checkout -- <file>` on a dirty tree allow; `git checkout -- .` on a dirty tree deny; `git checkout -- .` followed by `&& cd <clean dir>` still deny (the `cd_at` ordering case); `git restore src/` allow; `git restore --staged src/` deny; `git reset --hard` on a dirty tree deny; `git clean -fd` with untracked files present deny, with none present allow, and both judged against the statement's own worktree rather than the hook's (the `:326` gate carries the identical wrong-worktree bug and deletes the one file class `reset --hard` never touches); `git checkout -b chore/bump-0.9.0` deny; `git checkout -b bumpkin-feature` allow (the existing case must still pass); `git commit -m 'mention bump-1.0.0'` allow, proving Gate C matches the EXTRACTED branch name and not the whole statement; `--body-file "$TMPDIR/body.md"` with a `Release:` line allow, and the `${TMPDIR}`, `$HOME`, `${HOME}` and `--body-file=$TMPDIR/body.md` spellings with it; `git commit` on main in a `tatari-tv` remote deny, in a `scottidler` remote allow.
- **Success criteria:** `git-release-guard.sh --self-test` exits 0. The six defects this design reproduced on `main` flip: `git tag -f` denies, off-main tag creation denies, `chore/bump-0.9.0` denies, the subshell tag name allows, the path-scoped revert allows, `$TMPDIR` body-file allows.

#### Phase 5: branch guards
**Model:** opus
- `branch-pr-title-guard.sh`: source `lib.sh`, use the standard pre-pass, resolve the branch in the effective worktree (`--head`, `--repo`, `cd_at`, `git -C`, then the payload `cwd`, in that order; `--repo` is never read today, verified by `rg 'repo' branch-pr-title-guard.sh` returning nothing), and emit the three case-specific denial texts.
- Two guards can now deny the same command: `git checkout -b chore/bump-0.9.0` trips Gate C (a bump-named release branch) and `branch-name-guard.sh` (a slash). Measured 2026-09-13 by firing two live guards with one command, twice: the model sees exactly ONE `PreToolUse:Bash hook error` reason, never both. Which one it sees is what spike 0f settles; this phase's registration order is then chosen so the actionable reason wins. The disjoint case is the common one anyway: `bump-0.2.1` is a legal flat slug that only Gate C rejects, and `fix/x` is a legal branch name that only the new guard rejects.
  - **Phase 0 outcome (0f):** the surfacing reason is the last deny to COMPLETE, a race no registration slot controls. This phase picks no order: `branch-name-guard.sh` is appended. Each text must stand alone: Gate C's says not to create the release branch at all, the new guard's names the flat slug. A command tripping both converges in at most two round trips whichever wins.
- New `branch-name-guard.sh` plus `branch-name-guard-test.sh`, wired into `.otto.yml`; register on `Bash` only. NOT on `mcp__multi-account-github__create_pr`: that MCP server is dead (`config-audit.md` delete list) and chunk J removes the matcher along with 34 other dead entries. Adding a registration to a tool that no longer exists is how the next audit finds a tenth hook nobody can fire.
- New `branch-pr-title-guard-test.sh` carrying the audit's 43 denials as cases by shape.
- **Success criteria:** both `-test.sh` files exit 0. `gh pr create --head fix/markdown-dark-mode --title 'fix(render): markdown dark mode'` denies with text containing `git branch -m`, not the current text demanding a title that slugifies to `fix/markdown-dark-mode`. `git checkout -b fix/x`, `git switch -c Fix-X`, `git branch fix_x`, `git worktree add ../w -b a/b` all deny; `git checkout -b fix-auth-bug`, `git branch -d bump-0.2.1`, `git branch --list 'bump*'` all allow.

#### Phase 6: the `git -C <cwd>` strip folds into `rewrite-cd-read.py`; `git-no-dash-c.sh` is deleted
**Model:** opus

**Phase 0 outcome (0e) rewrote this phase.** Two `updatedInput` hooks on one Bash call do not compose: each is handed the ORIGINAL `tool_input`, and exactly one rewrite survives (the last to complete). Converting `git-no-dash-c.sh` into a second rewriter would silently lose one edit whenever it and `rewrite-cd-read.py` both fired (`cd <cwd> && git -C <cwd> ...`). The Rollout Plan pre-committed the fallback, and this is it. The original bullets are preserved in the evidence file's summary table; the plan is now:

- `HOME/.claude/hooks/rewrite-cd-read.py` gains the strip, in its own function beside the existing `cd` rewrite: for each statement whose command word is `git`, when a `-C <arg>` is present and `<arg>`, after trimming one trailing `/`, string-equals the payload's `cwd`, or is `.`, or is the literal `$PWD` / `"$PWD"` / `'$PWD'`, drop the two tokens. No `realpath`, no filesystem access, the same conservative match the Data Model specifies. The strip runs whether or not the command has a `cd` prefix, and it composes with the existing `cd` rewrite inside the one hook, which is the whole point of folding. The hook already emits `{**tool_input, "command": rewritten}` (the `:920-926` scar-tissue comment stays where it is) and already carries `permissionDecisionReason` without a decision on the REWRITE branch; a strip-only rewrite takes that branch. The existing `log()` gains a `STRIP-C` tag so the strip is observable in `~/.cache/claude/rewrite-cd-read.log`, which spike 0b showed is the ONLY place it can be observed: a rewrite's reason never reaches the model.
- Delete `HOME/.claude/hooks/git-no-dash-c.sh` and its `settings.json` entry (sandbox off for the settings edit, per the operator notes). Its `~/.claude/hooks/git-no-dash-c.sh` symlink goes dangling; the operator step removes it and the PR body says so. It is unregistered, so neither `bin/hooks-resolve` nor `hooks-preflight.sh` will flag it, which is correct: the dead-hook class is a REGISTERED hook with no file, not a stray link.
- New `rewrite-cd-read-test.sh` in the `git-release-guard-test.sh` shape (a `run <expect> <cwd> <command>` matrix feeding the hook JSON on stdin and asserting on `updatedInput.command`), wired into `.otto.yml`. Cases: `git -C <cwd> status` strips; `git -C "$PWD" status` strips (allowed by the old hook); `git  -C  <cwd>  status` with doubled spaces strips (allowed by the old hook); `git -C <cwd>/ status` strips (trailing slash); `git -C . status` strips; `git -C <other> status` unchanged; `git -C <cwd> status && git -C <other> log` strips only the first; `-C` inside a quoted string unchanged; `-C` inside a heredoc body unchanged; `cd <cwd> && git -C <cwd> status` gets BOTH rewrites in one output (the composition case that forced the fold); `git commit -C HEAD~1` unchanged (`-C` is a commit ref there, the Data Model's overload); `git -C <cwd> status` with a sibling `dangerouslyDisableSandbox: true` in `tool_input` emits that field unchanged (the scar-tissue case, asserted directly); a command with no `git` unchanged.
- Delete the `git -C` paragraph from `rules/git.md` Working Directory. Once the flag is stripped automatically, a rule telling the model not to type it is prose with nothing behind it, which is the program's enforcement-before-prose rule applied to itself. `rules/otto.md` keeps its `otto -C` rule: different tool, no rewrite, still worth stating.
- **Success criteria:** `rewrite-cd-read-test.sh` exits 0, including the `dangerouslyDisableSandbox` passthrough case and the `cd`-plus-`-C` composition case. `git-no-dash-c.sh` is absent from the repo and from `settings.json`. A live Bash call `git -C <session cwd> rev-parse --show-toplevel` succeeds with no denial and `~/.cache/claude/rewrite-cd-read.log` gains a `STRIP-C` line for it. The same call inside an Agent behaves identically (spike 0c: PreToolUse fires for subagent Bash calls with `agent_id` in the payload).

#### Phase 7: `hooks-preflight.sh` and the CI resolve check
**Model:** sonnet
- New `HOME/.claude/hooks/hooks-preflight.sh` per the Data Model, emitting `hookSpecificOutput.additionalContext` (spike 0a: both that and plain stdout reach the model in an interactive session; neither fires under `claude -p`, so headless runs are covered by `bin/hooks-resolve` alone). Register on `SessionStart` with the live file's matcher `*`, which 0a exercised.
- New `bin/hooks-resolve`, taking `--settings <path>` (default `HOME/.claude/settings.json`) and `--root <dir>` (default the repo root). It maps each registered `~/.claude/hooks/<x>` to `<root>/HOME/.claude/hooks/<x>` and asserts the file exists and is executable, because in CI nothing has been symlinked into the runner's home and a literal `~` check would fail unconditionally. Exits non-zero on a miss. This is the half that makes the failure impossible to MERGE; the preflight is the half that catches a deploy lag.
- The command-string parsing (tilde path, `bash '<path>' <arg>`, bare PATH name) lives in ONE place and both `bin/hooks-resolve` and `hooks-preflight.sh` use it. A resolver that understands fewer shapes than the live settings file contains is a checker that reports success it did not earn: today's file contains all three shapes, and the `bash '<path>' session` entry is the one a first-token check silently passes.
- New `hooks-preflight-test.sh` driving the preflight against fixture settings files, wired into `.otto.yml` along with `bin/hooks-resolve`.
- **Success criteria:** `bin/hooks-resolve --settings <fixture>` exits non-zero when the fixture names `~/.claude/hooks/does-not-exist.sh`, and `bin/hooks-resolve` with no arguments exits 0 against the repo as-is. A fixture whose only entry is the `bash '<path>' session` shape and whose path is missing also exits non-zero (the shape a first-token check would pass). The preflight, run against a fixture settings file naming a missing hook, emits a warning naming that hook; run against the live settings file it emits nothing.

#### Phase 8: text fixes and the lint list
**Model:** sonnet
- `rules/git.md:73` and `agents/release-driver.md:36`: replace the tag-first ungated flow with a pointer to `bump/SKILL.md` FLOW 1, and state the invariant in one line (the version commit lands first, the tag waits for green CI on that SHA, because a tag cut before CI can only be repaired by a second tag).
- `rules/cli.md`, `general.md`, `interaction.md`, `taste.md`: delete the `<!-- WORKAROUND -->` comment so `---` is line 1, matching `git.md`. The comment is stale: `issues/26868` is about `paths:` arrays, which `comments.md`, `js-ts.md` and `terraform.md` use successfully today.
- `rules/git.md`, the 18-line "Branch names: NEVER a slash" section (`:16`, commit `af61e71`): cut to a one-line pointer at `branch-name-guard.sh`. This doc already calls that section "prose written to compensate for a hook that was never updated", and Phase 5 builds the hook. Phase 6 deletes the `git -C` paragraph from the same file for exactly this reason; leaving the slash rule intact would be the same shape given the opposite treatment, which is the enforcement-before-prose rule applied everywhere except where it is inconvenient.
- `rules/pr.md`: document the two accepted release-intent lines the Gate D hook demands, `Release: rides this PR (vX.Y.Z)` and `Release: none, <why>`. 82 denials happened because the requirement lived only in the hook's own deny text.
- Extend `.otto.yml` (created in Phase 1): add this chunk's touched files to the `lint` em-dash list, add a rules-frontmatter check (line 1 is `---`), and add `bin/hooks-resolve`. The `test` task already lists every new `*-test.sh`, because each phase wired its own.
- Strip the em-dashes from every file this PR touches. Occurrence counts on `main` 2026-09-13, measured with `rg -o $'\\u2014' <file> | wc -l`: `release-driver.md` 28, `git-release-guard.sh` 24, `interaction.md` 13, `git.md` 11, `cli.md` 4, `general.md` 3, `branch-pr-title-guard.sh` 3, `manifest-scope-guard.sh` 1, `secret-echo-guard.sh` 1, `git-no-dash-c.sh` 1 (the deny text at `:16`, which this chunk rewrites anyway), `taste.md` 0, `pr.md` 0. `bump/SKILL.md` (32) is NOT touched by this chunk and stays off the list.
- **Success criteria:** every `.md` under `HOME/repos/.claude/rules/` except `voice.md` has `---` as line 1. `rg -c 'tags local HEAD' HOME/repos/.claude/rules/git.md HOME/.claude/hooks/git-release-guard.sh` prints nothing AND `rg -c 'tags HEAD' HOME/.claude/agents/release-driver.md` prints nothing (the single-command form goes green with `release-driver.md:36` untouched, which is why it is split; see AC7). `rg -c 'Release: rides' HOME/repos/.claude/rules/pr.md` prints 1 or more. `rg -c 'NEVER a slash' HOME/repos/.claude/rules/git.md` prints nothing. `otto ci` exits 0 and `rg -c $'\\u2014' <each file in the lint list>` prints nothing.

#### Phase 9: shakedown and close
**Model:** fable
- Re-run every Phase 1 to 8 criterion against the live setup after the PR merges and the manifest link step runs on desk.lan; record `Observed` lines in this doc.
- Flip chunk B to `done` in `docs/design/2026-09-13-setup-audit-program.md` with the PR URL; mark chunk C `next`.
- **Success criteria:** every criterion carries an Observed line dated after the merge; the tracker row reads `done`.

## Acceptance Criteria

- [ ] **AC1:** every bash guard that splits statements SOURCES the shared library. `rg -l -g '!lib.sh' '\. "\$\(dirname "\$0"\)/lib\.sh"' HOME/.claude/hooks/` lists exactly the five guards `branch-name-guard.sh`, `branch-pr-title-guard.sh`, `git-release-guard.sh`, `manifest-scope-guard.sh`, `secret-echo-guard.sh`. `bash HOME/.claude/hooks/lib-test.sh` exits 0.
  - Observed on main (2026-09-13): `lib.sh` does not exist, so the pattern returns nothing (rc=1). `strip_heredocs` exists in exactly one file (`git-release-guard.sh:342`). Passes after Phase 5.
  - Phase 0 outcome (0e): the list was six with `git-no-dash-c.sh`; that file is now deleted in Phase 6 rather than converted, so it cannot source anything. Five. The criterion's property form (decision 15) is what let this change ride as a list edit rather than a rewrite.
  - Phase 3 finding (2026-09-14): `lib.sh`'s own header comment quotes the sourcing line verbatim, so the bare grep lists the library beside its consumers (measured after Phase 3: four files, `lib.sh` among them). The command now excludes `lib.sh` by name. A library that documents how to source itself is correct; a criterion that counts the documentation as a consumer is not.
  - This criterion has now been wrong twice, and the second time is the instructive one. It first said "seven files" matching a bare `lib\.sh`; Phase 6 made `git-no-dash-c.sh` a sourcer, so it became eight; then Phase 7's `hooks-preflight.sh` checks `lib.sh` BY NAME, so a bare-string match would count it too and the answer becomes nine. Counting files that mention a string was never what the criterion meant. It means "these guards source the library", so it now matches the sourcing line itself and is immune to any file that merely names it. Verified 2026-09-13 against a scratch directory holding a sourcing guard, a preflight that names `lib.sh` in a comment, and `lib.sh` itself: the bare pattern returns all three, the sourcing pattern returns only the guard.
- [ ] **AC2:** the two prose false positives return `{}`. Fixture A: a `cat > x.md <<'EOF'` whose body contains the word `manifest`, piped to `manifest-scope-guard.sh`. Fixture B: `echo "RIPGREP_CONFIG_PATH=$RIPGREP_CONFIG_PATH"`, piped to `secret-echo-guard.sh`.
  - Observed on main (2026-09-13): both return `permissionDecision: deny`. Both also fired on this design session's own probe commands before the fixtures were built with the trigger words assembled at runtime, which is the same class reproducing live. Passes after Phase 2.
- [ ] **AC3:** `git-release-guard.sh --self-test` exits 0, and these six flip: `git tag -f -a v1 -m moved` deny; the combined short form `git tag -fa v1 -m moved` deny (the spelling a model actually types); `git tag -a v9.9.9 -m probe` on a non-main branch deny; `git checkout -b chore/bump-0.9.0` deny; `git push origin "$(git describe --tags --abbrev=0)"` allow; `git checkout -- <one tracked file>` on a dirty tree allow; `gh pr create --body-file "$TMPDIR/body.md"` carrying a `Release:` line allow.
  - Observed on main (2026-09-13, hook fed by stdin JSON, repo `scottidler/claude` on `main` with a dirty tree (16 entries at the time of these probes; the panel re-ran the same probes later against 17 and got the same verdicts)): `git tag -f` **allow** (gap), off-main annotated tag **allow** (gap), `chore/bump-0.9.0` **allow** (gap), subshell tag name **deny** (false positive), path-scoped revert **deny** (over-reach). The `$TMPDIR` body-file case was run against a fixture repo carrying a versioned `Cargo.toml`: **deny**, "--body-file path '$TMPDIR/body.md' carries a shell construct this hook cannot expand". The same command with the path written out literally and a `Release:` line in the file returned **allow**, so the refusal is the unexpanded variable alone. Passes after Phase 4.
- [ ] **AC4:** `gh pr create --head fix/markdown-dark-mode --title 'fix(render): markdown dark mode'` denies with text containing `git branch -m`; `git checkout -b fix/x` denies; `git checkout -b fix-auth-bug` allows; `branch-name-guard-test.sh` and `branch-pr-title-guard-test.sh` exit 0.
  - Observed on main (2026-09-13): the `gh pr create` case denies with "Rewrite the TITLE so that stripping its 'type(scope):' prefix and slugifying the rest equals 'fix/markdown-dark-mode'", which no title can satisfy, and no text offering a rename. `branch-name-guard.sh` does not exist, so `git checkout -b fix/x` allows. Passes after Phase 5.
- [ ] **AC5:** a Bash call `git -C <session cwd> rev-parse --show-toplevel` is NOT denied, prints the toplevel, and `~/.cache/claude/rewrite-cd-read.log` gains a `STRIP-C` line for it; `git-no-dash-c.sh` is absent from `HOME/.claude/hooks/` and from `settings.json`; `rewrite-cd-read-test.sh` exits 0 including the case asserting a sibling `dangerouslyDisableSandbox` field survives the `updatedInput` replacement.
  - Observed on main (2026-09-13): `git-no-dash-c.sh` denies with "git -C used with CWD, drop \"-C /home/saidler/repos/scottidler/claude\" and run git directly". It emits `permissionDecision: deny` and no `updatedInput` (`git-no-dash-c.sh:12-19`), and no `-test.sh` exists for it. Passes after Phase 6.
  - Phase 0 outcome (0b, 0e): the criterion first read "its tool result carries the reason line naming the strip". Spike 0b showed that is not a property this harness has: with `updatedInput` and `permissionDecisionReason`, with or without `permissionDecision: allow`, the `tool_result` content is the command's stdout and nothing else. The observable is the hook's own log, which is the in-repo precedent the Security section already names. And the test file follows the code into `rewrite-cd-read.py`.
- [ ] **AC6:** `bin/hooks-resolve` exits 0 against the repo and non-zero against a fixture settings file naming a missing hook; a new session started with that fixture surfaces a warning naming the hook.
  - Observed on main (2026-09-13): `bin/hooks-resolve` does not exist, and no check of any kind compares `settings.json` against the hooks directory. The warning half depends on Phase 0a: `ssh-agent-check.sh:10` has printed a bare WARN line to stdout since 2026-09-08 and the audit found zero such lines in any transcript, so whether a SessionStart hook can reach the model is UNPROVEN and is Phase 0a's job. Passes after Phase 7.
- [ ] **AC7:** `awk 'FNR==1 && $0 != "---" {print FILENAME}' HOME/repos/.claude/rules/*.md` prints `voice.md` and nothing else, and each of the three stale release-flow sites stops claiming a tag is created first, checked per file against its OWN wording: `rg -c 'tags local HEAD' HOME/repos/.claude/rules/git.md HOME/.claude/hooks/git-release-guard.sh` prints nothing, AND `rg -c 'tags HEAD' HOME/.claude/agents/release-driver.md` prints nothing.
  - Observed on main (2026-09-13): that awk command prints five files, `cli.md`, `general.md`, `interaction.md`, `taste.md` (all carrying the `<!-- WORKAROUND -->` comment) and `voice.md` (no frontmatter, the stated non-goal). After Phase 8 it must print only `voice.md`. For the second: `rg -c 'tags local HEAD'` returns `git.md:1` and `git-release-guard.sh:1` but does NOT match `release-driver.md`, whose `:36` reads "`bump` (tags HEAD) on the default branch". The criterion as first written was unfalsifiable for that file, which is the exact defect the ready-to-build gate exists to catch; it is split per file above. All three still describe the tag-first ungated flow, against `~/.claude/bin/release:11-14` and `bump/SKILL.md:19-30`. Passes after Phase 8.

## Resolved Decisions

Fifteen decisions. The round-by-round history behind them, including every pushback and every finding that was rejected, is in `docs/design/2026-09-13-guard-precision-review-log.md`; it is a companion file, not a follow-on list, and nothing in it is undecided.

1. **A masker may only erase a span the shell will never execute.** Heredoc bodies redirected to a file, single-quoted data, and comments are inert. Subshell bodies, backticks and `bash -c` arguments are nested statements, so `stmts` yields them and neutralizes the span in the enclosing statement. This one rule replaced three separate per-case fixes and closed two deny bypasses the earlier drafts would have introduced.
2. **Option detection never masks quotes.** `git push origin "--tags"` passes `--tags` to git exactly as the bare form does. What removes the measured false positives is `mask_heredoc`, nested-statement yielding, and the `cmdword_is git` anchor, which applies to every git gate in the file and not just the `--tags` one.
3. **`-C` is not in `mask_optarg`.** Git overloads it: `git -C <dir>`, `git commit -C <commit>`, `git switch -C <branch>`. Masking its value would hide a branch name from `branch-name-guard.sh`. `mask_optarg` carries `-m`, `--message`, `-F`, `--file`, `--reuse-message`, `--reedit-message`, long forms only for the reuse flags.
4. **`flag_value` always returns raw text; fail-open is the caller's decision.** Returning empty on an unexpanded `$` would hand Gate D an empty `--body-file` path and deny, which is the `$TMPDIR` friction this chunk exists to remove. `branch-pr-title-guard.sh` passes through on an unknowable `--title`; `git-release-guard.sh` expands the four spellings it knows.
5. **No offset crosses into bash.** `grep -b -o` reports bytes, `${var:off:len}` counts characters, and they diverge on multibyte input. Masking, matching and slicing all happen inside one `awk` program, whose `index` and `substr` share an index space.
6. **`mask_heredoc` is not lifted verbatim.** The existing `strip_heredocs` is not quote-aware, so `echo "<<EOF"` opens a heredoc and swallows every following command. That is a live deny bypass on `main`, not a false positive, and copying it would propagate it to all six guards.
7. **`secret-echo-guard.sh` follows bash's own expansion rules:** masks single quotes and escaped `$`, never double quotes. The double-quoted form is the leak vector; the single-quoted forms cannot emit anything.
8. **One sourced `hooks/lib.sh`, not a port onto the rails TypeScript parser.** rails is early access and fails open, it cannot deny, and PreToolUse is the only layer subagents share (67% of the `git -C` fires were subagents). A guard whose `lib.sh` is missing or broken passes through with one stderr line rather than denying.
9. **`git-no-dash-c.sh` is converted in place to an `updatedInput` rewrite, not deleted and not moved to rails.** `rewrite-cd-read.py` has done exactly this in a shell hook since 2026-09-03 across 786 logged rewrites. The rewrite emits `{**tool_input, command}`: emitting only `command` once discarded `dangerouslyDisableSandbox` and broke a `git push`.
   - **Superseded by Phase 0 (0e, 2026-09-14):** the strip folds INTO `rewrite-cd-read.py` and `git-no-dash-c.sh` is deleted. Measured: two `updatedInput` hooks on one call each receive the original input and only the last to complete keeps its edit. The "not moved to rails" half stands, for the reasons in decision 8. The `{**tool_input, command}` rule stands and is already what `rewrite-cd-read.py` does.
10. **Every guard reads the worktree from the payload's `cwd`, not the hook process cwd.** This is the shared root of three separately-reported defects. The destructive-op and `git clean` gates use `cd_at` (the `cd` in effect at that statement), not `cd_target` (the last in the chain), because `git checkout -- f && cd /clean` would otherwise judge the wrong tree.
11. **Path-scoped reverts are allowed, including a directory argument.** The measured harm was the dodge, not the revert: 66 denials produced 12 `git show HEAD:f > f` workarounds that destroy the same bytes unguarded. Tree-wide forms, `reset --hard`, and `git restore --staged`/`--source=` stay denied.
12. **`git stash && git reset --hard` is not a gap and nothing is built for it.** The stash is the backup and `reset --hard` does not touch untracked files. Scoped to the plain sequence: `--patch` and `--staged` variants leave tracked work outside the stash and stay denied.
13. **The `git commit` deny on `tatari-tv/*` main ships in this chunk.** The audit placed it here itself, in item 5's change list, and the `incidents` lens separates it (proposal 2) from the rails commit authorization that needs the last human prompt (proposal 8, chunk D).
14. **Enforcement before prose applies to the convenient rule too.** Phase 6 deletes `git.md`'s `git -C` paragraph because the rewrite makes it prose with nothing behind it; Phase 8 cuts the "Branch names: NEVER a slash" section for the same reason, now that Phase 5 builds the hook.
15. **An acceptance criterion asserts a property, never a census of the final tree.** AC1 was wrong twice by counting files (seven, then eight, then nine as later phases added sourcers and a preflight that names `lib.sh`). It now asserts that these guards source the library. A count is hostage to every later phase; a property is not.

Scope boundaries held: `voice.md` frontmatter is chunk H, the `Release:` auto-inject is chunk E (this chunk only documents the line), and the doc-gate and template work is chunk G.

## Alternatives Considered

### Alternative 1: port the four bash guards onto the rails parser
- **Description:** delete the shell guards; reimplement all of them as rails `tool.call` rules in TypeScript, using the one parser that is already tested with `bun`.
- **Pros:** one parser, one test runner, quote-awareness already proven.
- **Cons:** rails is early access and fails open, so a guard that must deny cannot live there; the plugin is a single point of failure for every rule at once; PreToolUse is the layer subagents share and the `git -C` evidence is 67% subagent.
- **Why not chosen:** the failure mode of a guard is "denied when it should not have", and moving to a fail-open layer changes that to "allowed when it should not have", which is the wrong direction for a safety hook.

### Alternative 2: register hooks by repo path to kill the symlink lag
- **Description:** `settings.json` names `~/repos/scottidler/claude/HOME/.claude/hooks/x.sh` directly, so a new hook is live the moment the file is written and no deploy step exists.
- **Pros:** removes the dead-hook class entirely rather than detecting it.
- **Cons:** abandons the manifest-managed deployment every other file in this repo uses, and hard-codes a repo path into settings.
- **Why not chosen:** the pair of `bin/hooks-resolve` (blocks the merge) and `hooks-preflight.sh` (catches the deploy lag) covers both measured windows without deviating from the house pattern. Recorded here so it is not re-proposed.

### Alternative 3: put the `git -C` strip in the rails plugin
- **Description:** delete `git-no-dash-c.sh` and add a third `tool.call` Bash rule to `HOME/.claude/skills/rails/hooks/index.ts`, beside gh-persona and chunk A's `rm` rule, reusing the quote-aware `ghSpots`/`segment` scanner.
- **Pros:** one tested TypeScript parser; `bun test`; the scanner is already quote-aware and heredoc-aware.
- **Cons:** rails is early access and fails open; it would be the third rewrite rule on one event, which this doc had to carry as a Med/High risk row; and it moves a rule OUT of the layer every other guard lives in, for a hook that already exists and already fires correctly.
- **Why not chosen:** this was the draft's design until the in-repo precedent turned up. `rewrite-cd-read.py` has been doing exactly this with `updatedInput` since 2026-09-03, in a shell hook, with 786 logged rewrites. Scott's 2026-09-03 ask paired `updatedInput` with this specific hook, and converting it in place is the smaller change, keeps the rails surface at two rules, and removes this chunk's rails dependency entirely. Recorded so the rails option is not re-proposed.

### Alternative 4: fix the four rule files by moving the comment below the frontmatter
- **Description:** keep the `<!-- WORKAROUND -->` text, relocate it under the `---` block.
- **Pros:** preserves the note about the upstream issue.
- **Cons:** the note is wrong: the issue it cites is about `paths:` arrays, and three rule files use `paths:` successfully today.
- **Why not chosen:** a stale workaround comment in an always-on file costs tokens every turn and misleads the next reader. Delete it.

## Technical Considerations

### Dependencies
- No new packages. `jq`, `bash`, `awk`, `sed` are already used by the existing hooks. No `bun`, no rails, no TypeScript: this chunk stays entirely in the shell-hook layer.
- Chunk A dependency: `.otto.yml` only. This chunk touches no rails file, so the two chunks' only shared artifact is that one config. If A has not landed when B builds, B creates it and A's phase becomes an extension; whichever lands second extends.
- Cross-repo blast radius: none. Every file is in `scottidler/claude`. The only external effect is on behavior inside every Claude Code session on desk.lan and the laptop, which is the point. Ship order: this PR merges, then `manifest -l HOME/.claude/hooks/* | bash` on each machine, then Phase 9.

### Performance
- Every Bash tool call today runs ten PreToolUse hooks: the nine matched on `Bash` plus `clyde permit log` on the empty matcher, each doing its own `jq` parse. This chunk keeps all ten (`git-no-dash-c.sh` is converted, not removed) and adds `branch-name-guard.sh`, so a Bash call runs eleven, and each guard that splits statements adds one `source` plus its masker passes. All of it is text in a pipeline with no subprocess beyond `awk` and `sed`.
- `hooks-preflight.sh` runs once per session: one `jq` over `settings.json` plus one `test -x` per registered hook, roughly a dozen stats.

### Security
- `secret-echo-guard.sh` masks heredocs, comments and SINGLE-quoted spans (plus backslash-escaped `$`), and deliberately does NOT mask double-quoted spans. That split is not a special case, it is bash's own expansion rule: `$VAR` expands inside `"` and does not inside `'`. The double-quoted form is the leak vector the guard exists to catch; the single-quoted and escaped forms cannot emit anything and were false positives. Stated in both file headers so the next reader does not "simplify" it into one uniform mask.
- The new `git commit` deny on `tatari-tv` main reads the `origin` URL from the effective worktree. It is a deny, so a misread fails toward refusing a commit, never toward allowing one.
- No hook in this chunk gains a network call. One hook in the repo does write a file today: `rewrite-cd-read.py:474-496` appends one tab-separated line per invocation to `~/.cache/claude/rewrite-cd-read.log` (4.0M, 8,904 lines on 2026-09-13), best-effort with every error swallowed so a logging failure cannot block the command. This chunk adds no new log. It is named here because it is the in-repo precedent if a later chunk wants the preflight to answer "is it working?" from a file instead of an inference, and because a doc claiming no hook writes anywhere would be wrong.

### Testing Strategy
- Five new fixture matrices in the `git-release-guard-test.sh` shape (`run <expect> <input>`, `--self-test` entry point), plus the existing 54-case matrix extended. Positive AND negative case per rule.
- The audit's own false positives are test cases: each of the 9 manifest-guard fires, the 13 `_PATH` fires, the 38 text-only `--tags` fires, and the 43 title-guard denials by shape.
- Break-the-code once per guard during Phase 9: invert one rule, confirm the matrix fails.
- No rails surface in this chunk, so no `bun test` and no `claude plugin validate`.

### Rollout Plan
- State when this doc was finished, so the next reader does not have to reconstruct it: both this doc and its review log are UNTRACKED on disk, the repo was sitting on chunk A's `enforcement-core` branch, and the program tracker still had chunk B as `queued` with no doc link. Nothing here is committed. The tracker row and the branch are the first two things to fix when this chunk starts.
- Phase 0 can change this plan, and that is the point of it. Two spikes are load-bearing: if 0a shows SessionStart output never reaches the model, the preflight is invisible and `bin/hooks-resolve` is the only surviving half of item 1; if 0e shows two `updatedInput` hooks do not compose, the `git -C` strip folds into `rewrite-cd-read.py` instead of converting a second hook.
  - **Phase 0 ran 2026-09-14.** 0a: both channels reach the model interactively, none under `-p`; the preflight stays, on `additionalContext`. 0e: rewrites do NOT compose; the fold happened (Phase 6 rewritten above). 0f: the surfacing deny reason is a completion-order race, so Phase 5 relies on no registration slot. 0b, 0c, 0d pass; 0b also showed a rewrite's reason never reaches the model (AC5 amended). Full record: `docs/design/2026-09-13-guard-precision-phase0/evidence.md`.
- After merge on desk.lan the operator step is now two commands: `manifest -l HOME/.claude/hooks/* | bash` from the repo root (glob unquoted) to link `lib.sh`, `branch-name-guard.sh` and `hooks-preflight.sh`, then `rm ~/.claude/hooks/git-no-dash-c.sh` to drop the symlink Phase 6 leaves dangling.
- One PR on this repo, branch `guard-precision`, title `fix(hooks): guard precision`, one commit per phase, `otto ci` green per phase.
- After merge on desk.lan: `manifest -l HOME/.claude/hooks/* | bash` from the repo root, glob unquoted, then a fresh session for Phase 9.
- Rollback, ordinary: every change is additive or a text edit. Reverting the commit and re-running the link step restores the previous behavior.
- Rollback, emergency, for the one failure this chunk can cause that a revert is too slow for: a broken `lib.sh` (a syntax error, not a missing file) would make every guard that sources it fail, and six guards sourcing one file is a new single point of failure that did not exist before. Three defenses, in order:
  1. Each guard sources defensively: `. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }`. A `source` of a file with a syntax error returns non-zero, so a broken library degrades to pass-through exactly like a missing one, rather than denying or crashing.
  2. `otto ci` runs `bash -n` over `lib.sh` and every guard, so a syntax error cannot merge.
  3. If it somehow ships: `rm ~/.claude/hooks/lib.sh` (the symlink, not the repo file) restores pass-through across all six guards in one command, and every guard keeps working with its pre-chunk behavior absent. That command is the operator's kill switch and it belongs in the PR body.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| A masker neutralizes text a guard needed to READ, not just match | Med | High | The slice never leaves awk: `flag_value` matches on the masked copy and returns the original value from inside one program, so no offset crosses into bash. `lib-test.sh` asserts every masker preserves byte length, that `flag_value` recovers a quoted value verbatim and an `--flag=x` form, and that it returns the RAW text for a value holding an unexpanded `$`, because deciding fail-open is the caller's job and not the library's |
| A masker hides a span whose contents the shell would still execute | Med | High | Option gates never mask quotes (`git push origin "--tags"` is a real bulk push); the per-gate masker table names the set each gate uses, and the four measured false-positive classes are each mapped to the specific masker or anchor that fixes them |
| `lib.sh` not linked after merge, guards go inert | High without the step | High | Operator step in the plan and the PR body; `hooks-preflight.sh` checks `lib.sh` by name; `bin/hooks-resolve` blocks the merge case |
| SessionStart output never reaches the model, so the preflight is invisible | Med | Med | Phase 0a decides before Phase 7 is written; if neither channel works, the preflight still exits non-zero and `bin/hooks-resolve` still blocks the merge, and the doc records the loss |
| Allowing path-scoped reverts loses work the old deny protected | Low | Med | The old deny was routed around 12 times with an unguarded equivalent; tree-wide forms and `reset --hard` stay denied |
| The new off-main tag deny blocks a legitimate tag | Low | Low | `git.md` forbids off-main tags absolutely; the deny text names the flow |
| `updatedInput` drops a sibling `tool_input` field, as it did in Sep 2026 | Med | High | The rewrite emits `{**tool_input, command}`; `git-no-dash-c-test.sh` asserts a `dangerouslyDisableSandbox` sibling survives; the scar-tissue comment rides in the file |
| `updatedInput` rewrites do not apply inside subagents, where 67% of the fires are | Low | Med | Spike 0c runs the probe inside an Agent call before Phase 6 is written |
| The payload `cwd` field is absent in some event or version, so the guards lose their worktree | Low | Med | Fall back to `$PWD`, the value used today, so the worst case is current behavior; `rewrite-cd-read.py:912-914` has failed open on this field across 8,904 invocations |
| `branch-name-guard.sh` blocks a branch Scott created by hand | Low | Low | The rule is Scott's own, set by commit `af61e71` and now carried by the hook rather than by the prose Phase 8 cuts; the deny names the flat slug to use |
| Only one deny reason reaches the model, so a new guard hides an older guard's better advice | Med | Med | Measured, not assumed (two live probes); spike 0f settles which one wins and Phase 5 picks the registration order from that |
| Chunk A and chunk B both edit `.otto.yml` | Med | Low | That file is now their ONLY shared artifact: chunk B touches no rails file since the `git -C` strip moved to `updatedInput`. One chunk lands before the next opens (program rule); whichever lands second extends |
| Two `updatedInput` hooks silently discard each other's rewrite | Med | High | Spike 0e settles the composition rule before Phase 6 is written; if rewrites do not compose, the `-C` strip folds into `rewrite-cd-read.py` rather than adding a second rewriting hook |
| `git commit` deny misfires on a `tatari-tv` repo where main is genuinely ungated | Low | Med | The gate reads the live remote URL only; Phase 3 adds an allow case for a `scottidler` remote and a deny case for `tatari-tv`, and the door is the existing `BUMP_ORDERED_BY_SCOTT` pattern if one is needed |

## Open Questions

- [x] none. OQ1 (whether the `git commit` deny on `tatari-tv/*` main belongs in this chunk or in chunk D) is closed by the audit's own placement; see Resolved Decisions.

## References

- Program tracker: `docs/design/2026-09-13-setup-audit-program.md`
- Chunk A: `docs/design/2026-09-13-enforcement-core.md`
- Ranked report item 5: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/
- Raw findings: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-audit-findings-2026-09-12/
- Hooks in scope: `HOME/.claude/hooks/git-release-guard.sh` (388 lines, `strip_heredocs` at `:342-377`, `cd_target` at `:108-113`, Gate C at `:189`, destructive op at `:329`), `branch-pr-title-guard.sh:32-37,46,71-81`, `manifest-scope-guard.sh:21-27`, `secret-echo-guard.sh:34,40-55`, `git-no-dash-c.sh:5-20`
- Test shape: `HOME/.claude/hooks/git-release-guard-test.sh:121-137` (54 cases, `run <expect> <branch> <command>`)
- `updatedInput` precedent and its scar tissue: `HOME/.claude/hooks/rewrite-cd-read.py:920-949` (wholesale replacement of `tool_input`, REWRITE branch shape), `:474-496` (the log), live since 2026-09-03
- rails parser, for the Alternatives record only (this chunk touches no rails file): `HOME/.claude/skills/rails/hooks/index.ts:45-94`
- Release flow truth: `~/.claude/bin/release:5-22,235-250`, `HOME/.claude/skills/bump/SKILL.md:19-32`
- Stale release text: `HOME/repos/.claude/rules/git.md:73`, `HOME/.claude/agents/release-driver.md:36`, `HOME/.claude/hooks/git-release-guard.sh:19`
