# Design Document: Rule routing, the right rule at the right time

**Author:** Scott Idler
**Date:** 2026-10-08
**Status:** Implemented
**Review Passes Completed:** 5/5, panel round 1 folded, refreshed against `retro-fixes` `500c4c8`

> Refresh 2026-10-09: `retro-fixes` Phase 6 (`ba21860`) moved cli.md and logging.md to `refs/`, split taste.md, and gave voice.md frontmatter. Updated counts (19 rules, 11 unscoped, always 33,170 bytes, routed 12,445), dropped the cli/logging path-scoping and Phase 1's `.otto.yml` step (already shipped there), re-pointed `CLAUDE.md` and rails line refs, re-ran every criterion command on `500c4c8`, and set the ship order: after `retro-fixes` lands. Removals and re-measurements only; no design change, so no panel round.

> Panel round 1 (2026-10-09, synthesis `/tmp/review-panel/B8p3iqz2/synthesis.md`): 7 must-fix, 8 cheap wins, all folded after each was checked against the typings or the repo; 6 architect findings dropped or deferred with reasons in the synthesis (already covered, or probed by Phase 0 (g)). Must-fix: prompt context direction, `$.state` Map/Set serialization, fail-open that could not restore dropped rules (now latch + `invalidate`), search after-context, wrong tool names and narrow git gates, Phase 1 breaking the `.otto.yml` frontmatter check, batched gate calls.

> Passes ran 2026-10-08. Pass 2 (correctness) made files outside the rule index explicitly kept, routed the rewrite through `next` so other hooks still chain, and replaced the live criteria's "ask the model what it loaded" with the router's own debug-log lines (`~/.claude/CLAUDE.md` names every rule, so self-report proves nothing). Pass 3 (clarity) defined "outward tool" and added the never-silently-rewrite-an-approved-draft clause to the gate deny. Pass 4 (edge cases) added Bash gates (git.md arriving after `git push` ran is useless) and four risks: resume, regex compile failure, mid-session edits, gate friction. Pass 5 fixed AC3's keep list, which still counted cli and logging after Phase 1 makes them path-scoped.

## Summary

Claude Code loads `~/repos/.claude/rules/` in one lump: all 11 unscoped rules at session start for a session rooted in `~/repos`, or all at once mid-session the first time a session rooted elsewhere touches a file under `~/repos`. Most of it is irrelevant to the work at hand when it lands. This doc adds a rule router to the `rails` mod: each rule declares in frontmatter when it applies (always, a prompt topic, a tool, a Bash command head), the mod drops routed rules out of the engine's bulk load, and injects each one once, at the moment its trigger fires.

## Problem Statement

### Background

- Rules live at `HOME/repos/.claude/rules/*.md` (19 files, 105,379 bytes), symlinked per file into `~/repos/.claude/rules/` by `manifest.yml:1-3`. Counts in this doc are measured on branch `retro-fixes` at `500c4c8`, after its Phase 6 steering trim (`ba21860`): cli.md and logging.md moved to `refs/`, taste.md's pipeline sections moved to `refs/process-taste.md`, voice.md gained `alwaysApply: true` frontmatter.
- 8 rules carry `paths:` frontmatter and load natively when a matching file is read (rust, python, js-ts, yaml, terraform, comments, fleet-plugins, safety). That part already works.
- 11 carry no `paths:`, all `alwaysApply: true`. They load unconditionally: 46,353 bytes on disk counting `HOME/repos/CLAUDE.md`.
- Since 2.1.261 the start-of-session load is one attachment of type `instructions` (`attachment.files[]` of `{path, type, content}`, rendered as one user-role block framed `Contents of <path> (<tier>):`). Example: `~/.claude/projects/-home-saidler-repos-scottidler-claude/2b8aebe2….jsonl:19`, 18 files, 68,220 characters.
- A mid-session load is one `nested_memory` attachment per file, rendered `Contents of <realpath>:` inside a system reminder.
- `rails` (`HOME/.claude/skills/rails/`) is the in-house function-hook plugin: `hooks/hooks.json` -> `hooks/index.ts` (`register` at `:956`), `userConfig` toggles in `.claude-plugin/plugin.json`, bun tests in `hooks/index.test.ts` (147 pass on `retro-fixes`). Its design doc makes it the one container for every function hook (`docs/design/2026-09-08-rails-bash-rewrite.md:55,361`). `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` is set in `HOME/.claude/settings.json`.

### Problem

Session `e9ef7f18` (cwd `/home/saidler`, CC 2.1.295), 2026-10-08: Scott asked for a scheduled Slack message. To draft it the model ran `cat ~/Claude/writing/VOICE.md; cat ~/repos/.claude/refs/slack.md`. CC counted that `cat` as a read under `~/repos` and appended 15 `nested_memory` rows (transcript `:191-205`, 58,416 rendered characters): `~/repos/CLAUDE.md`, marquee, interaction, logging, pr, otto, search, cli, git, recall, taste, voice, general, secrets, safety. Of those, the task needed voice. Scott: "half of that shit is not needed at that moment. interested into why it was loaded" and "do the fucking claude mods give us a way to load the correct fucking .md files at the RIGHT time?"

Measured over `~/.claude/projects/*/*.jsonl` since 2026-09-01 (top-level transcripts, 1,895 sessions). All of these predate `ba21860`; the trim shrinks each burst by cli, logging and part of taste, and changes nothing about when the rules load:

| case | sessions | rule characters |
|---|---|---|
| rooted in `~/repos`, rules at start | 82 cli | median 44,688 (Sep), 49,220 (Oct); 51,666 today across 13 files |
| rooted outside, mid-session burst | 31 (29 at `/home/saidler`) | 13 to 18 files; min 44,571, median 56,604, max 90,795; 1,845,853 total |
| rooted in `~/repos`, same file loaded twice (start under one path, nested under its symlink target) | 20 | 29 files, 116,731 characters |

The engine has no notion of "this rule matters now". It knows two triggers: session start and a read of a file under the rules' directory. Neither matches what the rules are about (git.md is about running `git`, not about being in `~/repos`).

### Goals

- Each rule in `rules/` declares when it applies, as data in its own frontmatter (Scott, this session: "load the correct .md files at the RIGHT time").
- A routed rule reaches the model once per context, when its trigger fires, and not before.
- The bulk load (start-of-session `instructions` and mid-session `nested_memory`) no longer carries routed rules.
- A file already in context is never loaded a second time under another path spelling.
- Any router failure falls back to today's full load and says so on screen.

