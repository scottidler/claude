# Implementation notes: handoff ownership and waiting discipline

Append-only. Design doc: `docs/design/2026-09-18-handoff-and-waiting-discipline.md`.
Branch: `worktree-f2-handoff`, built in the worktree `.claude/worktrees/f2-handoff` so that
no edit to `HOME/.claude/**` is live while it is being written. The live `~/.claude` symlinks
resolve into the MAIN checkout, so an in-place edit there changes every running session's hooks
and rules mid-turn; that is the reason this chunk is built out of a worktree at all.

## Phase 0: harness spike, zero code

Both probes ran out of a scratch project (`$SCRATCH/phase0`) under headless `claude -p`, never
against the live `~/.claude/settings.json`. Claude Code version on the box: **2.1.278**
(the doc's measurements were taken on 2.1.276; the two probes below were re-taken on 278).

### Probe 1: hook vs `validateInput` ordering. DECISIVE.

Setup: a project-local `PreToolUse(Bash)` hook that denies unconditionally with the reason
`PHASE0_HOOK_DENY_MARKER`, registered only in the scratch project's `.claude/settings.json`.

- `sleep 26` returned the **native** text: `Blocked: standalone sleep 26. To wait for a
  condition, use Monitor with an until-loop (e.g. \`until <check>; do sleep 2; done\`). To wait
  for a command you started, use run_in_background: true. Do not chain shorter sleeps to work
  around this block.` The hook's marker is absent from the whole transcript.
- Control, same project, same hook: `echo hi` returned `PHASE0_HOOK_DENY_MARKER` (3 occurrences
  across the stream). So the hook **was** registered and firing; only the sleep case bypassed it.

**Observed fact, recorded as the criterion asks: `validateInput` runs BEFORE the `PreToolUse`
hook chain.** Consequence for Phase 4, folded into the doc: our rule never sees a statement-0
bare `sleep >= 25`, because the harness has already refused it. The rule's whole domain is what
the native check lets through, which is exactly the three bypass classes B1, B2 and B3. T1's
`>=` boundary therefore matters for summed and multiplied totals (`echo A; sleep 25`), not for
the bare statement-0 case, which never reaches us.

### Probe 2: `silent_turn_reminder` at TURNS=2. INCONCLUSIVE HEADLESS, root cause localized.

Two runs, each six consecutive assistant turns carrying nothing but `Bash` tool calls:

1. `CLAUDE_CODE_SILENT_TURN_REMINDER_TURNS=2` alone: no reminder in the output stream.
2. `CLAUDE_CODE_SILENT_TURN_REMINDER=1` plus `..._TURNS=2`: no reminder in the output stream.

Rather than guess, the gate chain was read out of the 2.1.278 binary. The attachment is emitted
when `Ee && e===null && !y?.isRegularUserPrompt && !ute() && fxn(n.options.mainLoopModel)`:

- `Ee` is the main-session flag, resolved from the sibling ternary
  `callSite: Ee ? "attachments_main" : "attachments_subagent"`. True for a `-p` run.
- `ute()` is focus mode / brief transcript (`Ke().viewMode === "focus"`), not headlessness. False.
- `fxn(model)` is `_2("silent_turn_reminder", ..., a.CLAUDE_CODE_SILENT_TURN_REMINDER)`, and
  `_2` returns the env value directly when it is defined (`if(l!==void 0)return l`), so run 2
  forced this true and removed the served-capability question entirely.
- The counter `ojo()` treats a turn as user-visible only when the assistant message carries
  non-empty text or a `tool_use` in `rjo = new Set([Os, Cxn, qUo, z_, ey])`, of which two
  resolve to `"ExitPlanMode"` and `"SendUserFile"`. `Bash` is not in that set, so the six probe
  turns should have counted as silent.

**So the remaining unknown is not the gate, it is the surface.** Attachments are injected into
the model request, not echoed to stdout, and a headless `-p` run leaves no transcript under
`~/.claude/projects/` to inspect (searched: the only file on the box containing the probe marker
is this session's own transcript). A negative in the `-p` output stream is therefore not
evidence that the attachment did not fire.

**Status: the criterion is not satisfied and Phase 5 is NOT dropped on this evidence.** What
settles it is one interactive fresh session with `CLAUDE_CODE_SILENT_TURN_REMINDER_TURNS=2`
in `settings.json` `env`, two silent turns, then `grep -c silent_turn_reminder` over that
session's `~/.claude/projects/**/<session-id>.jsonl`. Phase 5 stays open until that runs.
