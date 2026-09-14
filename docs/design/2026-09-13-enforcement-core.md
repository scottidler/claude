# Design Document: Enforcement Core (sandbox fixes, first prose hooks, rm guard)

**Author:** Scott Idler
**Date:** 2026-09-13
**Status:** Partially Implemented (Phases 2 to 5 landed; Phase 1 partial, Phase 6 pending; see Observed table)
**Review Passes Completed:** 5/5
**Program:** chunk A of `docs/design/2026-09-13-setup-audit-program.md` (audit items 1, 2, 3)

## Summary

Three coupled fixes to the Claude Code harness config in this repo. Fix the sandbox config so the tools the rules require (rkvr, ssh commit signing, sccache, the reviewer CLIs) work inside the sandbox instead of failing and being routed around. Add the first hooks that inspect prose: a Stop hook that blocks offer-closers, em-dashes and oversized decision asks, and a PreToolUse deny on em-dashes in written content, commit text and outward posts. Make the `rm` ban mechanical with a rails rewrite to `rkvr rmrf`. Every item replaces rule text that the 2026-09-12 audit measured as not working.

## Problem Statement

### Background

- The audit (14 lenses, all sessions Jun 1 to Sep 12) found that hooks change behavior and rule text does not: AskUserQuestion 557 calls under a NEVER rule, zero three days after the hook; git hooks halved git mistakes twice; every prose-only rule flat or rising after landing.
- All nine hooks in `HOME/.claude/settings.json` are PreToolUse on Bash (plus two on an MCP create_pr, one on AskUserQuestion, two SessionStart). No Stop, SubagentStop, PostToolUse or UserPromptSubmit hook exists. Nothing inspects what the model writes or says.
- Sources: ranked report https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/ ; raw findings https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-audit-findings-2026-09-12/ (lenses hooks-sandbox, verbosity, frustration, incidents, tool-errors).

### Problem

Item 1, sandbox. Four tool families fail inside the sandbox for four verified, distinct reasons, and the model routes around each failure in a way that violates a rule:

