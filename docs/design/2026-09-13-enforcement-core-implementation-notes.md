# Implementation notes: enforcement core

Companion to `docs/design/2026-09-13-enforcement-core.md`. Append-only, one
section per phase, written at the end of that phase. Prior entries are never
edited.

## Phase 2: Stop hook prose.sh

### Design decisions
- Stale guard compares FILE POSITION, not timestamp (`prose.sh`, the prompt
  block). `last-prompt` records carry no timestamp: their keys are exactly
  `lastPrompt, leafUuid, sessionId, type`, verified against a live 1,491-record
  transcript. Position is equivalent to time in an append-only file and works
  for every record type, so one rule covers both prompt sources.
- Transcript reads are bounded to the last 4 MB (`TAIL_CAP`), dropping the
  necessarily partial first line of a truncated read. Records are one JSON
  object per line and the newest prompt always sits near the end; an unbounded
  read on every turn end is not acceptable.
- Quoted text in reason strings is truncated through jq (`head_chars`,
  `tail_chars`, `.[0:200]`). Bash substring and `cut -c` count BYTES under a C
  locale and would hand jq a split multibyte character, which is exactly the
  case the em-dash rule always hits.
- Rule order is em-dash, offer, decision ask. Em-dash is the only rule that
  needs neither the prompt nor a line count, so it still fires when the
  transcript is unreachable.
- Every reason quotes the offending line; the offer reason also quotes the
  prompt that made it imperative, so the model can see why the rule fired
  rather than guessing (the 8-block cap makes a second miss expensive).
- The banned character is built from a bash `$'...'` escape rather than typed,
  so neither file carries a literal U+2014 and the repo lint added in Phase 4
  will pass over them.

### Deviations
- A slash-command prompt counts as imperative (`is_imperative`, the `/?*`
  case). Same effect, correct seam: the doc's amendment made `last-prompt` the
  primary source precisely so `/skill` turns yield a prompt, but the imperative
  test is a first-word verb list and `/how-to-execute-a-plan` is in no verb
  list, so every slash turn would extract a prompt and then fail the gate,
  leaving the amendment inert. Invoking a command is an order. One line,
  reversible, fixture `offer after a slash command (last-prompt record)`.
- Fail-open is scoped to the OFFER rule, not the whole hook. The Phase 2 bullet
  lists "the transcript cannot be read" among the pass-throughs; the Data Model
  scopes fail-open to prompt extraction, and the risk table says "em-dash and
  length rules do not need the prompt". Implemented the Data Model reading.
  Measured effect: a headless `claude -p` reply carrying U+2014 is still
  blocked (live check below), which is what G2 asks for.
- The final-sentence cut requires a terminator FOLLOWED BY WHITESPACE. The doc
  says "after the last `.`, `!`, `?` or newline boundary"; a bare-dot cut
  truncates "Want me to update edges.md?" to "md" and misses the offer.
  Fixture: `offer whose sentence carries a dotted filename`.
- Offer phrases and go-ahead tokens match case-insensitively. The doc does not
  specify case; insensitive is the strictly wider gate and costs nothing.
- The linker step named in the Phase 2 bullet was NOT run: the phase dispatch
  excluded it. `prose.sh` is inert under `~/.claude/hooks` until the per-file
  link step for `HOME/.claude/hooks/*` runs from the repo root with the glob
  unquoted. Deferred prerequisite, not done and not faked.
- Only the `hooks` hunk of `HOME/.claude/settings.json` is in this commit. The
  working tree carried two unrelated uncommitted edits to that file (an emoji
  escaped in a permission entry, an `autoMode.allow` block) plus one to
  `HOME/.claude/CLAUDE.md`; they are none of this phase's business and stay
  unstaged.

### Tradeoffs
- jq for transcript parsing vs python3: jq matches the house hook shape and is
  already a dependency. Cost is a handful of jq invocations per turn end.
- Bounded 4 MB tail vs a full read: a turn that appends over 4 MB of records
  since the last typed prompt loses the prompt and the offer rule stands down.
  Chosen over an unbounded read on every single turn end.
