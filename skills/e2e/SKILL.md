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
pkill -f 'tee.*loopr-e2e' 2>/dev/null
sleep 2
echo "cleanup done"
```

### 2. Launch the E2E script in the background

```bash
/home/saidler/repos/scottidler/loopr/bin/e2e <TARGET> 2>&1 | tee /tmp/loopr-e2e-output.log
```

Use Bash `run_in_background: true` so you can monitor while it runs.

### 3. Actively monitor while it runs

Do NOT just wait for the script to finish. Poll these sources every 30-60 seconds and report what you find.

**IMPORTANT: Never use `cd` in Bash commands. Use absolute paths throughout.**

**E2E script output:**
```bash
tail -20 /tmp/loopr-e2e-output.log
```

**Daemon log:**
```bash
tail -30 /tmp/loopr-e2e/<TARGET>/latest/daemon.log
```

**Agent sessions:**
```bash
/home/saidler/repos/scottidler/loopr/target/release/loopr --config /tmp/loopr-e2e/<TARGET>/latest/loopr.yml agent list
```

**Work items and bundles:**
```bash
/home/saidler/repos/scottidler/loopr/target/release/loopr --config /tmp/loopr-e2e/<TARGET>/latest/loopr.yml work list
/home/saidler/repos/scottidler/loopr/target/release/loopr --config /tmp/loopr-e2e/<TARGET>/latest/loopr.yml bundle list
```

**Git state (worktrees and commits):**
```bash
git -C /tmp/loopr-e2e/<TARGET>/latest log --oneline --all
git -C /tmp/loopr-e2e/<TARGET>/latest worktree list
```

**Session logs (most recent):**
```bash
find ~/.local/share/loopr/sessions/ -name "*.log" -newer /tmp/loopr-e2e/<TARGET>/latest/loopr.yml | sort | tail -5
```

**Decomposer log (one per run, named by goal_id):**
```bash
find ~/.local/share/loopr/sessions/latest/agents/ -name "decomposer-*.log" | sort | tail -1 | xargs tail -50
```

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

Then cat every decomposer document from the run directory:

```bash
find /tmp/loopr-e2e/<TARGET>/latest/.loopr/runs/ -name "*.md" | sort | while read f; do
    echo "=== $f ==="
    cat "$f"
    echo ""
done
```

This surfaces the plan.md, spec.md, phase.md, and work.md files the decomposer produced so failures can be diagnosed directly from the LLM output.

## Key Paths

Each run gets a timestamped directory: `/tmp/loopr-e2e/<target>/<YYYYMMDD-HHMMSS>/`
A `latest` symlink always points to the most recent run.

| What | Where |
|------|-------|
| E2E script | `/home/saidler/repos/scottidler/loopr/bin/e2e` |
| Target definitions | `/home/saidler/repos/scottidler/loopr/bin/e2e-targets/` |
| Run directory | `/tmp/loopr-e2e/<target>/<timestamp>/` |
| Latest symlink | `/tmp/loopr-e2e/<target>/latest` |
| Daemon log | `/tmp/loopr-e2e/<target>/latest/daemon.log` |
| Config | `/tmp/loopr-e2e/<target>/latest/loopr.yml` |
| Session logs | `~/.local/share/loopr/sessions/` |
| Agent logs | `~/.local/share/loopr/sessions/<session_id>/agents/` |
| Decomposer log | `~/.local/share/loopr/sessions/<session_id>/agents/decomposer-<goal_id>.log` |
| Loopr binary | `/home/saidler/repos/scottidler/loopr/target/release/loopr` |

## Important

- **Kill existing runs before launching.** Always. No exceptions.
- **Never use `cd` in Bash commands.** Use absolute paths or `git -C <dir>` syntax.
- **Active monitoring is the whole point.** Do not fire-and-forget.
- **Report early and often.** The user wants to see progress, not just a final summary.
- **Diagnose failures in real time.** If you see a problem forming, call it out immediately.
- Target timeouts vary (600s-1200s). Run `bin/e2e ls` to see each target's timeout. Monitor throughout.
