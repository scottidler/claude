# Implementation notes: guard-precision (chunk B)

Append-only record of how the implementation interprets or departs from
`2026-09-13-guard-precision.md`. One section per phase, four buckets each.

## Phase 0: prove the harness assumptions

### Design decisions
- The nested-session method is chunk A's, reused unchanged: scratch hooks behind `--settings` on `claude -p --model sonnet`, every hook appending its payload to its own log. Evidence: `2026-09-13-guard-precision-phase0/evidence.md`.
- 0a needed an interactive session because `SessionStart` never fires under `-p`. It was driven under a detached tmux server (`tmux -L p0a`), sandbox off, because tmux talks over a unix socket the sandbox denies. The transcript of that session (`a4faad78`) is the primary record.
- 0f was extended from the two orderings the doc asked for to seven runs, because two runs could not separate registration order from a completion race. The sleep variants are what settled it.

### Deviations
- The doc's plan changes are recorded INLINE in the design doc under `Phase 0 outcome` markers (Status line, problem 1, Overview, Architecture, Data Model masker table, API Design, Phase 5, Phase 6 rewritten, Phase 7, AC1, AC5, decision 9, Rollout Plan) rather than in a separate addendum, so a phase implementer reading its own section sees the current plan without cross-referencing.
- Phase 6 is rewritten wholesale: the `git -C` strip folds into `rewrite-cd-read.py` and `git-no-dash-c.sh` is deleted. This is the fallback the doc's Rollout Plan pre-committed to for a failed 0e, so it is a deviation the doc authorized in advance, not a new decision.

### Tradeoffs
- `additionalContext` over plain stdout for Phase 7, when 0a showed both reach the model. The documented field, and its rendering names itself as context rather than as a hook's stdout.
- AC5's observable became the hook's own log line rather than anything model-visible, because 0b proved a shell hook has no channel to tell the model a rewrite happened. The alternative was to keep a deny (visible, but the round trip the chunk exists to remove).

### Open questions
- None. 0a's finding that `ssh-agent-check.sh`'s WARN would have been heard changes nothing this chunk builds; it corrects the doc's stated cause for the zero-WARN audit finding.

## Phase 1: `hooks/lib.sh` and its tests

### Design decisions
- One awk program dispatched by a `mode` variable, not ten. Every function needs the same quote/heredoc scan, and keeping mask, match and slice in one process is the whole point of the Data Model's offset rule. `_lib_run` pins `LC_ALL=C` on every call.
- The single primitive is a per-byte class map (`scan()` in `lib.sh`): `.` plain, `q` a quote character, `S` single-quoted, `c` single-quoted AND a `-c` argument, `D` double-quoted, `E` a backslash-escaped `$`, `H` heredoc body or terminator, `#` comment, `P` command substitution body. Each masker is a set of classes over that map, so "which spans may be erased" is one table instead of five regex passes.
- A newline is NEVER masked by any masker, whatever its class. Line structure is load-bearing for line-oriented callers and a newline carries nothing matchable. A heredoc body's newlines still get class `H`, which is what keeps them from being statement separators; the newline ending the LAST terminator is plain, so the command on the next line stays a statement of its own.
- `stmts` neutralizes class `H` bytes in the pieces it emits and drops a piece that is all mask, so a heredoc body fragment can never be handed to a gate even when a caller splits before it masks. Without that, `cat <<EOF ... EOF` yields the body as a statement whenever the caller's order is stmts-then-mask.
- Nested statements are emitted breadth first: every top-level statement, then the bodies they yielded. Depth first would make a statement's index depend on how deeply an earlier sibling nested.
- A `-c` argument is yielded as a nested statement only when the statement's command word resolves to `bash`, `sh` or `zsh` (path and env-assignment prefixes allowed), so `git commit -c HEAD~1` is left alone.
- `--self-test` is gated on `BASH_SOURCE[0] = $0`, because a guard sourcing `lib.sh` inherits the guard's own `$1`, and `git-release-guard.sh --self-test` would otherwise exec the library's matrix instead of its own.
- The test matrix renders `\x01` as `@` and builds every expected mask with `mk()`, one `@` per byte of the span that must disappear, so no expectation is a hand-counted run and no fixture may contain a literal `@`.

