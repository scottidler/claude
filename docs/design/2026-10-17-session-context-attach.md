# Design Document: session context attach (Jev-gated)

**Author:** Scott Idler (drafted with Claude)
**Date:** 2026-10-17
**Status:** In Review
**Review Passes Completed:** 5/5

## Summary

The `session` mod (`HOME/.claude/skills/session/`) answers `mcp__session__info` when an agent asks. An agent that does not think to ask gets nothing: on 2026-10-17 an agent ran `wl-copy` on ripr while Scott sat on lappy over SSH, and the token never reached his clipboard. This doc makes the mod push the right facts into each prompt's hidden context, judged per prompt by TypeSafe Jev, with a deterministic floor for `seat` and a rails guard that denies desktop-acting Bash commands when the prompt came over SSH.

## Problem Statement

### Background

- `mcp__session__info` ships: id, cwd, root, repo, context fill, cost, turns, startedAt, `seat` (`docs/design/2026-10-16-self-session-tool.md`, Addendum: seat; commit `1ca5535`).
- `seat.promptTypedOnHost` comes from the local herdr client's terminal atime at `prompt.submit`, and `remotePeers` from logind (`hooks/index.ts` `SEAT_PROBE`).
- Measured cost of attaching facts to a prompt (`claude -p --output-format json`, total input tokens vs a bare prompt, 2026-10-17):
  - full `mcp__session__info` JSON: +309 tokens on Opus 5.5 and Sonnet 5.5
  - `seat` alone: +83
  - each copy stays in history, so 100 prompts carry ~31k (full) or ~8k (seat)