- Synthetic transcript fixtures vs live session checks: the matrix pins the
  lagging, flushed and partially flushed orderings deterministically, which a
  live session cannot do on demand. The live checks stay in Phase 6.
- No warn-only path, per the doc's resolved decision: the hook blocks or
  passes.

### Open questions
- Is the slash-command imperative rule what Scott wants? If not, the doc's
  `last-prompt` amendment buys nothing for `/skill` turns and that should be
  recorded as the accepted cost.
- Phase 2's live offer criterion is unsatisfiable as written: `claude -p` writes
  no transcript at all (spike 0h defect 1), so the offer rule fails open in
  headless sessions by construction, which the doc's own Resolved Decisions
  already records. The live offer block needs an interactive session and
  belongs to Phase 6.

## Phase 1: sandbox config and text fixes (PARTIAL, two files blocked)

### Design decisions
- Landed out of order, after Phase 2, because Phase 1 was blocked when the loop
  reached it. Nothing else was resequenced.
- `ssh-agent-check.sh` was rewritten rather than patched at line 10. Its whole
  premise was agent reachability, and Phase 0 proved the sandbox denies
  `socket(AF_UNIX)` creation outright, so no sandboxed process can ever reach an
  agent. The hook now checks file readability of both halves of the active
  `user.signingkey`, which is the thing that actually determines whether a
  sandboxed `git commit` succeeds. `ssh-add -l` is kept only as an
  unsandboxed-push warning.
- The hook expands a leading `~/` in `user.signingkey` itself. git accepts that
  form in its config and the shell does not expand it for us, so without this the
  readability test would fail on a path that is actually fine.
- `review-panel.md` keeps its 44 existing em-dashes. The design doc names it as
  the one exemption in the touched set, because chunk C rewrites it wholesale.
  This edit introduced zero new ones.

### Deviations
- **`HOME/.claude/settings.json` was NOT edited. Blocked.** Every `sandbox` and
  `env` change in the Phase 1 bullet list is unlanded: the `allowWrite` additions
  (`/var/tmp/rmrf`, `/var/tmp/bkup`), the five `allowRead` absolute paths, the
  `excludedCommands` additions, and `env` gaining `TMPDIR` and `RUSTC_WRAPPER`.
- **`HOME/.claude/CLAUDE.md` was NOT edited. Blocked.** The two sandbox lines are
  unlanded.
- Cause in both cases: the Claude Code auto mode classifier denies the write with
  `[Self-Modification]`. Hit three times, on a `phase-implementer` dispatch whose
  prompt described the edits, on a direct Edit of `settings.json`, and on a direct
  Edit of `CLAUDE.md`. This is exactly the operator note in the doc's
  Implementation Plan preamble, item (b): these phases must run with auto mode
  off. It is an environment gate, not a code problem, so no workaround was
  attempted past the second failure.

### Tradeoffs
- Committed the three unblocked files rather than holding the whole phase. The
  alternative was one clean Phase 1 commit later, but that would have left the
  `ssh-agent-check.sh` rewrite and the `review-panel.md` correction unrecorded
  while the branch moved on. Phase 1 therefore takes two commits, and the second
  is owed.

### Open questions
- None for the author. One for the operator: auto mode must be off for the
  settings.json and CLAUDE.md half of this phase, and for Phase 3 (hook
  registration) and Phase 5 (the rails plugin under `HOME/.claude/skills/`).

## Phase 3: em-dash PreToolUse emdash.sh

### Design decisions
- The Bash branch detects an outward stage on the heredoc-STRIPPED text and
  then scans the RAW command, bodies included (`emdash.sh`, the Bash block).
  Those are opposite needs: a commit message line reading "git commit" is prose
  and must not create a stage (the otto-rs/otto b428680 false positive), while
  the message body is exactly where the character lives, so the scan cannot use
  the stripped text. Fixtures pin both directions: `commit message arriving by
  heredoc` denies, `heredoc body mentions git commit, the command is a cat`
  allows.
- `strip_heredocs` is a copy of git-release-guard.sh's awk stripper, not a
  shared library. House hooks are standalone scripts registered by absolute
  path in settings.json and linked one file at a time; there is no sourcing
  convention, and a second copy is cheaper than inventing one for two callers.