### Deviations
- `cd_target` requires the `cd` to be in command position of its statement; `git-release-guard.sh:108-113` matched `cd <dir>` anywhere in the text. Identical for the `cd <worktree> && bump` shape the gates care about, stricter for prose that happens to contain the word. Same effect, correct seam.
- `flag_value` drops every quote character inside the value token rather than only a matched surrounding pair, which is the shell's own concatenation semantics (`--title 'a'"b"` yields `ab`).
- `mask_optarg` covers exactly the flag list in the Data Model, so a combined short form (`git commit -am "msg"`) is not masked. Stated rather than silently widened: widening it is Phase 4's call if a fixture needs it.
- The library is bash, not POSIX sh (`read -r -d ''` for the awk program, `BASH_SOURCE`). The Data Model already commits `manifest-scope-guard.sh` to bash in Phase 2 for the same reason.

### Tradeoffs
- awk over `python3`, per the Data Model. The cost is one awk process per function call, so a gate applying four maskers pays four. Rejected the alternative of one composite call returning every mask at once, because the per-gate masker sets differ and a combined call would hand each gate masks it must not use.
- `mask_dquote` leaves a `$( )` inside double quotes intact, so `echo "$(manifest -l x)"` still shows the inner command to a bare-word gate that masks but does not split. That is the "a masker may only erase a span the shell will never execute" rule winning over quieter output; `stmts` is what removes the span from the outer statement.
- Byte-length preservation is asserted per masker per case (every mask case carries a second `[byte length preserved]` assertion) rather than once in a dedicated case. It doubles the case count and catches a length regression on the exact fixture that produced it.

### Open questions
- `cd_at <n>` indexes the SAME sequence `stmts` emits, nested statements included. Phase 4's destructive-op gate must therefore number statements straight off `stmts` output; if it filters or reorders them first, the index it passes to `cd_at` no longer means what it means here. Flagging it for the phase that wires the gate, not as a change to the library.

## Phase 2: port `manifest-scope-guard.sh` and `secret-echo-guard.sh`

### Design decisions
- Both guards mask PER STATEMENT rather than once over the whole command, because `stmts` yields nested statements (`$( )`, backticks, a `bash -c` argument) as records of their own and each needs its own mask pass. `manifest-scope-guard.sh` judges each statement in the loop; `secret-echo-guard.sh` reassembles the masked statements one per line and hands the whole block to its existing python matcher.
- One masked statement per LINE in `secret-echo-guard.sh:39-45`, deliberately: the matcher's windows are `[^\n;|&]*`, so a newline join is what keeps an `echo` in one statement from reaching a `$SECRET` in the next, and it is what makes the `(?m)^` anchor on the new safe form mean "statement start".
- `manifest-scope-guard.sh` runs its exemption grep and its scope-flag grep on the MASKED statement, not the original. A scope flag or the word `age` sitting inside a quoted argument can no longer exempt an unscoped apply.
- Both guards keep their existing matchers unchanged in kind (two `grep -E` calls; `re.search` in python). This phase changes what TEXT reaches them, which is the point of the shared library: the verdict logic is untouched and bisectable.
- Order of the mask pipeline is `mask_heredoc` first, because it is the only line-level pass and the bytes it neutralizes include quote characters that would otherwise unbalance the later scans.

### Deviations
- The doc's Phase 2 bullet adds `${#NAME}` to the safe forms as if it were a live false positive. It was not one: the `NAME` tail cannot begin at `#`, so `echo "${#GH_TOKEN}"` never matched the print check even before this phase. The strip is implemented as asked and the matrix pins it, but it is an invariant made explicit rather than a bug fixed. Recorded rather than silently skipped.
- The `[ -n "$NAME" ]` / `[ -z "$NAME" ]` safe form is anchored to the START of a statement (with an optional `if`/`elif`/`while`/`until` prefix), which the doc does not say. Unanchored, the strip would also erase the `[ -n "$GH_TOKEN" ]` inside `echo [ -n "$GH_TOKEN" ]`, which DOES print the value: a false-positive fix that opens a leak is the exact defect the Data Model's masking rule exists to prevent. `secret-echo-guard-test.sh` carries that command as a deny case.
- `[[ -n "$NAME" ]]` is accepted alongside the single-bracket form. Same idiom, and a guard that allows one spelling and denies the other teaches nothing.
- The design doc names `manifest-scope-guard.sh`'s masker set as heredoc, subshell, squote, dquote, comment. There is no subshell masker by construction (Phase 1's rule: a masker may only erase a span the shell will never execute), and `stmts` neutralizes the span in the enclosing statement itself, so the implemented pipeline is heredoc, squote, dquote, comment. Same effect, correct seam.

