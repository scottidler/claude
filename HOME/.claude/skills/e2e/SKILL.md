---
name: e2e
description: Run loopr-v5 end-to-end tests with active monitoring, decoded against the v5 instrumented spans. Use when the user says "e2e", "run e2e", "run bin/e2e", "test rust-version", or asks for an end-to-end run on the v5 repo (`~/repos/scottidler/loopr-v5`). For v3/v4 (`~/repos/scottidler/loopr` or `loopr-v4`), use `/e2e-v3` instead.
allowed-tools: Bash, Read, Grep, Glob, Agent
---

# Loopr v5 E2E Test Runner with Active Monitoring

Run `bin/e2e` from `~/repos/scottidler/loopr-v5/` against a target and actively monitor the pipeline. Report progress and failures early and often. Read `events.log` against the v5 instrumented spans (added by the 2026-04-24 instrumentation sweep) to diagnose failures without restarting the daemon at `-l debug`.

## Usage

```
/e2e                    # default target: rust-version
/e2e rust-version
/e2e ls                 # list available targets
```

To list targets manually: `~/repos/scottidler/loopr-v5/bin/e2e ls`.

## Available Targets

Defined as `~/repos/scottidler/loopr-v5/bin/e2e-targets/<name>.md` (the PRD passed verbatim as the goal-string to `loopr plan`). Add a new target by writing a sibling `.md` file and adding a `case` arm in `bin/e2e` that scaffolds it.

Current:
- `rust-version` (default) — adds a `--version` flag to a freshly `cargo init`-ed CLI; the original Stage 9 first-gate target.

## Execution Steps

### 1. Kill any prior run for this target

`bin/e2e` does this itself: it follows `/tmp/loopr/e2e/<target>/latest`, stops the previous daemon via `loopr -C <prev> daemon stop`, removes any leftover socket file, and `rm -rf`s the prev dir. You don't need to do anything before invoking.

If you need to nuke state outside the script (e.g., a daemon survived from a prior `bin/e2e` that crashed), do:

```bash
pgrep -af 'loopr.*daemon' | head
# For each stuck daemon:
~/.cargo/bin/loopr -C <its-target> daemon stop || true
```

Never `kill -9` a daemon as a first step — `daemon stop` SIGTERMs and escalates to SIGKILL after 3s on its own.

### 2. Launch the run in the background

```bash
mkdir -p /tmp/loopr && \
  ~/repos/scottidler/loopr-v5/bin/e2e <TARGET> 2>&1 | tee /tmp/loopr/e2e-output.log
```

Use Bash with `run_in_background: true`. Default timeout per target is 900s; override with `--timeout`.

If the user asks to refresh the binary first:

```bash
~/repos/scottidler/loopr-v5/bin/e2e --build <TARGET>
```

### 3. Verify the latest symlink before monitoring

```bash
readlink -f /tmp/loopr/e2e/<TARGET>/latest
```

The resolved path must contain today's timestamp (e.g. `20260424-203500`). Report this path so it's visible in the conversation — it is the ground truth for everything below.

If `latest` still points at a stale timestamp, the script hasn't reached `ln -sfn` yet. Wait a few seconds and retry. Do not proceed until the symlink resolves to the new run dir.

### 4. Resolve the log paths (XDG-rooted, NOT target-local)

v5 writes per-run logs under `~/.local/share/loopr/sessions/<sid>/targets/<slug>/`, NOT under `<run>/.loopr/runs/`. The slug is the absolute target path with `/` replaced by `-` (so `/tmp/loopr/e2e/rust-version/<ts>` becomes `-tmp-loopr-e2e-rust-version-<ts>`).

```bash
RUN=$(readlink -f /tmp/loopr/e2e/<TARGET>/latest)
SID=$(cat "${RUN}/.loopr/active-session")
PID=$(cat "${RUN}/.loopr/daemon.process-id")
SLUG=$(echo "${RUN}" | tr '/' '-')
XDG="${HOME}/.local/share/loopr/sessions/${SID}/targets/${SLUG}"

EVENTS="${XDG}/runs/${PID}/events.log"   # JSON, structured, every span field
FANOUT="${XDG}/session-fanout.log"       # human-readable, level-filtered
```