- The outward-stage regex allows only git's own option tokens between `git` and
  `commit` (`-c k=v`, `-C <dir>`), so `git -C <dir> commit` is caught and
  `git log --grep commit` is not.
- One jq pass returns both the field label and the first offending LINE, so the
  deny reason names the exact field (`MultiEdit edits[1].new_string`,
  `mcp__slack__chat_post_message text`) rather than the tool.
- The reason string keeps the design doc's wording verbatim as its prefix and
  appends the offending text, quoted and truncated to 200 codepoints. Same
  reasoning as Phase 2's resolved decision: a block that only names the rule
  costs a second attempt.
- Edit scans `new_string` only. Scanning `old_string` would make REMOVING an
  existing em-dash impossible, which is the exact operation Phase 4 and every
  future cleanup needs. Fixture: `Edit REMOVING it: only old_string carries it`.
- MCP payloads are walked with jq `paths(type=="string")`, so a nested body
  (`body.value` on a Confluence page) is scanned at any depth, and a matcher
  added later needs no change here.
- The path allowlist is checked before any scan and reads `file_path` or
  `notebook_path`, so it applies to all four write tools and to none of the
  others.
- Scar tissue, cost one wasted write: zsh expands `$'...'` inside a heredoc
  even when the delimiter is QUOTED (`<<'SH'`), which bash does not. Writing
  the bash escape form of U+2014 through a zsh heredoc silently produced a
  literal U+2014 in the file, i.e. a hook that denies its own source. Both files
  were therefore written with the escape inserted by a python pass, and both are
  verified literal-free by `rg -n` in this phase.

### Deviations
- The linker step named in the Phase 3 bullet was NOT run: the phase dispatch
  excluded it, same as Phase 2. The registration is live (the repo's
  `HOME/.claude/settings.json` IS `~/.claude/settings.json`) but
  `~/.claude/hooks/emdash.sh` does not exist yet, so the hook is inert until the
  per-file link step for `HOME/.claude/hooks/*` runs from the repo root with the
  glob unquoted. Deferred prerequisite, not done and not faked.
- Only the hooks hunk of `HOME/.claude/settings.json` is in this commit. The
  working tree carries two unrelated uncommitted edits to that file (an emoji
  escaped in a permission entry, an `autoMode.allow` block) plus one to
  `HOME/.claude/CLAUDE.md`; they are none of this phase's business and stay
  unstaged. The hunk was staged with `git apply --cached` against a filtered
  diff.
- The commit is unsigned (`--no-gpg-sign`). Signing is broken until the Phase 1
  operator prerequisite (the home signing key) is done.

### Tradeoffs
- Over-inclusive stage detection vs precision: `gh issue` matches any
  subcommand, including `gh issue list`. The design doc names `gh issue` without
  a subcommand list, and the failure mode of the wide form is a deny on a
  command that carries the character for some other reason, which fails closed.
- A copied stripper vs a shared library: duplication now, one more call site to
  fix if the heredoc parser ever gains a bug. Chosen because the hook contract
  is one self-contained file per registration.
- Scanning the whole raw command once an outward stage exists, rather than only
  the message argument: a `git commit -m x && rg 'text with the character'`
  chain denies on the `rg` half. Parsing the message out of every commit and gh
  form is a bigger surface than the false deny is worth, and the recast is the
  same either way.

### Open questions
- The path allowlist includes `*.json`, so any JSON file may carry the literal.
  That is the design doc's Data Model wording, implemented as written; if Scott
  meant only JSON fixtures, the entry should be narrowed to the fixtures path.
- Phase 3's live criterion ("live Write of a file containing U+2014 is denied")
  cannot be satisfied until the link step runs, because the registered path does
  not resolve. It belongs with the Phase 6 shakedown, alongside Phase 2's live
  offer check.

## Phase 4: prose dedupe and overrides

