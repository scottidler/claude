# voice-guard mod: implementation notes

## Phase 0: Prove the harness assumptions

Method: a throwaway mod (`voicespike`, 5 hook surfaces, plus a deliberately broken second one) lived in the session scratchpad, outside the repo. Each probe ran as `claude -p ... --plugin-dir <spike> --settings <spike settings> --debug-file <file>` on Claude Code 2.1.327, with this machine's managed settings (so `cc-plugin-sec-default` was seated). The `--settings` file added a settings-tier `PreToolUse` and `Stop` hook beneath the mod, as stand-ins for `git-release-guard.sh` and `prose.sh`. The debug log reports the spike as `hooks module voicespike@inline loaded (worker, environment 2, tier user)`, the same tier as `rails@skills-dir` and `session@skills-dir` (`tier user`), so the skips below apply to a skills-folder mod too. The spike script is not committed. API reference used: the bundled `plugin-authoring` skill for 2.1.327 (`reference.md`, `types/claude-code.d.ts`, under `/media/saidler/4tb/claude-tmp/claude-1000/bundled-skills/2.1.327/`).

### Design decisions

- Phase 0 lands no code in the repo; only this notes file is committed.
- Probes were driven by markers in the tool input (`SPIKE_MODDENY`, `SPIKE_THROW`, `SPIKE_CHAIN`, `SPIKE_HOOKDENY`) and env vars (`SPIKE_MODE`) read through `$.env.get`, so one spike answered every question.
- Marker strings in subagent and MCP probes were built by the model from two halves (`'SPIKE_' + 'MODDENY'`). The first attempt put the marker in the `Agent` tool's own `prompt`, and the mod denied the `Agent` call itself instead of the subagent's `Write`.
- Read-only Slack tool (`mcp__slack__search_messages`) used for the MCP probe, so a failed deny could not post anything.

### Deviations

- Q1, Q2a, Q4a (the Stop half) and Q5 could not be observed as the doc phrased them: the mod's `classic.Stop` and `classic.SubagentStop` never run, so `stop_hook_active` on the mod's retry, the mod's `{ block }` and the cap, and `$.session.messages()` at Stop have no mod-side observation. They are recorded as NEGATIVE with the reason. Q5's cap behavior was measured on a settings-tier hook instead (baseline only).
- The doc's matcher list names `MultiEdit`. Claude Code 2.1.327 offers no `MultiEdit` tool (the model reported none, and the debug log of the keys run has no `MultiEdit` string). Its `e` keys cannot be printed. Phases 1 and 2 should drop the `MultiEdit.edits[].new_string` selector or keep it as an inert guard.
- Q4a's `$.session.messages()` check ran at `turn.complete`, the only Stop-adjacent mod surface that runs, not at `classic.Stop`.
- `claude plugin validate` (non-strict) refuses a mod that passes `$` to a helper declared inside `register` (`$ is passed to "say", which is not a function declared at the top of this file`). Helpers that take `$` must be top-level function declarations. The Phase 1 layout must respect this.

### Tradeoffs

- One combined spike over one spike per question: faster, and the debug lines are directly comparable. Cost: a more elaborate mod.
- `--settings` stand-in hooks over the live `prose.sh` and `git-release-guard.sh`: no side effects on `hindsight` or the prose decision log. Cost: the real scripts were not exercised here (Phase 2 and 3 tests do that).

### Open questions

- Q1 is NEGATIVE. The continuation table drops Phases 3 and 4 and leaves both `prose.sh` entries. Confirm that is the path, or whether to ask the owner of `cc-plugin-sec-default` for a managed-settings allowance for user-tier `classic.*` before the doc goes on. Nothing in this repo can change it.
- Q4a's row says "Phase 3 ships its rules in shadow only"; Q1's row says Phase 3 is dropped. Both rows fire, and the stricter one (Q1, dropped) governs. The continuation table should say so.
- The Summary says the mod carries "the mechanical voice rules now split across `emdash.sh` and `prose.sh`". After Q1 that holds for `emdash.sh` only. The Summary, Goals and Phase 5 (new warn rules would run at `turn.complete`, since `classic.Stop` is unreachable) need the author's revision.
- Every deny check ran under `claude -p`. No interactive run was made (no TTY here). The engine path is the same `tool.call` hook, but the "in a live session" criteria in Phases 2 and 7 stay with the operator.

