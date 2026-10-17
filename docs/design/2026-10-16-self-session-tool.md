# Design Document: `self` mod, a session tool the model can call

**Author:** Scott Idler
**Date:** 2026-10-16
**Status:** Implemented
**Review Passes Completed:** 5/5

## Summary

A mod (an in-process Claude Code plugin, same shape as `rails`) named `self` that registers one model-callable tool, `mcp__self__session`. One call returns the session's id, cwd, project root, git repo, context-window fill, cost, prompt count and start time. Every read comes from `$.session`. None costs an API request unless the model asks for a context breakdown.

## Problem Statement

### Background

- A mod can give the model a tool: `$.tool.register` declares `mcp__<plugin>__<name>`, and a `tool.call` hook on that name answers it (`plugin-authoring/reference.md:245-254`, CC 2.1.302).
- `$.session` already has every value wanted, read-only: `id()`, `cwd()`, `root()`, `repo()`, `turns()`, `usage()` (`types/claude-code.d.ts`, the `session:` noun, CC 2.1.302).
- `usage()` with no argument is free: "The plain call costs nothing" (same file, `usage` doc comment).
- In-house precedent: `rails` at `HOME/.claude/skills/rails/` loads implicitly as `rails@skills-dir`, since `~/.claude/skills` is this repo's folder (`manifest.yml:5`). `.otto.yml:179-185` runs its bun specs, its kit tests and `validate --strict`. `self` copies that layout and that wiring.
- Not a setup-audit chunk. Scott asked for it directly, this session. Chunk H's item 15 ("context budget") is untouched: this doc exposes a reading and sets no budget or policy.

### Problem

- The model cannot ask for its own session id. Hooks and the status line see it; the model does not. Handoffs, session recall (clyde) and `rails`' per-session logs all key on it.
- The model cannot ask how full its context is. It learns only when the harness compacts.
- The system prompt's cwd goes stale after a `cd`.

### Goals

Each item names who asked for it.

- One tool call returns every fact below. Scott, 2026-10-16: "group them".
  - `sessionId`. Scott.
  - `context`: `tokens`, `window`, `percent`. Scott ("how much of its context was used").
  - `cwd`, `root`, `repo`, `costUsd`, `turns`, `startedAt`. Proposed this session, Scott: "everything else is interesting".
- Optional input `breakdown: "summary" | "full"`, which adds the `/context` split. Proposed this session with the grouping, accepted.
- Schema in the prompt's tool list from turn one (`isDeferred: false`), so the model calls it without a ToolSearch first. Proposed this session, not objected to.
- `agentId` when a subagent calls. Not asked for: it rides because without it a subagent cannot tell whose figures it got (Phase 0 (e)). Review panel round 1.

### Non-Goals

- Rate limits. Excluded. Scott, 2026-10-16: "ratelimits dont care".
- `model()`, `version()`. Excluded: the system prompt names the model; the version matters only when debugging a mod.
- Transcript path. Excluded: 2.1.302 has no `$.session` method for it.
- Any policy on the numbers (compact at N%, handoff at N%). Excluded: chunk H's ground.
- UI (band, pane, status entry). Excluded: the status line already draws context fill for Scott.
- `repo.internal` and `repo.name`. Excluded: both come from the CC build's own allowlist, and `name` is null whenever `internal` is false (types file, `SessionRepo`), so for every one of Scott's repos. `remote` already names the repo.
- Cloud and remote sessions. Excluded: the mod loads from `~/.claude/skills`, which those hosts do not have.
- Publishing to the org library or `tatari-skills`. Parked. Revisit after it has run in Scott's own sessions.

## Proposed Solution

### Overview

- `HOME/.claude/skills/self/`, the `rails` layout:
  - `.claude-plugin/plugin.json`: name `self`, version `0.1.0`, author block copied from `rails`.
  - `hooks/hooks.json`: `{ "modules": ["./index.ts"] }`.
  - `hooks/index.ts`: the hooks module.
  - `tests/session.test.ts`: kit tests (the engine kit refuses `bun:test` imports, `.otto.yml:177-178`).
