---
name: e2e
description: Run loopr E2E tests with active monitoring. Use when the user says "e2e", "run e2e", "run bin/e2e", "test lua-todo", "test python-todo", "test react-todo", "test rust-version", "test python-api", "test node-api", "test rust-cli", "test python-scraper", or asks to run an end-to-end experiment.
allowed-tools: Bash, Read, Grep, Glob, Agent
---

# Loopr E2E Test Runner with Active Monitoring

Run `bin/e2e` against a target and actively monitor the loopr process throughout the run. Report successes and failures early and often.

## Usage

```
/e2e                    # default: rust-version
/e2e lua-todo           # specific target by name
/e2e python-api
/e2e node-api
/e2e rust-cli
/e2e python-scraper
/e2e python-todo
/e2e react-todo
/e2e rust-version
```

To see all available targets: `bin/e2e ls`

## Available Targets

Defined in `bin/e2e-targets/`. Run `bin/e2e ls` to list them all with goals and timeouts.

Current targets:
- `rust-version` (default, 600s) - trivial: add --version flag
- `lua-todo` (900s) - Lua CLI todo app
- `python-todo` (900s) - Python CLI todo app
- `react-todo` (1200s) - Vite + React + Tailwind todo app in Docker
- `python-api` (1200s) - FastAPI + SQLite bookmarks API in Docker
- `node-api` (1200s) - Express + SQLite notes API in Docker
- `rust-cli` (1200s) - multi-subcommand notes CLI with clap + rusqlite
- `python-scraper` (1200s) - HTML link harvester with SQLite report in Docker

## Execution Steps

### 1. Kill any existing E2E run first

**Always kill before launching.** If a prior run is active, it must be cleaned up first:

```bash
pkill -f 'bin/e2e' 2>/dev/null
pkill -f 'loopr.*daemon' 2>/dev/null
pkill -f 'loopr.*run' 2>/dev/null
pkill -f 'check-loopr' 2>/dev/null
pkill -f 'tee.*loopr/e2e' 2>/dev/null
sleep 2
echo "cleanup done"
```

Also prune leftover Docker networks from prior runs to avoid address pool exhaustion:

```bash
docker network prune -f
```

### 2. Launch the E2E script in the background

Pre-create the log directory so `tee` works from the start:

```bash
mkdir -p /tmp/loopr && /home/saidler/repos/scottidler/loopr/bin/e2e <TARGET> 2>&1 | tee /tmp/loopr/e2e-output.log
```

Use Bash `run_in_background: true` so you can monitor while it runs.

### 3. Actively monitor while it runs

Do NOT just wait for the script to finish. Poll these sources every 30-60 seconds and report what you find.

**IMPORTANT: Never use `cd` in Bash commands. Use absolute paths throughout.**

**E2E script output:**
```bash
tail -20 /tmp/loopr/e2e-output.log
```

**Session log (all daemon + decomposer activity - the primary log):**
```bash
tail -50 ~/.local/share/loopr/sessions/latest/loopr.log
```

Note: `/tmp/loopr/e2e/<TARGET>/latest/daemon.log` exists but is always 0 bytes — ignore it.

**Agent sessions:**
```bash
/home/saidler/repos/scottidler/loopr/target/release/loopr --config /tmp/loopr/e2e/<TARGET>/latest/loopr.yml agent list
```

**Work items and bundles:**
```bash
/home/saidler/repos/scottidler/loopr/target/release/loopr --config /tmp/loopr/e2e/<TARGET>/latest/loopr.yml work list
/home/saidler/repos/scottidler/loopr/target/release/loopr --config /tmp/loopr/e2e/<TARGET>/latest/loopr.yml bundle list
```

**Git state (worktrees and commits):**
```bash
git -C /tmp/loopr/e2e/<TARGET>/latest log --oneline --all
git -C /tmp/loopr/e2e/<TARGET>/latest worktree list
```

**Per-agent logs (implementers, coordinator, etc.):**
```bash
ls -t ~/.local/share/loopr/logs/agents/ | head -10
# Read most recent implementer log:
tail -50 ~/.local/share/loopr/logs/agents/$(ls -t ~/.local/share/loopr/logs/agents/ | grep implementer | head -1)
# Read most recent coordinator log:
tail -50 ~/.local/share/loopr/logs/agents/$(ls -t ~/.local/share/loopr/logs/agents/ | grep coordinator | head -1)
```

Note: Log filename formats differ by agent type:
- Coordinator: `agent-coordinator-<ULID>.log`
- All others: `<type>-ag-<id>.log` (e.g. `implementer-ag-xxxxx.log`, `reviewer-ag-xxxxx.log`)

**LLM conversation logs (only present at DEBUG log level):**
```bash
ls -la ~/.local/share/loopr/sessions/latest/conversations/ 2>/dev/null
```

When the `conversations/` directory exists, it contains full LLM request/response pairs per domain action. Each file is named by context: `implement-<work_id>.log`, `coordinate-<session_id>.log`, `review-<session_id>.log`, `research-<session_id>.log`. These are invaluable for diagnosing bad decomposition or off-track implementer behavior:
```bash
# List conversation logs by size (largest = most LLM calls)
ls -lhS ~/.local/share/loopr/sessions/latest/conversations/ 2>/dev/null
# Read the last request/response pair from a specific implementer
tail -100 ~/.local/share/loopr/sessions/latest/conversations/implement-wk-*.log 2>/dev/null | head -100
```

Note: Conversation logs are only created when `--log-level debug` is set. At the default INFO level, the `conversations/` directory is not created. E2E runs that use `--log-level debug` in their target definition will have these logs.

### 4. Report pattern