### Tradeoffs
- Process count against precision. `secret-echo-guard.sh` runs first on EVERY Bash tool call and now spawns `stmts` plus three maskers per statement plus `python3`, where it used to spawn one `python3`. Rejected folding the maskers into a single composite awk call, because the two guards need different sets and a combined call would hand each of them a mask it must not use.
- Kept the python matcher rather than porting it to awk or `grep -E`. The negative lookahead `_PAT(?![A-Za-z])` is the phase's whole point and POSIX ERE has no lookahead; the masking that feeds it is bash-side, so the parser is shared even though the matcher is not.
- A double-quoted command word (`"manifest" -l x`) is invisible to `cmdword_is` after `mask_dquote`. Accepted: it is the standard bare-word set the Data Model specifies, and the alternative is to leave double quotes intact, which reinstates the `echo "=== manifest entry ==="` false positive that bit twice live.
- `manifest-scope-guard.sh`'s scope-flag grep stays unanchored (pre-existing shape, unchanged this phase), so any of the fifteen flags anywhere in the statement exempts it. Narrowing it to flag position is a behavior change no measured failure asks for.

### Open questions
- None.

## Phase 3: `git-release-guard.sh` parser swap

### Design decisions
- `lib.sh` is sourced AFTER the `--help` / `--self-test` dispatch, so both CLI entry points work whether or not the library is on disk, while the hook path keeps the fail-open pass-through the Data Model requires. Confirmed live: `git-release-guard.sh --self-test` still runs its own matrix after the source, because `lib.sh`'s self-test is gated on `BASH_SOURCE[0] = $0` and a sourced library never sees that hold.
- `stmts` already neutralizes heredoc bodies and command-substitution spans inside the statement it emits, and yields the nested ones as records of their own. So the per-statement pipeline in `check_stmt` is `mask_comment | mask_optarg` and nothing more: the "heredoc, subshell" half of every row in the Data Model's per-gate table is delivered by the splitter, not by a masker. Same effect, correct seam (this is Phase 2's finding applied to the second file).
- The command word is computed once per statement into `is_git`, `is_gh` and `is_bump`, and every gate tests the flag. One mask pass plus three `cmdword_is` calls per statement, rather than one anchor call per gate.
- `:207`'s hand-rolled command-position regex for `bump` becomes `cmdword_is bump`, which is where that regex came from in the first place (the Data Model names it as one of the two sources `cmdword_is` generalizes).
- Gate B and Gate D are anchored with `cmdword_is gh` as well as `cmdword_is git`, because Gate B matches `git push` OR `gh pr create`. The Data Model states the rule for git; a gate whose match is half gh needs both command words or it keeps the unanchored half.
- `BUMP_ORDERED_BY_SCOTT=1` is read off the mask, so the door cannot be opened by a marker sitting inside a `-m` message.
- Values are read from the statement with `flag_value`: `--body-file` (replacing the quoted-form `grep -oE` plus the quote-stripping `sed`) and Gate B's `--head`. `flag_value` returns the value with quotes dropped and an unexpanded `$` left raw, which is exactly the two things Gate D needs: the path with a space in it now reads, and the `$TMPDIR` spelling still hits the loud "cannot expand" refusal rather than a silently empty body. Gate D still searches the FULL, unstripped `$cmd` for the `Release:` line.

### Deviations
- `bump_dir` defaults to the payload `cwd`, not `.`. The doc's bullet names only `:97-98`, but `bump_dir="."` at `:107` was the identical hook-process-cwd assumption, and a relative `cd` target is now resolved against the payload cwd rather than against wherever the hook process happens to sit. With no `cwd` field in the payload both resolve to `$PWD`, which is what keeps every pre-existing case fixed. Same effect, correct seam.
- The doc says two verdicts move in this phase. Two move in the MATRIX, and both are added. A third class moves outside it, and it is measured rather than assumed: prose naming a git operation inside a message-flag value, or outside command position, no longer trips a gate. Probed against a dirty fixture tree, `git commit -m "explain git restore --staged in the docs"` DENIED before the swap and ALLOWS after. That is the masker-and-anchor class Phase 4's matrix pins by name (`echo "git tag -f v1"` allow, `git tag -a v1 -m "added --force"` allow), and it is a consequence of the maskers the doc's own table assigns to these gates. No pre-existing expectation was edited to accommodate it.
- 24 em-dashes stripped across 18 lines, six of them inside deny reason texts, which now read with colons and commas. Required because this phase adds the file to the `.otto.yml` lint list and Phase 8's count assumes it. No verdict depends on reason text, and the matrix asserts decisions.
- The header's MECHANICS paragraph is rewritten to describe the shared parser. The stale release-flow comment at `:19-24` is untouched: it is Phase 4's, and AC7 still measures it.