- No `$.state`, so no `types/index.d.ts`.

### Architecture

```
session.start -> await $.tool.register(spec) -> next(e)      listed by turn one

model: tool_use mcp__self__session { breakdown? }
  -> tool.call hook (self), matcher { tool: 'mcp__self__session' }
       -> Promise.all: $.session.id/cwd/root/repo/turns/usage({ breakdown })
       -> shape SessionFacts (strip remote userinfo, drop gridRows, ms -> ISO)
  <- { result: JSON.stringify(SessionFacts) }   any rejection -> { deny: "<method>: <message>" }
```

- The result is a JSON string, never the object: core rejects an object result (Phase 0 (b)). The hook never calls `next(e)`: no hook beneath serves this name, and a call nobody answers fails anyway (`reference.md:252-253`).
- `register` awaits inside `session.start` before `next(e)`, the documented pattern (types file, `session.start` doc: `$.tool.register(t).then(() => next(e))`). A reload re-runs `session.start`, and registering the same name again replaces the tool (`reference.md:253`).

### Data Model

```ts
type SessionFacts = {
  sessionId: string          // $.session.id()
  agentId?: string           // e.agentId: present only when a subagent called
  cwd: string                // $.session.cwd()
  root: string               // $.session.root()
  repo: {                    // $.session.repo(), null outside git
    root: string             // the MAIN working tree's root, even from a worktree
    remote: string | null    // userinfo stripped: https://tok@host/x -> https://host/x
  } | null
  context: {                 // usage().context
    tokens?: number          // absent until a window's first response
    window: number           // the model's window, in tokens
    percent?: number         // tokens / window, 0-100
    breakdown?: Omit<SessionContextBreakdown, 'gridRows'>
  }
  costUsd?: number           // usage().cost?.usd
  turns: number              // $.session.turns(): prompts Scott has sent
  startedAt: string          // usage().startedAt (ms) -> ISO 8601
}
```

- `gridRows` is dropped: it is the `/context` drawing grid, noise to the model.
- `breakdown.percentage` measures against `rawMaxTokens` (the compaction window), so it can differ from `percent`. The types file says so; the tool description says so too.
- Stripped, not dropped: a remote URL can carry a token in its userinfo. The tool never prints one.
- Three roots, three meanings: `cwd` is where the session runs now, `root` is where it started, `repo.root` is the main working tree. From a worktree `repo.root` differs from both.

### API Design

- Plugin `self`, tool `session`, so the model sees `mcp__self__session`.
- Description, verbatim: "This session's id, cwd, project root, git repo, context-window fill, cost, prompt count and start time. Context figures are from the last API response, so they miss the current turn, and are absent right after a compaction. Pass breakdown (summary: local estimate, free | full: counted like /context, slower) for the per-category split; its percentage is against the compaction window. From a subagent, context figures are the main conversation's. costUsd leaves out the response that made this call: it is priced only once that response ends."
- Input schema: `{ type: "object", properties: { breakdown: { type: "string", enum: ["summary", "full"] } }, additionalProperties: false }`.
- The hook re-checks `breakdown` and denies any other value, loudly: Phase 0 (g) showed core does not enforce the schema (the hook received `"bogus"` and ran), so the hook must not rely on it. `$.session.usage()` also validates its own argument (`takes breakdown "summary" or "full"`), so without the hook check a bad value would still fail closed, with engine text; the hook check runs first and names the input. The input arrives flat on the event: `e.breakdown`, not `e.input.breakdown`.
- Errors: any `$.session` rejection -> `{ deny: "<method>: <message>" }`, where `<message>` is the rejection's error message as the engine words it. Live, that is `<plugin>: $.session.<method>: <reason>`, so the model reads e.g. `usage: self: $.session.usage: <reason>`. Kept as-is, not stripped: parsing the engine's wording would break when it changes. No partial object; a half-filled answer reads as a true one.
- A requested `breakdown` that does not come back ("present only when the call passed `breakdown`, and only with a session bound", types file) -> `{ deny: "breakdown: not returned" }`. Same rule: asked for and missing is a failure, not an absence.
- The `tool.call` registration carries the guard `.catch`: `on(...).catch(($, e, next) => ({ deny: `self: ${next.error.message}` }))`. Without it a thrown hook is skipped (`reference.md:79`), nobody answers, and the model gets a generic failure.

