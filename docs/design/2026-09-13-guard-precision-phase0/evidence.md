# Phase 0 evidence: guard-precision

Run 2026-09-14 on desk.lan, Claude Code 2.1.270, from session `3c0cb07e`.
Design doc: `docs/design/2026-09-13-guard-precision.md`.

Method: the same one chunk A used. Throwaway hooks registered through a scratch `--settings`
file on a nested `claude -p --model sonnet` run, each hook appending the payload it received to
its own log, so every claim below has both the model's report and the hook's own record behind
it. Scratch artifacts under `$SCRATCHPAD/p0/` (`rw.sh`, `deny.sh` and their slow/timestamped
variants, one `settings-*.json` per spike, `logs/`).

One harness fact shapes the whole run: a nested `claude` inside this session's sandbox cannot
start its own sandbox (`EPERM ... listen '/tmp/claude-1000/srt-mux-*.sock'`), so the first Bash
call in every nested session fails with that error and the second runs unsandboxed. Every result
below is from the second call. The hooks fired on both.

## 0a: which SessionStart channel reaches the model -- BOTH, in an interactive session; NEITHER under `-p`

Two scratch SessionStart hooks: `ss-stdout.sh` prints `WARN: probe-stdout-marker-A7 ...` to
stdout; `ss-context.sh` prints
`{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"probe-context-marker-B8 ..."}}`.
Prompt: list every string in context containing `probe-` and `marker`.

| run | source of the hooks | matcher | hooks fired | model saw |
|---|---|---|---|---|
| `claude -p --settings` | scratch file | `*` | no (payload log never written) | NONE |
| `claude -p --settings` | scratch file | `` (empty) | no | NONE |
| `claude -p --settings` | scratch file | `startup` | no | NONE |
| `claude -p` in a scratch project dir | `.claude/settings.json` | `` | no | NONE |
| interactive `claude --settings` under tmux | scratch file | `*` | yes, 2 payloads, `"source":"startup"` | BOTH markers, quoted verbatim |

So `SessionStart` does not fire at all in print mode, from any settings source, and fires
normally in an interactive session. In the interactive transcript
(`a4faad78-ad5f-422b-ad47-4bd07966dcf0.jsonl`) both arrive as `attachment` records rendered into
a `<system-reminder>`:

- plain stdout: `{"attachment":{"type":"hook_success","hookName":"SessionStart:startup", "content":"WARN: probe-stdout-marker-A7 ...", ...}` rendered as `SessionStart:startup hook success: WARN: ...`
- `additionalContext`: a second record `{"attachment":{"type":"hook_additional_context","content":["probe-context-marker-B8 ..."]}}` rendered as `SessionStart hook additional context: ...`

The model's reply quoted both strings exactly (transcript line 30).

**This refutes the design doc's problem 1 second half.** It said a SessionStart hook's plain
stdout is shown in transcript mode only and never reaches the model. On 2.1.270 it does, as a
`hook_success` attachment. The audit's "zero WARN lines in any transcript" has a different cause:
across the 9 transcripts in this project dir that carry an `ssh-agent-check.sh` SessionStart
attachment, the recorded `stdout` is `""`, because the key was readable and an agent key was
loaded, so the hook had nothing to warn about. The channel works; the condition never tripped.

**Consequence for Phase 7:** `hooks-preflight.sh` emits `additionalContext`, the documented
context field, and its rendering (`SessionStart hook additional context: ...`) is the cleaner of
the two. Plain stdout would also work. In a headless `-p` session the preflight never runs, so
`bin/hooks-resolve` is the only half that covers automation; the doc already carries that as the
merge-time check.

## 0b: `updatedInput` reaches the shell -- PASS

`rw.sh 'echo original' 'echo rewritten'` registered as a PreToolUse Bash hook, emitting
`{hookSpecificOutput:{hookEventName, updatedInput:(tool_input + {command}), permissionDecisionReason}}`
and no `permissionDecision`. Raw `tool_result` from `--output-format stream-json`:

```
{"tool_use_id":"toolu_01CocjHMm6DTSL2FifJ36Ppx","type":"tool_result","content":"rewritten","is_error":false}
```

The hook's log shows the payload it received: `tool_input.command = "echo original"`, keys
`cwd, effort, hook_event_name, permission_mode, prompt_id, session_id, tool_input, tool_name,
tool_use_id, transcript_path`. The shell ran the rewritten command.

**Second finding, not asked for but load-bearing for AC5:** the `permissionDecisionReason` on a
rewrite is NOT surfaced to the model. The `tool_result` content is exactly `rewritten`, nothing
else, and the model reported `HOOKTEXT=none`. Re-run with the hook also emitting
`permissionDecision: "allow"` (the `rewrite-cd-read.py` ALLOW-branch shape): same, content is
`rewritten` only. A shell hook has no channel to tell the model a rewrite happened. The rails
plugin's "context line" is a function-hook feature and is not available to a command hook.

## 0c: the same rewrite inside a subagent -- PASS

Nested session told to dispatch a `general-purpose` Agent whose prompt runs `echo original`.
The main thread reported `AGENT_SAID=STDOUT=rewritten`. The hook log shows two more payloads from
the subagent's session, each carrying `agent_id` and `agent_type` keys that the main-thread
payloads lack, with `tool_input.command = "echo original"`. PreToolUse fires for subagent Bash
calls and the rewrite lands there too.