Both files are required:
- `events.log` is JSON-per-line with full span ancestry — use it for retrospective analysis (`grep` by span name + JSON field).
- `session-fanout.log` is human-formatted — better for live tailing.

Neither lives under `<run>/.loopr/runs/`. That dir does not exist; the target-local `.loopr/` only holds runtime state (socket, daemon.pid, daemon.process-id, taskstore, worktrees, active-session pointer).

### 5. Actively monitor while it runs

Poll every 30-60s. **Use absolute paths only — never `cd`.**

**Tail the human log (primary live view):**
```bash
/usr/bin/tail -100 "${FANOUT}"
```

**Read structured events.log (full span detail):**
```bash
/usr/bin/tail -100 "${EVENTS}"
# or grep by span name:
grep -F '"name":"run_implementer"' "${EVENTS}" | /usr/bin/tail -20
grep -F '"name":"check_action"' "${EVENTS}" | /usr/bin/tail -10
```

**TaskStore snapshot:**
```bash
~/.cargo/bin/loopr -C "${RUN}" plans
~/.cargo/bin/loopr -C "${RUN}" works
~/.cargo/bin/loopr -C "${RUN}" bundles
~/.cargo/bin/loopr -C "${RUN}" ticks
```

**Daemon status:**
```bash
~/.cargo/bin/loopr -C "${RUN}" daemon status
```

**Sessions:**
```bash
~/.cargo/bin/loopr -C "${RUN}" sessions list
~/.cargo/bin/loopr -C "${RUN}" sessions status
```

**Per-record summaries (written by the integrator on terminal transitions):**
```bash
find "${RUN}/.loopr/records" -name 'summary.md' 2>/dev/null
```

**Per-record transcripts (LLM round-trips, when written):**
```bash
find "${RUN}/.loopr/records" -name 'transcript.md' -o -name 'decomposition.md' -o -name 'review.md' 2>/dev/null
```

**Git state in the target repo:**
```bash
git -C "${RUN}" log --oneline --all
git -C "${RUN}" worktree list
```