### Q1: user-tier `classic.Stop` `{ block }` with `cc-plugin-sec-default` seated

The mod's `classic.Stop` handler never ran. The engine skipped it before it started, and the settings-tier `Stop` hook beneath ran instead. Zero `classic.Stop FIRED` lines in all 11 debug logs.

Verbatim debug lines (`q1.debug`, mode `blockonce`):

```
2026-11-18T23:23:42.316Z [DEBUG] hooks module voicespike@inline loaded (worker, environment 2, tier user); events: session.start,prompt.compose,tool.call,classic.Stop,classic.SubagentStop
2026-11-18T23:23:47.029Z [DEBUG] voicespike: classic.Stop bypassed by cc-plugin-sec-default (tier user); beneath runs
2026-11-18T23:23:47.029Z [DEBUG] [voicespike] $.ui.log: its classic.Stop hook was skipped. "cc-plugin-sec-default" runs first and sent the event on past it.
```

stderr under `-p` carried the same notice: `voicespike: its classic.Stop hook was skipped. "cc-plugin-sec-default" runs first and sent the event on past it.` The model's answer was a single `OK` with no re-answer, so there was no retry and no mod-side `stop_hook_active`. (For the settings-tier hook the retry did carry `stop_hook_active=true`: see Q5.)

Result: NEGATIVE -> Q1 (user-tier `classic.Stop` block does not run: Phases 3 and 4 dropped; both `prose.sh` entries stay; the mod carries `emdash` and the new bans only)

### Q2a: `classic.SubagentStop` fires for an Agent-dispatched subagent

