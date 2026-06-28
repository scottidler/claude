# sys-heat: Cause Investigation

## Current State (13:47 PDT)

Load averages: **2.09 / 10.87 / 18.59** — spike is subsiding. Peak was ~20-40 minutes ago.

Temps: pkg0 56°C / pkg1 63°C — well within safe range (high=82°C). GPU fan at 974 RPM (idle baseline ~960).

Compiler procs now: **0** (build is done).

---

## Root Cause: Multiple Concurrent Rust CI Runs

**Not a single build — multiple overlapping otto invocations across two repos.**

### Repo 1: `tatari-tv/clyde/main` (primary spike contributor)

Between **01:07 and 01:17 PDT**, 6 separate `otto` invocations fired against clyde/main:

| Timestamp | Time (PDT) | Tasks |
|-----------|-----------|-------|
| 1782677223 | 01:07:03 | bloat, check, lint, test |
| 1782677240 | 01:07:20 | bloat, check, lint, test |
| 1782677308 | 01:08:28 | bloat, check, lint, test |
| 1782677325 | 01:08:45 | bloat, check, lint, test |
| 1782677354 | 01:09:14 | bloat, check, lint, test |
| 1782677558 | 01:12:38 | bloat, check, lint, test |

That's 6 concurrent/overlapping CI runs all compiling `tatari-tv/clyde` within a 6-minute window. Cargo file lock contention confirmed in runs 1782677836 and 1782677849:

```
Blocking waiting for file lock on package cache   (check, test tasks)
Blocking waiting for file lock on build directory (test task)
```

The sixth run (01:17:16) also got a compile error: `error: could not compile 'sessions' (lib test) due to 1 previous error` — a `dead_code` denial.

### Repo 2: `scottidler/second-brain/main` (secondary, overlapping)

Two more otto runs at **01:25 and 01:34 PDT** compiled second-brain's full workspace (borg, cortex, oracle, distillers, cortex). The `check` task took **6 minutes** and also hit file lock contention:

```
Blocking waiting for file lock on package cache
Blocking waiting for file lock on build directory
```

### What Spawned the Clyde Builds

The clyde otto runs were triggered from **pts/25** (PID 377698, `claude --model opus`). Multiple Claude agents iterating on clyde/main triggered CI in rapid succession — each triggering a new `otto` invocation before the previous one finished, causing cascading file lock waits and parallel compilation.

### What Spawned the Second-Brain Build

Second-brain builds came from the **review-panel** workflow running on pts/25 as well. The staff-engineer skill (PID 1212187, `codex exec`) is currently reviewing `docs/design/2026-06-28-content-aware-slide-filtering.md` — it spawned a compilation pass to verify code claims.

---

## Is It Still Running?

- `rustc`/`cargo`/`cc1plus` count: **0** — all builds done
- sccache confirms 1164 compilations (1034 Rust cache misses), consistent with a heavy build session
- The `sb cortex` daemon (PID 1199155) and `codex` (PID 1212187) are still running but not compiling
- Load is already dropping: 2.09 at time of check vs. 18.59 peak

**No further thermal concern.** Machine is cooling off.

---

## Summary

| Factor | Detail |
|--------|--------|
| Cause | 6+ overlapping `otto ci` runs on `clyde/main` + 2 on `second-brain/main` |
| Trigger | Claude agents on pts/25 (opus) firing rapid CI iterations |
| Evidence | `Blocking waiting for file lock on build directory` in check/test stderr.log |
| Duration | ~01:07–01:35 PDT (~28 minutes total) |
| Status | **Complete — load declining, no active compilers** |