### Implementation Plan

#### Phase 0: Prove the tool path headless
**Model:** sonnet
- Throwaway probe plugin under `$TMPDIR/p0/`, loaded with `--plugin-dir`, run with `claude -p` only (Scott, 2026-10-09, rule-routing Phase 0: no interactive sessions). No repo code.
- Arms:
  - (a) A tool registered in `session.start` with `isDeferred: false` is listed in the stream-json `init` event's `tools` and callable on turn one.
  - (b) What the model reads for `{ result: <object> }` vs `{ result: JSON.stringify(<object>) }`. Judged mechanically: the probe reads the call's `ToolUseSummary.text` ("the result as the model read it") through `$.session.messages()` and checks it `JSON.parse`s once back to the original object.
  - (c) `$.session.id()` equals the `init` event's `session_id`.
  - (d) `context.tokens` is present when the tool runs on turn one.
  - (e) Called from a subagent on a different model than the parent (haiku under sonnet): what `id()`, `usage().context.window` and `e.agentId` report. A different model is what separates "own window" from "parent's window".
  - (f) Bash `mkdir -p sub && cd sub`, a second Bash `pwd` confirming `<launch>/sub`, then what `cwd()` reports. A subdirectory, because a `cd` out of the working dirs may be reset by Claude Code and fake a "does not follow".
  - (g) A call with `breakdown: "bogus"`: does core reject it before the hook?
  - (h) `rails` is loaded beside the probe (it loads in every session from `~/.claude/skills`). Its catch-all `tool.call` hook (`rails/hooks/index.ts:1778`) returns `next(e)` when no rule names the tool. Confirm the call reaches the probe unchanged: no added `context`, no deny.
- Decision rules, fixed now:
  - (b): whichever form the model reads as clean JSON ships. If both do, the object ships.
  - (e): `id()` is the parent's -> `sessionId` stays, the description says so. `window` matches the parent's model -> the description gains "From a subagent, context figures are the main conversation's". It matches the child's -> no caveat. `agentId` absent in a subagent -> Phase 1 stops and the doc goes back for a ruling, since the result could not say whose figures it holds.
  - (f): if `cwd()` does not follow the `cd`, the description drops "cwd" and the field is renamed `launchCwd`. Names tell the truth.
  - (h): any added `context` or a deny -> Phase 1 adds a rails exemption for `mcp__self__` and a test for it; else nothing.
- **Success criteria:** every arm's observed output pasted under Phase 0 Results below; arm (a) prints the probe's marker string.

#### Phase 1: Build the mod
**Model:** sonnet
- The four files per Overview. `index.ts` per Architecture, Data Model and API Design, with Phase 0's rulings applied: the `tool.call` answer is `{ result: JSON.stringify(facts) }` (an object result is rejected by core); `agentId` stays as `e.agentId`; `sessionId` stays (a subagent's `id()` is the session's); the description carries the subagent caveat; the field stays `cwd`; no rails exemption.
- Kit tests in `tests/session.test.ts`, each broken against the code once to prove it bites:
  - `registers mcp__self__session at session.start, not deferred`
  - `answers with sessionId equal to $.session.id()` (parse the JSON string result)
  - `omits breakdown unless asked`
  - `breakdown summary carries categories and no gridRows`
  - `denies an unknown breakdown value`
  - `strips userinfo from repo.remote`
  - `denies, naming the method, when a $.session call rejects`
  - `denies when a requested breakdown does not come back`
  - `repo is null outside git`
  - `startedAt is ISO 8601 of usage().startedAt`