### Tradeoffs
- Process count against precision, the same trade Phase 2 took: one `stmts` call per command plus two maskers and three `cmdword_is` calls per statement. Rejected computing the mask lazily per gate, which would spawn more awk processes on the deny paths and make the masker set per gate implicit instead of stated in one place.
- Gate B's `git push` refspec heuristic stays an awk one-liner over the statement. There is no flag to hand `flag_value`: the ref is positional, and the heuristic is pre-existing behavior this phase is not allowed to move.
- Two new fixture repos (one dirty, one clean) rather than dirtying the shared clone. The matrix had no dirty-tree case at all, and dirtying `$R` would have changed the tree every pre-existing case is judged against, which is the one thing a regression net for a refactor must not do.
- `runcwd` is a second runner beside `run` rather than a fourth parameter on it. `run` checks out a branch in `$REPO` and passes no `cwd`; the payload-cwd cases pass a `cwd` and deliberately run the hook process somewhere that is not a repo. Folding both into one helper would have meant editing the call shape of all 54 pre-existing cases.

### Open questions
- Phase 4's destructive-op gate needs a statement index for `cd_at`. This phase's loop does not number statements, because nothing consumes an index yet. Phase 4 must count straight off the `stmts` records, nested statements included, per Phase 1's note: a filtered or reordered count means something different to `cd_at` than it means to the library.
- The destructive-op and `git clean` gates still read one `porcelain` and one `untracked`, computed once in the payload cwd. That is the zero-verdict-change position, not the end state: Phase 4 moves them to the statement's own worktree, and the `git clean` gate additionally reads untracked files from the payload cwd rather than from the path being cleaned.

## Phase 4: `git-release-guard.sh` gaps and over-reach

### Design decisions
- `resolve_stmt_tree` resolves the statement's worktree LAZILY and caches it per statement, because most statements trip no tree-reading gate and the resolve costs an awk pass plus two `git` calls. The cache is reset at the top of `check_stmt`, beside the statement index it is keyed on.
- `stmt_idx` is assigned from a counter that increments on EVERY record `stmts` emits, before the empty-record skip, so the index the gates hand `cd_at` is the index `cd_at` walks. Phase 1's open question named this as the trap and Phase 3 flagged it; the loop now numbers first and skips second.
- The two new per-statement gates (tag creation, commit on a gated main) use `cd_at` alongside the destructive ops, not `cd_target`. The doc's decision 10 names only the destructive and `git clean` gates, but "the effective worktree" for a statement-scoped git operation is the same question in all four cases: `cd /repo && git tag -a v1` cuts the tag in `/repo`, and `cd_target` would answer correctly only when the `cd` happens to be last. `cd_target` stays on the bump gates, where the question really is where a later `bump` lands.
- Two gates need argument ROLE rather than a substring, so the guard carries one local tokenizer (`stmt_args`, an inline awk program in the same `read -r -d ''` shape `lib.sh` uses) that splits on UNQUOTED whitespace and drops quote characters. The revert gate feeds it the ORIGINAL statement, because a `$` or a backtick has to survive to be refused; the tag gate feeds it the MASKED copy, so a word inside a `-m` value is never read as a tag name. Same tokenizer, caller-chosen input, which is the Data Model's match-on-the-mask/extract-from-the-original contract with the caller deciding.
- An argument carrying a `\x01` byte is refused by the revert gate as "not a literal path". That is how `git checkout -- "$(pwd)"` is caught: `stmts` has already neutralized the command-substitution span by the time the gate sees the statement, so there is no `$` left to match, and the mask byte is the evidence.
- The tag-force match is a CLUSTER match (`-[a-zA-Z]*f[a-zA-Z]*`), which is what makes `-fa` and `-af` deny. Lowercase `f` only, so `git commit -q -F -` and `git tag -F file` are untouched.
- Tag CREATION is decided by the presence of a NAME operand plus the absence of any read/delete flag, not by the presence of `-a`/`-s`. `git tag v9.9.9` (lightweight) is a creation and denies off main; `git tag` alone has no operand and lists.
- The revert gate's structural match is unchanged from Phase 3 (`checkout[[:space:]]+--`, `restore\b`, `reset[[:space:]]+--hard`), so `git checkout HEAD -- f` still never enters the gate and still allows, exactly as it did before this phase. Only the verdict INSIDE the gate moved. Denying that form would have been a new deny no measured failure asks for.
- `--body-file` expansion is anchored at the START of the path (`${bf/#...}`), per the doc's "a leading `$TMPDIR`", and skipped entirely when the variable is empty in the hook's own environment, so an unset `TMPDIR` falls through to the loud "cannot expand" refusal rather than being guessed at as `/tmp`.
- The commit-on-gated-main gate reads `git remote get-url origin` and denies only on a match. It is a deny, so a failed read (no origin, not a repo) falls through to allowing a commit the gate knows nothing about, rather than refusing it.
- `runwith` is a third runner beside `run` and `runcwd`, setting ONE environment variable for the hook via `env VAR=value`. That is what makes the `$TMPDIR` / `$HOME` expansion observable instead of a coincidence of the machine the matrix runs on, and it needs no `eval`.

