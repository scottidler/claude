# Phase-worker liveness: what "went dark" was, measured 2026-09-20

Input for chunk G's design doc (agent definitions, `dispatch.md`, phase return
contract). Produced in a research session on 2026-09-20 while a live
`/how-to-execute-a-plan` run (second-brain `tags-only`, P7 of 11) was in flight.
Reproduce with `measure-gaps.py` beside this file; it reads the live
`~/.claude/projects/*/*/subagents/` tree, so counts move.

## The liveness file the harness already writes

Every named worker has
`~/.claude/projects/<slug>/<parent-session>/subagents/agent-<name>-<hash>.jsonl`
(mode 0600, appended on every tool round) and a sibling `.meta.json` frozen at
spawn with `agentType`, `name`, `model`, `permissionMode`,
`requestNonInteractive`, `taskKind`, `teamName`. Observed on four live research
workers: all four `.jsonl` mtimes within 21 seconds of wall clock. The worker
cannot forget or fake this file. Nothing in the setup reads it.
`how-to-execute-a-plan/SKILL.md:65-68` ("A silent mid-phase gap has no
mechanism today") is therefore false as written; 0d's "zero wakes" stays true.

## 743 phase-worker transcripts, all time

| measure | value |
|---|---|
| longest-gap median | 1.8m |
| longest-gap p90 | 5.2m |
| transcripts with a gap over 10m | 40 (5.4%) |
| transcripts with a gap over 60m | 11 (1.5%) |
| ended on an unanswered `tool_use` | 5 |

## Three dark classes

1. **Tool call parked on a permission prompt** (June/July, before auto mode).
   509m (`sed -i`, ended "The user doesn't want to proceed with this tool
   use"), 441m (`./target/debug/slack --help`), 343m (`otto ci | tee`), 280m
   (`find`). Each ended with normal output once approved hours later. Gone.
2. **Auto-mode escalation to an absent user** (2026-09-03). Three plain `grep`
   commands sat 218m, 24m, 21m
   (`agent-aphase10-b0eede63e7571bab`, `agent-aphase16-a84f550ea599914a`).
   Since workers carry `requestNonInteractive: true` (first seen 2026-09-17), no
   Bash call in a phase worker has exceeded 12m. Since 2026-08-15: 273
   transcripts, 0 gaps over 15m preceded by a Bash `tool_use`.
3. **Worker backgrounds a long task, says it will wait, ends its turn.** LIVE.
   - `agent-aphase3-mode-plumbing-d6d9d5f06858892c` (2026-09-17, parent
     `5c0e93fe-7c00-4c8e-b384-abf2c34de8cd`): last words "I'll stop issuing
     commands now and wait for the automatic notification when `otto ci`
     completes." SubagentStop fired, worker idle **500m**. The `otto ci`
     task-notification landed as a `queued_command` attachment and did not
     re-drive the idle worker. Unstuck by the parent's SendMessage at 13:30.
   - `agent-aphase5-evals-dfdf578ad7ec15f1` (2026-09-19, parent
     `e6d1b0b0-7607-4f41-96c9-606cbf349d8b`): "I'll wait for the background
     tasks to notify completion before continuing." Idle **124m**, then again
     after being unstuck ("I'll wait for the background eval notifications
     now."). Three `queued_command` task-notifications arrived during the idle
     stretch; none woke it.
   - Same class as `anthropics/claude-code#92410` (6.5h silent deadlock).

## The parent saw it at t=0 and did nothing

Both parents received, immediately, an `idle_notification` whose `result` was
the "I'll wait" sentence:

```
{"type":"idle_notification","from":"phase3-mode-plumbing","timestamp":"2026-09-17T05:09:38.520Z",
 "idleReason":"available","result":"I'll stop issuing commands now and wait for the automatic notification when `otto ci` completes."}
```

A phase report carries a `**Commit:**` (or `NOT COMMITTED`) line
(`phase-implementer.md`, Return value). An idle notification without one is a
stall, detectable from the report shape alone, no timer needed.

## What the hook payload offers

`SubagentStop` input carries `last_assistant_message`, `agent_transcript_path`,
`agent_type`, `hook_event_name` (read today by `prose.sh:113-118`), and the
event blocks: `hook_blocking_error` from the em-dash rule was observed on a
phase worker (`agent-aPhase2-d868f228d6b394a1`, 2026-09-17T18:21). Docs also
list `TeammateIdle` (blocks with exit 2 "to keep the teammate working"),
`asyncRewake` hooks, and `CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS`; none probed.

## What NOT to build, with the source

- A worker-written progress or heartbeat file: silence-blind (a hung or idle
  worker writes nothing) and self-report-prone; the skill's own rationale at
  `2026-09-17-dm-resolution-and-pipeline-glue-implementation-notes.md:870-873`.
- A token-silence timeout: `anthropics/claude-code#85615`, the native 600s
  stream watchdog killed healthy workers mid-report.
- A background babysitter fleet: rejected in F2
  (`2026-09-18-handoff-and-waiting-discipline.md:72`).

## Candidate design for G, ranked mechanical-first

1. SubagentStop (or TeammateIdle, probe first) report-shape guard for
   `agent_type: phase-implementer`: block unless `last_assistant_message`
   contains `**Commit:**` or `NOT COMMITTED`; reason tells the worker to wait
   for the background task in the foreground with a bounded `until` loop.
2. `phase-implementer.md`: never `run_in_background` for `otto ci`; never end a
   turn with a background task outstanding.
3. `how-to-execute-a-plan`: an `idle_notification` without a report is a stall;
   message the worker in the same turn. Replace the "accepted limit" paragraph.
4. `dispatch.md`: per dispatch, arm `Monitor` (30m cap, re-arm per wake; gated
   by `tengu_amber_sentinel`) or a `run_in_background` `until` loop on the
   worker's `.jsonl` mtime, one line when stale over 15m (p90 healthy 5.2m,
   longest legit `otto ci` 11m). Tail says which case: unanswered `tool_use`
   is a hung tool, assistant text is idle-without-report.
5. Recovery: `TaskStop`, fresh worker in the same tree reading git log plus
   implementation notes. SendMessage to the idle worker also resumes it, which
   is what unstuck both cases above.

Phase 0 probes G owes: TeammateIdle fires for `taskKind: in_process_teammate`;
a SubagentStop block re-drives a phase worker; `Monitor` is enabled on this
account (its schema loaded in the 2026-09-20 session).