**Session-fanout per-session log (the fanout layer's per-session view):**
```bash
ls "${RUN}/.loopr/runs/${PID}/sessions/" 2>/dev/null
# tail the active session
SID=$(cat "${RUN}/.loopr/active-session" 2>/dev/null)
/usr/bin/tail -100 "${RUN}/.loopr/runs/${PID}/sessions/${SID}/session-fanout.log" 2>/dev/null
```

### 6. How to read events.log — span dictionary

Every non-trivial function in every crate touched by a run carries `#[tracing::instrument]` (added by the 2026-04-24 sweep). Lines in events.log are timestamp + level + span path + KV fields. Grep by span name and read the field set to diagnose without restarting at `-l debug`.

**The span that motivated the whole sweep — Stage 9's mystery:**

| Span | Fields | Meaning |
|------|--------|---------|
| `agents.lifeguard.check_action` | `action_hash`, `action_count`, `max_repeat` | Lifeguard sees each agent action; if `action_count >= max_repeat` for the same `action_hash`, the agent is escalated. **Same-action-3-times** failures are now identifiable — grep `action_hash=<hex>` to see exactly which action looped. |

**Agents (the per-iteration story):**

| Span | Fields | Meaning |
|------|--------|---------|
| `agents.implementer.implement_iteration` / `agents.reviewer.review_iteration` | `work_id`/`bundle_id`, `iteration` | One LLM round-trip + tool calls. Iteration count climbing without progress is a stuck-loop signal. |
| `agents.dispatch` | `iteration`, `work_id`, `action_count` | The action dispatcher; runs after each LLM response. |
| `agents.parse.parse_action` | err line lists the malformed JSON | LLM produced unparseable tool-use; if recurring, the prompt or the model is the issue. |

**Tools (which command on which lane):**

| Span | Fields | Meaning |
|------|--------|---------|
| `tools.router.spawn` | `tool_name`, `lane`, `working_dir` | The router picked a lane (worktree / target / ephemeral) and dispatched. |
| `tools.spawn.process_group` | err line shows signal / exit code | Sandbox or process-group failure (OOM, signal, bwrap denial). |
| `tools.bash.execute`, `tools.read.execute`, `tools.write.execute`, `tools.edit.execute`, `tools.grep.execute`, `tools.glob.execute` | per-tool keys (path, pattern, command snippet) | Each tool's leaf invocation. |

**Decomposer (Plan -> Work DAG):**

| Span | Fields | Meaning |
|------|--------|---------|
| `decomposer.decompose` | `plan_id`, `goal_len`, post-record `child_count`, `outcome` | Top-level decomposition span. **Outcomes:** `ok`, `cycle_detected`, `llm_failed`, `workspace_scan_failed`, `parse_failed`. Read the outcome field first — it tells you which branch failed. |
| `decomposer.try_llm_once` | `system_chars`, `user_chars` | The LLM call. err line carries the model error. |
| `decomposer.detect_cycles` | `node_count` | If outcome is `cycle_detected`, this span fired and the err details which Works form the cycle. |
| `decomposer.collect_workspace_tree` | `target`, post-record `tree_chars` | Reads the target repo's file tree for the system prompt. |

**Integrator (Bundle -> merge -> Tick):**

| Span | Fields | Meaning |
|------|--------|---------|
| `integrator.integrate` | `bundle_id`, `phase` | Walks `preflight` -> `git_sequence` -> `commit`. The phase recorded last in `event.log` is where it stopped. |
| `integrator.transition_bundle` | `bundle_id`, `from`, `target` | FSM transition for a bundle. Failure here means the bundle's status couldn't move (e.g., reviewer rejected). |
| `integrator.fail_all` | `bundle_id`, `count` | The "fail every Work in this bundle" path. If you see this, integration aborted partway through. |

**Store (every record-level op):**

| Span | Fields | Meaning |
|------|--------|---------|
| `store.<op>` | `record_kind`, `record_id`, `op` | Every read/write/list. `op=write` on a hot path with err lines = JSONL append failure (disk full, permission, corruption). `op=list` lines record `count` post-query. |

**Worktree:**

| Span | Fields | Meaning |
|------|--------|---------|
| `worktree.create` | post-record `seq`, `branch` | Sibling worktree allocation. `seq` collisions on retry mean the registry is wedged. |
| `worktree.ops.<name>` | per-op keys | Lifecycle ops (cleanup, sweep, prune). |

**Context (prompt assembly):**

| Span | Fields | Meaning |
|------|--------|---------|
| `context.implementer.build_for_implementer` / `..._reviewer` | `iteration`, post-record `system_chars`, `user_chars`, `token_estimate` | Prompt assembly. Token estimate climbing past your model's window = prompt-cap fired. |

**LLM:**

| Span | Fields | Meaning |
|------|--------|---------|
| `llm.complete_*` | model, latency_ms, prompt/completion tokens | The actual API call. |
| `llm.classify_response` / `llm.classify_free_response` | classification keys | Did the response shape match expectations (tool_use vs free text)? |

**Daemon and IPC:**

| Span | Fields | Meaning |
|------|--------|---------|
| `daemon.run_active`, `daemon.serve_core`, `daemon.build_context` | `target`, `session_id`, `process_id`, `target_slug`, `pid` | Daemon startup; the err line carries every identifier needed to correlate XDG paths. |
| `daemon.spawn_implementer_for_work` / `..._reviewer_for_bundle` / `..._integrator_for_bundle` | `work_id`/`bundle_id`, status fields | When the daemon kicks off each agent. |
| `daemon.reconcile`, `daemon.sweep_worktrees` | counts | The reactive loop's housekeeping passes. |
| `ipc.dispatch` | `request_id`, `method`, `handshake_state` | Every request the daemon serves. |
| `ipc.plan_create` | `goal_len`, post-record `plan_id` | The `loopr plan "..."` IPC call. If this never appears, the client never reached the daemon. |
| `ipc.record_list` / `ipc.record_get` / `ipc.status` | `kind` / `record_id` | List and read calls. |
| `client.connect` / `client.handshake` / `client.request` | socket path, method, `session_id` | Client-side spans (these go to the client process's own events.log under a separate process-id). |

### 7. Reporting cadence

After each poll:

- **Phase:** Decomposing? Implementing work N of M? Reviewing? Integrating?
- **Counts:** plans / works / bundles / ticks (with status spread).
- **Span signal:** the most recent meaningful span line (lifeguard escalation, integrator phase, store error, etc.). Quote it verbatim with timestamp.
- **Anomalies:** lifeguard fires, parse failures, decomposer outcome != `ok`, integrator stuck at the same phase across polls, repeated reviewer rejections, recurring 401/429 from `llm.complete_*`.

### 8. Final report

On exit, summarize:

- Exit code: `0` (Tick landed + verify ok), `1` (timeout), `3` (verify failed).
- Tick landed? If yes, the merge commit hash from `git -C <run> log --oneline main`.
- Plan / Work / Bundle counts and final statuses.
- For each Work that did NOT complete: the lifeguard / parser / store error from events.log, with timestamp.
- Verification result: did `--version` (or the target's verify step) pass?
- Snapshot file: `<run>/.monitor/results.md`.
- Optional Claude evaluation: `<run>/.monitor/evaluation.md` (only when `claude` CLI is available and `--skip-eval` was not passed).

When relevant, render a **Hierarchy Document Summary** by reading the per-record summary.md and transcript files under `<run>/.loopr/records/`:

```
pl-abcde (Add --version flag) — status: complete
└── wk-fghij (Add --version to main.rs) — status: integrated
    ├── transcript.md — N iterations
    └── summary.md
└── wk-klmno (Add version test) — status: integrated
    └── transcript.md — N iterations

bd-pqrst (Bundle 0) — status: integrated
└── review.md
```

## Key Paths (v5)

| What | Where |
|------|-------|
| E2E script | `~/repos/scottidler/loopr-v5/bin/e2e` |
| Target PRDs | `~/repos/scottidler/loopr-v5/bin/e2e-targets/*.md` |
| Run dir | `/tmp/loopr/e2e/<target>/<YYYYMMDD-HHMMSS>/` |
| Latest symlink | `/tmp/loopr/e2e/<target>/latest` |
| Loopr binary | `~/.cargo/bin/loopr` |
| Per-process events.log | `<run>/.loopr/runs/<process-id>/events.log` |
| Per-session fanout log | `<run>/.loopr/runs/<process-id>/sessions/<session-id>/session-fanout.log` |
| TaskStore | `<run>/.loopr/taskstore/{plans,works,bundles,ticks}.jsonl` |
| Per-record summaries | `<run>/.loopr/records/<kind>/<id>/summary.md` |
| Per-record transcripts | `<run>/.loopr/records/<kind>/<id>/transcript.md` (or `decomposition.md` / `review.md`) |
| Worktrees | `<run>/.loopr/worktrees/` |
| Daemon socket | `<run>/.loopr/socket` |
| Daemon PID | `<run>/.loopr/daemon.pid` |
| Daemon process-id | `<run>/.loopr/daemon.process-id` |
| Active session pointer | `<run>/.loopr/active-session` |
| XDG sessions root | `~/.local/share/loopr/sessions/` |
| Results snapshot | `<run>/.monitor/results.md` |
| Claude evaluation | `<run>/.monitor/evaluation.md` |

## Important

- **Always read `events.log` first.** Every span you need is there. The point of the 2026-04-24 sweep was that you should never need `-l debug` to diagnose a failure.
- **Never use `cd`.** Use absolute paths or `git -C <dir>` syntax.
- **Active monitoring is the whole point.** Do not fire-and-forget.
- **Report early and often.** Quote span lines verbatim with timestamps.
- **Diagnose failures in real time.** If a lifeguard escalation lands, name the action_hash and the spans surrounding it before the run finishes.
- **`bin/e2e` exercises the installed binary** at `~/.cargo/bin/loopr`. Use `--build` when you want to refresh from this workspace before running.

## ABSOLUTE RULE: Never write code during an e2e run

The purpose of `/e2e` is to **gather telemetry** and **report what happened**. It is not a debugging or fix session.

**NEVER:**
- Edit source files in `~/repos/scottidler/loopr-v5/` or in the run dir.
- Run `cargo install` to apply a fix mid-run.
- Commit or push changes.
- Modify any config or script.

**ALWAYS:**
- Observe, log, and report.
- Describe failures with file/line/span/timestamp detail.
- Stop after the final report and wait for the user to decide next steps.

If you find a bug during monitoring: **name it, quote the span line, stop**. The user decides whether and how to fix.
