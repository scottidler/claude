# Review panel synthesis: chunk B implementation audit (Mode 2)

Doc: /home/saidler/repos/scottidler/claude/docs/design/2026-09-13-guard-precision.md
Round: 1 | Mode: 2 (Implementation Audit)
Branch: guard-precision | Range: 8ee8f60..db3e2ab (14 commits, local only)
Doc snapshot: doc-snapshot-r1.md (sha256 be46281c460a016b33906e41a89b0d7730b35603ebdffe9c827d3528cf9a9a09)
Drift: round 1, no previous snapshot to diff against.

## Seat status (from dispatch-status-r1.txt)

- architect (gemini-3.1-pro-preview): rc=124, TIMEOUT at the 10m wall clock, no
  review produced. Root cause, read from the preserved trace
  (/tmp/claude-1000/architect-trace-failed-554498.jsonl, 276KB): the seat made
  only 14 tool calls in 600s and its last several were rejected by its own
  policy engine with "Tool execution denied by policy. You are in Plan Mode with
  access to read-only tools." It was trying to run `cat <file> | sed -n '101,200p'`,
  a pipeline the architect policy.toml does not allow. It was not wedged; it was
  starved of the shell it needed to verify anything.
- staff-engineer (codex gpt-5.5): rc=0, 5916 bytes. Complete.
- ARCHITECT SUBSTITUTE (opus, labeled): the architect seat was re-run with the
  SAME persona file and the SAME prompt on an Anthropic model, because a one-seat
  panel is not a panel. rc=0, 16786 bytes. Cross-model independence for that seat
  is PARTIAL: the substitute shares a model family with the orchestrator. This is
  disclosed here rather than presented as the gemini seat.

Every claim below that either seat made as a negative, an absolute, or a bare
verdict was re-run as a command by the orchestrator. Results are in probes.md.
Where a seat was wrong, that is stated.

## [ARCHITECT] gemini seat: FAILED (rc=124 timeout), no review

```
architect: gemini review running -- pid 554498 (follow: kill -0 $(cat /tmp/claude-1000/architect.pid))
error: gemini exceeded the 10m wall-clock limit and was killed. No complete review.
       Over 10m means it hung, not that it's slow. Retry rather than waiting longer.
--- full gemini trace preserved: /tmp/claude-1000/architect-trace-failed-554498.jsonl (276333 bytes) ---
--- last 4000 bytes ---
D\" }\n        i += 2\n        continue\n      }\n      if (ch == \"\\\"\") { cls[i] = \"q\"; q = 0; i++; continue }\n      if (ch == \"`\") { i = subspan(s, i, n, \"`\"); continue }\n      if (ch == \"$\" && substr(s, i + 1, 1) == \"(\") { i = subspan(s, i, n, \")\"); continue }\n      cls[i] = \"D\"\n      i++\n      continue\n    }\n    if (ch == \"\\\\\") {\n      if (substr(s, i + 1, 1) == \"$\") { cls[i] = \"E\"; cls[i + 1] = \"E\" }\n      else { cls[i] = \".\"; if (i < n) cls[i + 1] = \".\" }\n      i += 2\n      continue\n    }\n    if (ch == \"'\") { cls[i] = \"q\"; sqcls = dashc_before(s, i) ? \"c\" : \"S\"; q = 1; i++; continue }\n    if (ch == \"\\\"\") { cls[i] = \"q\"; q = 2; i++; continue }\n    if (ch == \"`\") { i = subspan(s, i, n, \"`\"); continue }\n    if (ch == \"$\" && substr(s, i + 1, 1) == \"(\") { i = subspan(s, i, n, \")\"); continue }\n    if (ch == \"#\" && wordstart(s, i)) {\n      while (i <= n && substr(s, i, 1) != \"\\n\") { cls[i] = \"#\"; i++ }\n      continue\n    }\n    if (ch == \"<\" && substr(s, i, 3) == \"<<<\") { cls[i] = \".\"; cls[i+1] = \".\"; cls[i+2] = \".\"; i += 3; continue }\n    if (ch == \"<\" && substr(s, i, 2) == \"<<\") {\n      rest = substr(s, i)\n      if (match(rest, HDRE)) {\n        tok = substr(rest, 1, RLENGTH)\n        npend++\n        pdash[npend] = (substr(tok, 3, 1) == \"-\") ? 1 : 0\n        w = tok"}
```

## [ARCHITECT (substitute: opus, gemini seat timed out at rc=124)]

## Verdict

The spec is delivered: all 7 ACs hold, every Phase 0-8 bullet I could check is implemented, 402 test cases green, and the implementation-notes file discloses an unusually complete set of deviations. But the `cmdword_is` anchor introduced in Phase 3 is a **live deny bypass across all 14 gates of `git-release-guard.sh`**, and it is not in the doc's allowed set of behavior changes. That is the finding.

---

## (a) MECHANICAL

### M1 (CRITICAL, deny BYPASS + behavioral regression): `cmdword_is` un-anchors every gate for compound commands, `eval`, wrappers, escaped verbs, and process substitution

`lib.sh:416-422` (`cmdword_ok`) tests the statement against
`^(VAR=..)*((command|builtin|exec|sudo|env)[ \t]+)*(/?[^ \t]*/)?<word>([ \t]|$)`.

Anything else in leading position fails the test, and every gate is gated on it: `git-release-guard.sh:304,314,325,349,352,390,396,409,455,459,493,561,567,583` (14 gates), `branch-name-guard.sh:144,156`, `branch-pr-title-guard.sh:141`, `manifest-scope-guard.sh:31`.

Measured, baseline `8ee8f60` vs `db3e2ab`, session cwd `/home/saidler/repos/scottidler/claude` (17-entry dirty tree):

| command | 8ee8f60 | db3e2ab |
|---|---|---|
| `git push origin --tags` | deny | deny |
| `{ git push origin --tags; }` | deny | **allow** |
| `( git push origin --tags )` | deny | **allow** |
| `\git push origin --tags` | deny | **allow** |
| `cat <(git push origin --tags)` | deny | **allow** |
| `timeout 5 git push origin --tags` | deny | **allow** |
| `if true; then git push origin --tags; fi` | deny | **allow** |
| `for i in 1; do git push origin --tags; done` | deny | **allow** |
| `eval "git push origin --tags"` | deny | **allow** |
| `bash -lc 'git push origin --tags'` | deny | **allow** |

Every gate falls the same way, including the irreversible ones. Same table for `{ ...; }`:

| gate | 8ee8f60 | db3e2ab |
|---|---|---|
| `{ git reset --hard; }` | deny | **allow** |
| `{ git tag -d v1; }` | deny | **allow** |
| `{ git clean -fd; }` | deny | **allow** |
| `{ git checkout -- .; }` | deny | **allow** |
| `{ git push --force origin main; }` | deny | **allow** |
| `{ git push origin :refs/tags/v1; }` | deny | **allow** |
| `{ gh pr create --title t --body b; }` (Gate D, versioned fixture) | n/a | **allow** vs `deny` bare |
| `f(){ git tag -f v1; }; f` | allow | allow |

Repro (any of the above):
```
echo '{"tool_name":"Bash","tool_input":{"command":"{ git reset --hard; }"},"cwd":"/home/saidler/repos/scottidler/claude"}' \
  | bash HOME/.claude/hooks/git-release-guard.sh