### Design decisions
- `safety.md`'s File Deletion section is rewritten around intent per Scott's
  2026-09-13 ruling (closing OQ1): regenerable build output passes as plain
  `rm`/`rm -rf`, everything else goes through `rkvr rmrf`. It carries the
  regenerable set with its toolchain anchors verbatim from the Proposed
  Solution Overview table (one home per G5, rails carries the same table in
  Phase 5), the positional-match scar-tissue line (`crates/loopr/src/target/tests.rs`),
  the `# regenerable` marker rule, and the CI-teardown exception (Scott,
  2026-07-08).
- Every literal em-dash was stripped from every rule/hook file this phase
  edits for prose (`interaction.md`, `safety.md`, `voice.md`, `secrets.md`,
  `edges.md`), matching G5's "leaves with zero em-dashes" bar. The already-
  landed hook files in the lint list (`ssh-agent-check.sh`, `prose.sh`,
  `prose-test.sh`, `emdash.sh`, `emdash-test.sh`) were already at zero.
- The 8 SKILL.md files and `refs/slack.md` got only the bullet's named
  duplicate-rule-line deletions, not a full em-dash sweep: see Deviations.
- `.otto.yml`'s `lint` task file list is a closed bash array, not a glob, per
  the phase bullet's "explicit file list ... until it becomes a glob"; `test`
  runs every `HOME/.claude/hooks/*-test.sh` plus `bun test` under
  `HOME/.claude/skills/rails/hooks`, and `ci` runs both.

### Deviations
- `.otto.yml`'s lint list omits `HOME/.claude/CLAUDE.md`, which the design
  doc's own "touched set" count names (19 em-dashes today). CLAUDE.md carries
  a pre-existing uncommitted edit that is explicitly not this phase's to
  touch (Phase 1's sandbox-line fix is still blocked by the auto mode
  classifier), and it still holds all 19 literal em-dashes; including it in
  the lint would fail CI for a file this phase cannot fix. Owed to whichever
  phase lands the CLAUDE.md fix.
- The 8 SKILL.md files and `refs/slack.md` are edited (their duplicate
  "no em-dash" rule-copy lines removed) but not added to the lint list's
  literal-em-dash check. Reading: the Resolved Decision ("existing em-dashes
  are stripped only from the files this PR touches... the lint list grows
  chunk by chunk") together with the tree-wide non-goal ("parked; revisit
  when chunk H... rewrites the heaviest files anyway") scopes the zero-em-dash
  bar to the doc's named touched set, not every file that had one duplicate
  line removed. `anthropic-usage-report/SKILL.md` (40 today) and
  `create-design-doc/SKILL.md` (15 today) still carry their pre-existing
  decorative em-dashes elsewhere in the file; only the named lines were
  touched. Same effect intended by the doc, correct seam for this phase.
- `whitespace -r` (mandated by `general.md`, run inside the new `lint` task)
  cleaned trailing whitespace on one unrelated pre-existing file,
  `docs/design/2026-08-02-per-phase-verification-node-phase0-artifacts/panel-round2-agent-synthesis-KILL.md`.
  Included in this commit as a side effect of the required lint task, not
  scope creep.
- Commit is unsigned (`--no-gpg-sign`): signing is broken until the Phase 1
  operator prerequisite (home signing key) lands.

### Tradeoffs
- `safety.md`'s File Deletion section copies the Overview's regenerable table
  verbatim rather than a shortened summary, so rails (Phase 5) and safety.md
  never drift on the set; the cost is a longer rule file.
- `.otto.yml`'s `lint` task inlines the file list as a bash array rather than
  a glob, matching the design doc's instruction that the list stays named
  until later chunks make it a glob.

### Open questions
- Should the SKILL.md files' remaining decorative em-dashes (40 in
  `anthropic-usage-report`, 15 in `create-design-doc`) move up ahead of
  chunk H, since they are already being edited this phase for the rule-copy
  deletion? Left parked per the doc's non-goal; flagging in case Scott wants
  them folded in now instead.

## Phase 5: rails rm rule