### Non-Goals

- **Excluded:** changing native `paths:` rules. They already load at the right time; they get `load: native` so every rule is classified, and nothing else.
- **Excluded:** `refs/*.md`. They are read on demand by pointer today and are not auto-loaded.
- **Excluded:** `~/.claude/CLAUDE.md`, `WHOAMI.md`, `tools.md`, managed policy. User and managed tiers pass through untouched.
- **Excluded:** rewriting rule text or trimming always-on rules. That is chunk H item 16's prefix trim.
- **Parked:** giving sessions rooted outside `~/repos` the always-on core at start. Today they get nothing until a `~/repos` path is touched. Revisit if Scott asks; it is one `session.start` injection on the same ledger.
- **Parked:** subagent-specific routing. Routing applies to every loop the same way, keyed by `agentId` (see Data Model). Revisit if Phase 0 shows subagents do not receive the `instructions` attachment.

### Relationship to the setup-audit program

- Chunk H (`docs/design/2026-09-13-setup-audit-program.md:41`, queued) holds items 15 (context budget) and 16 (always-on prefix trim, rule dedupe). This doc covers the loading half of 15/16: when a rule loads and duplicate loads. It does not touch rule text, Read discipline, otto tail, or item 14 (security-guidance).
- Scott requested this doc directly on 2026-10-08, out of band, the way `2026-10-08-retro-fixes.md` was. H keeps its items; its author reads this doc first and does not re-derive the measurements.

## Proposed Solution

### Overview

Four parts, one repo (`scottidler/claude`). Ship order: after `retro-fixes` lands on `main`. Both edit rule frontmatter, `.otto.yml` and `~/.claude/CLAUDE.md`, and this doc is measured against that branch.

1. **Routing data:** a `load:` key in every rule's frontmatter.
2. **Router library:** `HOME/.claude/skills/rails/hooks/rules.ts`, pure functions: parse `load:`, split the `instructions` blob, parse a `nested_memory` path, match triggers.
3. **Hooks in rails:** drop routed and duplicate files from the bulk load (`prompt.attachment`); inject a routed rule once when its trigger fires (`prompt.submit`, `tool.call`).
4. **Tooling:** tests in `otto ci`, a `hooks-preflight.sh` check, one line in `~/.claude/CLAUDE.md` Rules.

Six phases, 0 through 5. Phase 0 is a throwaway spike that proves every engine behaviour the design rests on.

### Architecture

```
engine bulk load                         trigger moments
  instructions (start) ─┐                  prompt.submit  (Scott's prompt)
  nested_memory (read) ─┤                  tool.call      (before / after a tool)
                        v                         v
              prompt.attachment hook       router.match(trigger) -> rule files
              router.split -> per file             │
              routed?  -> drop                     v
              dup realpath? -> drop        ledger: injected already? -> skip
              else keep, record in ledger          │
                        │                          v
                        v                  inject `Contents of <path>:` + body
                  model context  <────────────────┘
```

- **Drop path.** `prompt.attachment` with `type: instructions | nested_memory`. The hook gets text only, no `files[]` (`types :14348-14365`), so it splits on the `Contents of <path>` headers. Two independent drop reasons:
  - **Routed:** a rule-index file whose `load:` is a trigger object.
  - **Duplicate:** any file (rule index or not, CLAUDE.md included) whose resolved real path is already in the ledger. Files outside the rule index are never routed, but they are de-duplicated.
  - Everything else is kept byte for byte and recorded in the ledger. An `instructions` blob is re-joined from the kept files and handed on with `next({ ...e, text })`; a `nested_memory` with nothing kept returns `{ text: null }`. Every keep and drop is logged (`rules: keep|drop <file> (<reason>)`) to the debug log always, and to the transcript when `debug` is on.
- **Inject path.** An injected rule is framed `Contents of <path>:` + body, the engine's own framing.
  - `prompt.submit`: match `load.prompt` regexes against the prompt text; inject on the way down, `next({ ...e, context: [...(e.context ?? []), ...rules] })`. Context put on the result after `next` resolves is not attached (`types :9054-9058`).
  - `tool.call`, gate (before the tool runs): a gate entry marks an action that leaves the machine or cannot be undone (a Slack post, a Jira or Confluence write, a marquee publish, a PR, a push, a tag). If its rule is not yet delivered, the hook returns `{ deny }` without calling `next`, carrying the rule text, so the tool never runs and the model retries with the rule in hand. When the conversation already showed Scott a draft for this action, the deny text ends "if your text changes, show Scott the new draft before sending", so an approved draft is never silently rewritten.
  - `tool.call`, after: for every non-gate match (`load.bash` per statement, `load.tools` by tool name, `ToolSearch` by query), call `next(e)` and append to the result's `context[]` (`types :12620+`), including on `isError`, so a failed `git push` still gets git.md. The router does not reuse rails' `withContext()` (`index.ts:947`), which skips deny and error results.
- **Delivery state.** Per rule per loop: `pending` from the moment a gate deny or a tool result's `context[]` inject carrying it is returned; `delivered` once the next model request starts (a `turn.step` hook promotes pending to delivered before `yield* next(e)`). Only a `prompt.submit` inject is `delivered` immediately: it rides the user turn, which reaches the model before any tool call of that turn exists. A gated call for a `pending` rule is denied with one line: "rule delivered above, retry after reading it". The inject and that deny land in the same next request, so the pointer is true. That closes the batch case both ways: two gated calls in one model response both deny, and so does a gated call after a sibling whose result injected the rule (`git log -1` + `git push` in one response: the push is denied until `turn.step`). (Amended 2026-10-10, implementation audit round 1: the first text made a `context[]` inject delivered immediately, which let that sibling push run before the model had read git.md.)
- **Ledger.** Plain JSON in `$.state`, since a Map or Set reads back as `{}` (`types :3335`): `{ [loop: string]: { kept: string[], rules: { [realPath: string]: 'pending' | 'delivered' } } }`, `loop` being `agentId` or `main`. Cleared for a loop only when its `session.compact` actually installs (the result carries `messages`); a `precompute` or a `skip` clears nothing.
- **Failure: a latch plus re-ask.** Every hook carries `.catch` (`reference.md:75`). Any router failure, or the `rule_routing` toggle going false, sets `routingOff` in `$.state` and calls `$.ui.invalidate('prompt.attachment')` (`types :4163, :5534`), which makes the engine ask again for every attachment. With the latch set the drop hook is plain `next(e)`, so every previously dropped rule comes back: today's full load. Status line `rules: router failed, full load restored`; the debug log names the throw. A `.catch` that cannot even set the latch returns `next(e)` for its own event. Fail-open is deliberate: fail-closed would hide rules, which is worse than today. Phase 0 (h) proved the re-ask re-delivers on the turn after the one that called `invalidate`, not within it: after a mid-turn failure the dropped rules stay missing for the rest of that turn. Accepted: the full load is back from the next turn on.

