# Phase 0 evidence: DM resolution and pipeline glue

Run 2026-09-17 on desk.lan. Design doc: `docs/design/2026-09-17-dm-resolution-and-pipeline-glue.md`.

Every entry below is an observed command output pasted verbatim, never an inference
from the bundle. Scratch artifacts under `$TMPDIR/0a/`.

## 0a: re-pin the baseline, and give the driver a replay mode

**Verdict: PASS. Phase 3 has a pinned denominator and a deterministic replay.**

### The drift is live, not historical

Two full walks of the live `~/.claude/projects` tree, minutes apart in one session:

```
posts=240  allow=206  deny=34      (first walk)
posts=241  allow=207  deny=34      (second walk, same session)
```

Round 2 measured 236, then 237, 239, 240 over one afternoon. So a count taken at 0a
has moved by Phase 3, which is a cross-repo ship later. This is why 0a's deliverable
is a file, not a number.

### Today's shipped guard against the pinned snapshot

```
snapshot rows-0a.json  posts=241  md5=4c70205d279a87ad19c8f73159bf5e07
posts=241  allow=207  deny=34
  TARGET=8  artifact=17  multi-statement=9  other=0
     8  [target] no typed turn in the last 3 asked for a Slac
     6  [artifact] the body file /tmp/claude-1000/-home-saidler
     5  [multi-statement] this command carries 2 Slack posting stateme
     3  [artifact] the body file $S/blocks.json is unreadable,
     2  [multi-statement] this command carries 4 Slack posting stateme
     2  [artifact] the body file $f is unreadable, so the text
     1  [artifact] the body file $TMPDIR/upstream-sec.txt is un
     1  [multi-statement] this command carries 3 Slack posting stateme
     1  [multi-statement] this command carries 5 Slack posting stateme
     1  [artifact] the body file $TMPDIR/slack-drafts.md is unr
     1  [artifact] the body file $S/prec.json is unreadable, so
     1  [artifact] the body file $S/fixed.json is unreadable, s
     1  [artifact] the body file $S/bad.json is unreadable, so
     1  [artifact] the body file $S/$f.json is unreadable, so t
```

**Phase 3's baseline is TARGET=8.** The 17/8/9 split reproduces the round-2 measurement
exactly. `rowsFinal.json`'s `216/26/9/0` is chunk D's record and is NOT the target: the
guard gained the multi-statement rule after that file was cut.

### The gate: replays deterministically, twice, to the same counts

```
replaying rows-0a.json  posts=241  md5=4c70205d279a87ad19c8f73159bf5e07
posts=241  allow=207  deny=34
  TARGET=8  artifact=17  multi-statement=9  other=0        (replay 1)

replaying rows-0a.json  posts=241  md5=4c70205d279a87ad19c8f73159bf5e07
posts=241  allow=207  deny=34
  TARGET=8  artifact=17  multi-statement=9  other=0        (replay 2)
```

Stronger than the gate asks: the scored rows are byte-identical across both replays
(`f23c42e6230549396f4c62495d52f0b1`) and byte-identical to the walk that produced the
snapshot. `cmp` returns clean on both pairs.

### The live ledger was never opened

10 entries before the first run, 10 after four full runs (two walks, two replays). The
scratch-`HOME` isolation holds; `REPLAY_LEDGER` stays buried.

### The snapshot is the payloads, not the scored rows

`rows-0a.json` stores each post's full `tool_input` and its verbatim prompt window. The
scored rows clip `target` to 60 and `text` to 90 chars for reading, so they are a summary
and could never be replayed: the guard would be handed a different body. Posts are sorted
by `(session, tool_name, tool_input)` because `rglob` order is filesystem order, which is
what makes the byte-comparison above possible.

## 0b: the `UserPromptSubmit` hook, six probes

Claude Code **2.1.274** (chunk C measured 2.1.272, chunk A 2.1.270). Method is chunk C's
verbatim: a scratch hook registered via `--settings` on a nested `claude -p` run, plus
`--plugin-dir` for the function-hook arms. Scratch artifacts under `$TMPDIR/p0b/`.

**Verdict: 0b's gate PASSES. Mechanism A is alive, and no discriminator exists.** Four of
the six probes are answered by execution. Two (0b-4, 0b-5) are **not measurable by this
method** and are handed to an interactive session; see below.

### Two environment facts anyone re-running these needs

- **A nested `claude -p` under the command sandbox cannot write `~/.claude/projects`**, so
  it leaves no transcript. `--output-format stream-json --verbose` is the only evidence
  channel. The first attempt at 0b-1b chased a transcript path that was never written.
- **Several flags are variadic and swallow a trailing positional prompt**: `--mcp-config`
  ate the prompt as a second config path, `--debug` ate it entirely
  (`Input must be provided either through stdin or as a prompt argument`). Feed the prompt
  on **stdin**; it is immune.

### 0b-1: `additionalContext` reaches the model. PASS

Hook emitted `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROBE-NONCE-7F3A9C: ..."}}`.
The nested session, asked only what was in its context, answered:

```
PROBE-NONCE-7F3A9C: this line was injected by a UserPromptSubmit hook, not typed by the user.

It appeared separate from your typed message: in a `<system-reminder>` block tagged as
UserPromptSubmit hook additional context.
```

So it arrives verbatim, as a `<system-reminder>`, attributed to the hook and distinguishable
from the typed text. **Mechanism A is not dead**, which is the branch 0b's gate cared about.

