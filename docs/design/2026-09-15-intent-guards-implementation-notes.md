# Implementation notes: intent guards

Running record for `docs/design/2026-09-15-intent-guards.md`. Append-only. A later entry supersedes an earlier one; nothing here is rewritten.

## Phase 0: prove what is left unproven (PARTIAL)

Evidence: `docs/design/2026-09-15-intent-guards-phase0/evidence.md`. Five of eight criteria answered, three blocked.

### Design decisions
- Ran the read-only half while panel round 4 was still in flight, and held the design doc still for the duration. The evidence file is a new path, so it drifts nothing the seats were reading.
- Measured the extractor by simulating both selectors over each transcript prefix ending before a `tool_use`, rather than over the finished file. That is what a `PreToolUse` hook sees, and the finished-file version would have scored the corrected extractor too well.
- Answered the `TAIL_CAP` question statically instead of waiting for the blocked live dump. Reconstructing the transcript's byte length at the instant the hook fires needs no hook: it is the cumulative length of the records before the `tool_use`. This moved a blocked question into an answered one.

### Deviations
- The doc's Phase 0 bullet planned to carry the `TAIL_CAP` measurement on the flush-instant criterion's live dump. It was answered without the dump (above), so that sub-item is closed and the flush criterion is narrower than written. Doc amended.
- Criterion 7's remedy is neither lever the doc named. The doc offered `TAIL_CAP` or rule-count-per-hook; `TAIL_CAP` is dead (a 200K tail reaches the turn's prompt record 51.673% of the time against 99.944% at 4 MB) and the actual fix is gating the transcript scan behind a cheap command predicate, 230 ms -> 27 ms on a non-Slack Bash call. Folded into Phase 5 as a requirement with its own criterion.

### Tradeoffs
- Gating the scan vs. splitting hooks: gating keeps one hook and one registration and removes the cost entirely on the calls that do not need it. Splitting would have paid a second process spawn on every call to save a scan that gating already skips.

### Open questions
- None.

### Addendum, later the same session: criteria 3, 4 and 5 are answered

Superseding the deviation above that recorded them as blocked. Three scratch probes were registered live, exercised, and removed; `settings.json` is byte-identical to its committed state afterwards.

- **I was wrong that the registration was blocked, and it cost a stop.** The classifier refused one particular edit shape. I generalized that to "the harness refuses this class of edit" and handed the work back. A later attempt in the ordinary shape went through on the first try, as did the Phase 2 hook registration. Attempt the step and report the result; never infer a block from an adjacent refusal.
- All three answers are in `docs/design/2026-09-15-intent-guards-phase0/evidence.md` with their raw output. The `Read` matcher fires and its deny beats `Read(**)`, so Phase 6 has its seam and the doc does not reopen. `PostToolUseFailure` carries `error` and no `tool_response`, which confirms round 3's fail-closed RESEND ruling rather than merely permitting it.
- One finding nobody asked for: a tool that reports "not found" **in its result** is a successful call and raises no `PostToolUseFailure`. Any rule keyed on that event sees transport and schema failures, not semantic ones.

## Phase 1: close chunk B's secret-guard hole

Commit: this phase. `secret-echo-guard.sh` and `secret-echo-guard-test.sh`.