After each monitoring poll, give a concise status update:
- What phase the orchestrator is in (planning, implementing, reviewing, integrating)
- How many work items exist and their statuses
- Any bundles proposed/accepted/rejected
- Any errors or warnings from daemon log
- Git commits made in worktrees
- Whether things are progressing or stuck

Flag problems immediately:
- Death loops (same work cycling through Ready -> InProgress -> Ready)
- Noop bundles with no commits
- Repeated reviewer rejections
- Agent session failures
- 401 auth errors (transient, but note them)
- Timeout approaching with no progress

### 5. Final report

When the script completes, summarize:
- Exit code and meaning (0=GoalComplete, 1=Timeout, 2=NeedHelp)
- Total agent sessions spawned
- Work items: how many completed vs failed
- Bundles: how many accepted vs rejected
- Key commits merged to main
- What went right, what went wrong
- Actionable next steps if it failed

If conversation logs exist, include a **Conversation Log Summary** listing each file with its size and line count:
```bash
wc -l ~/.local/share/loopr/sessions/latest/conversations/*.log 2>/dev/null
```
Note any particularly large files (many LLM round-trips) or suspiciously small ones (agent may have failed early).

Then produce a **Hierarchy Document Summary** — a tree view of all docs in the run, rendered using box-drawing characters. Read each file to extract its frontmatter (`title:`, `status:`, `spec_index:`, `phase_index:`) and render the full hierarchy as a tree:

```
## Hierarchy Document Summary

**Docs path:** /tmp/loopr/e2e/<TARGET>/latest/docs/loopr/

pl-rqcu4 (Python Bookmarks API)
├── sp-ttvp3 (Spec 0: Database Layer) — status: Complete
│   └── ph-iguop (Phase 0: Schema Bootstrap) — status: Complete
│       ├── wk-0cvgf (Create database.py skeleton) — Done
│       └── wk-ab12c (Write tests for database) — Done
│
└── sp-xy789 (Spec 1: API Routes) — status: Active
    ├── ph-mn456 (Phase 0: Application Module) — status: Active
    │   ├── wk-p1234 (Pydantic Models + FastAPI Scaffold) — Done
    │   └── wk-q5678 (CRUD Route Handlers) — InReview
    │
    └── ph-rs901 (Phase 1: Test Suite) — status: Active
        ├── wk-t2345 (Isolation Fixture + Health Tests) — Blocked
        └── wk-u6789 (Happy-Path Tests) — Ready
```

**Format rules:**
- Plan line: `<id> (<title>)` — no status, it's the root
- Spec lines: `<id> (Spec <N>: <title>) — status: <status>`
- Phase lines: `<id> (Phase <N>: <title>) — status: <status>`
- Work lines: `<id> (<title>) — <status>`
- Use `spec_index` / `phase_index` frontmatter for ordering; fall back to filename sort
- Blank line between sibling specs for readability
- IDs are the bare prefix without `.md` (e.g. `pl-rqcu4`, not `pl-rqcu4.md`)

To gather the files:
```bash
find /tmp/loopr/e2e/<TARGET>/latest/docs/loopr/ -name "*.md" 2>/dev/null | sort
```

Read each file (use Read tool, not cat) and extract the frontmatter fields needed to build the tree. Assemble the full hierarchy before printing — do not print a flat list.

Also check the fallback location (legacy, may be empty):
```bash
find /tmp/loopr/e2e/<TARGET>/latest/.loopr/runs/ -name "*.md" 2>/dev/null | sort
```

## Key Paths

Each run gets a timestamped directory: `/tmp/loopr/e2e/<target>/<YYYYMMDD-HHMMSS>/`
A `latest` symlink always points to the most recent run.

| What | Where |
|------|-------|
| E2E script | `/home/saidler/repos/scottidler/loopr/bin/e2e` |
| Target definitions | `/home/saidler/repos/scottidler/loopr/bin/e2e-targets/` |
| Run directory | `/tmp/loopr/e2e/<target>/<timestamp>/` |
| Latest symlink | `/tmp/loopr/e2e/<target>/latest` |
| Daemon log | `/tmp/loopr/e2e/<target>/latest/daemon.log` |
| Config | `/tmp/loopr/e2e/<target>/latest/loopr.yml` |
| Session log (unified) | `~/.local/share/loopr/sessions/latest/loopr.log` |
| Session summary | `~/.local/share/loopr/sessions/latest/summary.md` |
| LLM conversations (DEBUG only) | `~/.local/share/loopr/sessions/latest/conversations/` |
| Per-agent logs (coordinator) | `~/.local/share/loopr/logs/agents/agent-coordinator-<ULID>.log` |
| Per-agent logs (others) | `~/.local/share/loopr/logs/agents/<type>-ag-<id>.log` |
| Loopr binary | `/home/saidler/repos/scottidler/loopr/target/release/loopr` |

## Important

- **Kill existing runs before launching.** Always. No exceptions.
- **Never use `cd` in Bash commands.** Use absolute paths or `git -C <dir>` syntax.
- **Active monitoring is the whole point.** Do not fire-and-forget.
- **Report early and often.** The user wants to see progress, not just a final summary.
- **Diagnose failures in real time.** If you see a problem forming, call it out immediately.
- Target timeouts vary (600s-1200s). Run `bin/e2e ls` to see each target's timeout. Monitor throughout.

## ABSOLUTE RULE: Never write code during an e2e run

The purpose of `/e2e` is to **gather telemetry** and **report what happened**. It is not a debugging or fix session.

**NEVER:**
- Edit source files
- Run `cargo build` to apply a fix
- Commit or push changes
- Modify any config or script

**ALWAYS:**
- Observe, log, and report
- Describe failures with file/line/root-cause detail
- Stop after the final report and wait for the user to decide next steps

If you find a bug during monitoring: **name it, describe it, stop**. The user will decide whether and how to fix it.