- Jev (TypeSafe System One, field guide: https://marquee.internal.tatari.dev/p/~scott-idler/typesafe-jev/): typed `noul` (yes/no probability) answers, many questions per call in parallel, 70-500 ms vendor-stated, $0.042 per M input tokens.
- Vendor review closed: SEC-3102 Done 2026-10-15, superseded by SEC-3117. SOC 2 Type II, US-only processing, no training on our data, ZDR enabled 2026-10-09 (https://tatari.atlassian.net/browse/SEC-3102?focusedCommentId=399378).

### Problem

- The facts exist only on demand, and the agent decides whether to demand them. In the wl-copy case the agent never asked.
- Attaching everything to every prompt costs 309 tokens a prompt, most of it unused.
- Scott asked (2026-10-17): "how many tokens would be consumed by placing session data at the beginning of every prompt?", then "can we utilize jev to make a good judgement call when to include what?", then ran `/create-design-doc`.

### Goals

- Per prompt, attach only the facts that prompt needs, as hidden context (`PromptSubmitInput.context`).
- Jev makes the per-fact call. A Jev failure degrades to the deterministic floor, never blocks or delays a prompt past a cap.
- `seat` reaches the agent without a Jev call on the first prompt and whenever it changes.
- A Bash command that acts on ripr's desktop (clipboard, browser, notifications) is denied when the prompt did not come from ripr's keyboard, with a deny text that says why and what to do.
- Thresholds come from a labeled set Scott labeled, not from a guess.

### Non-Goals

- Changing `prose.sh` (it pins `jev-1.13.0` and skips the served-model check; noted, not fixed here).
- An OSC 52 clipboard path for SSH sessions (the deny text points to it; building it is a separate ask).
- Attaching facts to subagent prompts. Subagents inherit nothing new; the rails guard still covers their Bash calls through `$.state`.
- Reworking `mcp__session__info`: the tool stays as is.

## Proposed Solution

### Overview

```
prompt.submit (session mod)
  ├─ seat probe (sh, existing)          ─┐ in parallel, before next(e)
  └─ Jev call (4 nouls, $.http.fetch)   ─┘ raced against jev_timeout_ms
        │
        ├─ decide: seat? identity? location? usage?
        ├─ $.state.set(session.seat)        -> read by rails
        ├─ context += "session: {...}"      (one entry, only the chosen facts)
        └─ decisions.jsonl += one record
tool.call Bash (rails mod)
  └─ desktop command + session.seat.promptTypedOnHost === false -> deny
```

### Architecture

- **session mod**, `hooks/index.ts`:
  - `prompt.submit` runs the seat probe and the Jev call concurrently, then attaches one context entry and calls `next`.
  - Seat moves from the module `let prompt` to `$.state` key `session.seat`, so a hot reload keeps it and rails can read it.
  - New `types/index.d.ts` declares `PluginState['session']`.
- **rails mod**, `hooks/index.ts`: a new `tool.call` Bash rule `desktop_over_ssh`, same shape as the existing per-rule hooks (`rails/hooks/index.ts:1857-1899`): userConfig toggle, cheap interest regex, then `heads()` / `classifyStages` wrapper recursion, then a deny.
- **rails depends on session** (`dependencies: ["session"]` in rails `plugin.json`), so session's contract is laid into rails' types.

### Data Model

`PluginState['session']`:

```ts
seat: {
    host: string
    promptTypedOnHost: boolean | null
    promptAt: string | null
    origin: string            // PromptOrigin kind of the prompt that set it
    remotePeers: { ip: string; host: string | null }[]
}
attached: { seat: string | null }   // seatKey of the last seat attached; cleared on session.compact
lastAnswer: string | null           // tail (300 chars) of the last main-loop turn.complete answer
jev: { failures: number; offUntil: number | null }  // breaker: consecutive failures, retry time (ms)
```

- `seatKey(seat)` = JSON of `{ host, promptTypedOnHost, origin, remotePeers sorted by ip }`. `promptAt` changes every prompt, so it is left out of the change check (round 1 must-fix 1).
- Seat write ordering: each human prompt writes with its own `promptAt`; a write whose `promptAt` is older than the stored one is dropped. The latest submitted human prompt owns the seat, including a prompt queued locally while an SSH-origin turn runs (it flips the seat for that running turn, by design).

`promptTypedOnHost` by origin (one field, one meaning: "typed at this host's keyboard"):

| `e.origin.kind` | value |
|---|---|
| `composer` | atime rule (existing): `true` in `[submit - 9 s, submit + 1 s]`, else `false` when a remote peer is attached, else `null` |
| `bridge` (Remote Control phone/web) | `false` |
| anything else (`sdk`, `task-notification`, `plugin`, ...) | no write: the seat keeps the last human prompt's value; never written reads `null` |

Only a human prompt (`composer`, `bridge`) moves the seat, so a background task notification or a plugin-raised prompt cannot flip the guard mid-conversation.

Context entry (one per prompt at most, prefixed so a transcript reader can attribute it):

```
session: {"seat":{...},"sessionId":"...","usage":{...}}
```

Fact bundles, each one Jev question:

| bundle | fields | Jev question (`noul`, with `criteria.true`) |
|---|---|---|
| `seat` | `seat` | the reply may act on the user's own screen, clipboard, browser, notifications or files on their device |
| `identity` | `sessionId`, `startedAt`, `turns` | the prompt refers to this chat session itself: its id, transcript, resume, or how long it has run |
| `location` | `cwd`, `root`, `repo` | the prompt depends on which directory, repo or branch the session is in right now |
| `usage` | `context`, `costUsd` | the prompt asks about context used, compaction, tokens or cost of this session |

Decision record (`~/.local/state/session/decisions.jsonl`, one line per Jev-eligible prompt, copying prose.sh's log fields):

```json
{"ts":"...","session":"...","origin":"composer","source":"jev|fallback","reason":null,
 "model":"jev-1.13.0","ms":69,"p":{"seat":0.12,"identity":0.92,"location":0.03,"usage":0.01},
 "attached":["identity"],"seatChanged":false,"inputTokens":286,"prompt":"<300 chars>"}
```

### API Design

session `plugin.json` userConfig (snake_case keys, rails precedent: the plugin schema rejects hyphens):

| key | type | default | effect |
|---|---|---|---|
| `jev` | boolean | `true` | off -> deterministic floor only, no request |
| `jev_model` | string | `jev-1.14.0` | model sent; served model logged |
| `jev_timeout_ms` | number | `1500` | cap on the hook's added wait: the seat probe and the Jev call run together, each raced against it |
| `threshold_seat` / `_identity` / `_location` / `_usage` | number | set in Phase 4 | attach when `noul >= threshold`; a bundle with no threshold reaching precision 0.8 gets `1.01` (never attached by Jev) |

Phase 3 adds `jev`, `jev_model`, `jev_timeout_ms`; Phase 4 adds the four thresholds.

rails `plugin.json` userConfig: `desktop_over_ssh` boolean, default `true`.

Jev request (one call, copying second-brain `distillers/src/tags.rs:691-708`):

```json
{"model":"jev-1.14.0",
 "state":"USER PROMPT:\n<prompt head>\n\nPREVIOUS ASSISTANT REPLY (tail):\n<reply tail, 300 chars>",
 "questions":{"seat":{"type":"noul","instructions":"...","criteria":{"true":"..."}}, "identity":{...}, "location":{...}, "usage":{...}}}
```

- State: the assembled string, envelope included, is clipped to 900 chars (second-brain `tags.rs:82-96`). The reply tail takes up to 300, the prompt head the rest (round 1: 600 + 300 + envelope measured 948).
- Key: `$.env.get('ESCOTE_TYPESAFE_API_KEY')`, the variable prose.sh and second-brain read. Absent -> `no-key`, no request.
- Previous assistant reply: recorded from main-loop `turn.complete` (`answer`, `agentId` absent; types `TurnCompleteFields`) into `$.state` `lastAnswer`. It survives a reload, so no transcript read is needed.
- Skip the Jev call when the prompt is a slash command (`e.command` set) or its text is empty: there is nothing to judge.
- Accept an answer only when (second-brain checks, prose lacks them):
  - `model` starts with `jev` (`tags.rs:816`), else `not-jev`
  - every asked key has a `noul` in [0,1] (`tags.rs:824-838`), else `bad-answer`
- Fallback reasons, a superset of prose.sh's: `off`, `no-key`, `breaker`, `timeout`, `http-<status>`, `bad-answer`, `not-jev`.
- Circuit breaker (shepherd `jev.py:44`): 3 consecutive failures set `jev.offUntil` = now + 10 min; prompts in that window log `breaker` with no request; the first after it retries, and a success resets `failures`. A shepherd run is short and a Claude session is long, so a session-long trip is the wrong scope.
- Degrade visibly (taste.md "fail loudly"): the trip shows `$.ui.toast("session: Jev off for 10 min after 3 failures (<reason>)")` once per trip.
- Timeout: a Jev answer that lands after the cap is discarded and touches no state.
- Seat probe: its `timeoutMs` drops from 5000 to `jev_timeout_ms`; a probe that misses it leaves the stored seat as it was.

Which prompts get what (round 1 must-fix 2):

| origin | seat write | Jev call + record | bundles attached |
|---|---|---|---|
| `composer`, `bridge` | yes | yes | seat by rule 1, others by rule 2 |
| `sdk` (`claude -p`, Agent SDK) | no | yes | `identity`, `location`, `usage` by rule 2; never `seat` |
| anything else | no | no | none |

1. `seat` attaches when `seatKey(seat)` differs from `attached.seat` (first prompt included), or when Jev's `seat` noul clears its threshold.
2. Every other bundle attaches when its noul clears its threshold. On any fallback, only rule 1's change check runs.
3. All chosen bundles go in one `session:` entry. Nothing chosen -> no entry.
4. `attached` updates only after `next(e)` resolves with the prompt entered; a dropped prompt leaves it unchanged. `session.compact` clears it, so the seat is attached again after a compaction (rails clears its ledger the same way, `rails/hooks/index.ts:1734-1739`, `:1803`).

rails deny text:

```
rails: wl-copy acts on ripr's desktop, but this prompt was not typed there (<from>); print the value for Scott to copy, or use OSC 52
```

`<from>` is `over SSH from ltl-7007.lan` (each `remotePeers` host, else its ip) or `from Remote Control` for a `bridge` seat. `ripr` is `seat.host`.

Guard rules:
- Commands: `wl-copy`, `wl-paste`, `xclip`, `xsel`, `xdg-open`, `gio open`, `notify-send`, matched on the basename of the head, so `/usr/bin/wl-copy` counts (`excludedAs` compares the bare head today, `rails/hooks/index.ts:857-861`).
- Supported forms: a plain head, a pipeline stage, `bash|sh|zsh -c '...'`, `sudo [-u USER|-g GROUP] cmd`, `env VAR=x cmd`, `xargs cmd`, and `$(cmd)` inside double quotes. `innerCommand` skips `-u` but not its value today (`:874-879`); Phase 2 makes it skip the value of sudo's option-with-argument flags (`-u -g -h -p -C -D -R -T`), which fixes the same case for rails' other rules.
- Deny only when `promptTypedOnHost === false`. `null` (no prompt yet, `sdk`, unknown) allows: the guard prevents a wrong-machine mistake, not data loss, and a `claude -p` run on ripr must not lose its clipboard.
- Subagent Bash (`agentId` set) reads the same `session.seat`, the main loop's.
- Seat unknown vs guard broken are two cases. Unknown (`null`) allows silently. Broken (the hook throws, or `session` state cannot be read) allows through `.catch(($, e, next) => next(e))` and shows `$.ui.toast("rails: desktop_over_ssh guard failed: <message>")`, so a broken guard is never silent.
- Limit, kept from the seat addendum: `promptTypedOnHost` reads `true` when a local terminal was read in the window, even with an SSH peer attached (`readSeat`, `session/hooks/index.ts:104-107`). With both attached, the keyboard that moved wins.

### Implementation Plan

#### Phase 0: Prove the mod can reach Jev and share state (done, zero repo code)

**Model:** opus
- Throwaway mods `spikea` and `spikeb` under the session scratchpad, run with `claude -p --plugin-dir` (2026-10-17).
- **Success criteria:**
  - `$.http.fetch` POST to `https://api.typesafe.ai/v1/systemone` returns 200 with a numeric noul.
    - Observed: `{"status":200,"text":"{\"model\":\"jev-1.13.0\",\"answers\":{\"needs_session_id\":{\"type\":\"noul\",\"noul\":0.92}},\"usage\":{\"input_tokens\":286,\"output_tokens\":22}}","ms":69}` (asked `jev-latest`, served `jev-1.13.0`; key present via `$.env.get`).
  - A fetch to a non-responding host does not settle by itself, so the race is required.
    - Observed: `fetch('http://10.255.255.1/')` raced against `$.clock.sleep(4000)`: `{"error":"Error: race-4s","ms":4002}`.
  - Another plugin reads `session`-style state and `origin.kind` is stamped.
    - Observed: spikeb's Bash `tool.call` read `{"value":{"typed":false},"version":1}`, written by spikea's `prompt.submit`; spikea saw `"origin":"sdk"` for a `claude -p` prompt.

#### Phase 1: Seat in `$.state`, origin folded in, seat attached on change

**Model:** sonnet
- `types/index.d.ts` with `PluginState['session']` (`seat`, `attached`); `plugin.json` `"types"`.
- Replace module `let prompt` with `$.state` `session.seat`; apply the origin table.
- Attach `session: {"seat":...}` on first prompt and on change; record `turn.complete` answers for Phase 5.
- `mcp__session__info` reads the seat from `$.state` (same JSON shape, plus `origin`) and still re-reads `remotePeers` at call time (`session/hooks/index.ts:203-204`).
- `session.compact` hook clears `attached`.
- **Success criteria:**
  - Kit tests, with the mocked clock advanced between prompts: first `composer` prompt carries exactly one `session:` context entry; an unchanged second prompt (new `promptAt`) carries none; a flipped seat carries one; an `sdk` prompt writes no seat; after `session.compact` the next prompt carries the seat again; an older `promptAt` write loses to a newer one.
  - Kit test: after `register` runs again (simulated reload), the tool reads the stored seat, not `null`.
  - Each new test fails when its guarded line is broken (mutation proof recorded in the notes).

#### Phase 2: rails `desktop_over_ssh` guard

**Model:** opus
- rails `plugin.json`: `dependencies: ["session"]`, userConfig `desktop_over_ssh`.
- New Bash rule using `heads()` / `classifyStages` (`rails/hooks/index.ts:146`, `:900-925`), reading `session.seat`.
- **Success criteria:**
  - Kit tests deny `wl-copy`, `/usr/bin/wl-copy`, `printf x | wl-copy`, `bash -c 'echo x | wl-copy'`, `sudo xdg-open u`, `sudo -u saidler xdg-open u`, `echo "$(wl-paste)"` when the seat reads `false`; allow all seven on `true` and on `null`; allow `echo wl-copy` and a heredoc body containing `wl-copy`.
  - Kit test: with `session.seat` unreadable, the call goes through and a toast names the failure.
  - rails' existing 24 tests still pass after the `innerCommand` change.
  - The deny text names the stage and the peer, matching the template above.
  - A `tool.call` with `agentId` set is judged by the same seat.

#### Phase 3: Jev client and decision log in the session mod

**Model:** sonnet
- `jevAsk($, state, questions)`: `$.http.fetch` raced against `jev_timeout_ms`, the accept checks, the breaker, the fallback reasons; userConfig keys above.
- Append each decision to `~/.local/state/session/decisions.jsonl` (`$.process.run(['sh','-c','mkdir -p "$(dirname "$1")" && cat >> "$1"','sh',path], {stdin})`); `HOME/.claude/bin/session-report` summarizes it, copying `bin/prose-report`.
- Not yet wired into attach decisions (Phase 5).
- **Success criteria:**
  - Kit tests with a stubbed `http.fetch`: `model:"gpt-x"` -> `not-jev`; a missing noul -> `bad-answer`; no key -> `no-key` and zero fetches; three failures -> fourth prompt logs `breaker` with zero fetches and one toast; 10 min later (mocked clock) the next prompt fetches again; a never-settling fetch -> `timeout` within `jev_timeout_ms` + 100 ms of mocked clock.
  - The assembled state sent is at most 900 chars for a 10,000-char prompt with a 10,000-char previous answer.
  - No log line contains the key (test greps the written record for the stub key).

#### Phase 4: Labeled set and thresholds

**Model:** opus
- `HOME/.claude/bin/session-jev-eval`: extracts typed prompts (`type=="user"`, string content, no `isMeta`, no tool results) plus the prior assistant text from `~/.claude/projects/**/*.jsonl`, writes candidates to `~/.local/share/session/eval/candidates.jsonl`, and scores a labeled file against Jev, printing precision/recall per bundle per threshold.
- Candidate pull: per bundle, 40 keyword hits (`clipboard|wl-copy|lappy|ssh`; `session id|resume|transcript`; `which repo|branch|cwd`; `context|compact|tokens|cost`) plus 120 random prompts shared across bundles, plus the motivating no-keyword prompt (the ZenNotes token prompt before "im on my laptop, ssh'd into ripr.lan", with its prior assistant "paste it" reply).
- **Operator step (Scott):** label each candidate yes/no per bundle. The agent does not label (circular authority).
- Pick per bundle the lowest threshold with precision >= 0.8. The pasted table shows per bundle per threshold: labeled positives, predicted positives, precision and recall, with the random-120 slice reported apart from the keyword hits. A bundle that lands at 1.01 gets a one-line recorded decision (keep it on demand only). Set the userConfig defaults from the table, tied to the served model in the run.
- Labels stay outside the repo (prompt text); the tool is committed.
- **Success criteria:**
  - `session-jev-eval score` prints one row per bundle per threshold in {0.3, 0.5, 0.7, 0.9}, each with positives, predicted positives, precision, recall, for all labels and for the random slice, over >= 200 labeled prompts.
  - The chosen thresholds and their precision/recall appear in this doc under Phase 4 Results.

#### Phase 5: Wire Jev into the attach decision

**Model:** sonnet
- The `prompt.submit` hook runs the probe and `jevAsk` concurrently, applies the attach rule, calls `next` with the context entry, then appends the record after `next` resolves (the log write never delays the prompt).
- **Success criteria:**
  - Live `sid=$(claude -p --output-format json 'what is my session id?' | jq -r .session_id)` (the mod loads from `~/.claude/skills/session`; origin `sdk`): the record with `.session == $sid` has `source:"jev"`, `model` starting `jev`, `p.identity >= threshold_identity`, `attached` containing `identity`.
  - The same run under `env -u ESCOTE_TYPESAFE_API_KEY`: its record has `reason:"no-key"`, the prompt answers, `attached` is empty (an `sdk` prompt never attaches `seat`).
  - The four-question call's `ms` and `inputTokens` from 10 live records are pasted here (Phase 0 measured one question only).

## Acceptance Criteria

- [ ] `claude plugin test HOME/.claude/skills/session` and `claude plugin test HOME/.claude/skills/rails` both report `0 fail`, with more tests than today.
  - Observed on main (`a5855aa`): session `17 pass / 0 fail`; rails `24 pass / 0 fail`.
- [ ] `rg -c '"desktop_over_ssh"' HOME/.claude/skills/rails/.claude-plugin/plugin.json` returns 1 (the guard's toggle exists; a comment cannot satisfy it).
  - Observed on main: no match (rc=1).
- [ ] After `sid=$(claude -p --output-format json 'what is my session id?' | jq -r .session_id)`, `jq -r --arg s "$sid" 'select(.session==$s) | .source, .model' ~/.local/state/session/decisions.jsonl` prints `jev` then a value starting `jev`.
  - Observed on main: `~/.local/state/session` does not exist. Cannot run until Phase 5.
- [ ] In an interactive herdr session after load, `jq -r .origin ~/.local/state/session/decisions.jsonl | sort -u` includes `composer` for a prompt Scott typed.
  - Cannot run until Phase 5; needs one typed prompt (operator).
- [ ] With `desktop_over_ssh` on and the seat `false`, a Bash `wl-copy` is denied with text starting `rails: wl-copy acts on ripr's desktop`.
  - Cannot run until Phase 2; the kit test in Phase 2 asserts it.

## Resolved Decisions

- 2026-10-17, Scott: vendor review is closed (SEC-3102 comment 399378); Jev may see prompt text in all sessions.
- 2026-10-17, author: `jev_model` defaults to `jev-latest`, following second-brain's recorded ruling (`/v1/models` lists only `jev-latest` and `jev-preview`, so a pin can 400 once retired: `distillers/src/tags.rs:39-41`; its design doc `:393`). The served model is logged and anything not `jev*` fails closed.
- 2026-10-17, author: the guard lives in rails, which owns Bash parsing; session owns the seat and publishes it in `$.state`. Phase 0 proved a cross-plugin read.
- 2026-10-17, author: the guard allows on `null`; a broken guard allows with a toast (panel round 1, Q2: staff asked that the two cases be named apart).
- 2026-10-17, panel round 1 (architect + staff-engineer, synthesis `~/.cache/review-panel/runs/lx6iJb53/synthesis.md`): all 3 must-fix and 8 cheap-wins folded in, nothing pushed back. Q1 (guard in rails) and Q3 (`jev-latest`) both yes. Q4 and Q5 split; closed by the Phase 4 table additions and by the cap bounding both probe and Jev. The guard's command list (beyond `wl-copy`) was flagged as scope past the incident: it stays, as the stated Goal ("clipboard, browser, notifications"), for Scott to strike if unwanted.

## Alternatives Considered

### Attach everything to every prompt
- **Pros:** no Jev, no decisions.
- **Cons:** 309 tokens per prompt, compounding in history.
- **Why not chosen:** Scott asked for a judgment call on what to include.

### Regex prefilter, Jev only on a hit (prose.sh pattern)
- **Pros:** fewer Jev calls.
- **Cons:** the wl-copy case had no keyword in Scott's prompt; the trigger was the agent's own "paste it". A regex misses it, which is the case this doc exists for.
- **Why not chosen:** Jev at 69 ms (Phase 0) and $0.042/M costs less than the miss.

### Guard inside the session mod
- **Pros:** one plugin owns seat and guard.
- **Cons:** copies rails' quote-aware `heads()` / `splitWords()` / wrapper recursion; two parsers drift.
- **Why not chosen:** rails already parses Bash; `$.state` crosses the plugin line.

### GNOME idle time for seat
- Rejected in the seat addendum: needs a guessed window. Recorded so it is not re-proposed.

## Technical Considerations

### Dependencies
- TypeSafe `/v1/systemone`; key `ESCOTE_TYPESAFE_API_KEY` from `~/repos/scottidler/keep/.secrets/escote-typesafe-api-key.age`, decrypted into the shell env (`rules/secrets.md`).
- rails gains a load-order dependency on session.

### Performance
- Jev runs concurrently with the existing probe, before `next`. Phase 0: 69 ms. prose.sh log: p50 212 ms, p90 394 ms, max 778 ms (n=20). Cap 1500 ms.
- Jev cost: Phase 0 call was 286 input tokens for one question; four questions measured in Phase 5 from `usage.input_tokens`.

### Security
- Key read by `$.env.get`, sent only in the `Authorization` header to `api.typesafe.ai`, never logged or put in argv.
- State clipped to 900 chars (second-brain data boundary, `tags.rs:82-96`).
- The decision log holds 300 chars of each prompt, like prose.sh's log, under `~/.local/state`. No rotation, same as prose.sh; one line per Jev-eligible prompt (human and `sdk`).

### Edge cases
- A prompt typed while a turn runs fires `prompt.submit` at Enter (types, `'prompt.submit'` doc), so its atime and seat are taken then, the same as an idle prompt.
- Two prompts in quick succession: each writes the seat it measured; the later write wins, which matches the later prompt.
- First prompt with no local atime and no peer (a local terminal idle since login, no SSH): seat `null`, still attached once so the agent knows the field exists.
- `jev-latest` alias moves: the served `model` in each record shows when; thresholds are re-checked with `session-jev-eval score`.

### Testing Strategy
- Kit tests per phase, stubbing `http.fetch`, `process.run`, `clock.now`, `state` reads.
- Mutation proof per new test, recorded in the implementation notes.
- Live `claude -p` runs for Phases 5 and the acceptance criteria.

### Rollout Plan
- Same repo (`scottidler/claude`), ungated main. Both mods load from `~/.claude/skills/` as `session@skills-dir` and `rails@skills-dir`.
- Ship order: Phase 1 before Phase 2 (rails reads the state Phase 1 writes). Phase 4 thresholds before Phase 5.
- Kill switches: session `jev`, rails `desktop_over_ssh`.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Jev slow or down delays every prompt | Low | Med | 1500 ms race, 3-failure breaker, deterministic floor |
| Jev misjudges a bundle | Med | Low | thresholds from Scott's labels; the tool still answers on demand |
| Seat wrong for a non-keyboard prompt | Med | Low | origin table maps non-composer to `null`/`false`; guard allows on `null` |
| `jev-latest` moves to 1.14 (~2026-10-21) and shifts scores | High | Low | served model logged; re-run `session-jev-eval score` on the same labels |
| Guard blocks a legitimate local copy | Low | Low | only on `false`; toggle `desktop_over_ssh` |

## Open Questions

None.

## References

- `docs/design/2026-10-16-self-session-tool.md` (Addendum: seat)
- `HOME/.claude/hooks/prose.sh:112-310` (Jev call, fallback reasons, decision log)
- `~/repos/scottidler/second-brain/distillers/src/tags.rs` (accept checks, clip, model ruling)
- `~/repos/tatari-tv/shepherd/src/shepherd/jev.py:44` (breaker)
- `HOME/.claude/skills/rails/hooks/index.ts:146`, `:900-925`, `:1857-1899` (Bash parsing, per-rule hooks)
- https://marquee.internal.tatari.dev/p/~scott-idler/typesafe-jev/
- https://tatari.atlassian.net/browse/SEC-3102?focusedCommentId=399378

## Review Log

- Pass 1 (draft): from the design-research brief and the Phase 0 spike.
- Pass 2 (correctness): only human origins write the seat (a task notification could flip the guard); `lastAnswer` added to state, `turn.complete` field verified in types; deny text covers `bridge`; `.catch` simplified to `next(e)`; threshold keys split between Phases 3 and 4 with a never-attach value; log append moved after `next`.
- Pass 3 (clarity): one name per concept (`bundle`, `seat`, `record`); the userConfig table says which phase adds which key.
- Pass 4 (edge cases): queued prompts, back-to-back prompts, null first seat, slash commands and empty prompts skip Jev, alias drift.
- Pass 5 (excellence): every precedent cited by path:line; operator steps called out (Phase 4 labels, AC4 typed prompt).
- Panel round 1: seatKey excludes `promptAt`; per-origin table (sdk runs Jev, never seat); basename match and sudo option values; `$(...)` in quotes; assembled-state clip; cap bounds probe too; 10-minute breaker with toast; `attached` cleared on compaction; seat write ordering; Phase 4 counts and random slice; AC2 and AC3 made comment-proof and session-scoped.