- `.otto.yml`: add `index.ts` and the test to the lint list, plus `claude plugin test HOME/.claude/skills/self` and `claude plugin validate --strict HOME/.claude/skills/self` beside the rails lines.
- **Success criteria:** `claude plugin test HOME/.claude/skills/self` exits 0 with the 10 named tests passing; `otto ci` exits 0.

### Phase 0 Results

**Run 2026-10-16, CC 2.1.302.** Probe `p0self` (throwaway, `$TMPDIR/p0/probe`, not in the repo) loaded with `--plugin-dir`; four tools registered in `session.start` with `isDeferred: false` (`facts`, `obj`, `str`, `report`); every arm `claude -p --output-format stream-json --verbose --debug-file`, launched from `$TMPDIR/p0/launch`. `rails@skills-dir` loaded alongside (init `plugins` lists it; debug log `hooks module rails@skills-dir loaded ... events: prompt.attachment,prompt.submit,tool.call,...`). Marker: `P0-MARKER-7f3a91`.

- **Finding before the arms (changes Architecture):** a first run returned `{ result: <object> }` and core refused it: `tool.call step resolved mcp__p0self__facts with a result that does not match its output shape: [ { "code": "invalid_union", ... "Invalid input: expected string, received object" ... "expected array, received object" ... "expected undefined, received object" } ]`. A `tool.call` result is a string, an array or undefined. The doc's `{ result: SessionFacts }` could not have worked.
- **(a) PASS.** Init `tools` contains `mcp__p0self__facts, mcp__p0self__obj, mcp__p0self__report, mcp__p0self__str`. Model called `mcp__p0self__facts {}` as its first call; the tool result carries the marker: `{"marker":"P0-MARKER-7f3a91","sessionId":"6a932ade-8d54-4b60-8795-207c6b659279","cwd":"/tmp/claude-1000/p0/launch","root":"/tmp/claude-1000/p0/launch","tokens":34051,"window":1000000,"percent":3}`. Debug log: `[p0self] $.ui.log (to debug): P0: registered P0-MARKER-7f3a91`.
- **(b) string ships.** `{ result: <object> }` -> the model read the `tool_use_error` above (`parsesOnceToOriginal: false`). `{ result: JSON.stringify(obj) }` -> `ToolUseSummary.text` is `{"a":1,"b":["x","y"],"c":{"d":null,"e":true}}`, `parsesOnceToOriginal: true` (probe `report`, read through `$.session.messages()`). Ruling: the string form ships (the object form is not readable at all).
- **(c) PASS.** init `session_id` `6a932ade-8d54-4b60-8795-207c6b659279`; `$.session.id()` in the tool result: `"sessionId":"6a932ade-8d54-4b60-8795-207c6b659279"`. Same in every other run (e.g. `cb694a4b-c714-4b96-ae89-f2c17aae32a6` in (f)). The debug log redacts the id, so the comparison is the tool result against the stream.
- **(d) PASS.** Turn one, first call: `"tokens":34051,"window":1000000,"percent":3`.
- **(e) `agentId` present; `id()` is the session's; figures are the main conversation's.** Parent sonnet, child `haiku` via the Agent tool. Child's tool result: `{"marker":"P0-MARKER-7f3a91","sessionId":"c3e1510f-5f41-40e7-93b1-5ffeffff9568","agentId":"aa7fd8b9e5cf8e76c","cwd":"/tmp/claude-1000/p0/launch","root":"/tmp/claude-1000/p0/launch","tokens":35319,"window":1000000,"percent":4}`; parent's own calls: no `agentId`, `sessionId` the same `c3e1510f-...`. Debug log: `facts called event={"tool":"mcp__p0self__facts","tool_use_id":"toolu_017oZXGqfspspRirA5tZv1ff","agentId":"ae7d167457669fd60"}` for the child, no `agentId` key for the parent. The window does not separate parent from child on this machine: haiku as the main model also reports `"window":1000000`, and with `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` it reports `"window":200000`, so every model here shares one window. `tokens` does separate them: parent call 1 `34196`, child `35319` (after the child read the 1,945-line `rails/hooks/index.ts` itself, which would put its own context far higher), parent call 2 `36369`. The child's figure sits on the parent's growth line, so it is the main conversation's. Run 1 agreed: parent and child both `"tokens":34135`.
- **(f) cwd follows the cd.** Bash `mkdir -p sub && cd sub`; Bash `pwd` -> `/tmp/claude-1000/p0/launch/sub`; then `"cwd":"/tmp/claude-1000/p0/launch/sub","root":"/tmp/claude-1000/p0/launch"`. `cwd()` moved; `root()` did not.
- **(g) core does not enforce the schema.** Call `mcp__p0self__facts {"breakdown": "bogus"}` -> tool result is the normal facts JSON, no error. Debug log: `facts called event={"breakdown":"bogus","tool":"mcp__p0self__facts","tool_use_id":"toolu_01JdqzUZ2j1HVXmobb4NWw3b"}`. The hook ran with `bogus`, so the hook's re-check is the only enforcement. The input is flat on the event (`e.breakdown`).
- **(h) PASS.** With rails loaded and its catch-all `tool.call` hook beneath/above the probe, every `mcp__p0self__*` call reached the probe and returned the probe's string unchanged: no added `context`, no deny, in every run above. Rails was live in each run (debug log: `hooks module rails@skills-dir loaded (worker, environment 3, tier user); events: ...,tool.call,...`); the probe's `tool.call` matcher names only `mcp__p0self__*`, and rails answered none of those.

