# Fan Spike Investigation — 2026-06-28 ~13:47

## Phase 1: Snapshot

**Load averages (captured at 13:47)**
- 1m: 2.39 | 5m: 11.23 | 15m: 18.79

The 1m load was already dropping when this investigation started, but the 5m/15m tell the story: the machine peaked hard in the 13:25–13:45 window and is still winding down.

**CPU Package temps (dual-socket)**
- Package id 0: 54°C → later 70°C (high=82°C, crit=92°C)
- Package id 1: 60°C → later 83°C [BREACHED high threshold briefly]

Package id 1 touched 83°C at ~13:56 — 1°C over the 82°C high threshold. It settled back to 81°C shortly after. No thermal emergency, but it explains the CPU fans spinning hard: the CPU fan controller (not visible to lm-sensors) was responding to that socket.

**GPU fan (only fan visible to lm-sensors)**
- fan1: ~960–974 RPM — normal idle range. GPU was idle (PPT: 8W, clocks near minimum).

Note: The CPU fans that you actually heard are on a separate controller and are not reported by lm-sensors. The data above confirms the CPU sockets got hot — trust your ears.

**Compiler proc count at capture time:** 0 (builds had just finished)

---

## Phase 2: Root Cause — Two Concurrent Builds

Two separate Rust builds ran in the 13:07–13:42 window:

### Build 1: `tatari-tv/clyde/main` — `otto ci` (13:07–13:17)
Nine separate otto invocations hit clyde/main in a tight window:

| Time  | Run timestamp |
|-------|--------------|
| 13:07 | 1782677223   |
| 13:07 | 1782677240   |
| 13:08 | 1782677308   |
| 13:08 | 1782677325   |
| 13:09 | 1782677354   |
| 13:12 | 1782677558   |
| 13:13 | 1782677598   |
| 13:17 | 1782677836   |
| 13:17 | 1782677849   |

**Cargo file lock contention confirmed** — the `check` and `test` tasks in run `1782677849` both logged:

```
Blocking waiting for file lock on package cache
Blocking waiting for file lock on package cache
Blocking waiting for file lock on build directory
```

This is the classic concurrent-otto-invocations-in-same-repo problem: multiple claude sessions or agents hammering `otto` on clyde/main simultaneously. Each retried invocation had to wait for cargo's build directory lock before it could compile. The rapid-fire sequence (9 runs in 10 minutes) with task sets like `{bloat, check, ci, lint, test}` caused significant sustained CPU load.

### Build 2: `scottidler/second-brain/main` — `otto ci` then `otto deploy` (13:25–13:42)
- **Run 1782678308** (13:25–13:34): tasks `{bloat, check, lint, test}` — full CI with compilation. The `test` task compiled from scratch (cold build visible in stderr: hundreds of crates from `unicode-ident` through all workspace members).
- **Run 1782678892** (13:34–13:35): tasks `{bloat, check, ci, lint, test}` — another full CI pass.
- **Run 1782678952** (13:35–13:42): `deploy` task — **release build**, took 4m 58s per the log: `Finished release profile [optimized] target(s) in 4m 58s`. This compiled the full second-brain workspace in `--release` mode (vault, distillers, oracle, cortex, borg). Peak load aligned with this window.

These two build sequences did not directly overlap (clyde finished at 13:17, second-brain started at 13:25), but they stacked on top of the **`sb cortex` daemon restart** that followed.

### Contributing: `sb cortex` daemon restart (13:42 → ongoing)
The second-brain deploy restarts the cortex daemon. `sb cortex` was launched at 13:42 and has been running hot ever since — 131%+ CPU, growing from ~750MB to 2.3GB RSS. It was re-indexing/embedding the Obsidian vault after the new binary was installed. This is the residual load keeping the 5m/15m averages elevated.

### Contributing: Multiple Codex (`staff-engineer`) agents (ongoing)
Three concurrent `codex exec -m gpt-5.5` processes (PIDs 1212187, 1238837, 1256747) were each running the staff-engineer review persona at 20–28% CPU each. One was reviewing the second-brain slides design, another was auditing the clyde sessions-search-sort implementation. These are IO/network-bound but do run rg/read extensively.

### Contributing: 8+ concurrent `claude` processes
14 `claude` processes active at investigation time, collectively accounting for ~100%+ CPU load. This is the normal background load from parallel agentic workflows.

---

## Current State (13:56)

- Load: 8.88 / 7.36 / 13.12 — still above idle baseline but trending down
- Package id 1: 81°C (back just below the 82°C high threshold)
- Package id 0: 65°C (normal)
- `sb cortex` daemon: still running at ~130% CPU, 2.3GB RSS — still re-indexing. This will complete on its own and load will return to the ~2–5 idle baseline.
- No active compiler processes.

---

## Summary

The fans spiked because of a **release build of second-brain** (4m 58s, ~13:35–13:42), preceded by a **clyde/main CI storm** (9 rapid-fire otto invocations with cargo file lock contention, 13:07–13:17), and followed by a **sb cortex daemon restart + full vault re-index** that is still running.

No thermal emergency — Package id 1 touched 83°C briefly (1°C over the high threshold) but is already settling. No action required; the cortex re-index will finish on its own and load will drop.

The file lock contention in clyde/main is worth noting: 9 concurrent otto invocations from what appears to be multiple claude agents hammering the same repo in rapid succession. If that pattern repeats, consider whether the calling agents should serialize or check for an in-progress otto run before launching.