### Data Model

Frontmatter key `load:` on every file in `rules/`:

```yaml
load: always          # never routed; stays in the bulk load
load: native          # has native `paths:`; router leaves it alone
load:                 # routed: dropped from the bulk load, injected on trigger
  prompt: ['\bslack\b', '\bemail\b', 'confluence', '\bjira\b', 'announce']
  tools:
    - { match: '^mcp__slack__(chat_(post_message|schedule_message|update)|conversations_add_message)$', gate: true }
    - { match: '^(Write|Edit)$', path: '\.md$', gate: true }
    - { match: '^ToolSearch$', query: 'slack|atlassian|marquee' }
  bash:
    - '^git\b'                                          # after: context on the result
    - { match: '^git (push|tag|branch -D)\b', gate: true } # before: deny once with the rule
```

- `prompt`, `tools[].match`, `tools[].query`, `tools[].path`, `bash` are case-insensitive regex strings. `path` matches the tool input's `file_path`. A `bash` entry is a string or `{ match, gate }`.
- **Bash matching runs on a normalized statement**, after rails' existing statement split: leading `VAR=val` assignments and the wrappers `env` (its `-S` string re-split as the command), `sudo`, `command` and `exec` are stripped with their own options, a path-qualified head reads as its basename (`/usr/bin/git` is `git`), and git's global options (`-C <dir>`, `-c <k=v>`, `--git-dir=...`) are removed, so `env X=1 git -C repo push` and `sudo /usr/bin/git push` are matched as `git push`. `command -v`/`-V` only look a name up and are left as written. The statement split skips a heredoc body and resumes after its terminator line, so a command after the heredoc is still matched. (Wrappers, `env -S` and the heredoc resume added 2026-10-10, implementation audit round 1.) `gate` exists for Bash because an after-the-fact rule is useless for an irreversible command: git.md arriving after the `git push` ran is today's failure with extra steps.
- A missing, unknown, or unparseable `load:` is a test failure in CI (fail loud) and, at run time, treated as `always` (the file stays in context, status line names it).
- Classification (19 files; round 1 moved search and secrets to `always`):

| load | files | bytes |
|---|---|---|
| always | interaction, taste, pr, general, recall, search, secrets | 33,170 |
| native (unchanged `paths:`) | safety, comments, fleet-plugins, rust, python, js-ts, terraform, yaml | |
| routed | git, marquee, otto, voice | 12,445 |

- Why search and secrets stay always: search exists to stop the *first* unbounded `grep`/`find`, which after-the-fact context cannot do (1,456 bytes). secrets carries a never-print, never-log invariant that matters before `manifest age decrypt` writes anything (`secrets.md:7-11`), and `gh_persona` does not enforce it.
- cli and logging are out of scope: `ba21860` moved them to `refs/`, which nothing auto-loads, with pointers from `phase-implementer` and `review-panel`. The draft's plan to path-scope them is superseded.
- Routed triggers. Tool names are the ones registered in `HOME/.claude/settings.json` (GitHub is `mcp__multi-account-github__*`, not `mcp__github__*`); a Phase 2 test asserts every `tools[].match` matches at least one tool listed there.

| rule | prompt | tools | bash |
|---|---|---|---|
| git | `\b(push\|tag\|merge\|rebase\|release\|branch)\b` | after `^mcp__multi-account-github__`; gate `^mcp__multi-account-github__(create_pr\|delete_tag)$` | after `^git\b`, `^gh\b`; gate `^git (push\|tag\|branch -D)\b`, `^bump\b`, `^gh (pr (create\|merge)\|release)\b`, `^gh api .*refs/tags` |
| marquee | `marquee` | after `^mcp__marquee__` | after `^marquee\b` |
| otto | `\botto\b` | | after `^otto\b` |
| voice | `\bslack\b\|\bemail\b\|confluence\|\bjira\b\|announce\|draft\|design doc\|readme\|\bPR\b\|commit message` | gate: Slack post/schedule/update/add_message, `^mcp__atlassian__(create\|edit\|update\|add)`, `^mcp__marquee__marquee_(publish\|update)$`, `^mcp__multi-account-github__create_pr$`, Write/Edit of `\.md$`; after: ToolSearch query `slack\|atlassian\|marquee` | gate `^marquee (publish\|update)\b`, `^gh (pr\|issue) (create\|edit\|comment)\b`, `^git commit\b` |

- Real paths come from `$.fs.stat(path, { resolve: true }).realPath` (`types :4958+`), which folds the `~/repos/CLAUDE.md` symlink spelling into the repo path.
- Rule index: built once per session from `$.fs.list` + `$.fs.read` of `~/repos/.claude/rules/*.md`, keyed by real path. CC strips frontmatter before content reaches a hook (`InstructionFile.content`, `types :5505`), so the router reads the files itself.

### API Design

`rules.ts` exports pure functions; `index.ts` wires them.

```ts
type Load = 'always' | 'native' | { prompt?: string[]; tools?: ToolTrigger[]; bash?: (string | BashTrigger)[] }
type ToolTrigger = { match: string; gate?: boolean; query?: string; path?: string }
type BashTrigger = { match: string; gate?: boolean }

normalizeStatement(stmt: string): string                                 // strip env/assignments, git global options

parseLoad(frontmatter: string): Load | Error
splitInstructions(blob: string): { header: string; path?: string; body: string }[]   // preamble and `<managed-settings>` parts carry no path; always kept
joinInstructions(parts: ReturnType<typeof splitInstructions>): string   // inverse, byte-exact
nestedPath(text: string): string | undefined                             // from `Contents of <path>:`
matchPrompt(index: RuleIndex, text: string): string[]                    // real paths
matchTool(index: RuleIndex, tool: string, input: unknown): { gate: string[]; after: string[] }
```

Hooks registered in `register` behind `options.rule_routing` (new `userConfig` boolean, default true): `prompt.attachment` (drop), `prompt.submit` (inject), `tool.call` (gate and inject), `turn.step` (pending -> delivered), `session.compact` (clear ledger on install).

