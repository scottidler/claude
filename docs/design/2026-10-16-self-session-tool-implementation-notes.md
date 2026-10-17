# Implementation notes: `self` session tool

## Phase 0: Prove the tool path headless
### Design decisions
- Probe returned strings, not objects, from every `tool.call` hook after core rejected an object result - `$TMPDIR/p0/probe/hooks/index.ts` (throwaway, outside the repo) - the output shape is string | array | undefined, so the whole design's `{ result: SessionFacts }` becomes `{ result: JSON.stringify(facts) }`.
- Arm (b) was run with two separate tools (`obj`, `str`) plus a `report` tool that reads `ToolUseSummary.text` from `$.session.messages()`, so the judgment is mechanical as the doc specified.
- Arm (e) discriminated parent from child by `tokens`, not `window` - all models share one window on this machine (haiku main reports 1,000,000; 200,000 with `CLAUDE_CODE_DISABLE_1M_CONTEXT=1`), so `window` cannot tell "own" from "parent's"; the child's `tokens` (35319) sat between the parent's two readings (34196, 36369) after the child read a 1,945-line file, so the figures are the main conversation's.
- Folded rulings into the design doc: Architecture arrow and a sentence, the description's subagent caveat, API Design's schema-enforcement bullet, Phase 1's first bullet and the first test's name.

### Deviations
- The doc's Architecture `{ result: SessionFacts }` is wrong at the seam; the correct seam is a JSON string. Same effect, correct seam. Not a deviation from Phase 0's own steps.
- The `(e)` decision rule says "`window` matches the parent's model -> caveat". Window matched both models equally here; the caveat was applied on the `tokens` evidence. Recorded in Results.

### Tradeoffs
- Probe logged via `--debug-file` and the stream-json tool results vs. a transcript: `claude -p` in the sandbox may not write a transcript, and the debug log redacts ids, so ids were compared in the tool result against the `init` event.

### Open questions
- None blocking. Phase 1 should note that `window` is not a discriminator for a subagent on this machine, so the kit test for the caveat cannot be a window comparison.

## Phase 1: Build the mod
### Design decisions
- `tool.call` matcher is the literal `'mcp__self__session'`, not a const built from the tool name - `self/hooks/index.ts` - `claude plugin validate` reads the matcher statically and printed `tool=?` for a concatenated const, which would fail AC1's hooks-line check.
- Each `$.session` read is wrapped in `named(method, promise)`, and the handler catches the first rejection and returns `{ deny: <message> }` itself - `index.ts:named` and the `try` in the handler - so the deny names the method and the answer is all-or-nothing. The guard `.catch` stays for anything unforeseen and prefixes `self: `.
- `stripUserinfo` strips userinfo from any `scheme://user[:pass]@` URL (so `ssh://git@host/x` loses `git@` too) and leaves scp-style `git@host:x` alone - `index.ts:stripUserinfo` - the URL form is where a token lives; scp-style has no password slot.
- Optional fields (`tokens`, `percent`, `costUsd`, `agentId`) are omitted, never null or zero - `index.ts` - the doc's Data Model marks them optional, and a zero reads as a true figure.
- Kit test 2 compares to the constant the test's `session.id` hook returns: the kit's `$` has no `$.session.id()` of its own (`$.session.id is not a function`), so "equal to `$.session.id()`" is asserted against what the plugin's `$.session.id()` was answered.

### Deviations
- Doc says the hook re-checks `breakdown` because core does not enforce the schema (Phase 0 (g)). The kit DOES enforce it (host check: `takes breakdown "summary" or "full" (got bogus)`), so a test asserting only "denied" passes with the hook check removed. Test `denies an unknown breakdown value` therefore asserts the hook's exact wording. Same effect, correct seam.
- Likewise the kit prefixes a rejected `$.session` call with `$.session.usage:` itself, so test `denies, naming the method` asserts the exact `usage: self: $.session.usage: forced usage` / `id: self: $.session.id: forced id`; the leading `usage:`/`id:` is what `named` adds.
- Test hooks cannot `throw` to simulate a rejection (the kit skips a throwing hook and reports "no implementation"); they return `{ deny }`, which the plugin's `$` sees as a rejection.