### Deviations
- The doc's tag-creation exclusion list is `-d|-l|--list|-v|--verify`. The implemented list adds `--delete`, `-n[0-9]*`, `--contains`, `--no-contains`, `--points-at`, `--merged`, `--no-merged`, `--sort`, `--format` and `--column`. Every one of them is a git LIST-mode flag (each implies `-l`), and without them `git tag --contains HEAD` reads as a creation because `HEAD` is a non-flag operand: a false deny the doc's list would have shipped. Matrix case: `git tag --contains HEAD` allow on a feature branch.
- The revert gate refuses `?` and `[` as well as the `*` the doc names. The doc's positive rule is "every non-flag argument is an explicit LITERAL path", and a `?` or `[` glob fails it for the same reason `*` does. The doc's list is an example set, not an enumeration.
- Gate C's new regex `(^|/)(bump|release)[-/]` no longer matches a branch named exactly `bump` or `release`, which the old statement-wide `(bump|release)([-/]|[[:space:]]|$)` did. That is the doc's regex as written, and no matrix case covered the bare form. Recorded rather than silently widened back.
- The `git clean -f` and `reset --hard` denials are now two separate gates instead of one combined destructive-op gate, because their questions differ (untracked count vs porcelain) and the third gate, the path-scoped revert, needs the operand scan neither of the other two does. Same three verdicts, three named sites, each with a deny text that describes the loss it is actually refusing.
- `mask_optarg` was NOT widened. No Phase 4 fixture needed the combined short form, so `lib.sh` is untouched by this phase and Phase 1's stated limit stands.

### Tradeoffs
- One local tokenizer in the guard rather than a new `lib.sh` function. Two gates in one file need it; exporting it would mean designing an interface for one caller, and the phase's remit is the gates. If Phase 5's branch guard needs the same walk, that is the moment to promote it.
- The tag gates match `\bgit[[:space:]]+tag\b` twice (once for force, once for creation) rather than nesting the second inside the first. Flat gates keep each deny reachable by reading one `if`, and the cost is one extra `grep` on the statements that name `git tag` at all.
- `stmt_args` splits on unquoted whitespace and drops quote characters, which is not a full shell word split: `--body-file=a"b"c` style concatenation and `$'...'` are not modeled. Both gates ask only whether an argument is a literal path or a tag name, and neither question is changed by that gap.
- The `git checkout -- . && cd <clean>` ordering case is pinned as a matrix fixture rather than asserted in a comment. Swapping `cd_at` back to `cd_target` fails exactly that case plus its `reset --hard` twin and nothing else, which is the evidence that the ordering note is load-bearing and not decoration.

### Open questions
- None.

## Phase 5: branch guards