### Design decisions
- One scanner, parameterized by head word, not two. `ghSpots` is now a thin
  wrapper over `heads(command)` (`index.ts`), which returns every simple-command
  head with its offset, quote-aware, stopping at an unquoted `<<`. `headSpots`
  is the doc's "generalized to take the head word"; `heads` is what the rm rule
  needs, because it classifies by head (`rm`, a wrapper, `git`) rather than
  looking for one fixed word. gh behavior is bit-for-bit unchanged: the existing
  gh test block passes untouched.
- `heads` gained a `loop` flag, set when the head follows a `do` keyword.
  Without it the existing `TRANSPARENT` set (which already contains `do`, so
  `then gh ...` works) would have made `for f in *; do rm -rf $f; done` a
  rewritable rm stage. The doc says that form passes unchanged because the paths
  are a variable, so the flag is what implements it.
- `REGENERABLE` is a named constant carrying the safety.md table verbatim, with
  a doc comment pointing at `rules/safety.md` File Deletion and restating the
  positional rule and the `crates/loopr/src/target/tests.rs` scar tissue.
  `PY_ANCHORS` and `JS_ANCHORS` are spread into the entries so `dist` and
  `build` carry both anchor families without the table repeating itself.
- The anchor probe fails toward rkvr, never away from it: `envFor` catches on
  `$.fs.exists` and `$.fs.list` and returns false / empty, so an unreachable
  filesystem makes every path non-regenerable and every stage rewrites. Same for
  `resolvePath` returning null on a variable, a `~` or a glob. The safe default
  costs one tarball, never data.
- The session cwd is lazy (`envFor` memoizes one `$.session.cwd()` promise) and
  the hook is gated behind the `RM_INTEREST` regex. A Bash call with no delete
  head in it costs one regex test and no engine round trip; a `git status` costs
  a string scan and still no round trip, because cwd is only awaited when a path
  actually needs resolving.
- `$.fs.exists` is the plugin filesystem interface the doc mandates, never a
  subprocess. `claude plugin validate --strict` confirms the call set it sees:
  `$.fs.exists (via envFor), $.fs.list (via envFor), $.session.cwd, $.ui.log`.
  `$.fs.list` is there for the one glob anchor in the table, `.terraform` next
  to any `*.tf`; every other anchor is a literal `exists` check.
- `rm_rkvr` is a userConfig off switch mirroring `gh_persona`, and the plugin
  description now names both rules. Siblings behave identically (taste.md), and
  `rules/secrets.md` already documents the `pluginConfigs.rails.options` escape
  hatch for the gh rule; a second always-on Bash rewrite with no off switch
  would have been the odd one out.
- `debug()` now takes the rule name instead of hardcoding `rails/gh-persona:`.

### Deviations
- Signature: the doc's `rmRewrite(command)` is implemented as
  `async rmRewrite(command, env)` where `env` is `{ cwd, exists, list }`. Same
  effect, correct seam: the doc's own positional match needs the session cwd and
  a filesystem probe, which a one-argument pure string function cannot reach. It
  stays a plain function with no I/O of its own, so `index.test.ts` drives every
  case with a fake `env` and no harness, which is what "pure" bought.
- The rewrite preserves a trailing non-marker shell comment:
  `rm -rf ~/x #regenerable-ish` becomes `rkvr rmrf ~/x #regenerable-ish`. The
  doc only says the stage becomes `rkvr rmrf <paths>` with the flags dropped and
  does not say what happens to a comment that is not the marker. Keeping it is
  lossless (bash ignores it either way) and leaves the model's own note visible
  in `clyde permit log`.