Rulings:
- (b): string ships; Architecture and Phase 1 changed to `{ result: JSON.stringify(facts) }`.
- (e) `id()`: the session's -> `sessionId` stays. (e) window/figures: main conversation's -> description gains "From a subagent, context figures are the main conversation's" (folded above). (e) `agentId`: present -> Phase 1 proceeds, no stop.
- (f): follows the cd -> field stays `cwd`, description keeps "cwd".
- (h): no change -> no rails exemption, no extra test.
- (g): no rule; recorded: the hook's check is load-bearing.

## Acceptance Criteria

- [x] **AC1:** `claude plugin validate --strict HOME/.claude/skills/self` exits 0, and its hooks line lists `session.start` and `tool.call{tool=mcp__self__session}`.
  - Observed on main (`8af68b7`, CC 2.1.302): `File not found: .../HOME/.claude/skills/self`, `✘ Validation failed`, rc=1. Expected: the folder ships in Phase 1. The format holds: on the same export, `rails` prints `./index.ts hooks: ..., tool.call{tool=Bash}, ...`.
  - Observed after Phase 1: `claude plugin validate --strict HOME/.claude/skills/self` rc=0; `./index.ts hooks: session.start, tool.call{tool=mcp__self__session}`, `./index.ts gating hook with .catch: tool.call{tool=mcp__self__session}`, `✔ Validation passed`. (The matcher must be a literal in `index.ts`: a `const` concatenation printed `tool=?`.)
- [x] **AC2:** `claude plugin test HOME/.claude/skills/self` exits 0, with the tests named in Phase 1 passing (11 after the audit fold).
  - Observed on main: `claude plugin test: .../HOME/.claude/skills/self: no such plugin folder`, rc=1. Expected before Phase 1.
  - Observed after Phase 1: rc=0, `10 pass`, `0 fail`, `Ran 10 tests across 1 file`; the 10 names are those listed in Phase 1.
- [x] **AC3:** From a scratch dir, `claude -p --model haiku --output-format stream-json --verbose`, asked to call `mcp__self__session` and print only `sessionId`, prints exactly the `init` event's `session_id`.
  - Observed on main: `init session_id ee084e1c-3280-410a-97de-ac67093b5ca9`, `self tool listed: False`, result `NO-TOOL`, rc=0. The probe harness works; the tool is absent, as expected before Phase 1.
  - Observed after Phase 1: from `$TMPDIR/ac3`, init `session_id 79dbf03a-179b-4a21-b053-5a4737b7daf2`, `self tool listed: True`, tool result `{"sessionId":"79dbf03a-179b-4a21-b053-5a4737b7daf2","cwd":"/tmp/claude-1000/ac3","root":"/tmp/claude-1000/ac3","repo":null,"context":{"window":1000000,"tokens":34473,"percent":3},"turns":1,"startedAt":"2026-10-17T04:11:49.239Z","costUsd":0}`, model's final text `79dbf03a-179b-4a21-b053-5a4737b7daf2`, rc=0. Exact match.