## 0d: `lib.sh` resolves through the symlink -- PASS

`repo/probe.sh` sources `. "$(dirname "$0")/lib.sh"`; `repo/lib.sh` defines `probe_fn`. Symlink
`probe.sh` alone into `hooks/`, run `hooks/probe.sh`: `lib.sh MISSING at hooks` (the negative
case: `dirname "$0"` is the SYMLINK's directory, not the target's). Symlink `lib.sh` in too:
`lib-resolved-through-symlink OK from .../p0/hooks`. Same from `cd /` with the absolute symlink
path, which is how `settings.json` spells `~/.claude/hooks/<x>.sh`. The operator step in the plan
(link `lib.sh` alongside the guards) is exactly what the negative case demands.

## 0e: two `updatedInput` hooks on one event -- rewrites DO NOT compose; last to complete wins

Hooks: `one` rewrites `echo one` to `echo ONE`, `two` rewrites `echo two` to `echo TWO`, `gamma`
denies on `PROBE_CHAIN`. Command: `echo one; echo two`.

| registration order | what every hook RECEIVED | shell ran |
|---|---|---|
| one, two, gamma | all three: `echo one; echo two` (the ORIGINAL) | `one` / `TWO` |
| two, one | both: the original | `ONE` / `two` |
| one (sleep 3), two | both: the original | `ONE` / `two` |

Every hook is handed the original `tool_input`; no hook sees another's rewrite. Exactly one
`updatedInput` survives. Which one is decided by COMPLETION order, last writer wins: with both
instant, the later-registered hook (started later) won twice; with the first hook slowed by 3
seconds, the first hook's edit survived instead. A hook that returns `{}` (gamma, on the compose
run) does not clobber a sibling's rewrite.

Rewrite-then-deny chain, command `echo one PROBE_CHAIN`: the model received
`PreToolUse:Bash hook error: REASON-GAMMA: probe deny after rewrite`, nothing ran, and gamma's
log shows it received the ORIGINAL `echo one PROBE_CHAIN`. A deny cancels the rewrite outright,
and a denying hook never sees a rewriter's output.

**Consequence for Phase 6, per the doc's own pre-decided fallback:** rewrites do not compose, so
the `git -C` strip folds into `rewrite-cd-read.py`, the one `updatedInput` hook that already
exists, instead of converting `git-no-dash-c.sh` into a second one. Two rewriting hooks on the
same Bash call would silently lose one edit whenever both fired (`cd <cwd> && git -C <cwd> ...`).

## 0f: which denying hook's reason surfaces -- last to complete, so registration order cannot choose it

Two deny hooks on the same marker with distinct reasons. Every run: both hooks fired (each wrote
one payload); the model received exactly one `PreToolUse:Bash hook error: <reason>`.

| registration order | timing | reason the model got |
|---|---|---|
| ALPHA, BETA | both instant | ALPHA |
| BETA, ALPHA | both instant | ALPHA |
| ALPHA (via `z-deny.sh`), BETA (via `a-deny.sh`) | both instant | ALPHA |
| ALPHA (sleep 3), BETA | first slow | ALPHA |
| ZULU, ALPHA | both instant | ALPHA (twice) |
| ALPHA, ZULU | both instant | ZULU |
| ZULU (sleep 3), ALPHA | first slow | ZULU |

Ruled out: registration-first (row 2, 5, 6 contradict), registration-last (rows 1, 3, 4, 7),
command-string order (row 3: `z-deny.sh` beat `a-deny.sh`), reason-text order (row 6: ZULU beat
ALPHA). The only rule consistent with all seven rows is the same one 0e found: hook results are
folded in completion order and the LAST deny to complete supplies the reason. With equal-cost
hooks that is a race the later-registered one usually wins (rows 5, 6) but not always (rows 1, 3).

**Consequence for Phase 5:** the doc planned to pick `branch-name-guard.sh`'s registration slot
"so the actionable reason wins" over Gate C when one command trips both. There is no slot that
does that. Phase 5 therefore chooses no ordering and makes each deny text sufficient on its own:
Gate C's text says not to create the release branch at all, `branch-name-guard.sh`'s text names
the flat slug. A command that trips both converges in at most two round trips whichever reason
wins, and the disjoint cases (the common ones) are unaffected.

## Summary of plan changes

| spike | result | plan change |
|---|---|---|
| 0a | both channels reach the model interactively; none in `-p` | Phase 7 emits `additionalContext`; problem 1's stdout claim is withdrawn |
| 0b | pass; the rewrite reason is invisible to the model | AC5 and Phase 6's criterion drop "tool result carries the reason" for the existing log line |
| 0c | pass, with `agent_id`/`agent_type` in the payload | none |
| 0d | pass | none |
| 0e | rewrites do not compose; deny cancels rewrite | Phase 6 folds the `-C` strip into `rewrite-cd-read.py`; `git-no-dash-c.sh` is deleted and unregistered; AC1 counts five sourcing guards |
| 0f | last-completed deny's reason wins; a race | Phase 5 picks no registration order; both deny texts stand alone |