- `rkvr rmrf` writes its archive to `/var/tmp/rmrf` (config `~/.config/rmrf/rmrf.cfg`, default in `rkvr/src/main.rs:836-853`) and creates `/var/tmp/bkup` at startup (`main.rs:866-867`). Neither is in `sandbox.filesystem.allowWrite`. 43 in-sandbox rkvr failures ("Failed to create base directory ... Read-only file system"); the fallback was `rm -rf`: 1,452 statements vs 408 rkvr, safety.md violated since April.
- Commit signing: `gpg.format=ssh`, `commit.gpgsign=true`, `user.signingkey=~/.ssh/identities/home/id_ed25519.pub`; `~/.gitconfig-work:9` sets `~/.ssh/identities/work/signing.pub` under `~/repos/tatari-tv/`. `~/.ssh` is in the sandbox read deny list. 160 "Couldn't load public key ... failed to write commit object" (113 in Sep), 83 retried with the sandbox off. Scott 07-16: "I consider it a failure for you to NOT be signing the commits."
  - The two personas are NOT symmetric, and the asymmetry decides the fix (verified 2026-09-13 by blob-hash match against `github.com/<user>.keys`, `api.github.com/users/<user>/ssh_signing_keys`, `~/.ssh/config`, `~/.gitconfig-ssh` and desk.lan's `authorized_keys`; no private key file was opened). `work/signing` is registered on escote-tatari as a **Signing key only**, absent from its authentication keys, passphrase-less by design per `~/.gitconfig-work:5-8`. `home/id_ed25519` is the opposite: it is scottidler's **only GitHub authentication key**, is also its registered signing key, and is the `IdentityFile` for `github.com`, `desk.ts`, `nas.lan`, `*.lan` (with `ForwardAgent yes`) and `nixos`, and appears in desk.lan's own `authorized_keys`. Its 399-byte size matches an unencrypted ed25519 (the passphrase-locked work `id_ed25519` is 464 bytes for the same key type), so no passphrase gates it. Home never received the signing/auth split that work got on 07-16.
- sccache: the sandbox has its own network namespace, so a sandboxed cargo never reaches the host sccache server on 127.0.0.1:4227; the client self-spawns and intermittently hits EPERM. cargo then caches the failed `rustc -vV` in `target/.rustc_info.json` and replays it unsandboxed. 197 "sccache: error: Operation not permitted"; 1,067 cargo calls hand-prefixed with `RUSTC_WRAPPER=` (472 in Sep). `excludedCommands: ["cargo *", "otto *", "release *"]` does not help because the failing commands start with `cd <repo> &&`, `timeout 900 otto ci`, `bump --no-tag`, `script -q -c "cargo build"`.
- `$TMPDIR` is empty when the sandbox is off (verified live this session: sandboxed `TMPDIR=/tmp/claude-1000`, unsandboxed empty), so `"$TMPDIR/ci.log"` becomes `/ci.log`: 108 failures.
- Reviewer CLIs (gemini, codex) run from `~/.claude/skills/architect/script.sh` and `~/.claude/skills/staff-engineer/script.sh` and need egress to `generativelanguage.googleapis.com`, `ab.chatgpt.com` and the rest of codex's hosts; `allowedDomains` is `["tatari-tv.github.io"]`. `agents/review-panel.md:176-182` claims the scripts are in `excludedCommands`; they are not. 12 network denials.
- `systemctl`, `journalctl`, `crontab` need the user bus ("Failed to connect to user scope bus", reproduced); `ssh` needs `~/.ssh`. 712 burned in-sandbox attempts overall, plus 1,091 needless `dangerouslyDisableSandbox` calls on cargo/otto heads that are already excluded.

Item 2, prose. Three measured behaviors, each with a rule that did not move it:

- Offer-as-closer. The assistant message immediately before a rage prompt ended with "Want me to / Say the word / your call" 25 to 41% of the time against a 6% baseline. 328 post-edges final replies end with an offer (Opus 5: 178, Sonnet 5: 106, Fable 5.1: 2). September final blocks: "Want me to" 124, "Say the word" 43, "your call" 36, "Say go" 29. Asking-not-doing tripled in Sep (7.5 to 22.8 per 1,000 prompts) after edges.md said "A question is a question" (08-06) and interaction.md said "run all phases" (09-08).
- Em-dash. Banned in safety.md (07-30), voice.md, edges.md and nine SKILL.md files. Still in 31% of assistant turns in Sep (Opus 5 45%, Sonnet 5 65%, Fable 5.1 2%); 2,926 Write/Edit calls, 2,206 Bash commands, 423 tool inputs after the rule. Nine explicit complaints, two after the rule. The config tree carries 1,361 em-dashes across 145 tracked files.
- Decision asks. 671 asks after the shape rule (08-02); 28 follow the shape; 346 of the rest exceed 12 lines. The 08-05 rage case ("THIS IS TOO MANY FUCKING WORDS") followed the shape inside 62 lines.
- Two contradictions in the rules themselves: `safety.md:15` and `voice.md:22` say "Use `--`" while `~/Claude/writing/VOICE.md:65` bans spaced double-hyphen; `edges.md:11-13` says no closers while the harness's own writing guidance says "close with a short recap" and "offering follow-ups is fine".

Item 3, rm. `safety.md:9-10` is an absolute ban with no hook. 1,525 `rm` calls in four months, 378 on repo or home paths, 612 from subagents (which never load safety.md), one `rm -rf` inside `~/repos/tatari-tv/clyde` (07-05). rkvr fails in-sandbox (item 1), so the fallback is rational until item 1 lands.

### Goals

- G1 (Scott, audit item 1): the four tool families above succeed inside the sandbox; no rule text tells the model to work around a sandbox failure.
- G2 (Scott, audit item 2): a final reply that ends with an offer after an imperative prompt, contains U+2014, or is a decision ask over 20 lines is blocked before Scott sees it, and the model is told why.
- G3 (Scott, audit item 2): a Write/Edit, commit message, PR body, or Slack/Jira/Confluence/marquee post containing U+2014 is denied at the tool boundary with a reason naming safety.md.
- G4 (Scott, audit item 3): `rm` with delete flags is classified by intent for every session and subagent: regenerable build output passes as plain `rm`, everything else is rewritten to `rkvr rmrf`, and forms that cannot be rewritten are denied with the rkvr hint. Deterministic first (a named set), a model-asserted marker as the fallback.
- G5 (Scott, taste.md "one home per rule"): safety.md is the one written home of the em-dash rule, edges.md keeps a one-line pointer, every other copy is deleted; the "Use `--`" contradiction is gone; edges.md states its overrides of the harness writing block explicitly.

### Non-Goals

- The other hook fixes (git -C rewrite, branch-name guard, release-guard gaps, heredoc-aware parser, hooks preflight): chunk B.
- review-panel round cap: chunk C. Intent guards for commit/Slack/ingest and secret-guard vectors: chunk D.
- Stripping the 1,361 existing em-dashes from the config tree: parked; revisit when chunk H (prefix trim, tools.md regeneration) rewrites the heaviest files anyway. The lint in this repo's CI (Phase 4) stops new ones.
- Any change to the security-guidance plugin's headless sessions: chunk H. The hooks here fire for them if they share settings.json; that is a side benefit, not a goal.
- sccache restart churn (NRestarts=1248 since 06-28 on the host unit): separate dotfiles issue, noted in References.

## Proposed Solution

### Overview

- Item 1 is config: entries in `HOME/.claude/settings.json` `sandbox` and `env`, three text fixes, one Phase 0 spike for sccache over a unix socket.
- Item 2 is two shell hooks in `HOME/.claude/hooks/` in the existing hook shape (stdin JSON, jq, deny JSON, exit 0), registered in settings.json on `Stop` + `SubagentStop` and on `PreToolUse` with regex matchers; plus the prose edits listed in Phase 4.
- Item 3 is two more rules in the rails function-hooks plugin (the rm rewrite, and an excluded-compound deny added 2026-09-13 under OQ3) (`HOME/.claude/skills/rails/hooks/index.ts`), the same scanner style as the gh-persona rule, using the `{ deny }` result for forms it cannot rewrite.
- Layer choice: the Stop gate must be a shell hook (function hooks' `turn.complete` is observe-only, `claude-code.d.ts:1322-1331`). The em-dash deny is a shell hook too: settings matchers are documented and already proven live on an exact MCP name; rails is early access and fails open. The rm rule is rails because it needs a rewrite, not a deny, and rails already owns Bash rewrites.

### Architecture

```
turn ends ---------> settings Stop/SubagentStop -> hooks/prose.sh --------> {"decision":"block","reason"} | {}
Write/Edit/Bash/MCP -> settings PreToolUse (regex matcher) -> hooks/emdash.sh -> permissionDecision deny | {}
Bash rm ... -------> rails tool.call (index.ts rm rule) -> next({command: "rkvr rmrf ..."}) | { deny } | next(e)
sandboxed command -> settings.sandbox (allowWrite, allowRead, excludedCommands, allowedDomains, env)
```

- `prose.sh` reads `last_assistant_message` from the Stop payload (present in 2.1.270; falls back to parsing `transcript_path` for the last assistant text block) and the last typed user prompt from `transcript_path`. It returns `{}` when `stop_hook_active` is true. The harness caps consecutive blocks at 8 (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8`, from the binary) and then ends the turn, so a hook bug cannot wedge a session.
- `emdash.sh` reads `tool_name` and `tool_input`; the string set to scan depends on the tool (Write `content`; Edit `new_string`; MultiEdit `edits[].new_string`; NotebookEdit `new_source`; Bash `command` only when a `git commit`, `gh pr create|edit|comment`, `gh issue`, or `gh api ... comments` stage is present; MCP tools every string value in `tool_input`).
- rails rm rule, four outcomes per pipeline stage. The question the rule answers is intent: is this regenerable build output (rebuilding costs only time and compilation) or an artifact that cannot be reproduced (which is what the three-week bin exists for)?
  - Pass as plain `rm`, regenerable: stage head is `rm` with delete flags and EVERY path is a build-output directory: its final component is in the regenerable set AND its parent directory holds the toolchain file that produces it. A bare basename match is not enough: `crates/loopr/src/target/tests.rs` is a tracked Rust module named `target` (found by the round-2 scan of 476 worktrees, along with tracked `build/`, `dist/`, `out/`, `coverage/` dirs in seven repos). The set and its toolchain anchors live in safety.md (one home) and rails carries the same table:
    - `target` next to `Cargo.toml`
    - `node_modules`, `dist`, `build`, `out`, `coverage`, `.next`, `.turbo`, `.parcel-cache` next to `package.json`
    - `dist`, `build`, `.venv`, `venv`, `.tox`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `*.egg-info` next to `pyproject.toml`, `setup.py`, `setup.cfg` or `requirements.txt`; additionally `.tox` next to `tox.ini` and `.pytest_cache` next to `pytest.ini`
    - `pom.xml` is deliberately not an anchor for `target`: a tracked Maven `target/` in one work repo holds data files, not only classes
    - Known limit of the positional match (measured 2026-09-13 across the 11 tracked build-named dirs in 476 worktrees): 7 of 11 now fall through to rkvr, including the loopr source module; 4 tracked `dist/` dirs (a committed action bundle, three homework solutions) still pass as plain rm. All four are git-tracked, so recovery is `git checkout`, not the bin. Recorded, accepted.
    - `.gradle` next to `build.gradle`, `build.gradle.kts` or `settings.gradle`; `.terraform` next to any `*.tf`
    - `__pycache__` anywhere (it only ever holds bytecode)
    Relative paths resolve against `$.session.cwd()`; rails checks the anchor with the plugin filesystem interface, no subprocess. If the anchor is absent or the path cannot be resolved (a subagent that `cd`ed elsewhere), the stage falls through to the rkvr rewrite: the safe default costs one tarball, never data. `bin/` and `vendor/` are deliberately not in the set (tracked in 18 and 6 repos respectively; general.md mandates `bin/`). Context line: "rails: rm kept, regenerable build output (rules/safety.md)". Deterministic, no model judgment.
  - Pass as plain `rm`, model-asserted: the stage ends with the shell comment `# regenerable`, defined exactly: an unquoted `#` that STARTS a word (preceded by whitespace or the stage start; `a# regenerable` is two filenames, not a comment, same as bash), followed by exactly ` regenerable` to the end of the stage. `rmRewrite` reuses the existing quote-aware scanner and heredoc stop (`ghSpots`/`segment`, `index.ts:45-94`, generalized to take the head word), so a `#` inside a quoted argument or a heredoc body is data. The marker is stripped BEFORE path collection; the current tokenizer (`SEP` at `index.ts:33`, `WORD` at `:34`) has no `#` handling and would otherwise count `#` and `regenerable` as paths. This is the stochastic fallback Scott asked for: the model decides intent for a path the set does not name, and the marker makes that decision visible in the transcript and in `clyde permit log`. Context line: "rails: rm kept, model asserted regenerable". A path in a home or repo tree that is not obviously build output should never carry the marker; the audit's incident register is the check on abuse.
  - Rewrite: stage head is `rm`, every flag is drawn from `-r`, `-R`, `-f` or their combinations (`-rf`, `-fr`, `-Rf`), no `--`, and neither pass condition holds. Becomes `rkvr rmrf <paths>` with the flags dropped. Context line: "rails: rm -> rkvr rmrf (rules/safety.md); archive at /var/tmp/rmrf; if this was regenerable build output, re-issue with a trailing `# regenerable`". rkvr tars a directory with `-czf` before deleting (`rkvr/src/main.rs:320-326,586`) and copies rather than tars a file whose extension is already an archive (`is_archive`, `copy_files`, `main.rs:363-393`), so the cost of a wrong rewrite is one tarball for 21 days, never data loss.
  - Deny: a wrapper form that deletes through another head (`sudo rm`, `xargs rm`, `find ... -delete`, `find ... -exec rm`, `sh -c '... rm ...'`, `bash -c`, `ssh ... rm`, `docker exec ... rm`, `kubectl exec ... rm`) unless every literal path argument in that stage starts with `$TMPDIR`, `/tmp/claude`, or `/tmp/review-panel`. A wrapper stage with no literal path (bare `xargs rm`) is denied. Reason text names rkvr and safety.md.
  - Pass unchanged: `rm -i`, `rm --` (interactive or ambiguous forms the model chose on purpose), `git rm`, `rm` inside a heredoc body or a quoted string, `rm` inside a `for ... do` body (stage head is `do`; out of scope for a string rewrite). These are logged in the context line as "rails: rm form not rewritten" so the transcript shows the miss.

### Data Model

Stop payload fields used: `stop_hook_active`, `last_assistant_message`, `transcript_path`, `session_id`. SubagentStop adds `agent_id`, `agent_transcript_path`, `agent_type`; the same script handles both.

Prompt extraction, per event:
- Stop (main thread): the last record in `transcript_path` with `type=="last-prompt"`, taking its `lastPrompt` string. Amended 2026-09-13 after Phase 0h: the original predicate (last `type=="user"` record with string `message.content`, not starting with `<`, `isSidechain != true`) discards every slash-command turn, because the harness records a `/skill` invocation as `<command-message>...</command-message>\n<command-name>/...</command-name>`, which the `<` clause throws away. Measured on this doc's own execution session: 16 user records, 0 surviving the predicate. The `last-prompt` record carries the verbatim typed prompt including the leading `/`. Two measured caveats, both handled: it also records agent-injected text (a `Another Claude session sent a message:` teammate relay), which is not a typed prompt and is skipped by that literal prefix; and in one prior session its newest entry lagged the newest typed user record by a turn, so the user-record scan above is retained as a cross-check and the NEWER of the two by position wins.
- SubagentStop: every record in a subagent transcript carries `isSidechain: true` (verified 2026-09-13 on a live subagent transcript: 25 user records, all sidechain), so the main-thread predicate matches nothing there. Use the FIRST user record with string content in `agent_transcript_path`: that is the dispatch prompt, and it is imperative by construction.
- Stale guard: the transcript is written asynchronously and may lag, in which case the newest user record is the PRIOR turn's prompt. Let A be the newest assistant text record in the file and U the newest typed user record. If A's text equals the payload's `last_assistant_message`, the file is fully flushed and U (which precedes A) is the current prompt. Otherwise A is the prior reply, and U must be newer than A by `timestamp`; if it is not, U is stale and the offer rule does not fire. (A predicate that only compared U against the assistant record preceding it in the file would be unconditionally true in an append-only transcript, measured 448 of 448 pairs; comparing U against A alone would be false on the healthy flushed path. This form is safe under both orderings.) If no record qualifies: fail open, one stderr line. Spike 0h proves the extraction in both events, and `prose-test.sh` carries a synthetic lag fixture (U older than A, payload text different from A) that must fail open.

Imperative test: a prompt whose first character is `/` (a slash-command invocation) counts as imperative outright (amended 2026-09-13 during Phase 2: without this the `last-prompt` amendment above is inert, because `/how-to-execute-a-plan` is in no verb list, so every `/skill` turn would extract its prompt correctly and then fail the gate anyway). Otherwise: the first word, lowercased and stripped of punctuation, is in a fixed verb list (do, fix, add, run, write, make, ship, bump, merge, publish, update, remove, delete, dispatch, send, build, implement, execute, create, install, commit, push, land, finish, proceed, continue, use, read, check, search, find, look, review, verify, test, probe, pull, rebase, open, close, resolve, address, apply, deploy, babysit, shakedown), or the whole prompt is a bare go-ahead: five words or fewer and, matched on WORD BOUNDARIES, contains `yes`, `y`, `ok`, `okay`, `go`, `do it`, `proceed`, `ship it`, or `send it`. Word boundaries matter: "read the okta docs" and "check the golang build" are not go-aheads. `using` and bare `go` are out of the verb list ("Using X, explain Y" is not imperative; `go` is covered by the go-ahead form).

Offer test: strip fenced code blocks and backtick spans from the assistant text (a reply that quotes or searches for the phrase "Say the word" is not offering), take the final sentence (after the last `.`, `!`, `?` or newline boundary, up to 300 characters), and match `(Want me to|Shall I|Should I|Say the word|Say go|your call|Would you like me to|Do you want me to|If you want,? I can)`. `Let me know if` is out: it is the loosest form and reads as a status closer as often as an offer. A legitimate confirmation before a destructive action is asked in the decision shape (interaction.md), which none of these phrases match.

Decision-ask test: the text contains a line starting with `Rec:` or its last non-empty line ends with `?`, and the text exceeds 20 lines.

Em-dash predicate: any literal U+2014 in the scanned strings is a deny. The escape forms `\u{2014}` and `\x{2014}` are the substitute for the literal (safety.md:28), never a companion to it, so their presence exempts nothing. The only carve-out is the path allowlist `tests/fixtures/` and `*.golden`. (Amended 2026-09-13 after Phase 3: the original spec also carried a bare `*.json`, which exempts every config and data file in the tree, far wider than the JSON-fixture case it existed for. A JSON fixture that needs the character goes under `tests/fixtures/`, which the allowlist already covers. Doc defect, caught at finalization; the implementation and its fixture matrix were narrowed to match.) A verbatim quote that carries an em-dash (a log excerpt, a pasted message) is recast or written under a fixtures path; the rule has no "quoting" exemption, same as the CI lint in safety.md.

Empty-text pass-through: when the last assistant message has no text block (a StructuredOutput-only turn, as in the security-guidance plugin's headless sdk-py sessions), `prose.sh` returns `{}`. Those sessions otherwise fire the hook on every commit and push.

### API Design

Hook registration in `HOME/.claude/settings.json`:

```json
"Stop":         [{ "matcher": "", "hooks": [{ "type": "command", "command": "~/.claude/hooks/prose.sh" }] }],
"SubagentStop": [{ "matcher": "", "hooks": [{ "type": "command", "command": "~/.claude/hooks/prose.sh" }] }],
"PreToolUse": [
  { "matcher": "Write|Edit|MultiEdit|NotebookEdit", "hooks": [{ "type": "command", "command": "~/.claude/hooks/emdash.sh" }] },
  { "matcher": "Bash", "hooks": [ ...existing nine..., { "type": "command", "command": "~/.claude/hooks/emdash.sh" }] },
  { "matcher": "mcp__slack__chat_post_message|mcp__slack__chat_update|mcp__slack__conversations_add_message|mcp__atlassian__(addCommentToJiraIssue|createJiraIssue|editJiraIssue|createConfluencePage|updateConfluencePage|createConfluenceFooterComment|createConfluenceInlineComment)|mcp__marquee__marquee_(publish|update)", "hooks": [{ "type": "command", "command": "~/.claude/hooks/emdash.sh" }] }
]
```

Hook outputs: `prose.sh` prints `{"decision":"block","reason":"<rule> (rules/safety.md | rules/interaction.md | output-styles/edges.md)"}` or `{}`. `emdash.sh` prints `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"em-dash (U+2014) in <field>; recast with a colon, parens, comma, or a split sentence (rules/safety.md)"}}` or `{}`. Both take `--self-test` like git-release-guard.sh and ship a `-test.sh` fixture matrix in the same `run <expect> <fixture>` shape as `git-release-guard-test.sh:121-137`.

Sandbox config after Phase 1 (additions only):

```json
"sandbox": {
  "filesystem": {
    "allowWrite": [ ...existing..., "/var/tmp/rmrf", "/var/tmp/bkup" ],
    "allowRead":  [ ...existing...,
                    "/home/saidler/.ssh/identities/home/signing",
                    "/home/saidler/.ssh/identities/home/signing.pub",
                    "/home/saidler/.ssh/identities/work/signing",
                    "/home/saidler/.ssh/identities/work/signing.pub",
                    "/home/saidler/.ssh/allowed_signers" ]
    // Absolute paths: the existing entries are absolute and `~` expansion in this list is unproven.
    // Private halves are included deliberately (OQ2 / decision D): ssh-agent is unreachable in-sandbox
    // (the sandbox denies socket(AF_UNIX) creation outright), so ssh-keygen -Y sign must read the key file.
    // Both are SIGNING-ONLY keys. Nothing named `id_ed25519` ever appears in this list.
  },
  // WARNING: an entry matches ANY STAGE ANYWHERE in a compound and exempts the WHOLE command,
  // not just a leading head. So every entry here is a general sandbox-escape hatch
  // (`<anything> ; ssh -V` runs unsandboxed). Measured 2026-09-13, evidence.md 0g. The rails
  // excluded-compound deny in Phase 5 forbids mixing an excluded stage with a non-excluded one,
  // which is the only way the model can reach that hatch.
  "excludedCommands": [ "cargo *", "otto *", "release *", "bump *", "systemctl *", "journalctl *", "crontab *", "ssh *",
                        "~/.claude/skills/architect/script.sh *", "~/.claude/skills/staff-engineer/script.sh *" ]
},
"env": { ...existing..., "TMPDIR": "/tmp/claude-1000", "RUSTC_WRAPPER": "" }
// TMPDIR: confirmed by Phase 0e. Sandboxed value is unchanged; the unsandboxed value was EMPTY and is now set.
// 1000 is Scott's uid on desk.lan, the same value the sandbox injects.
// RUSTC_WRAPPER="": the Phase 0f fallback, adopted because the unix-socket remedy is dead at the syscall level.
```

rails rule shape (index.ts, beside the gh-persona rule):

```ts
// same event shape as the gh-persona rule: e.command is the string, next({...e, command}) rewrites,
// withContext decorates the RESULT of next (index.ts:124-126, 137-138, 169-170)
on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
  const command = e.command
  if (typeof command !== 'string') { return next(e) }
  const r = rmRewrite(command)                       // pure string fn, tested in index.test.ts
  if (r.deny !== undefined) { return { deny: r.deny } }
  if (r.command === command) { return r.note ? withContext(await next(e), r.note) : next(e) }
  return withContext(await next({ ...e, command: r.command }), r.note)
})
```

### Implementation Plan

Operator steps that are not code, stated once: (a) a NEW hook file is inert until `manifest -l HOME/.claude/hooks/* | bash` runs from the repo root with the glob UNQUOTED (per-file symlinks, `manifest.yml:1-7`). Verified 2026-09-13: the quoted form `'HOME/.claude/hooks/*'` emits a linker script with an empty link list and exits 0, so a hook registered in settings.json would silently never exist under `~/.claude/hooks`. The unquoted glob also links `__pycache__/*.pyc`; Phase 1 adds `HOME/.claude/hooks/__pycache__/` to `.gitignore`. Editing an existing linked file is live; (b) phases that edit `HOME/.claude/settings.json` or hooks run with auto mode off (11 `[Self-Modification]` classifier blocks in the audit); (c) the sccache socket change, if Phase 0f passes, is a `scottidler/dotfiles` PR (`HOME/.config/systemd/user/sccache.service`) and ships before Phase 1.

#### Phase 0: prove the harness assumptions (zero code)
**Model:** fable
Each spike runs against a scratch `--settings` file or a throwaway rails copy, sandbox off where noted, and records its evidence under `docs/design/2026-09-13-enforcement-core-phase0/`.
- 0a Stop hook fires and blocks: scratch Stop hook that tees stdin to a file and returns `{"decision":"block","reason":"probe"}` when `stop_hook_active` is false. Also one Agent call to capture a SubagentStop payload.
- 0b PreToolUse regex matchers: a probe hook on `Write|Edit|MultiEdit|NotebookEdit` and on `mcp__slack__chat_post_message` that logs `tool_name`.
- 0c rails deny: superseded 2026-09-13. The throwaway probe is replaced by the real excluded-compound deny rule, whose live check (`$TMPDIR/marker.sh; ssh -V` denied, in main and in a subagent) must run before Phase 5 ships. Never run as a spike.
- 0d sandbox edits apply live: add the allowWrite/allowRead entries, then in the same session run in-sandbox `rkvr rmrf $TMPDIR/probe` and `git -C <scratch repo> commit --allow-empty -m probe`. **Result 2026-09-13: PASS, proven during Phase 1 rather than as a spike.** The settings patch applied to the RUNNING session with no restart: both commands failed before it and succeeded immediately after.
- 0e TMPDIR: `--settings '{"env":{"TMPDIR":"/tmp/claude-1000"}}'`, print `TMPDIR` sandboxed and unsandboxed.
- 0f sccache over a unix socket: host-side second server with `SCCACHE_SERVER_UDS=~/.cache/sccache/server.sock`; in-sandbox `SCCACHE_SERVER_UDS=... sccache --show-stats`. **Result 2026-09-13: FAILED, and the approach is dead.** The sandbox denies `socket(AF_UNIX, SOCK_STREAM)` creation outright, EPERM before any `connect()`, so no filesystem allowlist entry can reach a socket that a sandboxed process cannot even create. Trace: `connect_to_server(...server.sock)` then `sccache: error: Operation not permitted (os error 1)`; isolated in Python to the bare `socket.socket(AF_UNIX, SOCK_STREAM)` call. The doc's recorded fallback applies: `"RUSTC_WRAPPER": ""` in settings `env`, which loses the cache for sandboxed cargo runs while the excluded (unsandboxed) ones keep using the host server on 127.0.0.1:4227. The dotfiles `sccache.service` PR named in Dependencies is therefore not needed and the ship order loses its first step.
- 0g excludedCommands accepts a path prefix: add `~/.claude/skills/architect/script.sh *`, run the script in-sandbox with a no-op prompt, confirm egress.
- 0h prompt extraction: the 0a probe hook also prints the prompt it extracts (per the Data Model rules) next to the known typed prompt, in main and in one subagent, and prints whether the transcript's newest assistant text equals the payload's `last_assistant_message` (the flushed vs lagging case). The stale case itself is not left to chance: it is a synthetic transcript fixture in Phase 2's `prose-test.sh`.
- **Success criteria:** 0a tee file contains `last_assistant_message` and `transcript_path`; the transcript shows the block reason then a second assistant turn; a SubagentStop payload was captured. 0b log has lines for Write, Edit and the MCP tool and none for Read. 0c tool_result is an error carrying the deny text in main and in a subagent. 0d both commands exit 0 without a restart (or the doc records that a restart was needed). 0e sandboxed value unchanged, unsandboxed value set. 0f in-sandbox stats equal the host's. 0g the script reaches its host from inside the session. 0h the extracted prompt equals the typed prompt in main and equals the dispatch prompt in the subagent, and the flushed-vs-lagging observation is recorded; the stale case is covered by the Phase 2 fixture, not by this spike.

#### Phase 1: sandbox config and text fixes
**Model:** sonnet
- **Prerequisite, operator steps, BEFORE the settings.json edit** (OQ2 decision D, Scott 2026-09-13). Home gets the signing/auth split work already has:
  1. `ssh-keygen -t ed25519 -N '' -C 'home signing key' -f ~/.ssh/identities/home/signing`. Passphrase-less on purpose: AF_UNIX is denied in-sandbox so no agent can unlock it, and a passphrase would just reproduce the failure this phase fixes.
  2. Register the public half on scottidler as a **Signing** key, never an Authentication key: `gh ssh-key add ~/.ssh/identities/home/signing.pub --type signing --title 'home signing key (desk)'`. **Blocked today:** this needs `admin:ssh_signing_key`, and neither PAT carries it (`gh api user/ssh_signing_keys` 404s on both). Re-scope `github-pat-home` or register the key by hand first.
  3. Append to `~/.ssh/allowed_signers`: `scott.a.idler@gmail.com namespaces="git" <contents of signing.pub>`. That file is untracked and already holds the two work entries; leave it untracked.
  4. `scottidler/dotfiles` `HOME/.gitconfig` `user.signingkey` -> `~/.ssh/identities/home/signing.pub`. `~/.gitconfig-work:9` is unchanged, work already points at its signing-only key.
  - Ship order is load-bearing: steps 1 to 4, THEN the settings.json edit. Reversed, AC1 fails on personal repos with `No private key found for public key`.
  - Blast radius: the `scottidler/dotfiles` repo and the scottidler GitHub account. Work side needs no new key and no GitHub change.
- `HOME/.claude/settings.json`: the `sandbox` and `env` additions above. `excludedCommands` is unchanged by the OQ2 decision: `"git commit *"` is deliberately NOT added, because D is one mechanism and adding a second would leave two half-working paths.
- `agents/review-panel.md:176-182`: replace the false excludedCommands claim with the true entry.
- `hooks/ssh-agent-check.sh:10`: the hook's premise is dead. It checks agent reachability, and Phase 0 proved no sandboxed process can reach any agent (`socket(AF_UNIX)` is EPERM). Rewrite it: probe that the active `user.signingkey` `.pub` AND its private sibling are readable, printing one WARN line naming the `sandbox.filesystem.allowRead` key if either is not; drop the "commits need the sandbox disabled" text entirely; keep `ssh-add -l` only as a warning about unsandboxed pushes, not about signing.
- `CLAUDE.md` sandbox section (`:34-42`): two lines. "A command that fails with Operation not permitted / Read-only file system is retried unsandboxed once, silently; the failure is never narrated or diagnosed as a system problem." "Never set dangerouslyDisableSandbox on a command whose head is in sandbox.excludedCommands."
- `.gitignore`: add `HOME/.claude/hooks/__pycache__/` (the unquoted manifest glob would otherwise link the `.pyc`).
- **Success criteria:** in-sandbox `git commit --allow-empty -m probe` exits 0 with a good signature (`git log -1 --show-signature`) in a scratch repo under `~/repos/scottidler/` AND in one under `~/repos/tatari-tv/`, once per persona, each reporting the matching email; both signing keys fail auth (`ssh -T git@github.com -i ~/.ssh/identities/<home|work>/signing -o IdentitiesOnly=yes` returns `Permission denied (publickey)`); in-sandbox reads of `~/.ssh/identities/home/id_ed25519` and `~/.ssh/identities/work/id_ed25519` are still denied; in-sandbox `rkvr rmrf $TMPDIR/probe` exits 0 and prints a `/var/tmp/rmrf/` path; in-sandbox `cd ~/repos/scottidler/rkvr && cargo check` emits no `sccache: error`; unsandboxed `echo $TMPDIR` is non-empty; `git check-ignore -q HOME/.claude/hooks/__pycache__/x.pyc` exits 0.

#### Phase 2: Stop hook `prose.sh`
**Model:** opus
- New `HOME/.claude/hooks/prose.sh` and `prose-test.sh`; register on `Stop` and `SubagentStop`; run the manifest link step.
- Rules: em-dash in the final text; offer-closer in the final sentence (per the Data Model offer test: code and quoted spans stripped, final-sentence anchor) when the last typed prompt is imperative or a bare go-ahead; decision ask over 20 lines. Pass-through when `stop_hook_active` is true, when the last assistant message has no text block, or when the transcript cannot be read (fail open, one stderr line).
- Reason text names the rule file and quotes the offending line, so the model's rewrite is one edit. No warn-only path: a Stop hook blocks or passes, and a non-blocking note reaches only the user, so "real <noun>" and sizing words stay in edges.md as prose.
- Fixtures are inline in `prose-test.sh` like `git-release-guard-test.sh`: each case is a JSON payload piped to the hook and an expected `decision` field.
- **Success criteria:** `prose-test.sh` passes a positive and negative fixture per rule plus the `stop_hook_active` and empty-text pass-throughs; a live reply containing U+2014 is blocked with a reason naming safety.md. **The live OFFER check moved to Phase 6** (amended 2026-09-13 during Phase 2): it was written as a `claude -p` run, and Phase 0h proved `-p` sessions write no transcript at all, so no prompt exists, the offer rule fails open by construction, and the criterion is unsatisfiable in this phase's harness. It needs an interactive session, which is what Phase 6 has. This is a doc defect, not an implementation gap: the em-dash half of the live check was run and passed in Phase 2.

#### Phase 3: em-dash PreToolUse `emdash.sh`
**Model:** opus
- New `HOME/.claude/hooks/emdash.sh` and `emdash-test.sh`; register on the three matchers above; run the manifest link step. Bash branch reuses git-release-guard's heredoc-aware stage split for the `git commit` / `gh` detection.
- **Success criteria:** fixtures pass (Write with a literal U+2014 denied; Write whose content carries the escape `\u{2014}` and no literal allowed; Write with a literal U+2014 under `tests/fixtures/` allowed; Write with a literal U+2014 plus the escape text denied; Edit `new_string` denied; `git commit -m` with a U+2014 in the message denied; `rg` with a U+2014 pattern and no commit stage allowed; `mcp__slack__chat_post_message` with U+2014 in `text` denied); live Write of a file containing U+2014 is denied with the safety.md reason.

#### Phase 4: prose dedupe and overrides
**Model:** sonnet
- `safety.md:15` and `voice.md:22`: drop "Use `--`"; replacements are a colon, parens, a comma, or a split sentence.
- `safety.md` File Deletion section, rewritten around intent (Scott, 2026-09-13: "if its a build directory, fuck it we can rebuild the files and it only costs us time and compilation. other artifacts cant be easily recovered or reproduced, thats why they get the rmrf"): regenerable build output may be removed with plain `rm -rf`; the named set WITH its toolchain anchors (the table above) and one scar-tissue line on why the match is positional, not bare basename (`crates/loopr/src/target/tests.rs` is a tracked source module named `target`); the `# regenerable` marker for a path outside the set, with the rule that the marker asserts intent and is audited; everything else goes through `rkvr rmrf`. Plus the CI-teardown exception: a repo's own pipeline uses plain remove; rkvr is for Scott's machines (Scott, 2026-07-08, git-tools session `16fbd7b8`: "rkvr is meant for protecting files on MY SYSTEM!"). Both are rulings he already made, recorded once, here.
- `rules/secrets.md:109`: "The transcript shows the prefixed command" is false (verified 2026-09-13: the transcript records the model's original command; only `clyde permit log` and the context line show the rewrite). Correct it to say so.
- Delete the em-dash lines from `skills/slackify/SKILL.md:44,48,53`, `slack-clipboard:25,32`, `slack-old:47`, `openday:59`, `closeday:36`, `create-design-doc:32,124`, `anthropic-usage-report:105`, `clauderize:119`, `refs/slack.md:48`. Leave `last30days` (vendored). `edges.md:13` stays as the one in-session line pointing at safety.md.
- `edges.md`: add a section "Overrides of the harness writing block": no opening line announcing what is about to happen; no closing recap and no closing offer (in scope means do it, otherwise omit it); labels with colons, pipes and `->` allowed; parens allowed; at most one three-line status block per phase or external wait.
- `interaction.md` under the question shape: "A decision ask is the entire message. Nothing above The problem, nothing below Rec. State and progress go in an earlier message or not at all."
- Every file this PR edits leaves with zero em-dashes, with one named exception: `agents/review-panel.md` (44 today) is rewritten wholesale by chunk C, so only its lines 176-182 change here. Today's counts in the touched set: `interaction.md` 12, `CLAUDE.md` 19, `ssh-agent-check.sh` 2; `safety.md`, `voice.md`, `edges.md`, `index.ts` 0.
- Add `.otto.yml` to this repo with a `lint` task carrying the em-dash check from `safety.md:17-28` over an explicit file list (the touched set above minus review-panel.md; chunks that touch more files extend the list until it becomes a glob), plus `whitespace -r`, and a `test` task that runs every `HOME/.claude/hooks/*-test.sh` and `bun test` in `HOME/.claude/skills/rails/hooks`.
- **Success criteria:** `rg -c 'Use `--`' HOME/repos/.claude/rules/safety.md HOME/repos/.claude/rules/voice.md` prints nothing; `rg -l -i 'em.dash' HOME/.claude/skills` prints nothing (rg does not follow the vendored `last30days` symlink, so it never appears); `rg -c $'\\u2014' <each file in the lint list>` prints nothing for every file; `otto ci` exits 0.

#### Phase 5: rails rm rule and excluded-compound deny
**Model:** opus
- `skills/rails/hooks/index.ts`: `rmRewrite(command)` (pure, returns `{command, note}` or `{deny}`) and its `tool.call` registration; the regenerable regex as a named constant with a comment pointing at safety.md. `index.test.ts` cases: `rm -rf ~/x` -> `rkvr rmrf ~/x`; `rm -r a b` -> `rkvr rmrf a b`; `rm -rf $TMPDIR/x` -> `rkvr rmrf $TMPDIR/x`; `cd $TMPDIR && rm -rf x` -> `cd $TMPDIR && rkvr rmrf x`; `rm -rf "a b/c"` -> `rkvr rmrf "a b/c"` (quotes preserved); `rm -rf target/` with `Cargo.toml` beside it unchanged, regenerable note; `rm -rf ./target node_modules` with both anchors unchanged; `rm -rf crates/loopr/src/target` (no `Cargo.toml` in `src/`) -> rkvr; `rm -rf target` with no anchor in cwd -> rkvr; `rm -rf target src` -> `rkvr rmrf target src` (one non-regenerable path makes the whole stage rkvr); `rm -rf ~/scratch/big # regenerable` unchanged, model-asserted note; `rm -rf ~/x #regenerable-ish` -> rkvr (marker must be exact); `rm -rf precious a# regenerable` -> rkvr (`a#` is a filename, no comment opened); `rm -rf "x # regenerable"` -> rkvr (quoted, not a marker); `cat <<EOF ... # regenerable\nEOF` with an `rm -rf y` stage before it -> the rm stage rewrites, the heredoc body is data; `rm -i x` unchanged; `rm -- -weird` unchanged; `git rm x` unchanged; `rm` inside a heredoc body unchanged; `for f in *; do rm -rf $f; done` unchanged with the miss noted; `sudo rm -rf /opt/x` denied; `find . -name '*.o' -delete` denied; `find $TMPDIR -delete` passes; `xargs rm -rf` denied; `sh -c 'rm -rf /x'` denied.
- Context lines: on rewrite "rails: rm -> rkvr rmrf (rules/safety.md); archive at /var/tmp/rmrf; if this was regenerable build output, re-issue with a trailing `# regenerable`"; on a regenerable pass "rails: rm kept, regenerable build output (rules/safety.md)" or "rails: rm kept, model asserted regenerable"; on a pass-unchanged miss "rails: rm form not rewritten (<reason>)".
- `git` leaves `RM_INTEREST` and the `git rm` branch leaves `rmRewrite` (added 2026-09-13 beside the excluded-compound rule): `git rm` stages a deletion whose content stays recoverable from git history, so it is not the class rkvr protects, and the branch spent a context line on every one. The test that pinned the old note is inverted rather than deleted.
- **Excluded-compound deny, the third rails rule** (OQ3, Scott's option D). `sandbox.excludedCommands` matches any stage ANYWHERE in a compound and exempts the ENTIRE compound, so appending `; ssh -V` to anything opts it out of the sandbox with no approval prompt. Only the model can compose such a command, so rails removes the composition:
  - The list comes from `$.settings.read()`, the engine's own merged settings view, read once per session on the first Bash call and cached, with the trailing ` *` stripped. One source of truth: the ten entries are never restated in the plugin. A read that rejects, or a list that is absent or wrongly typed, yields no entries, which makes the rule inert (fail open, same posture as the rest of rails). Not read from `~/.claude/settings.json` by path: a hooks module may import nothing but its own files and `claude-code`, so `node:fs` is unavailable and `claude plugin validate --strict` refuses it by name (measured 2026-09-13). `$.settings.read()` is the better seam anyway, because it carries `--settings` and project overrides the engine is actually running under.
  - Per command, reusing the existing quote-aware, heredoc-stopping scanner (`heads`, `segment`, `splitWords`; no second parser): `EX` is every stage whose head matches an excluded entry, `REST` is every other stage minus the transparent ones (`cd`, `export`, bare `VAR=value` assignments, `true`, `echo`) and minus a stdin-only pipe target (below). `EX` non-empty AND `REST` non-empty is a deny; everything else passes untouched.
  - Stdin-only pipe targets are transparent too (Scott 2026-09-13, option C, after the pipe blast radius below was measured). A consumer is transparent only when BOTH hold: (1) it is a PIPE target, separated by a single `|` and never by `;`, `&&` or `||`; (2) it carries no file operand, meaning every argument is a flag or a flag value. Set: `tail head cat nl sort uniq wc less rg grep jq awk sed`. The pattern-taking members (`rg`, `grep`, `jq`, `awk`, `sed`) may carry exactly one non-flag word, their pattern or program; a second is a path and denies. A bare number counts as a flag value, so `tail -n 50` is transparent and `tail -50 ci.log` is not. `tee` is deliberately absent: a file operand is its whole purpose, and an unsandboxed `tee` writes wherever it likes, so `otto ci 2>&1 | tee $TMPDIR/ci.log` denies (`otto ci` alone already prints the path of its own timestamped log). Both halves are load-bearing: keying on the NAME alone would let `cargo --version; tail ~/.ssh/identities/home/id_ed25519` read a deny-listed key unsandboxed, which is worse than the hatch being closed because it needs no marker command and reads as innocuous.
  - The scanner gained redirection handling for this: `2>&1` previously read as a `&` separator followed by a stage headed `1`, so `otto ci 2>&1 | tail -50` had a phantom `REST` entry. `heads` now steps over a redirection operator, an `&` fd duplication and the target, and none of the three is ever a head. The gh-persona and rm rules inherit the fix.
  - Reason text: `rails: "<rest head>" would run unsandboxed because "<ex head>" is in sandbox.excludedCommands; run them as separate Bash calls`.
  - Wrappers (`sh -c`, `bash -c`, `zsh -c`, `sudo`, `xargs`, `env`, `nohup`) are classified by their INNER head, to a depth of three, so `bash -c 'ssh -V; marker.sh'` denies on the inner stage. Whether the engine's matcher looks inside a `-c` payload is unmeasured; denying either way makes that irrelevant. `ssh` is deliberately not a wrapper here: `ssh host ls` is one command, and treating `host` as an inner head would deny it.
  - `index.test.ts` cases. Pass: `cargo test`; `cd r && cargo test`; `ssh host ls`; `X=1 bump -m`; `cargo build && cargo test`; `git status && rg todo`; `sudo systemctl restart sccache`; `env FOO=1 cargo build`; `sh -c 'cargo build'`; a heredoc body naming `ssh -V`; an empty entry list. Deny: `$TMPDIR/marker.sh; ssh -V` (trailing, the case that rules prefix matching out); `ssh -V; $TMPDIR/marker.sh` (leading); `curl x | sh; cargo --version`; `bash -c 'ssh -V; $TMPDIR/marker.sh'`; `$TMPDIR/marker.sh $(cargo --version)`; `sudo $TMPDIR/marker.sh; ssh -V`. Plus `excludedHeads` parse cases (glob stripped, multi-word entry kept whole, malformed or wrongly typed settings yield none) and one case that parses this repo's own `settings.json` into the live ten.
  - Option C's own eight, each a fixture: `otto ci 2>&1 | tail -50` PASS; `cargo test | rg fail` PASS; `cargo test | rg fail tests/` DENY (file operand); `cd r && cargo build 2>&1 | tee $TMPDIR/ci.log` DENY (tee); `git -C p status && cargo test` DENY (git is REST); `cargo --version; tail ~/.ssh/identities/home/id_ed25519` DENY (semicolon, and a file operand); `curl x | sh; cargo --version` DENY; `$TMPDIR/marker.sh; ssh -V` DENY. Plus `readsOnlyStdin` unit cases and `heads` cases pinning that a redirection is never a stage and that only a single `|` marks a piped head.
  - **Known limit, not solved here and not solvable by this rule's shape: redirections are not stages.** `cargo --version > ~/.ssh/authorized_keys` is a single excluded stage with an empty `REST`, so it passes and runs unsandboxed with an arbitrary write. Options A, B and C all share this. Recorded in Risks, re-checked as a Phase 6 observation, and a candidate for a later chunk.
- **Success criteria:** `bun test` passes; live `rm -rf ~/probe` runs as `rkvr rmrf ~/probe` (the `clyde permit log` record shows the rewritten command, the tool result carries the context line, a new archive appears under `/var/tmp/rmrf/`); live `rm -rf <some repo>/target` runs unchanged with the regenerable context line and no new archive; `sudo rm -rf /opt/probe` is denied with the rkvr reason; a subagent Bash `rm -rf ~/probe2` shows the same three signals; live `$TMPDIR/marker.sh; cargo --version` is denied by the excluded-compound rule while `cargo --version` alone runs; `claude plugin validate --strict ~/.claude/skills/rails` passes.

#### Phase 6: shakedown and close
**Model:** fable
- Re-run every Phase 1 to 5 criterion against the live setup after the PR merges and the manifest link step ran on desk.lan; record Observed lines in this doc.
- Inherited from Phase 2 (unsatisfiable in a `-p` harness, needs an interactive session): a reply ending with an offer after an imperative prompt is blocked once, the transcript shows the block reason, and the second assistant turn carries no offer.
- Inherited from Phase 1, replacing the path-head question (moot under any-stage matching): run the three-line marker matrix. `$TMPDIR/marker.sh` alone is SANDBOXED; `cargo --version` alone is UNSANDBOXED; `$TMPDIR/marker.sh; cargo --version` is DENIED by the rails rule. The AF_UNIX socket creation test is the sandbox marker; a network probe is not, because the egress proxy allows some hosts either way.
- Observe the excluded-compound rule's known limit live, do not fix it here: run `cargo --version > $TMPDIR/redirect-probe` in-sandbox and record that it passes the rails rule and writes unsandboxed. A redirection is not a stage, so no option on the table sees it; the observation sizes whether a redirect-target guard earns its own chunk.
- Also settle one inconsistency the audit leaves open: findings F7.3 reports `cd x && cargo` FAILING in-sandbox, which contradicts today's any-stage measurement. Either the matcher changed between binaries or those runs were child processes under `bump`/`otto`/`python3 -`, which is a process-tree issue and not a stage. Run `cd ~/repos/scottidler/rkvr && cargo check` and record which it is.
- Inherited from Phase 1 (blocked on the operator prerequisite): AC1 and AC1b, once Scott has minted and registered the home signing key.
- Flip chunk A to `done` in `docs/design/2026-09-13-setup-audit-program.md` with the PR URL; mark chunk B `next`.
- **Success criteria:** every criterion has an Observed line dated after the merge; the tracker row is `done`.

## Acceptance Criteria

- [ ] AC1: in a sandboxed Bash call, `git commit --allow-empty -m probe` exits 0 and `git log -1 --show-signature` reports a good signature, run twice: once in a scratch repo under `~/repos/scottidler/` and once under `~/repos/tatari-tv/`, each reporting its persona's email.
  - Observed on main (2026-09-13, sandboxed, scratch repo under `$TMPDIR`): `fatal: failed to write commit object` (the signing failure this doc fixes). Passes after Phase 1 and its operator prerequisite.
- [ ] AC1b (the property that makes AC1's key exposure acceptable): neither signing key can authenticate, and no auth key is readable in-sandbox. `ssh -T git@github.com -i ~/.ssh/identities/home/signing -o IdentitiesOnly=yes` returns `Permission denied (publickey)`, same for `work/signing`; in-sandbox reads of `~/.ssh/identities/home/id_ed25519` and `~/.ssh/identities/work/id_ed25519` are still denied; `https://github.com/scottidler.keys` and `https://github.com/escote-tatari.keys` contain neither `signing.pub` blob.
  - Observed on main: the home half cannot run; `home/signing` does not exist until the Phase 1 prerequisite. The work half holds today (2026-09-13, blob-hash match): `work/signing.pub` is absent from escote-tatari's authentication keys and present in its signing keys.
- [ ] AC2: in a sandboxed Bash call, `rkvr rmrf $TMPDIR/probe` exits 0 and the archive lands under `/var/tmp/rmrf/`.
  - Observed on main (2026-09-13, sandboxed): rkvr panics at `src/main.rs:556` creating its base directory (read-only `/var/tmp`). Passes after Phase 1.
- [ ] AC3: a Stop-hook fixture whose final text ends with "Want me to run it?" after the prompt "fix the test" returns `{"decision":"block",...}`; the same fixture with `stop_hook_active: true` returns `{}`.
  - Observed on main: cannot run; `prose.sh` does not exist until Phase 2.
- [ ] AC4: a PreToolUse fixture for Write with `content` containing a literal U+2014 returns `permissionDecision: deny`; content that carries the escape text `\u{2014}` and no literal U+2014 returns `{}`; content with a literal U+2014 under `tests/fixtures/` returns `{}`.
  - Observed on main: cannot run; `emdash.sh` does not exist until Phase 3.
- [ ] AC5: a Bash tool call `rm -rf ~/probe` reaches the shell as `rkvr rmrf ~/probe`: the `clyde permit log` record for that call shows the rewritten command, the tool result carries the context line "rails: rm -> rkvr rmrf", and `~/probe` is absent afterwards with a new archive under `/var/tmp/rmrf/`. The transcript's `tool_use.input.command` still shows the model's original `rm -rf ~/probe` (verified 2026-09-13 against a live rails session: the transcript records what the model emitted, not what rails ran).
  - Observed on main: cannot run; the rails rm rule does not exist until Phase 5. Today `rm -rf` passes through unchanged (the audit's 1,452 statements).
- [ ] AC6: `rg -c 'Use `--`'` over `rules/safety.md` and `rules/voice.md` prints nothing, and `rg -l -i 'em.dash' HOME/.claude/skills` prints nothing.
  - Observed on main (2026-09-13): `voice.md:1`, `safety.md:1` for the first command; the second lists 8 files (anthropic-usage-report, clauderize, closeday, create-design-doc, openday, slack-clipboard, slackify, slack-old) and not `last30days`, because rg does not follow that symlink. Passes after Phase 4.

Each criterion gets an `Observed on main:` line before this doc is marked ready; the ones that depend on an unshipped phase say so and cite the phase.

### Observed after Phases 1 to 5 (2026-09-13, branch `enforcement-core`, nothing merged, linker step NOT run)

| AC | Result | Evidence |
|---|---|---|
| AC1 signed commit in-sandbox | **PASS** | After Scott minted `home/signing`, appended `allowed_signers` and ran the settings patch: `Good "git" signature for scott.a.idler@gmail.com with ED25519 key SHA256:9YsW/1jYsliBbkKfUK9UVBU0QzWvwGc83UFjl81zZNE`. GitHub registration of the key is still pending but does NOT gate this: signature validity is local via `allowed_signers`; the GitHub step only controls the Verified badge. |
| AC1b signing keys cannot auth | **PARTIAL** | Work half holds (blob-hash verified: `work/signing.pub` absent from escote-tatari auth keys). Home half cannot run, `home/signing` does not exist yet. |
| AC2 `rkvr rmrf` in-sandbox | **PASS** | `rkvr rmrf $TMPDIR/ac2probe` exits 0 and prints `-> /var/tmp/rmrf/2026-09-13-162946-000/`. |
| AC3 Stop hook fixtures | **PASS** | `prose-test.sh`: 27 passed, 0 failed. Break-the-code run twice (stale guard inverted: 5 failures; em-dash predicate negated: 16). |
| AC4 em-dash PreToolUse fixtures | **PASS** | `emdash-test.sh`: 30 passed, 0 failed. Break-the-code run once (escape-exempts-payload predicate: 29/30). |
| AC5 live `rm` rewrite | **DEFERRED to Phase 6** | The rails rule is unit-tested (66 tests, 109 assertions, `claude plugin validate --strict` passes) but inert until the linker step runs. No live `rm` was executed. |
| AC6 prose dedupe greps | **PASS** | Both commands print nothing. |

Phases 1 to 5 commits: `7fde500` (Phase 1, PARTIAL), `3ff78d1` (Phase 2), `1523d22` (Phase 3), `4ef9019` (Phase 4), `544df56` (Phase 5). `otto ci` exits 0 as of Phase 4.

**What is owed before this doc can be marked Implemented:**
1. Scott's operator prerequisite: mint `~/.ssh/identities/home/signing`, register it on scottidler as a Signing key (needs `admin:ssh_signing_key`, which neither PAT carries today), add the `allowed_signers` line, point dotfiles `user.signingkey` at it.
2. Phase 1's second commit, which needs auto mode off: the `settings.json` `sandbox`/`env` block and the two `CLAUDE.md` sandbox lines. Denied three times with `[Self-Modification]`.
3. `HOME/.claude/CLAUDE.md` added to the `.otto.yml` lint list once its em-dashes can be fixed (Phase 4 omitted it because it could not fix what it could not edit).
4. Phase 6 itself: the linker step on desk.lan, then every live criterion re-run.

## Resolved Decisions

- 2026-09-13, Scott (closes OQ3): **option D.** All ten `excludedCommands` entries stay, and a third rails rule denies any command that mixes an excluded stage with a non-excluded one. Reasoning that decided it: hatch count is not the variable. `excludedCommands` matches any stage anywhere and exempts the whole compound, so `; cargo --version` has been a silent, classifier-free escape since `cargo *` landed. One hatch is total access; ten is the same total. Reverting the five new bare words would surrender the tool fixes audit item 1 counted (712 burned in-sandbox attempts, 1,091 needless `dangerouslyDisableSandbox` calls) while `cargo *` left the hole wide open. Only the model can compose a mixed compound, so the rails deny closes it at the one point it is reachable. Rejected: (A) revert the five bare words, spends five real fixes for zero delta; (B) keep them and accept an open hatch the model can use silently; (C) revert only `ssh *`, which confuses the hatch word with the capability, since `X; cargo --version` still runs `X` unsandboxed and `X` may be `ssh`. Note on provenance: the audit did not merely omit this, it asserted the opposite. Findings F7.3 states "the `cargo *` exclusion only matches a leading `cargo`". Its prescription for item 1 survives on function and dies on rationale. Advisory brief by a Fable subagent, 2026-09-13.
- 2026-09-13, Scott (closes OQ2): **option D.** A sandboxed commit gets signed by a signing-only private key that the sandbox is allowed to read. Home gets the same signing/auth split work received on 2026-07-16: mint `~/.ssh/identities/home/signing`, register it on scottidler as a Signing key only, and add the two signing-only private halves to `sandbox.filesystem.allowRead`. Why not the others: (A) allowRead of the existing keys exposes `home/id_ed25519`, which is scottidler's only GitHub auth key and the ssh identity for desk, nas and every LAN host, to any sandboxed subprocess; (B) `excludedCommands "git commit *"` matches on command string prefix, so `cd x && git commit` and `git -C p commit` keep failing, the exact gap the doc already documents for cargo; (C) dropping AC1 reverses Scott's 2026-07-16 ruling. The audit's own "public halves only" recommendation rested on the premise that signing needs only the `.pub` plus the agent socket; Phase 0 falsified that premise, so the audit text gives no ruling here. Evidence: `docs/design/2026-09-13-enforcement-core-phase0/evidence.md` sections 0f and "0f corollary". Advisory brief by a Fable subagent, 2026-09-13.
- 2026-09-13, author, folded from Phase 0 (evidence: `docs/design/2026-09-13-enforcement-core-phase0/evidence.md`): two amendments that need no ruling. (1) Prompt extraction switches its primary source to the transcript's `last-prompt` records, because the original user-record predicate discards every slash-command turn; the user-record scan stays as a cross-check for the measured lag case. (2) The sccache unix-socket remedy is dead at the syscall level, so the pre-recorded `RUSTC_WRAPPER=""` fallback is adopted and the dotfiles `sccache.service` PR drops out of the ship order. Also recorded: `claude -p` sessions write no transcript at all (the payload's `transcript_path` never materializes), so the offer rule fails open in headless sessions by construction, and `excludedCommands` was confirmed live to match on command string prefix and to carry the whole compound command out of the sandbox.
- 2026-09-13, Scott (closes OQ1, superseding the author's earlier "no exception" line): the rm rule is about intent. Regenerable build output is removed with plain `rm` ("fuck it we can rebuild the files and it only costs us time and compilation"); artifacts that cannot be reproduced go through rkvr, the three-week bin. Mechanism: deterministic first (the named set in safety.md, matched positionally: basename plus the toolchain anchor in the parent), stochastic fallback second (the model asserts intent with a literal `# regenerable` marker that is audited). No scratch-path exception beyond that: a scratch file outside the set costs one small archive, and the choice removes the cwd-resolution problem (rails sees the session cwd, not a subagent's `cd`). The scratch allowlist still applies to the wrapper forms, where the choice is deny vs pass. Correction to the panel's finding: rkvr copies rather than tars a file that is already an archive by extension (`is_archive`); directories are always tarred, so the build-directory cost was real and the set is the fix.
- 2026-09-13, author: existing em-dashes are stripped only from the files this PR touches (minus review-panel.md, chunk C). The other 1,300 across the tree are a non-goal here; the lint list grows chunk by chunk.
- 2026-09-13, author: `prose.sh` reason text quotes the offending line. A block that only names the rule costs a second block when the model rewrites the wrong sentence; the 8-block cap makes each miss expensive.
- 2026-09-13, author: no warn-only path in the Stop hook. It blocks or passes; the "real <noun>" and sizing-word warnings stay prose in edges.md.
- 2026-09-13, author: em-dash deny is a shell PreToolUse hook, not a rails rule. Settings matchers are documented, already live on an exact MCP name, and reach SDK-driven sessions; rails is early access and fails open.
- 2026-09-13, author: reviewer egress via `excludedCommands` on the two script paths, not `allowedDomains`. Deterministic, no host list to maintain; codex's host set is not verified. (Corrected 2026-09-13: the claim that Phase 0g proves the path-prefix form is FALSE. Matching is any-stage, so the entries work, but the path-head form was never separately proven and is moot under any-stage matching.)
- 2026-09-13, author: sccache remedy is decided by Phase 0f. Unix socket if it works (keeps the cache, one dotfiles PR); otherwise `RUSTC_WRAPPER=""` in settings env with the cache loss recorded here. Scott decides only if 0f fails.
- 2026-09-13, author (closes round-2 M1 without escalation, because it is Scott's intent test made deterministic): a regenerable match is positional. Basename in the set AND the toolchain file that produces it in the parent directory; anchor absent or path unresolvable falls through to rkvr. Chosen over `git check-ignore` (a subprocess per rm stage, and gitignored dirs include local databases) and over dropping the ambiguous names (which would push every `target/` delete to the marker path). `bin/` and `vendor/` stay out of the set: tracked in 18 and 6 repos.
- 2026-09-13, review panel round 3, final (both seats), folded: stale guard rewritten to compare the payload's `last_assistant_message` against the transcript's newest assistant record (the previous form was unconditionally true in an append-only file, 448 of 448 pairs); the OQ1 entry corrected from "basename" to positional; `tox.ini` and `pytest.ini` anchors; `pom.xml` rejected as an anchor with the tracked Maven `target/` as evidence; the four residual tracked `dist/` dirs recorded as the known limit of the positional match; safety.md citation corrected to `:28`. Panel budget spent: 3 of 3 rounds, 0 open findings, 0 unresolved pushbacks.
- 2026-09-13, review panel round 2 (both seats; CI-teardown pushback accepted by both, settled), folded: positional regenerable match (M1); marker defined with bash comment semantics, stripped before path collection, scanner reuse stated (M2); `.gitignore` bullet and criterion in Phase 1 (M3); Phase 2 bullet aligned to the final-sentence offer test (M4); four marker and nesting test cases added to Phase 5; safety.md carries the scar-tissue line. Deferred with the panel's agreement: growing the set (`_build`, `htmlcov`, `.vite`, `.cache`, `obj`) until a name recurs; a miss costs one tarball, not data.
- 2026-09-13, review panel round 1 (architect + staff engineer, both seats, no disagreements), folded: manifest glob must be unquoted (verified by diff of the two emitted scripts); rails snippet corrected to the live event shape (`e.command`, `withContext` on the result); AC5 verifies through `clyde permit log`, the context line and the archive, not the transcript (verified against a live rails session); SubagentStop extracts the dispatch prompt because every subagent record is sidechain (verified); stale-record guard and spike 0h added; go-ahead tokens match on word boundaries, `using` and `go` dropped from the verb list, `Let me know if` dropped from the offer regex, code and quoted spans stripped first; em-dash escape text exempts nothing (safety.md:28); cap-burn risk row added; `rules/secrets.md:109` correction added to Phase 4. Pushed back with rationale: the CI-teardown exception stays, it is Scott's 2026-07-08 ruling, now cited. Escalated to Scott: OQ1 (build-directory archive cost), the one line the doc had already flagged.

## Alternatives Considered

### Alternative 1: rewrite the rules again
- **Description:** stronger wording in safety.md, edges.md, interaction.md.
- **Why not chosen:** measured three times; the em-dash ban is in 14 files and the September rate is 31%. Scott 09-08: "rules dont do shit."

### Alternative 2: rails for everything (Stop gate and em-dash deny)
- **Description:** one TypeScript codebase for all three items.
- **Why not chosen:** `turn.complete` is observe-only, so rails cannot block a turn; the em-dash deny would then be the only rails deny, in an early-access API that fails open. Shell hooks are the stable path and match the existing nine.

### Alternative 3: `RUSTC_WRAPPER=""` in settings env without the socket spike
- **Description:** disable sccache for every Claude session.
- **Why not chosen outright:** loses the cache for all cargo runs, including the excluded (unsandboxed) ones that reach the server fine today. Kept as the Phase 0f fallback.

### Alternative 4: sign with the existing keys, or not at all (OQ2 rejects)
- **A, allowRead the existing private keys:** exposes `home/id_ed25519`, scottidler's only GitHub auth key and the ssh identity for `github.com`, desk, nas and every LAN host, to any sandboxed subprocess. Rejected on that fact alone.
- **B, `excludedCommands "git commit *"`:** rejected, but NOT for the reason first recorded. Matching is any-stage, not string prefix, so `cd x && git commit` WOULD have been exempted. The real objections: it adds an eleventh escape hatch, and it is a second mechanism beside D for one failure.
- **C, drop AC1:** reverses Scott's 2026-07-16 ruling, "I consider it a failure for you to NOT be signing the commits."

### Alternative 5: disable the sandbox
- **Description:** `sandbox.enabled: false`.
- **Why not chosen:** removes the blast-radius control the rest of the setup assumes; every family here has a precise config fix.

## Technical Considerations

### Dependencies
- No new packages. `jq`, `python3`, `bash` already used by existing hooks; `bun` (1.3.14, `~/.bun/bin`) dev-only for rails tests; `rkvr` needs `eza` and `tar` on PATH (both present).
- Cross-repo: `scottidler/dotfiles` owns `rmrf.cfg`, `.gitconfig` and `sccache.service`; none change here except `sccache.service` if Phase 0f passes. Ship order: dotfiles sccache PR (if any) -> this PR -> manifest link step on desk.lan -> Phase 6.

### Performance
- `prose.sh` reads one JSON payload and, when `last_assistant_message` is absent, tails the transcript for the last two records; bounded by `tail -c`. `emdash.sh` is a `jq` string scan. Neither shells out to the network.

### Security
- **Every `sandbox.excludedCommands` entry exempts any compound command that contains it, at any position** (measured 2026-09-13, evidence.md 0g). That has been true since `cargo *` landed, so the list growing from 3 entries to 10 adds no capability: one hatch already granted total escape. The only party who can compose such a command is the model; a subprocess cannot append a stage. The rails excluded-compound deny removes that composition, which is why the entries are safe to keep. Subprocess exposure is unchanged either way: `cargo *`, `otto *` and `release *` already run build scripts, proc-macros and test binaries fully unsandboxed.
- allowRead makes two **signing-only** private keys readable inside the sandbox (`home/signing`, `work/signing`), which is OQ2 decision D. The earlier "public halves only; private keys stay denied" line was false as a fix: Phase 0 proved the sandbox denies `socket(AF_UNIX)` creation, so ssh-agent is unreachable and `ssh-keygen -Y sign` must read the private key file. Priced exposure: neither key appears in any GitHub authentication-key list nor in any `authorized_keys` (blob-hash verified 2026-09-13), so the worst case is a forged Verified-badged commit, which still needs separate push access to land anywhere; the remedy is revoke and rotate, with zero authentication impact. Every authentication key stays denied, `home/id_ed25519` above all: it is scottidler's only GitHub auth key and the ssh identity for desk, nas and every LAN host. For scale, `cargo *`, `otto *` and `release *` already run fully unsandboxed, so build scripts, proc-macros and test binaries see all of `~/.ssh` today; D adds nothing to that surface.
- `/var/tmp/rmrf` and `/var/tmp/bkup` become writable inside the sandbox: `/var/tmp` is world-writable by design and both dirs already receive archives from unsandboxed runs, so no new exposure.
- Both hooks fail open on parse errors (print `{}` plus one stderr line) so a malformed payload cannot lock a session; the harness's 8-block cap bounds the Stop hook regardless.

### Testing Strategy
- Per-hook fixture matrices (`*-test.sh`) in the git-release-guard-test.sh shape, positive and negative per rule, run by the new `.otto.yml` `test` task. Break-the-code once per hook during Phase 6 (invert one rule, confirm the fixture fails).
- rails: `bun test` in `skills/rails/hooks`, `claude plugin validate --strict`.
- Live checks per phase as listed; all re-run in Phase 6.

### Rollout Plan
- One PR on this repo (branch `enforcement-core`, title `feat(hooks): enforcement core`), one commit per phase, `otto ci` green per phase once Phase 4 adds `.otto.yml` (Phases 1 to 3 run their `-test.sh` and `bun test` directly).
- After merge on desk.lan: `manifest -l HOME/.claude/hooks/* | bash` from the repo root (glob unquoted, see the operator note above), then a fresh Claude session for Phase 6.
- Rollback: remove the two hook registrations from settings.json and the rails rules. Sandbox entries are additive and harmless to leave ONLY while the rails excluded-compound deny is live; without it, every `excludedCommands` entry is an open escape hatch.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Stop hook blocks a legitimate question (a genuine decision ask that is short) | Med | Med | The offer rule requires an imperative or go-ahead prompt; short asks pass; reason text tells the model exactly what to change; 8-block harness cap |
| `last_assistant_message` absent in some payloads | Low | Low | Transcript fallback; fail open with a stderr line |
| Regex matcher `Write\|Edit\|...` not honored | Low | High | Phase 0b proves it before Phase 3; fallback is one registration per tool name |
| rails rewrite mangles a quoted path or heredoc | Med | High | Reuse the quote-aware scanner and heredoc stop from the gh rule; bail on anything not a plain stage; fixtures for quoted paths and heredoc bodies |
| sccache socket approach fails | Med | Low | Phase 0f decides; fallback recorded |
| New hook files inert after merge (manifest link lag) | High without the step | Med | Operator step named in the plan and in the PR body; Phase 6 re-runs criteria on the live setup |
| Self-Modification classifier blocks the settings edit | Med | Low | Phases touching HOME/.claude run with auto mode off |
| Headless sdk-py sessions (security-guidance reviews) hit the Stop hook on every commit | High | Low | Empty-text pass-through; their turns end in StructuredOutput, not text; chunk H decides the plugin's fate |
| Em-dash deny blocks a legitimate verbatim quote (log excerpt in a doc) | Med | Low | Recast or write under a fixtures path; same rule the CI lint already applies to code |
| Transcript lag hides the last user prompt from the Stop hook | Low | Low | Offer rule fails open; stale guard compares timestamps; em-dash and length rules do not need the prompt |
| Cap-burn loop: the model answers an em-dash block with another em-dash, eight times | Low | Low | The reason quotes the offending line; the harness cap (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8`, verified in the 2.1.270 binary) then ends the turn with a visible override notice, so the worst case is one noisy turn, not a wedge |
| `excludedCommands` matcher semantics change in a future Claude Code binary | Med | Med | The Phase 6 three-line marker matrix is rerun on every upgrade the release driver performs, and becomes a lens in the next audit |
| rails excluded-compound deny blocks a legitimate mixed compound | Med | Low | The reason text names the exact split to make; `cd`, assignments, `echo` and `true` are transparent and never count as REST |
| A regenerable directory with a name outside the set (a custom `_build/`) gets gzipped into the bin | Med | Low | The rewrite's context line names the `# regenerable` marker; the model re-issues; the set grows when a name recurs |
| An excluded stage redirects to an arbitrary path (`cargo --version > ~/.ssh/authorized_keys`): one stage, empty REST, so the excluded-compound rule cannot see it | Med | High | Known limit of every option on the table, because a redirection is not a stage. Recorded here and re-checked in Phase 6; closing it needs a different mechanism (a redirect-target guard), which is a later chunk, not this one |
| The excluded-compound rule denies a legitimate pipeline | Med | Low | Option C makes a stdin-only pipe target transparent, so `otto ci 2>&1 \| tail -50` passes; a file operand or a `;` still denies, and the reason names both heads and says to split the call |
| The model over-uses `# regenerable` on a precious path | Low | High | The marker is literal and visible in the transcript and in `clyde permit log`; safety.md states it asserts intent and is audited; the incident lens of the next audit counts it |

## Open Questions

- [x] OQ3, closed by Scott 2026-09-13 with option D: keep all ten entries, and deny mixed compounds in rails. See Resolved Decisions. Original text: (opened 2026-09-13 after Phase 1 landed) `sandbox.excludedCommands` matches **any stage anywhere** in a compound command and exempts the ENTIRE compound, not the string prefix as this doc and the Phase 0 evidence both assumed. Measured decisively with the excluded stage in TRAILING position (`$TMPDIR/marker.sh; ssh -V` runs unsandboxed; the marker alone does not). So every entry is a general sandbox-escape hatch: appending `; ssh -V` to any command opts it out of the sandbox with no approval. Phase 1 grew the list from 3 entries to 10, widening that surface while fixing the tool failures audit item 1 counted. Options: (A) revert the five new bare words (`ssh`, `systemctl`, `journalctl`, `crontab`, `bump`), keeping the two script paths; (B) keep them and record the widening as accepted; (C) revert only `ssh *`. Note the self-reference: `excludedCommands` was the audit's OWN prescribed remedy for these failures, so that recommendation needs re-reading against this measurement. Evidence: `docs/design/2026-09-13-enforcement-core-phase0/evidence.md` section 0g, which carries the correction.
- [x] OQ2, how a sandboxed commit gets signed, closed by Scott 2026-09-13 with option D; see Resolved Decisions. Original text: (opened 2026-09-13 by Phase 0) Phase 0 proved the sandbox denies `socket(AF_UNIX)` creation, so ssh-agent is unreachable in-sandbox, and proved `ssh-keygen -Y sign -f <pub>` without an agent needs the matching PRIVATE key readable (`No private key found for public key`). Phase 1 as written adds only the `.pub` halves to `allowRead` and states "private keys stay denied", so **AC1 cannot pass**. Options on the table: (A) add `~/.ssh/identities/home/id_ed25519` and `~/.ssh/identities/work/signing` to `allowRead`, exposing two signing keys to any sandboxed command; (B) `excludedCommands` `"git commit *"`, which leaves `cd x && git commit` and `git -C p commit` broken because matching is string-prefix; (C) drop AC1 and accept unsigned in-sandbox, reversing the 2026-07-16 ruling. Evidence: `docs/design/2026-09-13-enforcement-core-phase0/evidence.md` sections 0f and "0f corollary".
- [x] OQ1, the build-directory archive cost, closed by Scott 2026-09-13; see Resolved Decisions

## References

- Audit program tracker: `docs/design/2026-09-13-setup-audit-program.md`
- Ranked report: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/
- Raw findings: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-audit-findings-2026-09-12/
- rails precedent: `docs/design/2026-09-08-rails-bash-rewrite.md`, `HOME/.claude/skills/rails/hooks/index.ts`
- Hook shape precedent: `HOME/.claude/hooks/secret-echo-guard.sh:23-24,59-67`, `git-release-guard-test.sh:121-137`
- rkvr: `~/repos/scottidler/rkvr/src/main.rs:836-853,866-867`, `src/cli.rs:38-52`; config `~/.config/rmrf/rmrf.cfg`
- Official hooks reference (Stop, PreToolUse matchers, sandbox live-apply): https://code.claude.com/docs/en/hooks , https://code.claude.com/docs/en/sandboxing , https://code.claude.com/docs/en/settings#when-edits-take-effect
- Function hooks contract: `claude-code.d.ts` (regenerate with `/plugin-types`): `tool.call` deny at 3901-3906, `turn.complete` observe-only at 1322-1331
- sccache restart churn (NRestarts=1248 since 06-28): separate dotfiles issue, not in scope