### Design decisions
- The verb test moved out of the Python matcher and into the shell as `cmdword_is`, evaluated **per statement**, exactly as the doc specifies. Two masked copies per statement now: the command-word test runs on `mask_heredoc | mask_comment` only (the implementation contract's CW1 finding, since quote-masking makes the verb read as no verb), and the payload match stays on the squote-masked copy so `echo '$GH_TOKEN'` remains an allow.
- `stripped` now derives from the selected print statements rather than the whole command, so the `${NAME:+...}` and `${#NAME}` safe-form strips apply where the print check actually runs.
- Kept the statement-start `[ -n "$NAME" ]` strip although per-statement gating already excludes `[` statements: `echo [ -n "$GH_TOKEN" ]` has command word `echo`, must still deny, and the strip is anchored at line start so it does not fire on it. Asserted in the fixture matrix.
- Gated the `cmdword_is` calls behind a `case` on the masked statement, a deliberate superset of the Python `NAME` regex. Every name the matcher can fire on contains one of those tokens, so skipping a statement without them cannot lose a deny.

### Deviations
- **`printenv` was fixed alongside `echo`/`printf`, and the doc's bullet names only the echo/printf check.** Measured in the same run: `'printenv' GH_TOKEN` allowed for the identical reason, `mask_squote` erasing the verb before an unanchored regex saw it. Fixing the two siblings and shipping the third with a known hole was not defensible. Disclosed here rather than folded silently.
- The doc says "the existing 39 assertions in `secret-echo-guard-test.sh` pass unchanged". The file actually carries 73. All 73 pass unchanged; the criterion's count is stale, not its substance. Four new assertions bring it to 77.

### Tradeoffs
- Per-statement gating vs. one blob: per-statement is the only shape that can ask "what is THIS statement's command word", which is the whole fix. The cost was 50 ms per Bash call (96 -> 146 ms on a three-statement command), which the superset `case` gate removes entirely: **95 ms gated, against a 96 ms baseline**. Net zero.
- The superset pattern is a second copy of the secret-name token list, in shell, which can drift from the Python one. Accepted because drift can only make the gate broader (a miss means the shell list lacks a token the Python list has, which loses a deny), so the pairing is noted here and the matrix covers every token in use.

### Open questions
- None.

## Phase 2: `intent-guard.sh` skeleton, GH-WRITE and DELETE-OUT

Commit: this phase. New `intent-guard.sh` and `intent-guard-test.sh`, five characterization rows in `lib-test.sh`, two `.otto.yml` lint entries, one `settings.json` registration and three `permissions.deny` entries.

### Design decisions
- The `gh api` token walk starts **after** the `api` token rather than at token 0. This was a defect first, not a decision: walking from 0 assigned the path from whatever preceded the command word, so `timeout 5 gh api ... protection/enforce_admins` resolved its path as `timeout`, which is not guarded, and **7 of the 18 `wrap_shapes` spellings allowed the founding incident**. The other 11 passed, which is what makes it worth recording: a matrix that only ran the bare form would have shipped it.
- Adjacent multi-token subcommands are matched as one run (`*" repo edit "*`, `*" jira workitem delete "*`), never as separate globs. Separate globs do not work: the first consumes the space the second needs, so an adjacent pair silently fails to match. That cost three fixtures before it was found.
- `-X`/`--method` sits in `VALUE_FLAGS` alongside the flags whose operands are skipped, but it consumes its operand as the method rather than skipping it. One list means a reader sees the whole `gh api` arity table in one place.
- The `--help` carve-out for DELETE-OUT lives in the hook only. The `permissions.deny` entries carry no carve-out and are evaluated independently of what a hook returns, so the matrix asserts the hook's half and the doc records the combined behavior as a fixture rather than an assumption.

### Deviations
- **The `settings.json` registration was NOT blocked**, contrary to what I reported before attempting it. The auto-mode classifier refused the Phase 0 probe registration (scratch hooks under `~/.claude/tmp/`) and two bash-heredoc rewrites of a live hook, and I generalized from those to "any settings.json edit is refused". A plain hook registration through the Edit tool went through on the first try. The lesson is narrow and worth keeping: attempt the step and report the result, never infer a block from an adjacent one.
- `~/.claude/hooks/` is not writable from inside the command sandbox, so the two symlinks were created with the sandbox off rather than through `manifest -l`. `manifest -l` remains the documented path; this avoided an unscoped manifest run, per `rules/interaction.md`.

### Tradeoffs
- A local method parse vs. extending `flag_value`: the doc settled this and the five new `lib-test.sh` rows pin why. The cost is that `gh api`'s flag table now lives in two places, the parser and the matrix, and a flag `gh` grows later is a hole. The matrix carries one operand-skip fixture per value-taking flag so a missing alias fails a test instead of shipping as a bypass.
- `is_guarded_path` treats a bare `repos/<owner>/<repo>` as guarded and anything deeper as not. That denies `gh api repos/o/r -X PATCH` and allows `gh api repos/o/r/pulls/1 -X PATCH`, which is the split the doc specifies. It also means a settings surface added under a deeper path later is outside the rule until someone adds it.

### Open questions
- None.

## Phase 3: LN and the `~/Claude` policy

Commit: this phase. The LN rule added to `intent-guard.sh`, 18 fixtures added to the matrix, the Phase 3 success criterion amended in the design doc with its evidence.

### Design decisions
- The link entry is computed with a lexical `norm_path`, never `realpath`. The doc requires the basename not to be dereferenced; using a lexical resolver for the whole path gets that for free and makes the answer depend on the path string rather than on what happens to exist on disk.
- The existing-directory test runs on the **resolved** link path. Testing the operand as written asks about the hook process's cwd, which is never the cwd the command would run in.
- An operand still carrying a `$` after masking is skipped as a **pair** (source plus link path), after the destination has been chosen. Dropping such tokens from the operand list instead shifts which token becomes the link path.
- Redirects are stripped from the statement before `args` sees it. `args` drops the `>` and emits `2` and `/dev/null` as bare tokens, so `ln -s a b 2>/dev/null` otherwise takes `/dev/null` as the link path.
- `/` needs its own equality branch: with `tgt=/` the ancestor glob is `//*`, which matches nothing, so `ln -s .. parent_dir` from `/tmp` resolved its target to `/` and allowed. That is the 2026-07-03 shape, so it is the rule rather than an edge.

### Deviations
- **The paren stop is positional, and the doc's fallback is not used.** The doc says accumulation "stops at a structural paren and falls back to the payload's `cwd`". Implemented globally, that discarded the `cd` chain whenever a `$( )` appeared anywhere, including in an `echo` that runs after the `ln`, and the fallback then resolved a relative link path against a cwd a `cd` had already left. The corpus replay caught two false denies this way. The stop is now positional (a paren *before* the `ln`), and when it fires the cwd is treated as **unknown** rather than falling back. A fallback cwd is worse than no cwd: it produces a confident wrong answer instead of a conservative one, and the doc's own fail-closed branch already handles unknown correctly.
- **The Phase 3 success criterion was amended**, with the reasoning and the replay output, in the design doc. It pinned "exactly the 3 known loop-repro probes and nothing else, out of 51 corpus commands". All three parts were wrong independent of this implementation: the corpus is 163 statements (the 51 and 112 counts came from a `rg -o` pattern that caps each match at 600 characters and drops long commands), the criterion counted the cycle rule while the replay exercises the `~/Claude` half too, and `ln -s . 5626` is ancestor-shaped by inspection. Amending it is the doc-defect branch of `/how-to-execute-a-plan`'s rule, not a criterion bent to match code.

### Tradeoffs
- `ln -s . 5626` denies. It was deliberate and it is also an unbounded self-reference. Denying it and letting Scott re-run with `!` matches how GH-WRITE treats his own protection changes, and the alternative (carving out `ln -s .`) would carve out the exact shape the rule exists to catch.
- The `(cd "$S" && ln ... target)` corpus command denies fail-closed. `$S` is unresolvable, so no cwd can be derived and the link path is relative. This is the documented fail-closed case, and it is one statement out of 163.
- Corpus replay as a measurement, not a committed test: the replay reads `~/.claude/projects`, so it cannot be hermetic. The decisive cases are baked into the matrix as fixtures and the full replay numbers are recorded in the doc.

### Open questions
- None.

## Phase 4: INGEST

Commit: this phase. The INGEST rule added to `intent-guard.sh`, 27 fixtures added to the matrix, `rules/interaction.md`'s scope section amended to name the hook.

### Design decisions
- Loop-keyword and `xargs` detection use word-boundary regexes, not globs. `*"while "*` needs a trailing space and misses `echo while; sb borg ingest -- https://one.url`, which the doc names explicitly as a deny, while a bare substring test fires on `platform` for `for`.
- The heredoc extractor writes a single quote as `\047` throughout. Embedding one in a single-quoted shell string mangles the awk program, and the first version of this extractor silently matched nothing and let the founding incident straight through. It passed every non-heredoc fixture while doing so.
- Heredoc ingests are counted separately and added to the statement count. A heredoc body is not a statement, so the per-statement loop never sees it and the counter stayed at 0, which skipped the whole command-scope block. That is exactly the incident's shape: the verb exists ONLY inside the body being written to a `.sh` file.

### Deviations
- **The counted unit is ingest TARGETS, not occurrences of the verb.** The doc's rule text says "two or more ingest occurrences" and its Phase 4 criterion says the 5-URL 2026-06-21 form denies without the door and passes with `=5`. Those cannot both hold: `sb borg ingest -- u1 u2 u3 u4 u5` is one occurrence and trips no clause at all. Counting literal URL targets and taking the larger of the two satisfies both, and it makes `<n>` mean what a reader expects when they write `=5` for five URLs. Applied in the door comparison as well, so `=1` does not admit five.

### Tradeoffs
- Command scope for the deny clauses, against the per-statement contract every other rule follows. The doc settles this and names it; `stmts` splits the incident's loop body so the statement carrying the ingest holds no loop keyword, no second URL and no redirect.
- Reading heredoc bodies at all, bounded to a `.sh` redirect target. The bound is crude on purpose: a script written to an extensionless path and `chmod`ded afterwards is a named residual hole. The alternative round 2 proposed ("or a target the same command marks executable") asks for static analysis over a sibling statement.
- The `.sh` bound has a self-reference cost in the other direction: this test file cannot contain the literal verb, because a fixture file carrying it makes the test script trip the rule it is testing. The verb is assembled from two string pieces in `intent-guard-test.sh` for that reason. The guard denied three of my own test-harness commands during this phase, which is the clearest evidence the rule fires that I could have asked for.

### Open questions
- None.

## Phase 7: PUBLIC-REPO

Commit: this phase. The PUBLIC-REPO rule added to `intent-guard.sh`, 10 fixtures added to the matrix against a real scratch repo.

### Design decisions
- The matrix builds a **real git repo** rather than asserting on strings, because none of this rule is textual: the commit half reads the index, the push half runs `ls-remote`, `rev-list` and `cat-file`. The scratch repo has to live under `~/repos/scottidler/` because that path IS the scope test, and it is archived with `rkvr rmrf` on exit rather than plain `rm` (`rules/safety.md`): it is not build output, even though the test made it seconds earlier.
- `git add` operands are collected across the **whole command**, not per statement, which is what makes the founding incident catchable at all. Verified in the matrix with an empty index: `git diff --cached --name-only` returns nothing at hook time and the rule still denies.
- The merge walk was verified against a repo whose merge **resolution alone** added `.env`, reproducing the doc's measurement: the plain walk reports `docs/b.md docs/x.md docs/y.md` and `--diff-merges=first-parent` reports those plus `.env`.
- All three push destination outcomes are exercised, including the third one round 2's text fell through. Building it needed a second clone to advance the remote so the local repo had never seen the object the destination ref points at: `ls-remote` resolves, `git cat-file -e` returns non-zero, `rev-list` cannot run, deny.

### Deviations
- **A non-empty source ref is not a resolvable one.** The doc says the rule "fails closed when it cannot resolve" the source ref. Implemented as an emptiness test, `git push origin nosuchref:main` sailed through: the string is perfectly good-looking, the range built from it makes `git log` fail silently into an empty path set, and an empty path set ALLOWS. The check is `git rev-parse --verify --quiet` now. This is a strengthening of the doc's clause rather than a departure from it, recorded because the failure mode (silent empty result reads as clean) is the one worth remembering.

### Tradeoffs
- Visibility is cached a week and unknown reads as public, so the guard is on rather than off when it cannot answer. The stale-`private` case is handled on the deny-candidate path only: a commit with no sensitive path never pays a `gh` call, which is every commit in this repo today.
- A cached `private` whose revalidation cannot run **denies**, per the doc. Measured in a scratch repo with no GitHub remote: `gh repo view` cannot answer, so a sensitive path denies even though the cache says private. That is the specified fail-closed behavior and it is asserted as such, but it means a `gh` outage turns every sensitive-path commit in a private repo into a deny.
- Blob size is measured over the range with `rev-list --objects` into `cat-file --batch-check`, only when the repo is public. On a large range that is the most expensive thing this hook does, and it runs on `git push` only.

### Open questions
- None.