- [x] **AC4:** `otto ci` in `scottidler/claude` exits 0, with `rg -c 'skills/self' .otto.yml` printing exactly `4` (lines: the index.ts lint entry, the test lint entry, `claude plugin test`, `claude plugin validate --strict`).
  - Observed on main (`8af68b7`, detached worktree): `[ci] ✅ All CI checks passed!`, rc=0. `rg -c 'skills/self' .otto.yml` prints nothing, rc=1 (zero matching lines). Expected before Phase 1: CI is green today and the self lines don't exist yet. Note: a `git archive` export fails lint with `fatal: not a git repository`, so run this on a git checkout.
  - Observed after Phase 1: `otto ci` rc=0, `[ci] ✅ All CI checks passed!`; `rg -c 'skills/self' .otto.yml` prints `4`.

## Resolved Decisions

- 2026-10-16, Scott: one grouped tool, not one per fact.
- 2026-10-16, Scott: rate limits out; cwd, root, repo, cost, turns, startedAt in.
- 2026-10-16, author: home is `HOME/.claude/skills/self/` in this repo, copying `rails`. No marketplace, no settings edit.
- 2026-10-17, Scott ("fold everything in"), superseding the author's call below: unknown input keys are denied, naming the key. The allowlist is the engine's own keys from the 2.1.302 types (`tool`, `tool_use_id`, `consent`, `agentId`, `requestMeta`) plus `breakdown`. A key a later engine adds denies every call with a message naming it, until it is listed in `index.ts:ENGINE_KEYS`. Test 11, `denies an unknown input key`.
- 2026-10-17, author, from the implementation audit (`~/.cache/review-panel/runs/mWGXuphR/synthesis.md`), SUPERSEDED above: unknown input keys (`{"breakdwon":"full"}`) are accepted, not denied. The engine puts its own keys flat on the same event (`tool`, `tool_use_id`, `agentId`), so rejecting unknown keys needs an allowlist of engine keys, and the next key the engine adds would deny every call. A typo costs a missing `breakdown`, which the model sees. Scott can overrule.

## Alternatives Considered

### Alternative 1: One tool per fact
- **Description:** `mcp__self__session_id`, `mcp__self__context`, and so on.
- **Pros:** Smaller results.
- **Cons:** One prompt tool-list entry per fact, every turn. A round trip per fact when the model wants two.
- **Why not chosen:** Scott chose grouping.

### Alternative 2: Push the facts into every prompt (`prompt.submit` context)
- **Description:** No tool. Inject the facts each turn.
- **Pros:** No call.
- **Cons:** Tokens every turn, used or not. Stale by mid-turn.
- **Why not chosen:** Scott asked for the ability to query.

### Alternative 3: Status-line script or settings hook
- **Description:** Out-of-process scripts already get `session_id` and `context_window` on stdin.
- **Cons:** They feed the status line or a hook verdict, never a tool the model calls.
- **Why not chosen:** Only a mod registers a model-callable tool.

### Alternative 4: Add the tool to `rails`
- **Description:** One more `tool.call` hook in the existing mod.
- **Cons:** `rails` keeps Bash on the rails. A read-only facts tool is unrelated, and `rails/hooks/index.ts` is 1,945 lines with userConfig toggles it does not need.
- **Why not chosen:** Decompose along change frequency: `self` should not reload or break with a rails guard change.

## Technical Considerations

### Dependencies
- CC >= 2.1.302, the build these types were read from.
- `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`, already set (`HOME/.claude/settings.json:7`).
- No cross-repo blast radius. One repo, no ship order.

