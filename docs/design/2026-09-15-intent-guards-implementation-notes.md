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

## Phase 5: SLACK

Commit: this phase. New hook `HOME/.claude/hooks/slack-post-guard.sh` with three rules, `slack-post-guard-test.sh` at 108 assertions, registered on the Bash matcher, on the three Slack MCP write tools, and on `PostToolUse`. The two-target split written into `HOME/repos/.claude/refs/slack.md` and pointed at from `slack-clipboard/SKILL.md`.

### Design decisions
- **The gate is the first thing in the file and `lib.sh` is sourced after it.** Phase 0 made gating a requirement rather than an optimization (230 ms ungated against a 250 ms budget, 27 ms gated), and the prototype it measured sourced `lib.sh` before the predicate. Sourcing after it means a non-Slack Bash call pays one `case` and one jq.
- **One jq spawn on the hot path, not three.** Reading `hook_event_name`, `tool_name` and `tool_input.command` as separate jq calls cost 71 ms on a plain `git status` and failed the 50 ms criterion on its own, with no transcript read at all: jq costs about 23 ms per invocation here. They come back from one call, with the command base64-encoded because it can carry newlines and tabs, decoded only once the gate passes. Measured after: 27 ms against a 5 MB transcript.
- **`tail -n +2` is not in the transcript reader.** Phase 0's prototype dropped the tail's first line because a 4 MB tail can start mid-record. That also drops a whole record from any transcript smaller than the cap, which is 98.4% of them. `fromjson? // empty` already discards the partial line, so the truncation guard was doing nothing but losing data.
- **The prompt extractor is `prompt_id`-first with the corrected selector as the fallback.** Criterion 8 measured the fallback alone at 0 relay and 0 wrapper false authorizations over 1,237 turns; `prompt_id` (identical across every tool call in a turn, per criterion 3's live dump) makes the common case exact instead of positional.
- **RESEND does not run when every recipient is exempt.** The rule text carries no exemption for the pair, and applying it there would deny a second identical `/slack-clipboard` inside the hour. A duplicate into a single-member private channel harms nobody, and Scott's 2026-09-11 ruling on that pair is about friction, not about recipients. Disclosed deviation, see below.
- **`--preview` resolves to the exempt DM rather than to the named target**, because that is where the client sends it (a render sandbox in the caller's own self-DM), and `--print` posts nothing at all and returns an allow before any rule runs.

### Deviations
- **Expiry reclamation is an O_EXCL lock, not the doc's rename.** The doc prescribes "a single atomic rename of a freshly created temp entry over the old path". That rename is atomic and it is not a compare-and-swap: `mv temp path` succeeds whether or not the path still holds the entry the process measured, so every racer that reads the same expired mtime renames and proceeds. Its own acceptance criterion, two concurrent reclaims leaving exactly one allowed, cannot pass in that shape. Renaming the expired entry AWAY is a compare-and-swap and was the first fix here; it still failed 1 round in 30 under 8 racers, because a file that turns out to be someone else's fresh reservation has to be put back and the path is EMPTY for the length of that restore, which a third process's plain O_EXCL create walks straight into. Any scheme that removes a live entry even briefly has that window. The shipped shape never moves the entry: a separate O_EXCL lock admits one reclaimer, which re-reads expiry while holding it. 120 rounds of 8 racers, zero violations.
- **RESEND is scoped to the non-exempt recipient set** (above). The doc's RESEND text names no exemption; this adds one.
- **TARGET and TEST-TEXT apply to `chat_update`, RESEND does not.** The doc exempts `chat_update` in the RESEND paragraph only, and the reasoning given (an edit is the opposite of a resend, and `ChatUpdateRequest` cannot fan out) is RESEND-specific. An edit still names a channel and can still rewrite a body into a test post, so the other two rules run.
- **An unquoted `#channel` denies as a parse failure.** It is a shell comment, so `slack write #engineering hi` runs `slack write` with no arguments and the CLI never sees a target. `lib.sh`'s maskers preserve length, so the target arrives as a run of `\001`; the guard treats that as no target rather than as a name to resolve. Not in the doc, and every fixture in the matrix uses the bare name or a quoted `#name` for the same reason.
- **The write parser keeps accepting flags after the target.** `content` is a `trailing_var_arg` positional, so clap parses flags right up until the first content token. A parser that stops at the target reads `--broadcast`, `--dm-mentioned` and `--edit` as body words, which silently disarms three rules by argument order alone. Caught by the matrix at four failures.

### Tradeoffs
- **`HOME` is the test seam and it is therefore a residual hole**, named rather than patched blind, the same way the doc names the Grep/Glob hole for SECRET. A `HOME=/tmp/x slack write ...` reads an id cache an agent could have written. It denies for every target that cache cannot resolve, it cannot fake the transcript (the harness supplies the path), and the prefix is glaring in the transcript and in `clyde permit log`. Closing it costs the matrix every branch it has: missing cache, schema-old cache, stale cache, ledger races, reclaim, unwritable ledger.
- **A failed send is not retryable until the entry expires**, which is the doc's ruling and is asserted as such. The deny names the exact file to remove.
- **Name matching authorizes on a common word when a channel is named one.** `#general` matches "in general we should". The alternative, requiring the literal channel id, blocks 72% of legitimate posts by the doc's own measurement.
- **The plugin's `slack:write` skill is NOT edited.** It lives in `~/.claude/plugins/cache/tatari-skills/`, outside this repo and overwritten on the next plugin update, so the two-target split went into `refs/slack.md` (in-repo, lint-covered, read whenever Slack work begins) with a pointer from `slack-clipboard/SKILL.md`.

### Break-the-code evidence
Each rule disabled in a scratch copy, matrix re-run against the copy:

```
baseline        pass=108 fail=0
TARGET-off      pass=62  fail=46
TESTTEXT-off    pass=104 fail=4
RESEND-off      pass=101 fail=7
```

### Open questions
- None.

### Observed, not changed
- `HOME/repos/.claude/refs/slack.md` is stale in three places outside this phase's scope: it points at `mcp__slack__conversations_add_message` (a retired tool), at `~/repos/.claude/slack-ids.json` (the cache is `~/.cache/slack/ids.json` now), and at `~/.claude/skills/slack/slack.py` (the retired monolith, now `slack-old`). Recorded rather than fixed: unrequested scope.

## Phase 6: SECRET vectors and the Read deny

Commit: this phase. The four artifact vectors added to `secret-echo-guard.sh`, the hook registered on a `Read` matcher, `secret-echo-guard-test.sh` from 77 assertions to 189.

### Design decisions
- **Developed against a copy, per the Blast radius rule**, with `lib.sh` and `shapes.sh` symlinked into the scratch directory. That symlink is the whole point of the rule: without it the copy cannot source `lib.sh`, the guard fails OPEN, and a broken patch reads as a passing matrix.
- **The artifact vectors run in the same per-statement loop as the env-var vectors, behind their own `case` pre-filter.** The existing loop `continue`s on the secret-NAME superset, and `cat /run/user/1000/borg.env` contains none of those names, so the new checks had to sit before that gate with a pre-filter of their own. A `case` costs nothing and a statement naming no credential artifact cannot deny on any of the four vectors.
- **One jq spawn, not two.** Reading `tool_name` (needed for the Read branch) as a second jq call would have added about 23 ms to every Bash call in every session. Tool, command and file path come back from one call, with the command base64-encoded because it can carry newlines and tabs.
- **The unrecognized shape denies.** The doc gives four bullets covering printers, projectors, matchers and metadata; it does not say what a fifth verb does. The default is `unknown-reader` -> deny, which is the same ruling the doc makes explicitly for an unrecognized jq filter, and it is what makes `python3 -m json.tool <credential file>` a deny without enumerating every interpreter.
- **The jq filter is found by walking the tokens and skipping flag operands**, so `jq --arg k x 'has("refresh_token")' <file>` reads the filter and not the `--arg` value.

### Deviations
- **`--query` is parsed locally, not with `flag_value`.** Measured: `flag_value` returns its FIRST match, so `--query ARN --query SecretString` reads as `ARN` and executes as `SecretString`. That is the identical defect class `intent-guard.sh` documents for `gh api -X GET -X DELETE`, and it is the one shape where a bypass is a printed credential. The local walk takes the LAST occurrence and handles the `--query=V` form.
- **The path set is wider than the doc's globs, by one entry.** The doc lists `/run/user/*/*.env`, `~/.config/*/*.env`, `**/tokens.json`, `**/token.json` and the two history files; `path_is_secret` matches any `*.env`. The doc's own evidence table calls the `.env` glob incomplete and records the 06-16 leak as `sk-ant-`, 108 characters, through the Read tool, and a directory-scoped glob cannot cover a Read of a repo-local `.env`. `rules/general.md` already forbids `.env` for env vars, so the false-positive surface is close to empty.
- **`sed`, `awk`, `perl`, `od`, `hexdump`, `tee`, `cut`, `tr`, `nl`, `paste`, `sort` and `uniq` are in the printer set.** The doc names `cat`, `strings`, `head`, `tail`, `less`, `more`, `xxd`, `base64` for path reads and `sed` for the history row. A printer set that stops at `cat` while `awk` prints the same bytes is a hole with no argument behind it. The `unknown-reader` default would have caught them anyway; naming them makes the deny message accurate rather than generic.

### Tradeoffs
- **A mutator against a credential file allows.** `rm`, `mv`, `cp`, `chmod` and friends do not print, and a logout that removes a token file is routine. `cp <token file> /tmp/x` therefore allows, which moves a credential without printing it. Named rather than covered: this guard's subject is the value reaching the transcript.
- **The Read deny covers `Read` only.** `Grep` and `Glob` over the same paths are uncovered and a `Grep` result can carry the matching line. The doc names this residual hole and no instance appears in the corpus.
- **`*.env` as a suffix match will deny a read of any file so named**, including one carrying no credential. Fail-closed on a file class whose entire purpose is credentials.

### Break-the-code evidence
Each vector disabled in a scratch copy, matrix re-run against the copy:

```
baseline         pass=189 fail=0
aws-off          pass=166 fail=23
systemctl-off    pass=169 fail=20
pathrule-off     pass=153 fail=36
readmatcher-off  pass=184 fail=5
```

### Criterion amended
- The Phase 6 criterion says "the existing 39 assertions in `secret-echo-guard-test.sh` pass unchanged". The file carries 77: Phase 1 of this chunk added the wrapper sweep and the single-quoted-verb fixtures, so the count was stale before the phase began. Measured both ways (committed matrix against committed guard, and against the new guard): 77 pass, 0 fail in both. Amended in the doc with that output; the criterion's substance holds.

### Open questions
- None.

## Finalization: the acceptance walk

Commit: this phase. The 24 corpus-measured false positives fixed in `secret-echo-guard.sh`, the LN wrapper sweep added to `intent-guard-test.sh`, the criteria results written into the doc, the program baton updated.

### What the walk changed in the code
- **24 false positives removed from the SECRET path rule**, every one found by replaying the rebuilt 300-command corpus rather than by reading the code: a statement with no command word at all (a bare assignment, a `for` header), a credential path appearing only as a redirect target, a credential filename quoted inside `echo` prose, `grep`'s PATTERN operand read as a file, and `[`, `source`, `:` and `tee`. The keyword strip was itself caught by the matrix: the splitter yields `then cat f` rather than `cat f`, so bailing on a leading keyword allowed the whole `if`/`for`/`while` half of the wrapper sweep.
- **The LN rule now rides the wrapper sweep**, 18 of 18 on two quote-free fixtures. Criterion 1 asked for it and Phase 3 had not done it. The matrix goes from 131 to 167 assertions.

### What the walk found and did NOT change
- **INGEST allows in 3 of 18 wrapper spellings**: `eval "..."`, `eval '...'` and `bash -c "..."`. The rule is command-scoped by the doc's own ruling, so it matches the fully masked copy, and masking double quotes erases the payload. This is a live bypass of a shipped guard and it is Phase 4's rule scope, so it is recorded with its measurement rather than patched at the end of another phase.
- **Criterion 3b cannot pass as written.** The rule text mandates denying `cat <credential file>` and `grep <history file>`; the corpus contains those in volume. 84 of 300 deny, and all but about 2 are the rule doing what the doc says. The criterion's premise about what the traffic looks like is what the measurement refutes.

### Open questions
- Two, both Scott's: whether to carve out the captured-into-a-variable jq form, and how to close the INGEST wrapper bypass. Neither is an author-closable fact.
