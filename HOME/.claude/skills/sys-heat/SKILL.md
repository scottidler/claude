---
name: sys-heat
description: >
  Diagnose and monitor high system load, CPU temperature spikes, and fan noise on desk.lan.
  Invoke this skill whenever the user mentions fans spinning up or spiking, system sluggishness,
  high load average, "what's burning", "system hot", "check temps", "watch the build",
  "build wedged", or asks why the machine is loud/slow/hot. Also trigger on bare "check uptime"
  when combined with any thermal or load context. Covers the full investigation chain: snapshot
  load+temps via sensors, identify top CPU consumers, trace process trees to the triggering agent
  or build job, dig into otto run logs to confirm the cause, detect cargo file-lock contention,
  and watch until the build completes. Do NOT wait for the user to say "sys-heat" explicitly —
  fire on any sign of thermal or load distress.
---

# sys-heat

Investigate and monitor high CPU load and thermal events on this machine.

## Phase 1: Snapshot

Always run these first, in parallel:

```bash
uptime
sensors
ps aux --sort=-%cpu | head -20
```

Report:
- Load averages (1m / 5m / 15m) — context: this is a dual-socket machine, normal idle load is ~2-5
- CPU package temps from `sensors` — thresholds are `high=82°C`, `crit=92°C`
- Top CPU consumers by name and %CPU
- Compiler proc count: `ps aux | grep -E "rustc|cc1plus|cmake" | grep -v grep | wc -l`
- Fan RPM if visible: `sensors | grep -i fan` — note: only the GPU fan (fan1, ~960 RPM idle) is exposed; CPU fans are on a controller not visible to lm-sensors

## Phase 2: Identify the cause

If `rustc`, `cc1plus`, or `cmake` appear in the top consumers, this is a Rust/C++ build. Trace the parent chain:

```bash
ps auxf | grep -E "rustc|cargo|cmake|otto|cc1plus" | grep -v grep
```

Look for:
- Which repo's `target/` path appears in the rustc args (e.g., `second-brain/main/target/`)
- Which `otto` task spawned the cargo invocation
- Which Claude session (pts/NN) spawned otto

## Phase 3: Otto context (if an otto build is running or just finished)

Otto stores a run directory per invocation at `/home/saidler/.otto/<repo-hash>/`:

```bash
# Find the repo hash for a given repo
ls /home/saidler/.otto/

# List recent runs (sorted by timestamp dir name)
ls /home/saidler/.otto/<hash>/ | sort | tail -5

# For each recent run:
cat /home/saidler/.otto/<hash>/<timestamp>/run.yaml   # cwd, args, who invoked it
ls  /home/saidler/.otto/<hash>/<timestamp>/tasks/     # which tasks ran
```

`run.yaml` contains `cwd` (the repo), `args` (what otto was invoked with), and `timestamp`.

If multiple invocations ran close together, check if they overlapped — two concurrent otto runs in the same repo mean cargo contention. Confirm with:

```bash
grep -r "Blocking waiting for file lock" /home/saidler/.otto/<hash>/<timestamp>/tasks/*/stderr.log
```

If this string appears, two cargo invocations were fighting over the same build directory.

## Phase 4: Watch mode

If a build is still in progress and the user wants to watch it, use Monitor:

```
while true; do
  procs=$(ps aux | grep -E "rustc|cc1plus|cmake --build" | grep -v grep | wc -l)
  load=$(uptime | grep -oP 'load average: \K[^,]+')
  pkg0=$(sensors 2>/dev/null | grep "Package id 0" | grep -oP '\+\K[0-9.]+')
  pkg1=$(sensors 2>/dev/null | grep "Package id 1" | grep -oP '\+\K[0-9.]+')
  echo "$(date +%H:%M:%S) | load: $load | pkg0: ${pkg0}°C pkg1: ${pkg1}°C | compiler procs: $procs"
  [ "$procs" -eq 0 ] && echo "BUILD DONE" && break
  sleep 15
done
```

Report each tick to the user and notify when BUILD DONE.

## Known gaps

- **CPU fans**: lm-sensors only exposes `fan1` (the GPU fan, ~960 RPM idle). The CPU fans are on a separate controller not visible from Linux. If the user reports fans spiking but `fan1` looks normal, trust the user — the CPU fans are real but invisible to software.
- **Build cause**: Always read `run.yaml` and the otto task list before stating what triggered a build. Never guess based on process names alone.
- **Parallel cargo tasks**: `cargo check` and `cargo test` running in parallel via otto's `before:` list are intentional — they produce different artifact types and share the cargo cache. This is NOT "double compilation." Two separate `otto` invocations in the same repo IS a problem (leads to file lock contention).

## Available tools on this machine

- `sensors` — lm-sensors, shows CPU package/core temps and GPU fan
- `btop` — interactive process/resource monitor (TUI)
- `s-tui` — CPU frequency and temp TUI
- `turbostat` — Intel per-core frequency, temp, and power stats
- `sccache` — compiler cache daemon (already running as a service)