- A regenerable pass requires at least one of `-r`, `-R`, `-f`. Read literally
  from the Overview ("stage head is `rm` with delete flags and EVERY path is a
  build-output directory"). Consequence: bare `rm target` rewrites to
  `rkvr rmrf target` even beside a `Cargo.toml`. Harmless, because every name in
  the set is a directory and plain `rm` cannot delete one.
- The wrapper deny is deliberately wide: any `sh -c` / `bash -c` payload
  containing an `rm` word denies, including `sh -c 'echo rm'`. Fails closed, and
  the recast is trivial. Recorded rather than narrowed, because parsing a
  wrapper payload is the exact string-rewrite problem the deny exists to avoid.
- No live checks were run. The Phase 5 criteria list four
  (`rm -rf ~/probe` rewriting, `rm -rf <repo>/target` passing, `sudo rm -rf
  /opt/probe` denied, the same three signals from a subagent); all four need the
  plugin reloaded in a session that has the new `index.ts`, and the phase
  dispatch scoped them to Phase 6 alongside Phase 2's and Phase 3's inherited
  live checks. Deferred, not faked.
- The commit is unsigned (`--no-gpg-sign`). Signing is still broken until the
  Phase 1 operator prerequisite (the home signing key) lands.

### Tradeoffs
- Injected `env` vs a two-phase split (a pure `rmParse` that names the anchor
  paths, then a probe, then a pure `rmApply`). The split would keep the letter
  of "pure string function" but spreads the four outcomes and their exact
  context lines across three exported functions and parses the command twice.
  One function, one place where the strings live, one fake in the tests.
- A conservative `resolvePath` that gives up on any `$`, `~`, `*`, `?` or `[`
  vs expanding what it can. Giving up sends `rm -rf target/*` in a Rust repo to
  rkvr, which is a wasted tarball. Expanding means reimplementing shell
  expansion inside a hook, where a wrong guess deletes the wrong thing.
- Scanning stops at the first unquoted `<<`, inherited from the gh rule, so an
  `rm` stage AFTER a heredoc is never seen and passes silently with no note.
  Kept for one scanner and one heredoc rule across both hooks; the miss is a
  pass-through, which is today's behavior.
- `RM_INTEREST` includes `git` so `git rm` gets its "form not rewritten" context
  line, as the doc's pass-unchanged list asks. Cost: every git command runs the
  string scan. Measured cost is a regex plus one pass over a few hundred bytes,
  with no engine call, because cwd is lazy.

### Open questions
- The doc's pass-unchanged list says these forms "are logged in the context line
  so the transcript shows the miss", and `git rm` is on it. Every `git rm` now
  carries a context line. If that reads as noise in practice, dropping `git`
  from `RM_INTEREST` is a one-word change.
- `sudo rm -rf $TMPDIR/probe` passes through to the shell unchanged (scratch
  carve-out) rather than being rewritten to `sudo rkvr rmrf`. The doc defines the
  wrapper outcome as deny vs pass only, so pass is what is implemented; flagging
  in case Scott wants scratch wrappers rewritten too.

## Finalization amendments (2026-09-13, team lead)

### Design decisions
- Em-dash path allowlist narrowed from `tests/fixtures/`, `*.golden`, `*.json` to
  `tests/fixtures/`, `*.golden`. The bare `*.json` exempted every config and data
  file in the tree, which is far wider than the JSON-fixture case it existed for,
  and a JSON fixture needing the character already qualifies under
  `tests/fixtures/`. Doc defect, not an implementation gap: Phase 3 implemented
  the spec exactly as written. Spec, hook and fixture matrix all updated together;
  `emdash-test.sh` is 31 passed / 0 failed, with a new deny case for a plain
  `data/fixture.json` and a new allow case for `tests/fixtures/payload.json`.

### Deviations
- None.

### Tradeoffs
- Narrowing rather than keeping the wider allowlist costs nothing measurable: the
  only material that legitimately needs a literal em-dash is verbatim captured
  text, which belongs under a fixtures path by the same rule.

### Open questions
- **STILL OWED, blocked:** dropping `git` from `RM_INTEREST` in the rails plugin
  (`HOME/.claude/skills/rails/hooks/index.ts:408`). `git rm` stages a deletion
  whose content stays recoverable from git history, so it is not the class rkvr
  protects, and the current code emits a "rails: rm form not rewritten" context
  line on every one. The one-word edit was denied by the auto mode classifier
  with `[Self-Modification]`. Owed alongside Phase 1's settings.json half.

## Phase 5b: rails excluded-compound deny (2026-09-13)

### Design decisions
- Third `tool.call` rule in `HOME/.claude/skills/rails/hooks/index.ts`, beside
  gh-persona and rm-rkvr. `excludedDeny(command, entries)` is pure and takes the
  entry list, so every case is a unit test; the engine only supplies the list.
- The entry list comes from `$.settings.read()` (`readExcluded`), the engine's
  own merged settings view, read once per session on the first Bash call and
  cached in a register-scope promise. One source of truth: the ten entries are
  never restated in the plugin.
- Classification reuses `heads()`, `segment()` and `splitWords()` unchanged. No
  second scanner, so the quote awareness and the heredoc stop come for free: a
  heredoc body naming `ssh -V` is data and never denies.
- Wrappers (`sh -c`, `bash -c`, `zsh -c`, `sudo`, `xargs`, `env`, `nohup`) are
  classified by their inner head, recursively to depth 3. `ssh` is deliberately
  NOT a wrapper here even though the rm rule treats it as one: `ssh host ls` is
  one command, and an inner-head reading would make `host` a REST stage and deny
  a positive case.
- `git` left `RM_INTEREST` and the `git rm` branch left `rmRewrite`. A comment on
  `RM_INTEREST` says why: `git rm` stages a deletion whose content stays
  recoverable from git history, so it is not the class rkvr protects.

### Deviations
- Spec said "read `sandbox.excludedCommands` from `~/.claude/settings.json` at
  plugin load". Implemented at the correct seam instead: `$.settings.read()`,
  lazily on the first Bash call. A hooks module may import nothing but its own
  files and `claude-code`, so `node:fs` is unavailable; `claude plugin validate
  --strict` refuses it by name (`cannot import "node:fs" (from hooks/index.ts)`).
  Same effect, and strictly better: the engine's merged view carries `--settings`
  and project overrides that a path read would miss.
- Spec named only `RM_INTEREST` for the `git` removal, but the stated goal (stop
  the context line on every `git rm`) needed the `head.word === 'git'` branch in
  `rmRewrite` gone too: `git rm x` still matches `RM_INTEREST` through its bare
  `rm` alternative, so dropping the word alone would have changed nothing
  observable. Both removed.
- The test that pinned the old behavior (`git rm is an index operation`,
  expecting a note) was inverted by name rather than deleted: it now asserts
  `note === ''`.

### Tradeoffs
- Deny over rewrite. Rails could in principle split a mixed compound into its
  stages and run them separately, but that changes shell semantics (exit codes,
  pipes, redirections) invisibly. A deny that names both heads and says "run them
  as separate Bash calls" keeps the model in charge of the split.
- Inert on a settings read failure rather than falling back to a hardcoded list.
  A stale hardcoded list would deny on entries that no longer exist and miss ones
  that do; failing open matches the rest of rails, which is early access.
- Wrapper depth capped at 3 rather than unbounded: past any use that is not
  deliberately adversarial, and adversarial nesting is not the threat model here
  (the model composing a convenience compound is).

### Open questions
- **The rule's blast radius on pipes, measured 2026-09-13 against the live ten
  entries, raised to the team lead before commit and still open.** Any pipe or
  `&&` beside an excluded stage is a deny, because REST is "every non-excluded
  stage minus `cd`, `export`, assignments, `true`, `echo`". So `otto ci 2>&1 |
  tail -50`, `cargo test | rg fail` and `git -C p status && cargo test` are all
  denied and have to be split into separate Bash calls, which cannot pipe.
  The narrowing on the table is a read-only consumer set (`tee`, `tail`, `head`,
  `cat`, `rg`, `grep`, `jq`, `sort`, `uniq`, `wc`, `less`) joining the transparent
  list, which keeps `; ssh -V` and `| sh` denied. Not taken unilaterally: it is a
  rule-semantics call. Scott's to settle.
- Whether the engine's `excludedCommands` matcher looks inside a `sh -c` payload
  is unmeasured. The rule denies either way, so the answer does not change
  behavior, but it would change how the hole is described.
- `sudo -u scott cargo build` classifies `scott` as a REST stage, because the
  wrapper unwrap skips flags but not their arguments. It over-denies only when an
  excluded stage is also present. No live case observed; recorded rather than
  fixed with an option table that would need per-wrapper knowledge.
