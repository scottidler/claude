# CPU Sluggishness Investigation — desk.lan

**Investigated:** 2026-06-28 ~13:47 local time  
**Machine:** desk.lan, Linux, 32 cores, 94 GiB RAM, 16 GiB swap

---

## Immediate Findings

### Load Average
```
 13:49:42 up 28 days,  3:18, 30 users
 load average: 10.07, 11.33, 17.69
```
The 15-minute load (17.69) is well above the 32-core threshold. The 1-minute load (10.07) shows the system is still elevated but recovering from a worse spike. Something hammered the machine ~15-30 minutes ago and the tail is still working through.

---

## Root Causes (Ranked)

### 1. Swap Exhaustion — The Primary Sluggishness Driver

**Swap: 15.7 GiB / 16 GiB used (98% full)**

```
SwapTotal:      16777212 kB
SwapFree:         301432 kB
```

Total swap consumed by processes: **~14.5 GiB**. When swap is full, the kernel stalls on memory allocation, causing visible latency spikes even for CPU-bound tasks. The `sda` disk shows active I/O (14 ops/sec) which is the swap device churning.

**Top swap consumers:**
| Process | PID | Swap Used |
|---------|-----|-----------|
| rust-analyzer | 2439093 | 2.1 GiB |
| clamd | 1868 | 940 MiB |
| gnome-shell | 10700 | 729 MiB |
| obsidian | 507019 | 434 MiB |
| rust-analyzer | 774904 | 431 MiB |
| zoom | 638910 | 396 MiB |
| firefox-bin | 3844178 | 266 MiB |
| Telegram | 506394 | 238 MiB |
| sb (oracle) | 2388932 | 226 MiB |
| spotify | 1185223 | 213 MiB |
| slack (×2) | multiple | ~350 MiB |
| claude (×14) | multiple | ~700 MiB combined |

The oldest rust-analyzer (PID 2439093, running 15+ hours, working on the `tatari-tv` backstage/catalog repo) has 2.1 GiB cold in swap and 0.2% CPU — it's a zombie analyzer from an old session that is just sitting there occupying swap.

### 2. Fourteen Claude Processes — ~108% CPU Combined

```
14 claude processes × avg ~7.7% CPU each = ~108% total CPU
```

PIDs: 223737 (7.4%), 278028 (12.6%), 377698 (10.9%), 381475 (8.5%), 505644 (8.9%), 986034 (19.6%), 1065832 (19.7%), plus 7 more. Each claude instance spawns `sb oracle serve` as a subprocess, multiplying the footprint. This is the direct CPU load.

### 3. sccache — Active Rust Build (Winding Down)

PID 775139, running for 42 minutes, processed **4,814 compile requests** (1,164 cache misses = actual compilations). Currently at 12% CPU but the build itself appears done — no active `rustc` processes. sccache stays resident as a server. This was a significant contributor to the earlier spike (15-minute load of 18.35).

### 4. sb cortex Daemon — 20% CPU, Just Started

PID 1199155, started at 13:42 (5-6 minutes ago), consuming 19-20% CPU with 42 threads and 1.2 GiB RSS. It is doing initial embedding/indexing work on the Obsidian vault. This will settle once the initial pass completes.

### 5. Firefox Main Process — Long-Running, 24% CPU

PID 3844178, cumulative 2743 minutes of CPU (45+ hours), currently 24% CPU. This is high for a browser main process and suggests tab/extension churn or a JS-heavy page.

---

## Summary

The sluggishness has two layers:

1. **Swap thrashing (primary):** Swap is 98% full. The biggest contributor is a stale rust-analyzer (PID 2439093) from a 15-hour-old session with 2.1 GiB cold-swapped. clamd, gnome-shell, obsidian, zoom, and many other background apps collectively fill the rest. When the kernel needs to swap pages in/out, everything stalls.

2. **CPU saturation (secondary):** 14 concurrent claude sessions + a completed Rust build + newly-started sb cortex daemon collectively drove load average to ~18 on a 32-core machine. The system is recovering; 1-minute load is dropping.

---

## Recommended Actions

1. **Kill the stale rust-analyzer:** `kill 2439093` — frees 2.1 GiB of swap immediately.
2. **Review open claude sessions:** 14 concurrent instances is unusually high. Close finished sessions to free CPU and swap.
3. **Wait for sb cortex to finish indexing** — it will settle to near-zero CPU once the initial pass completes.
4. **Consider adding swap space** or closing long-running GUI apps (Obsidian, Zoom, Telegram) if swap pressure persists.
5. **Firefox:** close unused tabs or restart to reclaim the 272 MiB swapped and bring CPU down.