# -> {} ; baseline returned permissionDecision: deny
```

Why this is not a disclosed deviation: the design doc's Data Model justifies `cmdword_is git` on four named false positives (`grep -n "git push ... --tags"`, `git-release-guard.sh --help`, heredoc prose, `$(git describe --tags)`), and the implementation notes (Phase 3, Deviations) disclose one extra class: *prose* naming a git operation outside command position. `{ git reset --hard; }` is not prose. It is the command, and bash runs it. The allowed set in the doc does not contain it.

Root cause is a category error in `cmdword_ok`: it models "command word" as a regex over a raw statement prefix, but `stmts` (`lib.sh:376-399`) splits only on `; \n & |` and leaves `{`, `(`, `do`, `then`, `else`, `eval`, and non-runner wrapper verbs sitting in front of the verb. `<(...)` and `>(...)` are additionally not handled at all by `scan()` (`lib.sh:79-116` has cases for `$(`, backtick, `<<<`, `<<`, but none for `<(`), so a process-substitution body is neither yielded as a nested statement nor neutralized, which contradicts decision 1's stated rule ("a masker may only erase a span the shell will never execute" and its corollary that executed bodies become nested statements).

None of the 402 test cases cover any of these shapes:
```
grep -nE 'eval|\{ git|\( git|if true|^then |timeout|<\(' HOME/.claude/hooks/*-test.sh   # zero hits
```

### M2 (MED, deny BYPASS): `find_dashc` matches only the exact token `-c`, so `bash -lc` / `bash -xc` escape the secret guard

`lib.sh:344-356` requires `tokword(s,k) == "-c"`. Combined short flags are not recognised, so the body is neither yielded as a nested statement nor neutralized.

```
echo '{"tool_name":"Bash","tool_input":{"command":"bash -lc '"'"'echo $GH_TOKEN'"'"'"},"cwd":"/tmp"}' \
  | bash HOME/.claude/hooks/secret-echo-guard.sh
# -> {}   (baseline: deny)
```
`bash -c 'echo $GH_TOKEN'` still denies correctly. This is a regression against `8ee8f60`, which matched the token text anywhere.

### M3 (MED, gap, pre-existing but now locked in): `mask_heredoc` erases heredoc bodies unconditionally, including unquoted-delimiter bodies bash expands

`lib.sh:94-142`. The Data Model justifies the masker with "heredoc bodies **redirected to a file** ... are inert". Neither condition is checked: the delimiter's quoting is discarded (`lib.sh:102-103` `gsub` strips both quote kinds) and there is no redirect test.

```
printf '{"tool_name":"Bash","tool_input":{"command":"cat <<EOF\n$GH_TOKEN\nEOF"},"cwd":"/tmp"}' \
  | bash HOME/.claude/hooks/secret-echo-guard.sh
# -> {}
```
Bash expands `$GH_TOKEN` there and `cat` prints it to the transcript, which is the exact vector `secret-echo-guard.sh:13-18` says it exists to catch. Not a regression (baseline emitted nothing, i.e. pass), but the new masker is now the structural reason it can never fire. The quoted form `cat <<'EOF'` is correctly inert and should stay masked; the unquoted form should not.

### M4 (LOW): `cmdword_ok` rejects `env VAR=x <word>`

`lib.sh:420` orders env-assignments *before* the `command|builtin|exec|sudo|env` prefix group, so only `VAR=x env git` matches, never `env VAR=x git`.
```
. HOME/.claude/hooks/lib.sh; printf '%s' 'env X=1 git push' | cmdword_is git; echo $?   # 1
```
The Data Model says `cmdword_is` allows "leading env assignments, `command|builtin|exec|sudo|env` prefixes". It allows them in one order only.

### M5 (LOW): `branch-name-guard.sh` misses the attached short-flag spelling

`branch-name-guard.sh:104-135` compares tokens for exact `-b`/`-B`/`-c`/`-C`.
```
echo '{"tool_name":"Bash","tool_input":{"command":"git checkout -b\"fix/x\""},"cwd":"/home/saidler/repos/scottidler/claude"}' \
  | bash HOME/.claude/hooks/branch-name-guard.sh   # -> {}
```
`git checkout -bfix/x` is valid git. All other API-Design shapes (`-b`, `-B`, `-c`, `-C`, `--create`, `branch <name>`, `branch -m [old] new`, `worktree add` both orders, `gh pr create --head`) verified deny/allow correctly, including `git branch -d bump-0.2.1` and `git branch --list 'bump*'` allow.

### M6 (LOW, wiring drift): `.otto.yml` lint FILES list omits 3 touched files

`.otto.yml:16-59`. Touched but unlisted: `docs/design/2026-09-13-guard-precision.md`, `-implementation-notes.md`, `-phase0/evidence.md`. All three are currently em-dash-clean, so the gate is latent, not failing. This is the identical class the file's own comment at `.otto.yml:9-11` records as chunk A's finding M3. Phase 8's bullet says "add this chunk's touched files to the lint em-dash list".

### M7 (LOW): the preflight's remediation string tells the operator to run the glob the notes say is wrong

`hooks-preflight.sh:42` emits `manifest -l HOME/.claude/hooks/* | bash`. The implementation notes ("Orchestrator note after Phase 7") record that the bare `*` also links `__pycache__/*.pyc`, and the doc's Rollout Plan was updated to `HOME/.claude/hooks/*.sh HOME/.claude/hooks/*.py`. The hook's own string was not.

### M8 (LOW): two new test files are not executable

```
ls -l HOME/.claude/hooks/branch-name-guard-test.sh HOME/.claude/hooks/branch-pr-title-guard-test.sh
# -rw-rw-r--  (every other hook file in the tree is 775)
```
Harmless today (`.otto.yml:83` invokes `bash "$t"`), but inconsistent with the 26 siblings.

---

## What verified clean

I checked these and they hold; listing them so the report has no unattributed bucket.

**Phases.** Phase 0 evidence file present (157 lines), all six spikes recorded. Phase 1 library present with all 12 documented functions. Phase 2 both guards ported, `_PAT(?![A-Za-z])` in place (`secret-echo-guard.sh:57`), `${#NAME}` and `[ -n/-z ]` safe forms added, explicit `echo '{}'` pass path added at `:103`. Phase 3 parser swap, `git -C "$cwd"` at `:155`. Phase 4 all gate changes. Phase 5 both guards, no registration-order reliance (`branch-name-guard.sh:15-22` states 0f's rule). Phase 6 rewritten as specified: strip in `rewrite-cd-read.py`, `git-no-dash-c.sh` gone from repo and `settings.json`. Phase 7 `additionalContext` emitted (`hooks-preflight.sh:43`), shared parsing in `hooks-resolve-lib.sh` used by both consumers. Phase 8 all text fixes.

**Data Model contract.** `mask_optarg` covers exactly the 6 listed flags and leaves `git -C /tmp status` byte-identical; `flag_value --body-file` on `"$TMPDIR/b.md"` returns raw `$TMPDIR/b.md`; option gates leave double quotes intact (`git push origin "--tags"` denies); nested `$(...)`, backticks and `bash -c` bodies are both yielded and neutralized; no offset crosses into bash (multibyte `flag_value` on a 🎉-bearing title returns the correct value, mask byte-length preserved at 19/19); all 5 guards read the payload `cwd`; `secret-echo-guard` masks squote + escaped `$`, never dquote.

**`cd_at` vs `cd_target`.** Verified in all six directions against two fixture repos: session-clean/target-dirty denies, `git reset --hard && cd <clean>` denies, `cd <clean> && git reset --hard` allows, and `cd_at 5` on a three-`cd` chain returns the second while `cd_target` returns the third.

**API Design gate table.** tag force including `-fa`; off-main tag creation deny and on-main allow; `git tag -l`/bare `git tag`/`--contains HEAD` allow; `git tag -d` still deny; Gate C `(^|/)(bump|release)[-/]` on the extracted name (`chore/bump-0.9.0` deny, `git commit -m 'mention bump-1.0.0'` allow); path-scoped revert allow with `.`/`:/`/`*`/`$X`/`` `pwd` ``/`$(pwd)` all refused; `git restore --staged` and `--source=` deny; `git clean` per-statement worktree; commit-on-`tatari-tv`-main deny, `scottidler` allow; `--body-file` expansion for all four spellings plus the `=` form, no `eval` anywhere in the path (`git-release-guard.sh:523-530` is pure `${bf/#...}`).

**All 7 ACs pass**, run verbatim. AC6's interactive half I could not run (a new Claude session with a fixture settings file); the implementation notes record it with the model's verbatim quote, and `bin/hooks-resolve` exits 0 against the repo and non-zero against the missing-hook fixture via `hooks-preflight-test.sh` 8/8.

**Deviations in the notes.** I walked all 26 recorded deviations across the 9 sections. Every one is disclosed with a reason, and I found no *recorded* deviation that misstates what the code does. The undisclosed drift is M1 and M2, which the notes do not mention in any form.

---

## (b) ARCHITECTURE / SYSTEMIC

**S1. The command-word test is the wrong shape for the job.** `cmdword_ok` is a prefix regex over an unparsed statement. The library already has a token map with per-byte classes (`cls[]`) and a tokenizer (`tokenize`), which is enough to answer "is token 1 the verb, after skipping assignments, wrappers, `{`, `(`, `do`, `then`, `else`, `!`, `time`" structurally. The regex was lifted from `block-draft-pr.sh:42`, where it guarded one command; generalizing it to 18 call sites turned a local heuristic into the single load-bearing precondition for every irreversible-operation gate in the tree. The doc's decision 2 makes the anchor the thing that replaces quote-masking for option gates, so its precision *is* the guard's precision, and nothing in the 402-case matrix measures it against a compound command.

**S2. The 113-case matrix validated the refactor it was written for, not the class the refactor moved.** The Phase 3 split (swap first, gates second) is exactly right and the notes' reasoning for it is correct. But the regression net only proves "no pre-existing expectation moved"; it says nothing about inputs no pre-existing case covered, which is where the anchor's blast radius lives. The doc's own quality bar ("tests must bite: break the code to prove the test fails") was applied per-gate and not to the anchor. A differential harness (replay every matrix command through the baseline hook and diff verdicts, plus a shape-mutation pass wrapping each in `{ }`, `( )`, `eval`, `timeout`) would have caught all of M1 in one run, and is the structural remedy rather than adding ten cases.

**S3. The single-parser consolidation is right and worked.** One quote model, five consumers, one test file, and the promotion of `args` out of `git-release-guard.sh` in Phase 5 with 113/113 still green is good evidence the seam holds. The fail-open source (`. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }`) is present verbatim in all five guards and is the correct trade. The mid-build discovery that every ported guard was silently inert through the symlink path is the strongest argument in the whole chunk for `hooks-preflight.sh` existing, and the notes captured it as a rule for later chunks.

**S4. Fail-open on the parser, fail-closed on the verdict, is the right split and is honored.** A missing or broken `lib.sh` degrades to `{}`; a misread remote falls through to allowing a commit; an unknowable `--title` passes through; an unreadable `--body-file` denies loudly. Each of those directions matches the doc.

---

## (c) PRODUCT UTILITY

Net positive on precision, net negative on coverage, and the two are not separable.

**Better:** the three measured false-positive classes are gone and I confirmed each (prose in a heredoc, `RIPGREP_CONFIG_PATH`, `$(git describe --tags)`). The `git -C` deny became a silent rewrite that also catches the two shapes the old lookbehind missed (`"$PWD"`, doubled spaces). The title guard's denial now names a satisfiable fix instead of an impossible one, which is the single highest-value text change in the chunk. `branch-name-guard.sh` closes the slashed-branch class at creation, where it costs one round trip instead of four. The preflight plus `bin/hooks-resolve` pair genuinely kills the dead-hook class, and it proved itself during the build.

**Worse:** an agent that writes `{ git reset --hard; }` or `eval "git push --tags"` now runs it unguarded. Models reach for brace groups and `eval` routinely, and `for`/`if` wrappers are common in the exact multi-repo sweeps where a `reset --hard` hurts most. The gates that matter most (tag deletion, tag force, force-push, `reset --hard`, `clean -f`) are the ones that were *unanchored regexes* on `8ee8f60` and are now anchored, so the chunk traded a measured false-positive rate for an unmeasured false-negative rate on its own irreversible-operation surface. Until M1 is closed, this chunk's enforcement layer is more precise and less safe than the one it replaced.

**Doc hygiene.** Status reads `Implemented` while the tracker row at `2026-09-13-setup-audit-program.md:33` still reads `building`, all seven AC checkboxes are `[ ]`, and Phase 9's flip-to-`done` step has not run. The Status line scopes itself to Phases 0-8, so this is internally consistent, but the tracker and the doc now disagree. LOW.

---

## PROBE lines (re-runnable regressions vs `8ee8f60`)

```
PROBE: echo '{"tool_name":"Bash","tool_input":{"command":"{ git reset --hard; }"},"cwd":"'"$PWD"'"}' | bash HOME/.claude/hooks/git-release-guard.sh
       baseline: permissionDecision deny | current: {}
PROBE: ... "command":"( git push origin --tags )"        baseline deny | current {}
PROBE: ... "command":"\\git tag -d v1"                   baseline deny | current {}
PROBE: ... "command":"cat <(git clean -fd)"              baseline deny | current {}
PROBE: ... "command":"timeout 5 git push --force origin main"  baseline deny | current {}
PROBE: ... "command":"if true; then git push origin --tags; fi"  baseline deny | current {}
PROBE: ... "command":"for i in 1; do git reset --hard; done"     baseline deny | current {}
PROBE: ... "command":"eval \"git push origin --tags\""    baseline deny | current {}
PROBE: ... "command":"{ git push origin :refs/tags/v1; }" baseline deny | current {}
PROBE: ... "command":"{ git checkout -- .; }"             baseline deny | current {}
PROBE: echo '{"tool_name":"Bash","tool_input":{"command":"bash -lc '"'"'echo $GH_TOKEN'"'"'"},"cwd":"/tmp"}' | bash HOME/.claude/hooks/secret-echo-guard.sh
       baseline: deny | current: {}
```

Baseline hook for comparison: `git show 8ee8f60:HOME/.claude/hooks/<guard>.sh > $TMPDIR/base/<guard>.sh`.

No live `git tag`, `git push`, `git checkout <branch>`, or `git reset` was run against this repo or any real repo; every probe fed JSON to a hook, and the two fixture repos live under `$TMPDIR`.

## [STAFF-ENGINEER] (codex gpt-5.5, rc=0)

**Verdict**

Not complete. The implementation delivers a lot of the planned wiring, but I found live deny bypasses in the shared parser. Highest risk: command text that Bash executes is not always yielded as a statement or recognized as the command word.

**Mechanical Findings**

**Critical: quoted command words bypass every `cmdword_is` gate.**
`cmdword_is` matches raw text with a regex and does not model shell quote removal: [lib.sh](/home/saidler/repos/scottidler/claude/HOME/.claude/hooks/lib.sh:416). Bash executes `"git" push origin --tags` as `git push origin --tags`, but `git-release-guard.sh` allows it because `is_git` stays false: [git-release-guard.sh](/home/saidler/repos/scottidler/claude/HOME/.claude/hooks/git-release-guard.sh:284). Same class affects `branch-name-guard.sh`, `branch-pr-title-guard.sh`, and `manifest-scope-guard.sh`.

Repro JSON:
```json
{"tool_name":"Bash","tool_input":{"command":"\"git\" push origin --tags"},"cwd":"/home/saidler/repos/scottidler/claude"}
```
Observed:
```json
{}
```
Also allowed: `"git" tag -fa v1 -m moved`, `"git" checkout -b fix/x`, `"gh" pr create ...`, and `"manifest"`.

**Critical: process substitution bodies are executed by Bash but never yielded by `stmts`.**
`lib.sh` yields `$()`, backticks, and `*-c`, but not `<(...)` or `>(...)`: [lib.sh](/home/saidler/repos/scottidler/claude/HOME/.claude/hooks/lib.sh:73), [lib.sh](/home/saidler/repos/scottidler/claude/HOME/.claude/hooks/lib.sh:87). `git-release-guard.sh` then sees only outer `echo`, not the inner `git`: [git-release-guard.sh](/home/saidler/repos/scottidler/claude/HOME/.claude/hooks/git-release-guard.sh:349).

Repro JSON:
```json
{"tool_name":"Bash","tool_input":{"command":"echo <(git push origin --tags)"},"cwd":"/home/saidler/repos/scottidler/claude"}
```
Observed current:
```json
{}
```
Baseline `8ee8f60` denied the same input with the `git push --tags` reason, so this is a regression.

PROBE: `jq -n --arg c 'echo <(git push origin --tags)' --arg cwd "$PWD" '{tool_name:"Bash",tool_input:{command:$c},cwd:$cwd}' | bash <(git show 8ee8f60:HOME/.claude/hooks/git-release-guard.sh)` denied; the same command piped to `bash HOME/.claude/hooks/git-release-guard.sh` returns `{}`.

**High: one-line function definitions hide executed git commands.**
`stmts` splits on `;` without understanding function bodies: [lib.sh](/home/saidler/repos/scottidler/claude/HOME/.claude/hooks/lib.sh:376). `f(){ git push origin --tags; }; f` executes the inner push when `f` is invoked, but current guard allows it.

Repro JSON:
```json
{"tool_name":"Bash","tool_input":{"command":"f(){ git push origin --tags; }; f"},"cwd":"/home/saidler/repos/scottidler/claude"}
```
Observed current:
```json
{}
```

PROBE: baseline `8ee8f60` denied `f(){ git push origin --tags; }; f`; current returns `{}`.

**High: Phase 9 is not complete despite the doc status saying Implemented.**
Phase 9 requires post-merge live shakedown and tracker flip: [guard-precision.md](/home/saidler/repos/scottidler/claude/docs/design/2026-09-13-guard-precision.md:376). Implementation notes say the post-push rerun and tracker flip remain: [implementation-notes.md](/home/saidler/repos/scottidler/claude/docs/design/2026-09-13-guard-precision-implementation-notes.md:280). Tracker still says chunk B is `building`: [setup-audit-program.md](/home/saidler/repos/scottidler/claude/docs/design/2026-09-13-setup-audit-program.md:33). This contradicts the status line: [guard-precision.md](/home/saidler/repos/scottidler/claude/docs/design/2026-09-13-guard-precision.md:5).

**Completeness Walk**

Phases 0 to 8 are broadly wired: `lib.sh`, five sourcing guards, branch guard, `rewrite-cd-read.py` strip, preflight, resolver, settings registration, text fixes, and `.otto.yml` exist. Phase 9 is not complete.

Data Model status:
- Maskers preserving inert spans: partial. Single quotes, comments, heredocs mostly hold, but quoted command words prove the command-word model is incomplete.
- Nested `$()`, backticks, `bash|sh|zsh -c`: verified by tests and probes.
- Process substitution: missing, and it is executable.
- Option gates do not mask double quotes: verified.
- `mask_optarg` excludes `-C`: verified at [lib.sh](/home/saidler/repos/scottidler/claude/HOME/.claude/hooks/lib.sh:267).
- `flag_value` raw, no bash offsets: implemented in awk.
- `cd_at` vs `cd_target`: implemented.
- Secret guard masks single quotes and escaped `$`, not double quotes: verified by tests.

Acceptance Criteria:
- AC1: verified.
- AC2: verified.
- AC3: partially verified by direct probes; full self-test could not run because this sandbox is read-only and fixture setup failed.
- AC4: direct probes verified; full matrices could not run for the same sandbox reason.
- AC5: code-path verified with `REWRITE_CD_READ_LOG=/dev/null`; I did not mutate the live log.
- AC6: `bin/hooks-resolve` verified; interactive SessionStart fixture not re-run.
- AC7: verified.

**Architecture / Systemic**

The shared parser is now the single point of enforcement, which is the intended architecture, but that makes parser correctness existential. The current parser handles several shell constructs, but not enough of Bash’s executable grammar to be the gate for irreversible operations. The most important missing cases are quote removal on command words, process substitution, and function bodies.

**Product Utility**

This is directionally useful: dead-hook checks, cwd handling, `git -C` rewrite, branch-name enforcement, and release-flow text are real improvements. But with the bypasses above, the enforcement layer is not yet trustworthy for the user’s highest-value safety goal: preventing irreversible git actions. The implementation should not ship as complete until those parser gaps are closed and Phase 9 is actually run.
---

# [SYNTHESIS]

Verdict: **NOT ready to close.** The chunk delivers its spec: all seven
acceptance criteria pass when run verbatim, every Phase 0 to 8 bullet is
implemented, all seven test matrices exit 0, `otto ci` is green, and the
implementation notes disclose 26 deviations with reasons. But the Phase 3
`cmdword_is` anchor, combined with a `stmts` splitter that does not understand
compound-command syntax, turned **22 measured DENY verdicts into ALLOW** across
three guards, including every irreversible-operation gate. That class is not in
the doc's allowed set of behavior changes. Until it is closed, the enforcement
layer is more precise and less safe than the one it replaces.

## Convergence: both seats found the same root cause independently

Both reviewers, on different models, with no shared context beyond the prompt,
landed on the same finding as their top severity: the command-word anchor
un-gates every guard for any command where `git` is not the first word of a
statement `stmts` yields. The staff engineer reached it through process
substitution and function bodies; the architect substitute reached it through
brace groups, `eval`, and wrapper verbs. Both cited `lib.sh:416` (`cmdword_ok`)
and `lib.sh:376` (`split_one`). Convergence on a security finding across two
independent reviewers is the strongest signal this panel produces.

## Must-fix

### MF1 (CRITICAL, deny bypass and undisclosed regression): the command-word anchor un-gates every guard for compound commands

`cmdword_ok` at `HOME/.claude/hooks/lib.sh:416-422` tests a statement against
`^(VAR=..)*((command|builtin|exec|sudo|env)[ \t]+)*(/?[^ \t]*/)?<word>([ \t]|$)`.
`split_one` at `HOME/.claude/hooks/lib.sh:376-399` splits only on
`; \n & | && ||`. So `{`, `(`, `if`, `then`, `do`, `else`, `while`, `until`,
`for`, `case ... )`, `!`, `time`, `coproc`, a leading backslash, `eval`, and any
wrapper verb outside the five allowed ones sit in front of the verb, the anchor
fails, and the gate never runs. This is the single precondition on 14 gates in
`git-release-guard.sh` (`:304,314,325,349,352,390,396,409,455,459,493,561,567,583`),
2 in `branch-name-guard.sh` (`:144,156`), 1 in `branch-pr-title-guard.sh` (`:141`),
and 1 in `manifest-scope-guard.sh` (`:31`).

22 measured baseline-deny to current-allow flips are in `probes.md`. The ones
that matter most:

```
jq -nc --arg c '{ git reset --hard; }' --arg cwd "$PWD" \
  '{tool_name:"Bash",tool_input:{command:$c},cwd:$cwd}' \
  | bash HOME/.claude/hooks/git-release-guard.sh
# current: {}    baseline 8ee8f60: permissionDecision deny
```

Same shape allows `{ git push --force origin main; }`, `\git tag -d v1`,
`eval "git push origin --tags"`, `timeout 5 git push origin --tags`,
`if true; then git reset --hard; fi`, `for x in 1; do git push origin --tags; done`,
and `f(){ git push origin --tags; }; f`.

Why it is UNDISCLOSED. The design's Data Model justifies the anchor on four
named false positives, all of them prose or a non-git command word. The Phase 4
implementation notes disclose one extra class: "prose naming a git operation
inside a message-flag value, or outside command position, no longer trips a
gate," with the example `git commit -m "explain git restore --staged in the docs"`.
`{ git reset --hard; }` is not prose. Bash runs it. Nothing in the doc or the
notes says a brace group, an `if`, or `eval` now passes. Under the owner's
standard that undisclosed deviations are the primary finding class, this is it.

Why the tests did not catch it: zero of the 402 matrix cases wrap a gated command
in any compound-command syntax.

```
grep -cE 'eval |\{ git|\( git|if true|timeout |<\(' HOME/.claude/hooks/*-test.sh
```
returns zero hits across every matrix.

### MF2 (CRITICAL, deny bypass and undisclosed regression): process substitution is neither yielded nor neutralized

`scan()` at `HOME/.claude/hooks/lib.sh:79-116` has cases for `$(`, backtick,
`<<<` and `<<`, and none for `<(` or `>(`. Bash executes a process-substitution
body, so under the Data Model's own rule it must become a nested statement. It
does not, and the span is not neutralized either.

```
jq -nc --arg c 'echo <(git push origin --tags)' --arg cwd "$PWD" \
  '{tool_name:"Bash",tool_input:{command:$c},cwd:$cwd}' \
  | bash HOME/.claude/hooks/git-release-guard.sh
# current: {}    baseline 8ee8f60: deny
```
`echo >(git push origin --tags)` behaves identically. This is a distinct code
site from MF1 and needs its own fix, though both seats reported them together.

### MF3 (HIGH, secret leak regression): `find_dashc` matches only the exact token `-c`, so `bash -lc` escapes

`HOME/.claude/hooks/lib.sh:344-356` requires `tokword(s,k) == "-c"`. A combined
short flag is not recognised, so the body is neither yielded nor neutralized.

```
jq -nc --arg c "bash -lc 'echo \$GH_TOKEN'" --arg cwd "$PWD" \
  '{tool_name:"Bash",tool_input:{command:$c},cwd:$cwd}' \
  | bash HOME/.claude/hooks/secret-echo-guard.sh
# current: {}    baseline 8ee8f60: deny
```

Narrowing the substitute's claim: this fires ONLY when the `-c` body is
single-quoted. `bash -lc "echo $GH_TOKEN"` and `bash -xc "echo $GH_TOKEN"` still
deny, because the raw double-quoted `$GH_TOKEN` is visible to the matcher without
any nesting. `bash -c` and `sh -c` in both quotings still deny. The substitute
stated it more broadly than the code behaves.

### MF4 (HIGH, contract violation, pre-existing but now structural): `mask_heredoc` erases unquoted heredoc bodies, which bash expands

`HOME/.claude/hooks/lib.sh:94-142`. The Data Model justifies the masker with
"heredoc bodies redirected to a file ... are inert." Neither condition is tested:
the delimiter's quoting is discarded at `:102-103` and there is no redirect check.

```
jq -nc --arg c "$(printf 'cat <<EOF\n$GH_TOKEN\nEOF')" --arg cwd "$PWD" \
  '{tool_name:"Bash",tool_input:{command:$c},cwd:$cwd}' \
  | bash HOME/.claude/hooks/secret-echo-guard.sh
# current: {}
```

Bash expands `$GH_TOKEN` in an unquoted heredoc and `cat` prints it to the
transcript, which is precisely the vector `secret-echo-guard.sh:13-18` says it
exists to catch. Correcting the substitute: this is NOT a regression. Baseline
`8ee8f60` also allowed it (the old guard printed nothing on its pass path). It
is a pre-existing gap that the new masker now makes structurally unreachable,
and it breaks the doc's own stated masking rule. The quoted form `cat <<'EOF'`
is genuinely inert and should stay masked; the unquoted form should not be.

## Cheap wins

- **CW1 (MED, pre-existing, NOT a regression): quoted and escaped command words.**
  `"git" push origin --tags`, `"git" tag -fa v1 -m moved`, `"git" checkout -b feat/x`,
  `git push origin --ta""gs` and `git push origin -"-tags"` all ALLOW. Verified
  against the baseline: it allowed them too, so this is not something this chunk
  broke. Correcting the staff engineer, which presented it as the top new finding.
  It IS a live bypass and belongs in the same fix as MF1, since both are
  "cmdword_ok does not model quote removal." The one escaped-verb spelling that
  IS a regression is `\git tag -d v1` (baseline deny, current allow), because the
  baseline's unanchored regex matched the `git` substring.
- **CW2 (LOW): `cmdword_ok` accepts env assignments in one order only.**
  `lib.sh:420` puts the assignment group before the wrapper group, so
  `X=1 env git push` matches and `env X=1 git push` does not. The Data Model
  says both prefixes are allowed; it does not say they are ordered.
  Verified: `printf '%s' 'env X=1 git push' | cmdword_is git` returns 1.
- **CW3 (LOW): `branch-name-guard.sh` misses the attached short-flag spelling.**
  `git checkout -bfix/x` is valid git and returns `{}`. The token comparison at
  `branch-name-guard.sh:104-135` tests for an exact `-b`/`-B`/`-c`/`-C`. Every
  other API Design shape verified correct.
- **CW4 (LOW): the preflight's remediation string tells the operator to run the
  glob the notes call wrong.** `HOME/.claude/hooks/hooks-preflight.sh:42` emits
  `manifest -l HOME/.claude/hooks/* | bash`. The implementation notes and the
  doc's Rollout Plan were both updated to `HOME/.claude/hooks/*.sh HOME/.claude/hooks/*.py`
  after the bare glob linked `__pycache__/*.pyc`. The hook's own string was not.
- **CW5 (LOW): `.otto.yml` lint list omits three files this branch touched.**
  `docs/design/2026-09-13-guard-precision.md`, its implementation-notes sibling,
  and `2026-09-13-guard-precision-phase0/evidence.md`. Phase 8's bullet says
  "add this chunk's touched files to the lint em-dash list." Measured: all three
  are em-dash-clean today, so the gate is latent, not failing. Every non-docs
  touched file IS listed, so there is no chunk-A-style M3 drift on the code.
- **CW6 (LOW): two new test files are not executable.**
  `branch-name-guard-test.sh` and `branch-pr-title-guard-test.sh` are `-rw-rw-r--`;
  the other eight matrices are `775`. Harmless because `.otto.yml` invokes
  `bash "$t"`, but inconsistent.

## Defer

- **D1 (LOW): doc and tracker disagree.** The design doc Status reads
  `Implemented`, all seven acceptance-criteria checkboxes are still `[ ]`, and
  the program tracker row at `docs/design/2026-09-13-setup-audit-program.md:33`
  still reads `building`. The Status line scopes itself to Phases 0 to 8 and the
  implementation notes state plainly that "the post-push re-run and the tracker
  flip are the remaining Phase 9 work," so this is disclosed and internally
  consistent, not drift. Nothing is pushed yet, so Phase 9 genuinely cannot
  complete. It closes when the branch lands. Both seats raised it; neither
  treated the disclosure as sufficient, and it is.

## What verified clean (no unattributed buckets)

Run by the orchestrator, not taken from either seat.

- **All 7 acceptance criteria pass.** AC1: the sourcing grep returns exactly the
  five named guards, `lib-test.sh` rc=0. AC2: both prose fixtures return `{}`.
  AC3: `git-release-guard.sh --self-test` rc=0 and all six named verdicts flip
  as specified. AC4: the `gh pr create` denial text contains `git branch -m`,
  `git checkout -b fix-auth-bug` allows, both matrices rc=0. AC5: the strip
  emits `updatedInput` with a `STRIP-C flag-pointed-at-cwd` log line and no
  `permissionDecision`; `git-no-dash-c.sh` is gone from the tree and from
  `settings.json`. AC6: `bin/hooks-resolve` rc=0. AC7: the frontmatter awk prints
  only `voice.md`, and both stale-release-flow greps return nothing.
  AC6's interactive half was not re-run; the notes record it with the model's
  verbatim quote. Marked [UNVERIFIED by this panel].
- **All 7 test matrices exit 0** and `otto ci` prints "All CI checks passed!".
- **Library degradation contract HOLDS.** Missing, empty, syntax-broken, and
  stubbed `lib.sh` all produce `{}` from all four tested guards, never a deny.
  Full matrix in probes.md. Stderr noise in the empty and stub cases only.
- **`--body-file` expansion never evals.** Both a `$(touch ...)` and a backtick
  payload were fed through; neither created its file. `git-release-guard.sh:523-530`
  is pure parameter substitution.
- **Design contract on double quotes holds.** `git push origin "--tags"` and
  `git push origin '--tags'` both still deny. This was the round-1 finding the
  doc says drove the whole no-mask-quotes rule, and it is honored.
- **Nested `$(...)` yielding works.** `echo $(git push origin --tags)` denies via
  the nested statement.
- **`settings.json` registrations correct.** `branch-name-guard.sh` appended to
  the Bash array, `git-no-dash-c.sh` absent, `hooks-preflight.sh` on SessionStart.
- **The `test` task runs every matrix plus the resolver.** `.otto.yml` globs
  `HOME/.claude/hooks/*-test.sh` and then invokes `bin/hooks-resolve`.
- **All five guards source `lib.sh` defensively** with the identical
  `. "$(dirname "$0")/lib.sh" 2>/dev/null || { echo '{}'; exit 0; }` line.
- **26 recorded deviations walked.** Every one is disclosed with a reason and
  none misstates what the code does. MF1 through MF3 are the undisclosed drift.
- **Gate table verified**: tag force including `-fa`, off-main tag creation,
  `git tag --contains HEAD` allowed as list mode, `git tag -d` still denied,
  Gate C on `chore/bump-0.9.0`, path-scoped revert allow with `.`, `:/`, `*`
  and `$` all refused, `git restore --staged` and `--source=` denied,
  `git clean` gated on untracked count per statement worktree.

## Architecture and systemic

- **S1. `cmdword_ok` is the wrong shape for the load it now carries.** It is a
  prefix regex over an unparsed statement, lifted from `block-draft-pr.sh:42`
  where it guarded one command, and generalized to 18 call sites where it is the
  single load-bearing precondition on every irreversible-operation gate. The
  library already has a per-byte class map and a tokenizer, which is enough to
  answer "is token 1 the verb, after skipping assignments, wrappers, `{`, `(`,
  `do`, `then`, `else`, `!`, `time`" structurally. That is the fix, not more regex
  alternatives. Both seats reached this independently.
- **S2. The 113-case matrix validated the refactor it was written for, not the
  class the refactor moved.** Phase 3's swap-then-gate split was correct and the
  matrix proves no pre-existing expectation moved. It says nothing about inputs
  no pre-existing case covered, which is exactly where the anchor's blast radius
  lives. The structural remedy is a differential harness: replay every matrix
  command through the baseline hook and diff verdicts, plus a shape-mutation pass
  wrapping each in `{ }`, `( )`, `eval`, `if`, and `timeout`. That single run
  produces every finding in MF1 and MF2. It also matches the owner's standard
  that a regression test must make the bug class unable to recur, rather than
  pinning ten more cases.
- **S3. The consolidation itself is sound and worked.** One quote model, five
  consumers, one library, fail-open on the parser and fail-closed on the verdict,
  honored in every direction checked. The mid-build discovery that every ported
  guard was silently inert through the symlink path is the strongest argument in
  the chunk for `hooks-preflight.sh` existing, and it was captured as a rule for
  later chunks rather than fixed and forgotten.

## Product utility

Net positive on precision, net negative on coverage, and the two are not
separable while MF1 stands.

Better: the three measured false-positive classes are gone, each confirmed. The
`git -C` deny became a silent rewrite that also catches the two shapes the old
lookbehind missed. The title guard's denial now names a satisfiable fix instead
of an impossible one, which is the highest-value text change in the chunk.
`branch-name-guard.sh` closes the slashed-branch class at creation, where it
costs one round trip instead of four. The preflight and `bin/hooks-resolve` pair
kills the dead-hook class and proved itself during the build.

Worse: an agent that writes `{ git reset --hard; }`, `eval "git push --tags"`, or
`for r in ...; do git reset --hard; done` now runs it unguarded. Models reach for
brace groups, `eval`, and `for` loops routinely, and multi-repo sweeps are exactly
where an unguarded `reset --hard` costs the most. The gates that matter most were
unanchored regexes on `8ee8f60` and are now anchored, so the chunk traded a
measured false-positive rate for an unmeasured false-negative rate on its own
irreversible-operation surface.

## Counts

must-fix 4 (MF1 CRITICAL, MF2 CRITICAL, MF3 HIGH, MF4 HIGH)
cheap-win 6 (CW1 MED, CW2 to CW6 LOW)
defer 1 (D1 LOW)