### Tradeoffs
- Return the deny from the handler vs. let the `.catch` produce it - handler, so the message reads `<method>: <message>` as the doc's API Design says, not `self: <method>: ...`.
- Strip all URL userinfo vs. only password/token-looking userinfo - all; simpler and never prints a credential.

### Open questions
- None.

### Mutation proof (each test broken once against the code)
Each named test fails alone or with others when its guarded line is broken, and the suite is back to 10 pass after restore:
1. register: `isDeferred: false` -> `true`: test 1 fails.
2. sessionId: `sessionId: 'x'`: test 2 fails.
3. omits: breakdown block made unconditional: test 3 fails (plus 4 others).
4. summary: gridRows kept: test 4 fails.
5. unknown value: hook check disabled: first attempt PASSED (kit's host check denied it); test strengthened to the hook's exact wording, then fails as it should.
6. userinfo: remote passed through: test 6 fails.
7. method named: `named()` removed: first attempt PASSED (kit prefixed the method); test strengthened to the exact string, then fails.
8. not returned: returns a result instead of deny: test 8 fails.
9. repo null: `{ root: '', remote: null }` instead of null: test 9 fails.
10. ISO: `String(startedAt)`: test 10 fails.

### Acceptance
AC1-AC4 observed values are recorded under each AC in the design doc. `otto ci` rc=0, `rg -c 'skills/self' .otto.yml` = 4. Nothing left running.

## Implementation audit fold (round 1, Mode 2)

Synthesis: `~/.cache/review-panel/runs/mWGXuphR/synthesis.md`. 0 must-fix, 3 cheap wins, 1 marked defer.

### Design decisions
- Unknown input keys accepted, recorded in the doc's Resolved Decisions with the reason (an engine-key allowlist breaks on the engine's next key).
- Deny text kept as the engine words the rejection, documented in API Design rather than stripped in `named()` (`index.ts:named`): stripping parses engine wording.

### Deviations
- Supersedes Phase 1 Deviations bullet 1: the `takes breakdown "summary" or "full"` text is `$.session.usage`'s own argument validation, present in the live engine too, not a kit-only schema check. Live core still does not enforce the tool's input schema (Phase 0 (g)). Test 5 stands: it asserts the hook's wording and that `usage` was never asked.
- Supersedes Phase 1 Deviations bullet 2: the inner `<plugin>: $.session.<method>:` prefix comes from the engine, live and in the kit, not from the kit alone.
- Tool description (`index.ts:DESCRIPTION`) gains the costUsd lag: the calling response is priced only at its `message_delta` stop, after the tool runs (audit probe: first call 0, second call 0.005277, run total 0.006396).

### Tradeoffs
None.

### Open questions
None.

## Unknown input keys denied (Scott: "fold everything in")

### Design decisions
- Supersedes the audit-fold decision above: unknown input keys deny (`index.ts:ENGINE_KEYS`, `INPUT_KEYS`). Engine keys taken from the 2.1.302 types: `ToolCallReserved` (`tool`, `tool_use_id`, `consent`), `AgentLoop` (`agentId`), `ToolRequestMeta` (`requestMeta`). The deny names the key, so a key a later engine adds is diagnosable from the first failed call.
- New kit test 11, `denies an unknown input key`, asserting the hook's wording and that `usage` was never asked.

### Deviations
None.

### Tradeoffs
- Allowlist from the types vs. accept unknown keys: allowlist, Scott's ruling; the cost is a hard failure on the next engine key, mitigated by the named-key message.

### Open questions
None.

## Rename: `self` -> `session` (Scott)

### Design decisions
- Plugin `session`, tool `info` (`mcp__session__info`), folder `HOME/.claude/skills/session/` (git mv). The guard `.catch` prefix and the engine's deny prefix both follow the plugin name, so test 7 now expects `usage: session: $.session.usage: forced usage`.
- `.otto.yml` count pattern anchored: `skills/session(/|$)`, because `skills/session-recall/SKILL.md` also matches the bare prefix (5 lines vs 4).

### Deviations
None.

### Tradeoffs
- Kept the design doc and notes filenames (`2026-10-16-self-session-tool*`): they are point-in-time records; the doc carries a rename banner.

### Open questions
None.