### Implementation Plan

#### Phase 0: Spike, prove the engine behaviours
**Model:** opus
- Throwaway probe plugin under `$TMPDIR/p0/` loaded with `--plugin-dir`, `claude --debug`. Canary project `$TMPDIR/p0/proj/.claude/rules/canary-a.md` (no frontmatter, token `CANARY-A-<rand>`) and `canary-b.md` (with `load: {bash: ['^otto']}`, token `CANARY-B-<rand>`). Every arm runs headless with `claude -p` (Scott, 2026-10-09: no interactive sessions); multi-turn arms use `--input-format stream-json` or `--resume`. No repo code.
- Prove, each against a control arm without the hook:
  - (a) the probe loads (`claude plugin validate`, debug log line).
  - (b) `prompt.attachment` fires for `instructions` (session rooted at `proj`) and `nested_memory` (session rooted at `$TMPDIR`, `cat proj/x`); log type and first 120 chars; text starts `Contents of <abs path>`.
  - (c) `{ text: null }` on the canary `nested_memory`, and an `instructions` rewrite without canary-a, remove the token: ask the model to list every `CANARY` token verbatim. Transcripts keep the engine's record (`types :4161-4162`), so the canary answer is the evidence, not `rendered`.
  - (d) `prompt.submit` `context` and `tool.call` `context` (Bash `otto --version`) each deliver a canary the model quotes.
  - (e) a `tool.call` `{ deny }` on an MCP tool returns its text to the model and the model retries.
  - (f) the unknown `load:` key leaves native loading unchanged (same `instructions.files[]` path list with and without it).
  - (g) a subagent's attachments: does it receive its own `instructions`, and does `prompt.attachment` carry its `agentId`? And does `withheld_memory` (undeclared type in the binary, entries `{path, why, displayPath}`, 0 transcripts) appear in any arm?
  - (h) after canary-b was dropped, `$.ui.invalidate('prompt.attachment')` with the hook now passing through makes `CANARY-B` reachable again (the model quotes it on the next turn).
  - (i) a `turn.step` hook fires once per model request, before any `tool.call` that request produces.
  - (j) `claude plugin test <dir>` runs a `*.test.ts` that drives `prompt.attachment` and `tool.call` through `claude-code/testing`.
- Canaries, not self-report: the tokens are random and appear nowhere but the canary file, so a model that quotes one saw it.
- Decision rules fixed now:
  - (c) `instructions` rewrite fails -> routed rules move to a directory CC does not auto-load (Alternative 1); Scott is asked before Phase 1, since that changes the failure direction.
  - (d) `prompt.submit` context fails -> prompt triggers inject from a UserPromptSubmit shell hook's `additionalContext` (proven, `session-recall-guard.sh:13-17`).
  - (g) subagents get their own `instructions` with `agentId` -> routing per loop as designed; they get none -> nothing to route there, the ledger simply never sees that loop; `withheld_memory` appears -> stop and redesign around it.
  - (h) re-ask does not re-deliver -> the latch injects every routed rule through the next `context[]` (described under Failure).
  - (i) fails -> delivery state uses "the next `tool.call` after a different `toolUseId` batch" instead; Phase 3 tests whichever holds.
  - (j) fails -> hook tests use the `internals` export pattern rails already uses (`index.test.ts`), with hand-built inputs.
  - Any other failure stops the doc.
