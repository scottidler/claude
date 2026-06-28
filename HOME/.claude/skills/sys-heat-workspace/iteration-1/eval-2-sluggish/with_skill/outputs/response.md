# sys-heat: System Sluggishness Investigation

## Phase 1: Snapshot

**Uptime / Load averages**
```
13:47:18 up 28 days, 3:18, 30 users
load average: 2.27 (1m) / 11.06 (5m) / 18.69 (15m)
```

The load is dropping from a spike — 18.69 at 15m, now down to 2.27. The machine took a hit in the past ~15 minutes and is recovering. For a dual-socket machine (normal idle ~2-5), a 5m load of 11 is significant but not catastrophic. It is actively subsiding.

**CPU Temperatures**
- Package 0: +54.0°C (high=82°C, crit=92°C) — nominal
- Package 1: +60.0°C (high=82°C, crit=92°C) — slightly elevated, well within safe range
- GPU edge: +63.0°C (crit=105°C) — normal
- GPU fan (fan1): 974 RPM — idle-range GPU fan; CPU fans are on a separate controller, not visible to lm-sensors

No thermal alerts. The sluggishness is load-driven, not temperature-driven.

**Fan RPM**
- fan1 (GPU): 974 RPM — normal idle. CPU fans are on a separate hardware controller and are invisible to lm-sensors. If the user heard fan noise, it was the CPU fans responding to the earlier load spike.

**Compiler processes**
- `rustc`/`cc1plus`/`cmake`: **0 active** — no build in progress now.

---

## Phase 2: Cause — Review Panel Burst

The load spike was caused by a fan-out of AI review agents launched simultaneously (the review-panel skill), all doing heavy reasoning work. Two classes of processes drove it:

### Active now (residual from burst, winding down)
| Process | PID | %CPU | Notes |
|---|---|---|---|
| Chrome renderer | 1242389/1242391 | 133% + 111% each | Transient spike, new renderers on page load |
| codex (staff-engineer gpt-5.5) | 1238837 | 36% | Reviewing marquee MCP design doc |
| codex (staff-engineer gpt-5.5) | 1212187 | 23.5% | Reviewing second-brain slide-filtering design doc |
| gemini (architect, gemini-3.1-pro-preview) | 1240276 | 22.8% | Reviewing marquee MCP design doc |
| firefox | 3844178 | 24.2% | Background, chronic low load (~563 hours CPU lifetime) |
| sb cortex daemon | 1199155 | 12–20% | Obsidian vault cortex indexing daemon (spike in progress) |
| sccache | 775139 | 12% | Compiler cache daemon, persistent |
| claude (multiple) | ~8 instances | 7–20% each | Active claude sessions across multiple ptys |

### Process tree: review-panel triggered the burst

```
pts/NN (claude session)
└── /usr/bin/zsh -c [review-panel script]
    ├── timeout 600 staff-engineer/script.sh  [second-brain slide-filtering doc]
    │   └── codex exec gpt-5.5 --model_reasoning_effort=high (PID 1212187, ~24% CPU)
    └── timeout 600 staff-engineer/script.sh  [marquee MCP doc]
        └── codex exec gpt-5.5 --model_reasoning_effort=high (PID 1238837, ~36% CPU)
```

A second gemini (architect) process (PID 1240276, ~23% CPU) ran in parallel for the marquee MCP doc.

**What happened:** Two review-panel invocations (one for each design doc: `2026-06-28-content-aware-slide-filtering.md` and the marquee MCP doc) launched their architect+staff-engineer pairs in parallel. Each codex/gemini process runs at `model_reasoning_effort=high`, which is CPU-intensive during the reasoning/streaming phase. Combined with 8+ active claude sessions (each sustaining 7–20% CPU), plus the sb cortex daemon indexing the vault (12–20% CPU), the aggregate pushed the 15-minute load above 18.

### Otto context

No active otto builds. The last recent otto run was `tatari-tv/clyde/main` (tasks: bloat, check, ci, lint, test) and `tatari-tv/marquee/main` (lint, plugin-guard) — both completed. No cargo file-lock contention detected.

### sccache

Stats show 4814 compile requests since the daemon started, 61.6% hit rate. This is historical data, not an active build. sccache is idle-serving cache reads.

---

## Summary

**Root cause:** A review-panel burst — two simultaneous design-doc review invocations, each spawning parallel codex (gpt-5.5 high-effort) + gemini reviewer processes — combined with 8+ active claude sessions and the sb cortex daemon doing vault indexing, pushed the load average to ~18 roughly 15 minutes ago. As of measurement time the load is actively recovering (2.27 at 1m). No Rust/C++ build is running, no cargo contention, no thermal threat. The system is sluggish because it has a lot of ongoing AI agent work, not because of a single hung or runaway process.

**No action needed unless:** the load doesn't continue dropping. If it stalls, the codex (PID 1212187, 1238837) and gemini (PID 1240276) review processes are the primary remaining CPU consumers. They will exit when their reviews complete (both have 600s timeouts).

**Watch command** (if you want to monitor until they finish):
```bash
while true; do
  procs=$(ps aux | grep -E "codex|gemini" | grep -v grep | wc -l)
  load=$(uptime | grep -oP 'load average: \K[^,]+')
  pkg0=$(sensors 2>/dev/null | grep "Package id 0" | grep -oP '\+\K[0-9.]+')
  pkg1=$(sensors 2>/dev/null | grep "Package id 1" | grep -oP '\+\K[0-9.]+')
  echo "$(date +%H:%M:%S) | load: $load | pkg0: ${pkg0}°C pkg1: ${pkg1}°C | ai-review procs: $procs"
  [ "$procs" -eq 0 ] && echo "REVIEWS DONE" && break
  sleep 15
done
```