### Performance
- Plain call: six local reads, no API request.
- `breakdown: "full"`: one token-count request per tool and memory file, as `/context`. It does not eat the 10 s hook budget: the clock stops while any `$` call is in flight (types file, `HookBudget`).
- Schema in every prompt: one short tool entry.

### Security
- Read-only. No `$.fs`, `$.process`, `$.http`, `$.state`.
- `repo.remote` userinfo stripped. Nothing else it returns is secret: cost, cwd and id are already on Scott's screen.

### Testing Strategy
- Kit tests per Phase 1, each proven to bite.
- Live: AC3, headless.

### Rollout Plan
- Commit to `main`. This repo takes no PR, both gates checked live per chunk D's log; re-check before the push.
- `~/.claude/skills` is this repo's folder, so the mod loads at the next session start. Whether an already-running session picks up a new folder is not verified and changes nothing here.
- Kill switch: `claude plugin disable self`, or `enabledPlugins["self@skills-dir"]: false`.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Context figures lag the current turn | High | Low | Description says so |
| `cwd()` does not follow a Bash `cd` | Med | Low | Phase 0 (f) rule renames the field |
| Subagent gets main-loop figures | Med | Low | Phase 0 (e) rule adds the caveat |
| rails' catch-all `tool.call` hook alters the result | Low | Med | Phase 0 (h) checks; rule adds an exemption |
| A remote URL leaks a token | Low | High | Userinfo stripped, tested |

## Open Questions

None. The Phase 0 unknowns each have a decision rule fixed above.

## References
- https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-mods/
- https://marquee.internal.tatari.dev/p/~scott-idler/putting-mods-to-work-at-tatari/
- `HOME/.claude/skills/rails/` (precedent)
- `docs/design/2026-10-08-rule-routing.md` (Phase 0 probe-plugin method)

## Review Log

- **Pass 1, Draft.** Shape: one mod, one tool, Phase 0 + Phase 1.
- **Pass 2, Correctness.** `register` must be awaited before `next(e)` in `session.start` (added). The hook answers and never calls `next`. Dropped `repo.internal` and moved it to Non-Goals. AC1 now uses the hooks-line format `validate` actually prints. The open subagent question became a decision rule.
- **Pass 3, Clarity.** Named the 7 kit tests. Added a Phase 0 Results slot. Wrote the description verbatim. Glossed `window` and both percentages.
- **Pass 4, Edge cases.** Remote URL userinfo leak: strip, test. `full` vs the 10 s hook budget: arm (h) plus a rule. Schema enforcement unknown: arm (g), hook re-checks. `cwd` after `cd`: arm (f) plus a rename rule. Post-compaction empty `tokens`: in the description. Right problem? Yes: three consumers key on the session id today.
- **Pass 5, Excellence.** Added Alternative 4 (fold into rails) and the kill switch. Ran AC1-AC4 against `main`.
- **Panel round 1** (`~/.cache/review-panel/runs/jUyFxdu3/synthesis.md`, 2 must-fix, 7 cheap wins, all verified against the types and rails before folding):
  - Must-fix: `repo.name` dropped (null outside the allowlist). Old (h) dropped: its 10 s premise was false (`HookBudget`), and its Risks row went with it.
  - Cheap wins: (b) judged by `ToolUseSummary.text`. (e) uses a different child model and has outcomes for `id()` and a missing `agentId`. (f) uses a subdirectory plus `pwd`. New (h) covers rails' catch-all hook. A requested-but-missing breakdown denies. The guard `.catch` is named. AC4 asserts exactly 4 lines. `agentId` provenance recorded. `repo.root` vs `cwd` vs `root` spelled out. The running-session claim is marked not verified.
  - Folded, not deferred: the fuller test matrix's cheap cases (non-git, ISO), 3 tests, 7 -> 10.
  - Dropped, panel's own call, agreed: a partial-failure fallback (contradicts fail-closed) and a `$.ui.log` per call (UI is a Non-Goal).