The subagent ran (its `Write` reached the mod's `tool.call` with an `agentId`), and the engine raised `SubagentStop`. The mod's handler was bypassed. The settings-tier `SubagentStop` beneath (the live `prose.sh`, wired in `settings.json`) ran.

```
2026-11-18T23:25:13.302Z [DEBUG] voicespike: classic.SubagentStop bypassed by cc-plugin-sec-default (tier user); beneath runs
2026-11-18T23:25:13.360Z [DEBUG] Hooks: SubagentStop [~/.claude/hooks/prose.sh] finished with status 0 (57ms)
```

Result: NEGATIVE -> Q2a (`classic.SubagentStop` does not fire for a user-tier mod: Phase 3 ports Stop only, and Stop is itself gone under Q1; the `SubagentStop` entry stays)

### Q2b: `tool.call` deny in a subagent, under `claude -p`, and on an `mcp__slack__*` call; `e` keys

All four contexts denied. Every probe ran under `claude -p`, so `-p` is covered by all of them.

Main loop, `-p`, Write and Bash (`q2b.debug`):

```
2026-11-18T23:24:48.683Z [DEBUG] [voicespike] $.ui.log (to debug): SPIKE tool.call mod DENY tool=Write agentId=undefined
2026-11-18T23:24:48.683Z ... tool.call Write toolu_01PTurCFyvHWa4tRRz4BRLWq: resolved by a hooks module (deny of 14 chars; reason left out because it can quote tool input)
2026-11-18T23:24:53.615Z [DEBUG] [voicespike] $.ui.log (to debug): SPIKE tool.call mod DENY tool=Bash agentId=undefined
```

The model saw `<tool_use_error>SPIKE mod deny</tool_use_error>` for both, and no file was written.

Subagent (`q2b2.debug`): `agentId` is set and the deny lands.

```
2026-11-18T23:25:11.231Z [DEBUG] [voicespike] $.ui.log (to debug): SPIKE tool.call tool=Write agentId=a049054c33a8436c1 keys=file_path,content,tool,tool_use_id,agentId
2026-11-18T23:25:11.231Z [DEBUG] [voicespike] $.ui.log (to debug): SPIKE tool.call mod DENY tool=Write agentId=a049054c33a8436c1
2026-11-18T23:25:11.227Z [DEBUG] tool.call Write toolu_01D6iNHX7DefZQWYCJLAV4o7: resolved by a hooks module (deny of 14 chars; reason left out because it can quote tool input)
```

MCP, `mcp__slack__search_messages`, `e` is `{query, tool, tool_use_id}` (`q2mcp.debug`):

```
2026-11-18T23:25:30.100Z [DEBUG] [voicespike] $.ui.log (to debug): SPIKE tool.call tool=mcp__slack__search_messages agentId=undefined keys=query,tool,tool_use_id
2026-11-18T23:25:30.100Z [DEBUG] [voicespike] $.ui.log (to debug): SPIKE tool.call mod DENY tool=mcp__slack__search_messages agentId=undefined
```

A mod deny ends the chain: the settings-tier `PreToolUse` hook did not run for the denied calls (the hook log has no `pre ran` row for them). That confirms the chain invariant's bypass risk.

`e` keys per tool (`q2keys.debug`; `tool` and `tool_use_id` on all, `agentId` added in a subagent):

```
Write        file_path,content,tool,tool_use_id
Edit         replace_all,file_path,old_string,new_string,tool,tool_use_id
NotebookEdit notebook_path,cell_id,new_source,tool,tool_use_id
Bash         command,description,tool,tool_use_id
Agent        description,subagent_type,prompt,run_in_background,tool,tool_use_id
mcp__slack__search_messages  query,tool,tool_use_id
```

MultiEdit: no such tool in 2.1.327 (see Deviations), so no keys to print. NotebookEdit's field is `new_source`, as the doc's map says.

Result: VERIFIED

### Q3: throwing hook skipped; broken module load failure on stderr under `-p`

A throwing `tool.call` hook is skipped, the call went on, and the settings hook beneath still ran:

```
2026-11-18T23:25:46.561Z [ERROR] voicespike: tool.call hook skipped: threw Error: spike deliberate throw
```

stderr: `voicespike: tool.call hook skipped: threw Error: spike deliberate throw`. The Bash `echo SPIKE_THROW` ran and printed `SPIKE_THROW`.

A module with a parse error prints its load failure once on stderr under `-p`, and the session goes on (`rc=0`, reply `OK`):

```
brokenspike: hooks module did not load: .../spike/broken/hooks/index.ts does not parse: Expected ")" but found end of file (line 3, column 61)
2026-11-18T23:25:48.917Z [ERROR] hooks module brokenspike@inline failed to load: brokenspike: .../hooks/index.ts does not parse: Expected ")" but found end of file (line 3, column 61)
```

This matches `reference.md:128`. Caveat for Phase 6: this stderr line is for a `--plugin-dir` mod. A skills-dir mod that fails to load was not exercised.

Result: VERIFIED

### Q4a: `prompt.compose` skipped; prompt visible at Stop; `$.http.fetch` + Jev, else `$.model.classify`

Three findings.

1. `prompt.compose` is skipped (reply-guard reproduced), on every run:

```
2026-11-18T23:23:44.859Z [DEBUG] voicespike: prompt.compose bypassed by cc-plugin-sec-default (tier user); beneath runs
```

2. The prompt at Stop could not be observed: `classic.Stop` never runs for the mod (Q1). At `turn.complete` (which does run) `$.session.messages()` shows the current prompt:

```
SPIKE turn.complete FIRED mode=q4a keys=answer,durationMs,isAborted,turnId,reason,usage
SPIKE Q4a session.messages count=2 last-user="[{\"role\":\"user\",\"text\":\"please run the word count of hello world in your head and reply with just the number\",\"toolUses\":[]}]"
```

3. The judge works from a mod (at `turn.complete`):

```
SPIKE Q4a ESCOTE_TYPESAFE_API_KEY via $.env.get present=true
SPIKE Q4a http.fetch Jev status=200 ok=true ms=82 body={"model":"jev-1.13.0","answers":{"instruction":{"type":"noul","noul":0.98}},"usage":{...}}
SPIKE Q4a model.classify label=instruction
```

`$.env.get` reads `ESCOTE_TYPESAFE_API_KEY`, `$.http.fetch` reaches `https://api.typesafe.ai/v1/systemone` with the body shape `prose.sh` sends (status 200, 82 ms), and `$.model.classify` returns a label. The judge exists. The blocking surface for the offer rule does not: a mod cannot block at Stop, so the "no prompt at Stop" row fires.

Result: NEGATIVE -> Q4a (no prompt at Stop: Phase 4 dropped; the offer rule stays in `prose.sh`, so both `prose.sh` entries stay and Phase 3 ships its rules in shadow only, which Q1 already drops)

### Q4b: `$.fs` writes under `~/.local/state`

`$.fs.write` and `$.fs.read` of `/home/saidler/.local/state/voice-spike/heartbeat.<sessionId>` worked from `session.start` in every run, `-p` included. The write created the directory. The spike's files were removed with `rkvr rmrf` afterward.

```
2026-11-18T23:23:42.704Z [DEBUG] $.fs.write (voicespike): /home/saidler/.local/state/voice-spike/heartbeat.10146c88-1893-46e0-a70a-1237f5e8a73a (17 bytes)
2026-11-18T23:23:42.717Z [DEBUG] [voicespike] $.ui.log (to debug): SPIKE Q4b fs.write ok under ~/.local/state, read back: "hb 1795044222648\n"
```

`session.start` fired once per process with `e` keys `cwd,surface,isInteractive`.

Result: VERIFIED

### Q5: a mod-returned `{ block }` counts toward `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (8)

Not observable: the mod's `classic.Stop` never runs (Q1), so a mod `{ block }` cannot be returned. Baseline instead: `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=2`, the mod set to block up to 12 times, and a settings-tier `Stop` hook that always blocks. The settings hook ran 3 times (the initial Stop plus 2 re-prompts, then the engine stopped). `stop_hook_active` was false, then true, then true. The mod's handler ran 0 times.

```
stop ran 1795044412 active=false
stop ran 1795044414 active=true
stop ran 1795044415 active=true
```

Final stdout was empty. The cap is real and counts settings-hook blocks. Whether a mod block would count is moot while Phase 3 is dropped. If Q1 flips, re-run this probe first.

Result: NEGATIVE -> Q5 (a mod block cannot be observed; recorded only: Phase 3 is dropped by Q1, so its added criterion has no home unless Q1 flips)

### Q6: what `await next(e)` resolves to at `tool.call` and `classic.Stop` when a settings hook beneath denies or blocks

At `tool.call` the chain beneath is exposed in-band. A settings-tier `PreToolUse` deny comes back through `next(e)` as an errored result with the hook's reason as `text`, prefixed `PreToolUse:Bash hook error: `. It is not a `{ deny }` value (matches `claude-code.d.ts:19276-19278`):

```
2026-11-18T23:26:29.074Z [DEBUG] [voicespike] $.ui.log (to debug): SPIKE Q6 tool.call next(e) resolved: {"ref":1,"result":"Error: PreToolUse:Bash hook error: SPIKE settings hook deny reason","text":"PreToolUse:Bash hook error: SPIKE settings hook deny reason","isError":true}
```

The clean control (no deny) resolves to a normal result:

```
2026-11-18T23:26:37.769Z [DEBUG] [voicespike] $.ui.log (to debug): SPIKE Q6 tool.call next(e) resolved: {"ref":1,"result":{"stdout":"SPIKE_CHAIN clean","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false},"text":"SPIKE_CHAIN clean","isReadOnly":true}
```

The `chainResult` mapping: `isError === true` with `text` starting `PreToolUse:<tool> hook error:` maps to `deny`. The match key is that prefix, since a tool that merely errors is also `isError`, so Phase 2 matches the prefix and not `isError` alone. The mod returned that `r` unchanged and the model saw the hook's reason, as the invariant requires.

At `classic.Stop` the question is unobservable: the mod's handler never runs (Q1), so no `next(e)` result exists to inspect. No Stop `{ block }` shape was recorded.

Result: VERIFIED

## Phase 1: Scaffold and the em-dash matcher

### Design decisions

- Layout copied from `rails`: `HOME/.claude/skills/voice-guard/` with `.claude-plugin/plugin.json`, `hooks/hooks.json`, `hooks/index.ts`, `hooks/rules.ts`, `spec/rules.spec.ts`, `tests/voice-guard.test.ts`, `types/index.d.ts`.
- `hooks/rules.ts`: pure functions only (`isAllowlistedPath`, `stripHeredocs`, `hasOutwardStage`, `judgeToolCall`, `emdashReason`), no `$`, no I/O. `judgeToolCall(tool, input)` takes the call's fields and returns a `Violation | null`, so Phase 2 only has to hand it `e` and decide what to do with the verdict.
- `hooks/index.ts`: a pass-through (`on('tool.call', ...)` returns `next(e)`), since Phase 2 owns the shadow wiring. It does not import `rules.ts` yet.
- The heredoc stripper is a line-by-line port of the awk in `emdash.sh` (queue of pending delimiters, indented terminator for the dash form, herestrings neutralized), and the outward-stage regex is the same alternation with the POSIX alnum class spelled `[A-Za-z0-9]`.
- `types/index.d.ts` holds `Tier` and `Violation` (Data Model); `plugin.json` declares only `enforce` (boolean, default false) in `userConfig`. `deny_outward` and `warn_structural` arrive with the phases that use them.
- The U+2014 literal must never appear in the source: the character is built from its JS escape. The first write through the Bash tool put a literal into `rules.ts` and the test file (the tool layer expands the escape in command text); both were converted back with `perl`, and a grep for the character over the folder is empty. Phase 2 and later should write these files with the Write or Edit tools, or re-run that grep after any heredoc.

### Deviations

- `MultiEdit.edits[].new_string` dropped from the field map (Phase 0: no `MultiEdit` tool in 2.1.327). The two `emdash-test.sh` MultiEdit cases (12, 13) are kept as spec cases that assert `MultiEdit` is not a scanned tool, so case 12 flips from deny to allow, named "allow (was deny)".
- Cases 30 and 31 (malformed and empty payload) have no payload to parse in the mod, which receives fields. They are ported as calls with no usable fields (`{ content: 42 }`, `{ command: [...] }`, `{}`, tool name `''`) that must pass.
- The 31 cases live in `spec/` (bun). `tests/` holds only two `claude plugin test` pass-through cases, because Phase 1 has no shadow logic to test through the engine; Phase 2 grows it.
- `userConfig` carries `enforce` only, where the Data Model lists three options.

### Tradeoffs

- `judgeToolCall(tool, input)` over a function that takes the engine's event type: keeps `rules.ts` free of the `claude-code` types and testable under bun without the engine.
- Matching `emdash.sh` exactly (stage split on `;` even inside quotes, `*.golden` suffix, `tests/fixtures/` prefix or infix) over fixing its quirks: Phase 2's parity criterion compares the two, so any improvement waits until after parity.

### Open questions

- None.

## Phase 2: Shadow em-dash at `tool.call`

### Design decisions

- Shadow wiring: `HOME/.claude/skills/voice-guard/hooks/index.ts:register`. One `tool.call` hook: a tool no `emdash.sh` matcher covers returns `next(e)` unjudged and unlogged; a covered one is judged, then `const r = await next(e)`, a row is queued, and `r` is returned untouched. The enforce branch (`{ deny: emdashReason(v) }`, row `chainResult: null`) exists and is tested, but `enforce` stays default false in `plugin.json`.
- Matcher set: `rules.ts:surfaceOf` mirrors the four `emdash.sh` entries in `settings.json` (`Write|Edit|MultiEdit|NotebookEdit`, `Bash`, the outward Slack/Atlassian/Marquee list, `mcp__multi-account-github__create_pr`). The mod sees every call, so judging one the hook never sees (a read-only `mcp__slack__search_messages`) would log a mismatch the hook could not agree with. The MCP regex is anchored.
- `chainResult`: `rules.ts:chainVerdict`, pure. `{ deny }` from a plugin beneath is `deny`; an errored result whose `text` opens `PreToolUse:<tool> hook error: ` is `deny` (Phase 0 Q6); anything else, a tool that merely errored included, is `allow`.
- Log: `~/.local/state/voice-guard/<sessionId>.<copyTag>.jsonl`, rails' scheme. Rows are kept in memory and the copy's own file rewritten per row through one serialized promise chain (`index.ts:record`), never awaited by the hook and never rejecting; a write failure is noted once in the debug log. `ROW_CAP` 2000; past it the oldest go and the file opens with `{"event":"dropped","count":N}`. A new session id (a `/clear`) starts a new file. Row: `ts, session, event, surface, tool, rule, label, modVerdict, chainResult, mode, agentId`, plus `error` on a catch row. No tool input text is logged.
- `.catch` fails open: `next` is replay-safe there, so it returns the chain's settled result (or runs the chain once if the hook had not), and queues a row with `rule: "catch"`, `modVerdict: null`, the chain's verdict, and `error` (`throw: <message>` or `timeout`).
- One case table, `spec/emdash-cases.ts`, holds the 31 `emdash-test.sh` cases as data. `spec/parity.spec.ts` (bun) runs the real `emdash.sh` on each payload and the mod's judgment (`surfaceOf`, then `judgeToolCall`) on each call. `tests/voice-guard.test.ts` (`claude plugin test`) imports the same table and drives each case through the engine.
- The U+2014 is built as `String.fromCharCode(0x2014)` in the new files. The Write tool, like the Bash tool, expands a typed JS unicode escape for the character (backslash, u, 2014) into the literal: the first Write of `emdash-cases.ts` was denied by `emdash.sh` for exactly that.

### Deviations

- `MultiEdit` restored in `rules.ts:writtenField` as an inert selector (`edits[].new_string`), reversing Phase 1's drop. The settings matcher beneath still names `MultiEdit`, and the criterion asks for the same verdict on every `emdash-test.sh` case; with the selector dropped, case 12 differed by design. Spec case 12 is flipped back by name ("12 deny (restored in Phase 2, inert selector)") and a 12b case pins that `old_string` is not scanned.
- The kit hands a test's `classic.PreToolUse` hook the call's own fields (`tool`, `command`), not `tool_name`/`tool_input`, and resolves a deny to the mod as `{"ref":1,"result":"Error: <reason>","text":"<reason>","isError":true}`, with no `PreToolUse:<tool> hook error: ` prefix. The live engine adds the prefix (Q6, and the live check below). The test's stand-in therefore states the prefix itself (`settingsDenyText`), documented in the test; the mapping keys on the live shape, not the kit's.
- The kit runs no process, so `git-release-guard.sh` and `emdash.sh` are stand-ins in `claude plugin test`: the release stand-in returns the script's verbatim deny text for `git push --tags` (captured by piping that payload through the real script), and the `emdash.sh` stand-in denies what `emdash-test.sh` expects denied. The real `emdash.sh` is exercised in `spec/parity.spec.ts` through `Bun.spawnSync`.
- Row fields: `prose.sh`'s offer fields (`source`, `p`, `reason`, `ms`, `threshold`, `prompt`, `final`) have no meaning at `tool.call` and Phase 4 is dropped (Q1, Q4a), so the row carries `ts`, `session`, `event` from `prose.sh` plus the doc's five and `tool`, `label`, `agentId`.
- The live check ran under `claude -p --plugin-dir`, not an interactive session (no TTY). With `--plugin-dir` the skills-dir copy is not loaded (`Not loaded: the name "voice-guard" is already taken by a session-only plugin`), so one copy judged.
- `.otto.yml` is untouched (Phase 6 owns it), so `otto ci` does not yet run the mod's three commands; they were run by hand.

### Tradeoffs

- One `tool.call` hook with a pure `surfaceOf` filter over four `on('tool.call', { tool })` registrations: one place mirrors `settings.json`, and bun tests it without the engine.
- Fire-and-forget row writes over awaiting each write in the hook: a hung `$.fs.write` cannot stall a tool call or push the hook into its `.catch`. Cost: the kit tests poll for the row (`rowsSettled`).
- A real-script parity spec under bun over restating the 31 expected verdicts only: if `emdash.sh` changes, the spec fails until the mod follows. Cost: the spec depends on `bash` and `jq` and on `emdash.sh` staying at `HOME/.claude/hooks/` (Phase 7 keeps it in the repo, unwired).
- The catch test induces a real throw (an MCP input nested 27,000 levels deep overflows `stringsOf`'s recursion; the kit refuses past 28,000) over a test-only throw switch in production code.

### Open questions

- `chainResult: deny` does not say which layer denied. In the live probe the first Write was denied by `rails`' rule gate (`rails (user) answered tool.call without next()`, `voice.md` gate) and logged `chainResult: deny` with `emdash.sh` never running. For the Phase 7 parity matrix that row would count as agreement. Should the row carry the denier (`settings` from the prefix, `plugin` from `{ deny }`) before Phase 7, or should Phase 7 discard rows whose deny came back as `{ deny }`?
- Matcher semantics: the mod anchors the MCP list (`^(...)$`). If Claude Code tests a settings matcher unanchored, a future tool whose name merely contains a listed name would reach `emdash.sh` but not the mod. No such tool exists today.

### Success criteria

1. PASS. Every `emdash-test.sh` case yields the same verdict in the mod. `spec/parity.spec.ts` runs the real `emdash.sh` and the mod's judgment on all 31 cases (`bun test`: `84 pass, 0 fail` across the two spec files); `tests/voice-guard.test.ts` drives the same 31 through the engine and checks `{ modVerdict, chainResult }` per case (`claude plugin test`: `11 pass, 0 fail`).
2. PASS. `claude plugin test` case "a settings hook beneath (git-release-guard.sh) still denies git push --tags through the mod": the call comes back denied with the script's text, the tool never runs, and the row reads `modVerdict: allow, chainResult: deny, mode: shadow`. The enforce-mode case shows the same deny still reaches a clean-by-the-mod call.
3. PASS, headless. `claude -p --plugin-dir HOME/.claude/skills/voice-guard --allowedTools Write` from a scratch dir, prompted to Write `alpha<U+2014>beta` to `probe.md`. The second Write reached `emdash.sh` (the first was stopped by `rails`' gate, see Open questions). Debug log (the literal character shown as `[U+2014]`):

```
2026-11-18T23:47:43.456Z [DEBUG] Hooks: PreToolUse:Write [~/.claude/hooks/emdash.sh] finished with status 0 (18ms)
2026-11-18T23:47:43.459Z [DEBUG] Hook PreToolUse (~/.claude/hooks/emdash.sh) returned permissionDecision: deny (reason: em-dash (U+2014) in Write content; recast with a colon, parens, comma, or a split sentence (rules/safety.md). The offending text: "alpha[U+2014]beta")
```

The model saw `PreToolUse:Write hook error: em-dash (U+2014) in Write content; ...`. Mod log row (`~/.local/state/voice-guard/d4413dc7-aa3b-4f92-830c-d371288fd9eb.1795045654308-zv44ix.jsonl`, second row):

```
{"ts":"2026-11-18T23:47:43.476Z","session":"d4413dc7-aa3b-4f92-830c-d371288fd9eb","event":"tool.call","surface":"write","tool":"Write","rule":"emdash","label":"Write content","modVerdict":"deny","mode":"shadow","agentId":null,"chainResult":"deny"}
```

No `probe.md` was written. The probe's log directory and scratch dir were removed with `rkvr rmrf`.