### 0b-1b: an injected INSTRUCTION is obeyed, not just delivered. PASS

Delivery is not obedience, and obedience is what Phase 7's criterion needs. A second hook
injected mechanism A's actual shape:

```
Inline skill tokens detected in the user prompt: /chisle-help. The user typed these as
imperatives, not as discussion. Invoke each one with the Skill tool now, before answering
the rest of the message.
```

Typed prompt: `merge, pull main, /chisle-help, install`. The stream carried:

```json
{"name":"Skill","input":"{\"skill\":\"chisle-help\"}"}
```

**A real `Skill` invocation, from an inline token, in a multi-clause prompt, with no second
prompt.** That is Phase 7's first success criterion demonstrated at the mechanism level
before Phase 7 is written.

**The caveat that Phase 7 must respect.** In 0b-3a, where the injected line was a bare nonce
referencing nothing the user had typed, the nested model **flagged it as prompt injection and
refused to act on it**, verbatim: "Flagging per prompt-injection policy rather than acting on
it." The difference is whether the injected line names a token actually present in the
prompt. Mechanism A does by construction, which is why it lands. The wording must keep doing
so: an injected instruction that cannot be corroborated against the visible prompt gets
treated as hostile, correctly.

### 0b-2: NO field discriminates a typed prompt from an injected one. PASS (answer: none)

The full `UserPromptSubmit` payload at 2.1.274, keys sorted:

```json
["cwd","hook_event_name","permission_mode","prompt","prompt_id","session_id","transcript_path"]
```

Seven keys, none carrying provenance. No `source`, no `promptSource`, nothing. This
confirms chunk C's 2.1.272 measurement at the current version and does not presuppose it.

**Per 0b's own gate, this is the accepted-cost branch:** the hook fires on every prompt, and
Phase 7 writes that in rather than designing it away.

### 0b-3: it fires for prompts that start with `/`. PASS

Both arms fired, captures incrementing each time:

```
2026-09-17 10:24:39  {"keys":7,"prompt":"/probe-nonexistent-xyz"}
2026-09-17 10:24:46  {"keys":7,"prompt":"/chisle-help"}
```

A nonexistent command and a real skill both reach the hook, and `prompt` carries the **raw
slash text, pre-expansion**. So Phase 5's `startsWith("/") -> no scan` rule is implementable
from the payload alone, and Phase 7's "a prompt already opening with a slash command is left
alone" is decidable at hook time.

### 0b-6: a `skillOverrides: "off"` skill does NOT resolve. PASS

`skillOverrides` is a flat `name -> "off"` map (read from the live settings, ~50 entries).
With `{"skillOverrides":{"chisle-help":"off"}}` and a typed `/chisle-help`, the run produced
**zero tool calls** and the harness itself answered:

```
Skill "chisle-help" is disabled via skillOverrides. Remove the override from your settings to run it.
```

That is the harness, not the model. **Phase 6's deny requirement is load-bearing:** emitting
an off skill does not degrade, it burns the turn on a hard error. The injected-instruction
arm was deliberately not run: the block is at resolution, so no prompting path can change it.

### 0b-4 and 0b-5: NOT MEASURABLE by nested `claude -p`. Handed to an interactive session

Both probe the rejected alternatives (Alternative 1's `prompt.submit` injection, Alternative
3's `turn.complete` plus `$.command.run`). Both need a function-hook plugin, built and
validated here:

```
❯ ./index.ts hooks: tool.call{tool=Bash}, prompt.submit
✔ Validation passed
```

```
❯ ./index.ts hooks: prompt.submit, turn.complete
❯ ./index.ts calls: $.command.run, $.ui.log
✔ Validation passed
```

So `prompt.submit`, `turn.complete` and `$.command.run` are all names this build's validator
recognizes. But **a `prompt.submit` hook's rewrite does not take effect in print mode**, and
that was isolated rather than assumed. One run, one plugin, both hooks registered:

- `tool.call` deny **fired**: marker `PROBE-PLUGIN-LOADED-9D1E` present 3x in the stream, and
  the nested model quoted it verbatim ("denied verbatim as `PROBE-PLUGIN-LOADED-9D1E`...").
  **The plugin loads under `--plugin-dir` in `-p` mode.**
- `prompt.submit` rewrite **did not fire**: the control arm rewrote the prompt to
  `Reply with exactly this and nothing else: REWRITE-LANDED-4B2C` and the model replied `OK`,
  answering the ORIGINAL prompt. Marker count 0, in the same run as the deny above.

The control arm is why this is reported as not-measurable rather than as "0b-4 PASS, the
slash rewrite was not expanded". Without it, an unfired hook is indistinguishable from a hook
that fired and was ignored, and the phase would have banked a false green.

**What is still owed, and it is an operator step the doc already predicted** (`Operator steps`:
"Run `/plugin-types` once in an interactive session ... It is not scriptable from a
subagent"): run both probe plugins in an **interactive** session, where a prompt is genuinely
submitted, and record whether a `/`-leading rewrite is expanded and what `$.command.run`
does from each event. Plugins are at `$TMPDIR/p0b/probe-expand` and `$TMPDIR/p0b/probe-cmdrun`.

**Neither blocks anything.** 0b's gate turns on mechanism A, which is proven alive and
obeyed. 0b-4 and 0b-5 only corroborate alternatives the doc already rejected in writing.