### Design decisions
- The tokenizer WAS promoted. Phase 4's tradeoff said "if Phase 5's branch guard needs the same walk, that is the moment", and it does: every branch-name extraction is a positional walk over arguments. `stmt_args` plus its inline `_ARGS_AWK` left `git-release-guard.sh` and became `lib.sh`'s `args` (mode `args`, `args_out()`), implemented on the library's existing `scan`/`tokenize`/`tokword` rather than as a second copy of the local awk, so there is one quote model in the tree instead of two. Both files call it, `lib-test.sh` gained five cases for it, and `git-release-guard-test.sh` stayed 113/113 green across the swap, which is the evidence the promotion changed no verdict.
- `branch-name-guard.sh` reads the new name by argument ROLE off `args`, never by regex over the statement. That is what makes `git branch -d x` and `git branch --list 'x*'` pass (the flag between `branch` and the name breaks the match, the same anchor Gate C uses) and what makes the guard immune to the class `mask_optarg` exists for: a quoted `-m` message is ONE argument, so `git tag -a v1 -m "switch -c Bad/Name"` has no token equal to `switch`. Matrix case, allow.
- `git branch -m` is judged on the LAST operand, so a rename is judged on where it LANDS: `git branch -m fix/x flat-slug` (the sanctioned fix for a bad name) allows, `git branch -m old-flat fix/x` denies.
- `gh pr create --head <name>` fires only when the name has no local ref. An existing branch is not a NEW name, and demanding a rename of a branch that already carries commits is the defect the title guard had. Matrix cases: the fixture's existing `legacy/old-thing` allows, `fix/markdown-dark-mode` denies.
- Uppercase is tested with `[[:upper:]]`, not `[A-Z]`. A bracket RANGE in a bash glob follows the locale's collation order and matches lowercase letters in a UTF-8 locale, so `[A-Z]` would have denied every branch name on this machine.
- `branch-pr-title-guard.sh` reads `--repo` as a GATE rather than as a directory oracle: when `--repo <owner>/<name>` does not appear in the effective worktree's `origin` URL, the PR targets a repository whose head branch this hook cannot read, so it passes through. When the named repo IS this worktree, the branch is read and judged normally. Both directions are matrix cases (`--repo tatari-tv/philo` allow, `--repo scottidler/fixture` judged).
- Both guards number statements off the records `stmts` emits, nested ones included, before any skip, because that is the index space `cd_at` walks (Phase 1's open question, Phase 4's precedent).
- Every deny case in `branch-name-guard-test.sh` asserts the OFFERED slug is in the reason, not just the decision. The measured failure was a model not knowing what to type next, so a deny naming no legal name is not a pass.

### Deviations
- The deny text carries a leading `Blocked: branch '<name>'.` before the doc's sentence. The doc quotes the text without the offending name, but a command can name more than one branch and Gate C's neighboring text names its branch for the same reason. The doc's sentence itself, slug included, is verbatim.
- The title guard resolves the worktree with `cd_at <n>` (the `cd` in effect AT the statement), not `cd_target` (the last `cd` in the chain). The doc says `cd_at` in its Phase 5 bullet and `cd_target` in its API Design line; `cd_at` is the statement-scoped answer and matches what Phase 4 chose for every statement-scoped gate. Identical for the measured `cd <worktree> && gh pr create` shape. Same effect, correct seam.
- `git -C <dir>` is honored only when the `cd` step resolved to nothing, and only when the `-C` value is an existing directory. The existence test is what disambiguates git's overload of the flag: `git switch -C <branch>` and `git commit -C <commit>` do not name directories, and decision 3 deliberately leaves those values unmasked.
- The plain-mismatch text is "today's text, unchanged" except for its em-dash, which became a colon. The file is now in the `.otto.yml` lint list (3 em-dashes stripped, one of them in that reason), and the em-dash rule has no exemption for a text the doc calls unchanged.
- The `mcp__multi-account-github__create_pr` branch of the title guard is left in place and gains the three new texts. The new guard is registered on `Bash` ONLY, per the doc; removing the dead MCP matcher is chunk J's, and leaving the handler working costs nothing while the matcher still exists in `settings.json`.
- An unexpandable `--title` is detected as a literal `$`, a backtick, or a mask byte. The doc names only the `$(gen-title)` shape (which arrives as a mask byte, because `stmts` neutralizes the span); `--title "$TITLE"` is the same unknowable value one spelling later. Both are matrix allows.

### Tradeoffs
- `args` reuses the library's `scan`/`tokenize` instead of copying Phase 4's local awk verbatim. The library tokenizer additionally breaks tokens on unquoted shell metacharacters (`;&|()<>`), which the local one did not, so a redirection glued to a path (`f>g`) now reads as two arguments. Accepted because the release guard's 113 cases are unchanged and both consumers ask only whether an argument is a literal path, a tag name, or the token after `-b`; the alternative was two tokenizers with two quote models, which is what the promotion exists to remove.
- The name guard does not judge a `--head` name when `--repo` names another repository, and does not read `--repo` at all: a branch that already exists somewhere else is still checked against the LOCAL refs, so a slashed branch living only on a remote would be denied. Left as the doc specifies (existence is a local-ref question) rather than widened to a network call in a PreToolUse hook.
- One deny per command. `judge` exits on the first violation, so `git checkout -b a/b && git switch -c B_c` reports only the first name. A second round trip surfaces the second, and a hook that concatenated reasons would bury the fix it is offering.