- Results pasted into this doc as text. Nothing committed but this doc.
- **Success criteria:** each of (a)-(f), (h)-(j) recorded PASS/FAIL with the canary or test output quoted; (g) recorded as one of its three named outcomes.
- **Results (2026-10-09, CC 2.1.296):** no fallback fires, nothing stops the doc. All arms `claude -p --model sonnet --output-format stream-json --debug-file`, probe `p0probe` via `--plugin-dir` (it logs `P0: ...` to the debug log with `$.ui.log(..., { to: 'debug' })`), control arm = same prompt with no `--plugin-dir` (0 `p0probe` lines in each control's debug log). Tokens: `CANARY-A-c7605d835496` (canary-a.md), `CANARY-B-1ee447142ab4` (canary-b.md), `CANARY-C-4c23b5f98a73` (canary-c.md, `paths: ["**/*.zz"]`, added for (f)); hook-injected tokens are `CANARY-<D1|D2|E>-ccb6a77887a5`, read by the probe from env, so no canary is in its source. The debug log redacts the tokens (`Remember this token: [REDACTED]`), so token evidence is the model's answer.
  - (a) PASS. `claude plugin validate probe`: `hooks: prompt.attachment, prompt.submit, tool.call, turn.step` ... `✔ Validation passed with warnings` (author missing). Debug log: `hooks module p0probe@inline loaded (worker, environment 2, tier user); events: prompt.attachment,prompt.submit,tool.call,turn.step`.
  - (b) PASS, with a framing correction for Phase 2. Rooted at `proj`: `P0: attachment type=instructions agentId=main origin=engine len=12693 head="Codebase and user instructions are shown below. Be sure to adhere to these instructions. IMPORTANT: These instructions O"`. Rooted at `$TMPDIR/p0`, after Bash `cat proj/x`: two rows, `P0: attachment type=nested_memory agentId=main origin=engine len=145 head="Contents of /tmp/claude-1000/claude-1000/p0/proj/.claude/rules/canary-b.md:\n\nProject note about otto. Remember this toke"`, and the same for canary-a.md. So `nested_memory` starts `Contents of <abs path>:` as specified, but `instructions` does NOT: it opens with that one-line preamble, then one section per file headed `Contents of <path> (<tier>):` (`(project instructions, checked into the codebase)`, `(user's private global instructions for all projects)`), and the managed tier's header is `Contents of <managed-settings> (organization-managed policy instructions):`, not a path. Frontmatter is stripped in both (canary-b's `load:` block never reaches the hook). `splitInstructions` must carry the preamble as a non-file part and tolerate the non-path managed header; "18" in Phase 2's criterion counts file sections.
  - (c) PASS. Control rooted at `proj` answers `CANARY-B-1ee447142ab4` / `CANARY-A-c7605d835496`; with the probe returning `next({ ...e, text })` minus the canary-a section (`P0: rewrite instructions without canary-a.md 12693->12485`) the answer is `CANARY-B-1ee447142ab4` alone. Control nested arm (`cat proj/x`) answers B and A; with `{ text: null }` on canary-a's `nested_memory` (`P0: drop nested_memory canary-a.md`) the answer is `CANARY-B-1ee447142ab4` alone.
  - (d) PASS. Control (`otto --version`, asked for `CANARY-D` tokens): `NONE`. With `prompt.submit` context and `tool.call` context on `^otto`: `CANARY-D1-ccb6a77887a5` / `CANARY-D2-ccb6a77887a5`. Finding: each injection comes back through `prompt.attachment` as its own row, `type=hook_additional_context origin=plugin`, framed `prompt.submit hook additional context: ...` and `tool.call hook additional context: ...`. The drop hook only matches `instructions` and `nested_memory`, so it never sees its own injections, and an injected rule's `Contents of <path>:` sits inside that engine prefix.
  - (e) PASS. Control on `mcp__clyde__sessions_ls`: one call, `succeeded (not refused)`, `CANARY-E tokens seen: NONE`. With a one-shot `{ deny }`: the tool_result is `{"is_error":true,"content":"<tool_use_error>Rule CANARY-E-ccb6a77887a5: before this tool runs you must read this rule. Retry the same call now, unchanged.</tool_use_error>"}`, the debug log shows a second `tool.call tool=mcp__clyde__sessions_ls` in the next step, and the model answers `CANARY-E-ccb6a77887a5 (from the refusal text)` ... `Call 1: refused` ... `Call 2: succeeded`.
  - (f) PASS. Same `proj` paths with and without the keys (canary-b `load: {bash: ['^otto']}`, canary-c `paths:` + `load: native`), Bash `cat y.zz`. Both arms: `headers type=instructions ["<managed-settings>","/home/saidler/.claude/CLAUDE.md","/home/saidler/.claude/WHOAMI.md",".../proj/.claude/rules/canary-b.md",".../proj/.claude/rules/canary-a.md"]`, then `headers type=nested_memory [".../proj/.claude/rules/canary-c.md"]` after the `cat`, and the model quotes A, B and C in both. The path list is read from the rendered `Contents of` headers, not the transcript's `files[]`: the Bash sandbox makes `~/.claude/projects` read-only, so `claude -p` wrote no transcript.
  - (g) Outcome: **subagents get their own `instructions` with `agentId` -> routing per loop as designed.** A `general-purpose` subagent raises its own row, `P0: attachment type=instructions agentId=a9d2ee3a6be89d36f origin=engine len=12693`, with the same five headers. Its `turn.step` and `tool.call` carry the same `agentId`. Rewriting canary-a out of every `instructions` row cuts it from the subagent too: control subagent answers B and A, rewritten subagent answers `CANARY-B-1ee447142ab4` alone. `withheld_memory` appeared in no arm (grep over every debug log and attachment dump: 0 matches). Side finding: the subagent's hand-back reaches main as a `prompt.submit` (`submit head="<agent-message from=\"a9d2ee3a6be89d36f\">..."`), so `prompt` triggers also fire on subagent hand-back text.
  - (h) PASS, one turn late. Three turns over `--input-format stream-json` in one process, canary-b rewritten out of `instructions`. Turn 2's `prompt.submit` sets the latch (the hook then returns `next(e)`) and, in the test arm, calls `$.ui.invalidate('prompt.attachment')`. Control (latch, no invalidate): turns 1 and 3 both answer `CANARY-A-c7605d835496` alone, and `instructions` is never asked again. Invalidate arm: turn 2's request does not ask again, but turn 3's asks for every attachment (`latch: pass-through type=instructions`, also environment, skill_listing, date, ...) and answers `CANARY-B-1ee447142ab4` / `CANARY-A-c7605d835496`. An extra arm calling invalidate from `tool.call` mid-turn showed no re-ask in the same turn's next step (answer `CANARY-A-c7605d835496` only). So re-asking does re-deliver (no fallback), but only from the turn after the one that called `invalidate`, which matches the typings' "a cached answer: dropped next turn". Rules dropped before a failure stay missing for the rest of that turn.
  - (i) PASS. `P0: turn.step begin` is logged before every `tool.call` its response produces, and step count equals request count (distinct assistant `message.id`s in stream-json): batch arm (two parallel Bash calls in one response) `begin index=0`, `tool.call ... "otto --version"`, `end index=0`, `tool.call ... "cat x"`, `begin index=1`, 2 steps / 2 requests; deny arm 4 steps / 4 requests, each `tool.call` after its step's `begin`. The first tool can start before the step's `next` resolves (`tool.call` logged ahead of `turn.step end`), so promoting pending to delivered has to happen at step begin, as designed.
  - (j) PASS. `claude plugin test probe` runs `hooks/index.test.ts` (imports `describe, expect, mock, test` from `claude-code/testing`) through `$.prompt.attachment(...)` and `$.tool.call(...)`, with `mock.env` for the probe's env: `4 pass 0 fail`. The first run proved the runner fails for real (`Expected: null Received: "Contents of /p/.claude/rules/canary-a.md:\n\nA"`, `p0probe's prompt.attachment hook was skipped: p0probe: no implementation for fs.write`): nouns with no mock (`fs.write`, `ui.log`) have no implementation under the kit, so hook code has to tolerate those calls failing or the test has to mock them. Phase 3 and 4 use `claude plugin test`.
  - Deviations from the spike as written: the nested arm was rooted at `$TMPDIR/p0`, not `$TMPDIR`, because `p0` holds only the spike. (f) compared rendered headers, not transcript `files[]` (no transcript in the sandbox). The install is 2.1.296, not 2.1.295.

#### Phase 1: Routing data
**Model:** sonnet
- Add `load:` to all 19 rules per the classification table. Every rule already opens with frontmatter, and `.otto.yml:119-128` already requires that (`ba21860`), so `load:` is one added line inside an existing block.
- **Success criteria:** `rg --files-without-match '^load:' HOME/repos/.claude/rules/*.md | wc -l` prints `0`; `otto ci` exits 0.
  - Observed on `retro-fixes` `500c4c8` (2026-10-09): `rg` count `19`; the `.otto.yml` frontmatter check's `awk` prints nothing.

#### Phase 2: Router library
**Model:** opus
- `rules.ts` with the API above; tests in `rules.test.ts` built from real attachment text pasted in as fixtures (the e9ef7f18 15-row burst, the 2b8aebe2 `instructions` blob).
- A test over the real `rules/` dir that every `load:` parses and every regex compiles (the CI teeth for Phase 1), and a test that every `tools[].match` matches at least one tool name in `HOME/.claude/settings.json`.
- `normalizeStatement` cases: `env X=1 git -C repo push`, `git -c k=v tag -d v1`, `GIT_DIR=x git branch -D b` all reach their gate; `git log`, `gitk`, `echo git push` do not.
- **Success criteria:** `splitInstructions(blob)` yields 18 file sections for the 2b8aebe2 fixture (its `files[]` count; a parser that never splits fails this), 17 with a `path` plus the path-less `<managed-settings>` section, after a leading path-less preamble (Phase 0 (b)) and `joinInstructions` of that split equals the blob byte for byte; the e9ef7f18 fixture maps to 15 paths, 4 of them routed (git, marquee, otto, voice); the fixture predates `ba21860`, so its cli and logging rows are outside the rule index and kept; `bun test` in `rails/hooks` passes with more than 147 tests.

#### Phase 3: Wire the hooks
**Model:** opus
- `index.ts`: the five hooks, the ledger, delivery state, the latch, `rule_routing` toggle, `.catch` on each.
- **Success criteria:** hook tests (runner per Phase 0 (j)):
  - the e9ef7f18 burst keeps 11 files and drops 4; a second `nested_memory` for an already-kept real path returns `{ text: null }`;
  - two gated calls for the same rule in one step both deny, and a third after a `turn.step` passes;
  - a forced throw in the drop hook sets the latch and calls `invalidate('prompt.attachment')`, after which the same attachment passes through unchanged.

#### Phase 4: Tooling
**Model:** sonnet
- `.otto.yml`: add the router tests to the `test:` task under the runner Phase 0 (j) chose; add new files to the lint list. `hooks-preflight.sh`: warn when `rails` is not enabled or `rule_routing` is false. `~/.claude/CLAUDE.md:67,78,79`: the Rules block labels voice, git and otto `(always-on)`; relabel them `(on trigger)` (marquee has no line there), and add one line saying routed rules arrive on trigger.
- **Success criteria:** `otto ci` exits 0.

#### Phase 5: Live acceptance (operator)
**Model:** opus
- Scott grants write access to `HOME/.claude/skills/rails` (sandbox `denyWithinAllow`) and starts a new session after landing.
- Replay e9ef7f18 from `/home/saidler`; run `git tag -l` in a fresh `~/repos` session; canary-verify each.
- **Success criteria:** the acceptance criteria below, run live.

#### Phase 6: Router log (addendum 2026-10-10)
**Model:** opus
- **Why.** Every router line (`say()`, `index.ts:1225`) goes to the CC debug log, written only under `--debug`/`--debug-file`; `~/.claude/debug`'s newest file is 2026-10-02, so normal sessions keep none. The session `.jsonl` records the engine's pre-hook attachment (Phase 0 (c)), so a dropped rule still looks loaded there, and the latch reason is nowhere. On 2026-10-10 the latch fired in a live session (`rules: router failed, full load restored`) and its cause (`$.fs.read(.../rules/cli.md) failed: ENOENT`) could only be recovered from a different session's debug log.
- **What.** `say()` also appends each line, prefixed with an ISO timestamp and the loop (`main` or `agentId`), to `~/.local/share/rails/router/<sessionId>.<copyTag>.log` (`$.session.id()`; `copyTag` is the module copy's load time in ms and a random suffix). `$.fs.write` writes whole files (no append, 4 MiB cap), so each module copy keeps its own lines in memory and rewrites its own file, writes serialized within the copy, at most one in flight plus one queued. One file per session and module copy, so neither concurrent sessions nor two loaded copies of the module (a hot reload) ever write one file; nothing is read back. A `/clear` or in-process resume (`session.end`, reason `clear`/`resume`) closes the file with a line and the next session id gets its own. Past 1 MiB the oldest lines are dropped and the file opens with `... <n> earlier lines dropped`. At index build, beside it and never awaited by it, `*.log` files in that directory older than 14 days go through `rkvr rmrf` (rules/safety.md: not regenerable), the first `rkvr` on the engine's `PATH`, else `~/.cargo/bin/rkvr`; with neither, nothing is deleted and the log says so.
- A log write failure never trips the latch and never fails a hook: it is swallowed, once noted in the debug log.
- The latch status line names the cause: `rules: router failed (<where>: <message, first 80 chars>), full load restored; log <path>`. A failure opens the log itself, so a latch before any hook opened it (a `$.state.get` that throws) still reaches the file and the status names its real path. A routing decision never awaits the log's opening.
- Logged beyond today's lines: one `rules: session <id> start, routing on|off, CC <version>` line at index build, and the latch reason line (`rules: routing off: ...`, already emitted by `latch()`).
- **Success criteria:**
  - spec tests: lines buffer and the file content equals the joined buffer; the 1 MiB cap drops oldest and writes the marker; a rejecting `$.fs.write` leaves routing on; pruning deletes only `*.log` older than 14 days in that directory.
  - live: a fresh `claude -p` session leaves `~/.local/share/rails/router/<id>.<copyTag>.log` holding the `session ... start` line and the drop lines for git, marquee, otto, voice, with no `--debug` flag.
  - Observed on `main` `373396d` (2026-10-10): `ls ~/.local/share/rails` -> `No such file or directory`.
  - Observed live 2026-10-10 (Phase 6 build, CC 2.1.296): spec tests `bun test` `300 pass 0 fail` (290 before), `claude plugin test` rails `19 pass 0 fail` (16 before), each listed case among them. Live: `claude -p "reply OK"` from `~/repos/scottidler/claude`, no `--debug` or `--debug-file`, session `a6c5ed70-64ca-4395-ad10-994e6c07d38a`, answer `OK`. `~/.local/share/rails/router/a6c5ed70-64ca-4395-ad10-994e6c07d38a.log` opens `2026-10-10T14:55:54.583Z main rules: session a6c5ed70-64ca-4395-ad10-994e6c07d38a start, routing on, CC 2.1.296`, then `main rules: pruned 1 router logs older than 14 days` (a `zz-prune-probe.log` touched to 20 days old was gone after the run, the other session's fresh log kept), `main rules: index of 19 files, routed git.md marquee.md otto.md voice.md`, and among the keeps `main rules: drop marquee.md (routed) .../HOME/repos/.claude/rules/marquee.md`, `drop otto.md (routed)`, `drop git.md (routed)`, `drop voice.md (routed)`, all stamped `2026-10-10T14:55:55.079Z`.
  - Observed live 2026-10-10 after implementation audit round 2 (synthesis X6CMQgQe, CC 2.1.296): spec tests `bun test` `302 pass 0 fail`, `claude plugin test` rails `24 pass 0 fail`, `otto ci` `All CI checks passed!`. Live: `claude -p "reply OK"` from `~/repos/scottidler/claude`, no `--debug` or `--debug-file`, session `49e81850-d59d-459e-97f2-2702fb1659ee`, answer `OK`. `~/.local/share/rails/router/49e81850-d59d-459e-97f2-2702fb1659ee.1791646700575-ovdvrb.log` opens `2026-10-10T15:38:23.478Z main rules: session 49e81850-d59d-459e-97f2-2702fb1659ee start, routing on, CC 2.1.296`, then `main rules: index of 19 files, routed git.md marquee.md otto.md voice.md`, `main rules: pruned 1 router logs older than 14 days` (a `zz-prune-probe.log` touched to 20 days old went to `/var/tmp/rmrf/2026-10-10-083823-000/router.tar.gz`, `metadata.yml` `targets: - zz-prune-probe.log`), and among the keeps `main rules: drop marquee.md (routed) .../HOME/repos/.claude/rules/marquee.md`, `drop otto.md (routed)`, `drop git.md (routed)`, `drop voice.md (routed)`, all stamped `2026-10-10T15:38:24.030Z`. The implementing session's own hot reloads left two files side by side, `ad0790ab-....1791646236702-gom310.log` and `ad0790ab-....1791646312183-ij7m5q.log`, each with its own start line.

## Acceptance Criteria

- [x] Every rule declares `load:`. `rg --files-without-match '^load:' HOME/repos/.claude/rules/*.md | wc -l` prints `0`.
  - Observed on `retro-fixes` `500c4c8`: `19`.
  - Observed live 2026-10-09 (`main` `030070d`): `0`.
- [x] `bun test` in `HOME/.claude/skills/rails/hooks` passes with the router tests included.
  - Observed on `retro-fixes` `500c4c8`: `147 pass, 0 fail` (no router tests yet).
  - Observed live 2026-10-09 (`main` `030070d`): `262 pass`, `0 fail`, `Ran 262 tests across 2 files` (`index.spec.ts`, `rules.spec.ts`). `claude plugin test HOME/.claude/skills/rails`: `15 pass`, `0 fail`, `Ran 15 tests across 1 file`.
- [x] In a `claude --debug` session rooted at `/home/saidler`, after `cat ~/repos/.claude/refs/slack.md`, the debug log holds `rules: drop` lines for exactly git, marquee, otto, voice and `rules: keep` lines for exactly `~/repos/CLAUDE.md`, interaction, taste, pr, general, recall, search, secrets, safety. cli and logging have no `keep` or `drop` line: they live in `refs/` since `ba21860` (amended 2026-10-09 from "do not appear at all": the stale `~/repos/.claude/rules/{cli,logging}.md` symlinks the move left behind are dangling, so the engine loads neither and the router's index logs each once as `skip`). Not the model's self-report: `~/.claude/CLAUDE.md` lists every rule by name, so a model asked what it has loaded can name files it never saw.
  - Observed: cannot run, needs Phase 3. The e9ef7f18 burst carried all 15; on `retro-fixes` the same read would carry 12 (`~/repos/CLAUDE.md` plus the 11 unscoped rules) plus safety.
  - Observed live 2026-10-09 (`claude -p --debug-file`, CC 2.1.296, cwd `/home/saidler`, one Bash `cat ~/repos/.claude/refs/slack.md`; the prompt spelled the name out so voice's `\bslack\b` prompt trigger did not fire). The burst after the `cat`, in log order: `keep CLAUDE.md (bulk) .../HOME/repos/CLAUDE.md`, `drop marquee.md (routed)`, `keep interaction.md (bulk)`, `keep pr.md (bulk)`, `drop otto.md (routed)`, `keep search.md (bulk)`, `drop git.md (routed)`, `keep recall.md (bulk)`, `keep taste.md (bulk)`, `drop voice.md (routed)`, `keep general.md (bulk)`, `keep secrets.md (bulk)`, `keep safety.md (bulk)`: 4 drops, 9 keeps, each matching the list. The engine's side, once per drop: `prompt.attachment nested_memory: rails (user) left it out (2518 characters)`, then `(1135 characters)`, `(6116 characters)`, `(1749 characters)`. cli and logging appear only at index build, before the prompt: `rules: skip cli.md (leads to no file) /home/saidler/repos/.claude/rules/cli.md` and the same for `logging.md`, then `rules: index of 19 files, routed git.md marquee.md otto.md voice.md`. The only other keep lines are the session-start `instructions` blob (`keep CLAUDE.md (bulk) .../HOME/.claude/CLAUDE.md`, `keep WHOAMI.md (bulk)`), before the `cat`.
- [x] In a fresh `claude --debug` session rooted in `~/repos`, the debug log holds `rules: drop git.md` at start, exactly one `rules: inject git.md` after Bash `git -C <repo> log -1` and a second `git -C <repo> status`, and a `git push --dry-run` issued before any git command is denied once with git.md's text before it executes. (Amended 2026-10-09 from `git tag -l` and a bare `git status`: this doc's own git row gates `^git (push|tag|branch -D)\b`, so `git tag -l` is a gate hit and is denied, never injected, and `~/repos` is not a git repository, so `git-release-guard.sh` denies any git command there without `-C`.)
  - Observed: cannot run, needs Phase 3.
  - Observed live 2026-10-09 (`claude -p --debug-file`, CC 2.1.296, cwd `/home/saidler/repos`, repo `/home/saidler/repos/scottidler/claude`). Inject session: at start `rules: drop git.md (routed)`; on the first Bash `git -C ... log -1 --oneline`, `rules: inject git.md (Bash)`; the second Bash `git -C ... status --short` adds no rules line; both calls `outcome=ok`, no `release` line. 1 inject line total. Canary, same prompt shape, two fresh sessions in `~/repos` asked for the date in the parenthetical after git.md's "Just yeet it.": with no tool call the answer is `NONE`; after one `git -C ... log -1` (`rules: inject git.md (Bash)`) the answer is `2026-07-03`. Gate session, the first and only git command `git -C ... push --dry-run`: `rules: drop git.md (routed)` at start, then `rules: gate git.md (deny Bash)` and the engine's `tool.call Bash ...: resolved by a hooks module (deny: rails: git.md must be in context before this call runs, so it did not run. Read the rule below, then retry the call.\n\nContents of /home/saidler/repos/scottidler/claude/HOME/repos/.claude/rules/git.md:\n\n# Git ...`, then `rules: delivered git.md (turn.step)`. No `tool_dispatch_start` for that call. The model's retry passed the router (no second gate line) and was denied by `intent-guard.sh` (git network command inside the sandbox), so `push` never ran. The criterion as first written, run as written: `git tag -l` logged `rules: gate git.md (deny Bash)` then `rules: delivered git.md (turn.step)`, the retry and `git status` added no rules line, and `git-release-guard.sh` denied both (`'/home/saidler/repos' is not a git repository`).
- [x] `HOME/.claude/hooks/hooks-preflight.sh` mentions `rule_routing`.
  - Observed on `retro-fixes` `500c4c8` (2026-10-09): `rg -c rule_routing HOME/.claude/hooks/hooks-preflight.sh` prints nothing, exit 1 (0 matches).
  - Observed live 2026-10-09 (`main` `030070d`): `rg -c rule_routing HOME/.claude/hooks/hooks-preflight.sh` prints `2`.

## Resolved Decisions

- 2026-10-08: build in `rails`, not a new plugin. rails' design makes it the one function-hook container, and it already loads on this install.
- 2026-10-08: routing is frontmatter data per rule, not a table in the mod (config drives behaviour; the rule owns its trigger).
- 2026-10-08: drop-and-inject (A) over relocate-and-inject (Alternative 1): A's failure mode is today's full load, B's is rules silently missing.
- 2026-10-09, panel round 1 (staff-engineer and architect converged; author verified each against the typings and repo): search and secrets stay `always`; voice's triggers widen to every surface `voice.md` names; cli and logging globs include design docs and READMEs (superseded the same day: `ba21860` moved both to `refs/`); prompt context goes down through `next`; ledger is plain JSON; failure is a latch plus `invalidate('prompt.attachment')`; gates carry pending vs delivered state; Bash matching runs on a normalized statement; tool names are asserted against `settings.json`. Scott can re-route any rule by editing its `load:` line; that is the point of putting it in data.

## Alternatives Considered

### Alternative 1: Relocate routed rules out of the auto-load directory
- **Description:** move routed rules to `~/repos/.claude/rules-on-demand/`; the mod only injects.
- **Pros:** no blob parsing; nothing to drop.
- **Cons:** a router failure means those rules never load, silently. Needs a manifest and symlink change.
- **Why not chosen:** fails in the wrong direction. Kept as Phase 0's fallback if the `instructions` rewrite does not take.

### Alternative 2: Native `paths:` for everything
- **Description:** give each rule a `paths:` glob.
- **Cons:** `paths:` matches files read, not what the work is. git.md is about running `git`; no file glob expresses that.
- **Why not chosen:** wrong trigger type. The two rules it fit (cli, logging) left `rules/` for `refs/` in `ba21860`.

### Alternative 3: Settings hooks (shell) only
- **Description:** PreToolUse / UserPromptSubmit shell hooks inject rules via `additionalContext`.
- **Cons:** a shell hook cannot remove an attachment; the drop half is impossible.
- **Why not chosen:** solves half. Kept as the Phase 0 fallback for prompt triggers.

## Technical Considerations

### Dependencies
- CC function hooks (`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`), CC auto-updates on the `latest` channel. Typings are from 2.1.292; the install is 2.1.295. Phase 0 runs on the installed version.

### Performance
- Rule index built once per session (19 small files). Regex matching per prompt and per tool call. Dropped text is answered once per attachment for the process (`types :4161`), which keeps the prompt cache stable.

### Security
- No new permissions. The mod reads files under `~/repos/.claude/rules/` with `$.fs`, which runs with Scott's permissions (mods are not sandboxed). secrets.md stays always-on: its never-print invariant has to be in context before any decrypt, and no hook enforces it.

### Testing Strategy
- Pure functions in `bun test` from real transcript fixtures. Hooks under the runner Phase 0 (j) picks (`claude plugin test`, or rails' `internals` pattern). Live behaviour verified with canary tokens and the router's debug log, never with transcript `rendered` text.

### Rollout Plan
- `rule_routing` defaults true. Flipping it false in `/plugin` config sets the latch and re-asks every attachment, so today's full load returns in the running session, no code change.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A trigger misses and a needed rule never loads | Med | Med | Prompt + tool + bash triggers per rule; gate on outward tools; always-on set kept for judgment rules |
| The engine changes attachment framing on auto-update | Med | High | Split failure throws -> latch + re-ask -> full load + status line; Phase 2 fixtures make the break visible in CI |
| A drop-path failure after some files were already kept leaves the ledger partial, so a later trigger injects a rule the full load already carried | Low | Low | With the latch set, injection stops too: no routing, no injects, today's behaviour |
| Injected rule lost on compaction | Med | Low | Ledger cleared on `session.compact`, rule re-injects on next trigger |
| `--resume` starts a new process with an empty ledger, so a rule already in the transcript injects a second time | Med | Low | Accepted: one duplicate per rule per resume, against today's full reload. Ledger is rebuilt from nothing rather than from the transcript, which the hook cannot read back reliably |
| A rule's regex fails to compile | Low | Med | Phase 2's test over the live `rules/` dir fails CI; at run time the file is treated as `always` and a status line names it |
| A rule edited mid-session keeps its old triggers | Low | Low | Index is per session; new session picks it up, same as the engine's own rule loading |
| A gate deny on a tool Scott already approved reads as friction | Med | Low | One deny per rule per context; prompt triggers usually load the rule before the draft, so the gate is the backstop |

## Open Questions
None. The classification question was answered by panel round 1 (see Resolved Decisions); whether invalidation re-delivers is Phase 0 (h), with its fallback fixed in advance.

## References
- Session `e9ef7f18-39ab-4657-9f49-64867f08695e`, transcript `:162` (trigger), `:191-205` (burst)
- Mods API: `plugin-authoring/reference.md`, `types/claude-code.d.ts` (2.1.292 bundle)
- `HOME/.claude/skills/rails/hooks/index.ts`, `docs/design/2026-09-08-rails-bash-rewrite.md`
- Marquee: `~scott-idler/claude-code-mods`, `~scott-idler/putting-mods-to-work-at-tatari`