### Open questions
- None.

## Phase 6: the `git -C <cwd>` strip folds into `rewrite-cd-read.py`

### Design decisions
- The strip is two functions, not one: `points_at_session_cwd` (the match) and `git_dash_c_drops` (the scan), both in `rewrite-cd-read.py` beside the `cd` rewrite. The scan returns token indices, so the strip and the `cd` rewrite go through the ONE existing `splice` call. Two independent splices could not compose: the second would be applying byte offsets measured against a string that no longer exists.
- `git_dash_c_drops` is deliberately NOT subject to `stage_is_dangerous`, which the `cd` rewrite bails on. That gate exists because a rewrite can move a command OUT of a `permissions.deny` pattern; removing `-C <cwd>` only ever moves one IN, since every pattern is written against the canonical form (`Bash(git tag -d *)` matches `git -C <cwd> tag -d v1` only after the strip). Checked against the live deny list: no pattern mentions `-C`. `git -C <cwd> tag -d v1` is a matrix case pinning this.
- `rewrite()` returns `(command, all_safe, kind)` with `kind` in `cd` / `strip-c` / `cd+strip-c`. The caller needs to tell a strip-only rewrite from a composed one to pick the log tag and the reason, and a third boolean would have encoded the same thing less legibly.
- A strip-only rewrite takes the REWRITE branch (`updatedInput` + `permissionDecisionReason`, no `permissionDecision`), per the doc. A strip riding a read-only `cd` rewrite keeps that branch's `allow`: dropping `-C <cwd>` cannot change what runs, so it cannot cost an auto-allow that was already earned.
- `log()` gains `STRIP-C` as a decision for a strip-only rewrite; a composed one keeps `ALLOW`/`REWRITE` and carries `+strip-c` in the detail column. One invocation stays one line (the log's stated contract) and `rg -i strip-c` finds every strip either way.
- `GIT_GLOBAL_VALUE_FLAGS` is extracted and the three existing copies of the literal tuple now use it. The strip's position test ("a `-C` before the subcommand") has to mean exactly what the three subcommand scans already mean, and four copies of that list is how they drift apart.
- `LOG` is now `REWRITE_CD_READ_LOG` with the live path as its default (it was a hardcoded path), so the matrix asserts on the log without appending to the live one.
- `drop_cd`'s docstring said `git-no-dash-c.sh` denies the redundant `-C` form. That file is deleted, so the sentence now names `git_dash_c_drops`. The function itself is dead code (its logic is inlined in `rewrite`) and was left alone otherwise.

### Deviations
- The doc says "in its own function"; there are two, because the match rule (cwd, `.`, `$PWD`, one trailing slash) is worth naming and testing separately from the position scan. Same effect, correct seam.
- The matrix is 33 assertions, more than the doc's case list: it adds bare `$PWD`, `git -C <cwd>x` (the near-miss), `git commit -C <cwd>` and `git switch -C <cwd>` (the overload with a value that WOULD match), the `git tag -d` canonicalization case, and direct assertions on the decision shape per branch and on the two log tags.
- The doubled-space case strips to `git  status`, with the two spaces the model typed between the flag and the subcommand. `splice` passes through every byte it is not dropping, and collapsing them would mean re-rendering, which this file abandoned for good reasons. The matrix asserts the two spaces.
- `-C` inside a heredoc body is unchanged because the pre-pass refuses any command containing a `<<` redirect, not because the strip scan understands heredocs. The matrix case is real and the comment says which mechanism earns it.

### Tradeoffs
- String match with no filesystem access, per the doc, so `git -C $(pwd) status`, `git -C ~ status` from `$HOME`, and a symlinked spelling of the cwd are all misses. A miss leaves the command exactly as written and it runs correctly anyway, which is the whole argument.
- The strip runs before the `cd` rewrite's dangerous-stage bail, so a command like `cd /x && git -C <cwd> tag -d v1` now gets the strip alone rather than being left untouched. Chosen over "one bail covers everything" because the bail's reason (deny-pattern evasion) does not apply to the strip, and the alternative silently drops the strip in exactly the composed case the fold exists to serve.

### Open questions
- None.

## Phase 7: `hooks-preflight.sh` and the CI resolve check

### Design decisions
- The command-string parsing is a small new sourced file, `HOME/.claude/hooks/hooks-resolve-lib.sh`, not an addition to `lib.sh`. `lib.sh` is one `awk` program built around a byte-index contract for masking and slicing shell statements; parsing a settings.json command string is plain word splitting with no masking, no statement tree, and no shared index space, so folding it in would bolt an unrelated shape onto that contract instead of reusing it.
- Tokenizing goes through `xargs -n1`, not `eval`. The three live shapes (`~/.claude/hooks/foo.sh`, `bash '/abs/path' session`, `clyde permit log`) only need single-quote stripping, and `xargs` does that without ever passing the string to a shell, so a crafted command in settings.json cannot execute anything during a resolve check.
- Two functions, per the doc: `hook_resolve_target` (parses a command string into `HOOK_KIND`/`HOOK_TARGET`, no filesystem access) and `hook_target_exists` (checks the target, filesystem access only here). `hook_resolve_target` walks past a leading `bash`/`sh` token looking for the first argument containing `/`, which is what catches the `bash '<path>' session` shape a first-token check would silently pass.
- `hook_target_exists` takes an optional `repo_root` third argument so ONE function serves both consumers: omitted, it tilde-expands against `$HOME` (`hooks-preflight.sh`'s live-session check); given, it remaps a `~/.claude/hooks/<x>` or literal `$HOME/.claude/hooks/<x>` target onto `<repo_root>/HOME/.claude/hooks/<x>` (`bin/hooks-resolve`'s CI check, where nothing is symlinked into the runner's home).
- `hooks-preflight.sh` hardcodes `$HOME/.claude/hooks/lib.sh` for the lib readability check (overridable via `HOOKS_PREFLIGHT_LIB` for tests), independent of its own `$0`, because the doc's check is of the LIVE symlink target, not of wherever this script happens to be invoked from.
- `bin/hooks-resolve` reports a missing bare PATH name as a `WARN` and does not fail the run on it, per the doc: a binary absent on a CI runner is not evidence of a missing hook file.

### Deviations
- None. The parsing lives in one file as specified, both scripts source it, and both fixture shapes the doc calls out by name (`does-not-exist.sh`, `bash '<path>' session`) are covered.

### Tradeoffs
- `xargs -n1` over a full shell-aware tokenizer. It only has to understand single-quote stripping for these three known shapes; a command string with double quotes, escapes, or nested quoting would tokenize wrong, but no such shape exists in `settings.json` today and the doc's remit is the shapes that are live.
- `hooks-preflight.sh` never exits non-zero and only ever emits `additionalContext`, never a `permissionDecision`. A SessionStart hook has no deny semantics to begin with, and failing loudly here would mean a broken preflight breaking every session start, the opposite of what a preflight is for.
- The live proof step (below) surfaces `~/.claude/hooks/lib.sh` as unresolved alongside `branch-name-guard.sh` and `hooks-preflight.sh` itself, one more entry than the task's stated expectation. That is not a bug: `lib.sh` genuinely is not linked live yet in this pre-merge state (Phase 1 through 6 landed the file in the repo but the operator link step has not run), and the preflight is specified to check it by name. Reporting it is the correct behavior, not scope creep.

### Open questions
- None.

### Live proof (2026-09-14, pre-merge, desk.lan)
- `bin/hooks-resolve` (no arguments): `hooks-resolve: all hook files resolved (0 PATH warning(s))`, exit 0. Passes because it resolves against the repo tree, where `hooks-preflight.sh` and `branch-name-guard.sh` already exist.
- `bash HOME/.claude/hooks/hooks-preflight.sh` against the live `~/.claude/settings.json` (after appending its own entry to `SessionStart`):
  ```json
  {
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": "hooks-preflight: unresolved hook(s): ~/.claude/hooks/branch-name-guard.sh; ~/.claude/hooks/hooks-preflight.sh; ~/.claude/hooks/lib.sh (not readable); fix: cd ~/repos/scottidler/claude && manifest -l HOME/.claude/hooks/* | bash"
    }
  }
  ```
  This is the dead-hook window the preflight exists to surface: three files this PR's phases add are not yet symlinked into `~/.claude/hooks/`, because that link step is the post-merge operator step, not part of any phase commit.
