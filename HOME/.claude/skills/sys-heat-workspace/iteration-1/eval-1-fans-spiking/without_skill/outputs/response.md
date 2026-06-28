# Fan Spike Investigation — desk.lan

## Root Cause

Two compounding problems: **swap exhaustion** and **massive CPU load from concurrent claude sessions**.

### Swap is nearly full

```
SwapTotal: 16 GiB
SwapFree:    291 MiB  ← almost gone
SwapUsed:   15.7 GiB
```

The system has 94 GiB RAM total, with 32 GiB used and 45 GiB in buffer/cache — but swap is nearly full anyway. That means something previously ate RAM heavily enough to push 15+ GiB to swap. With swap nearly exhausted, any new allocation pressure triggers heavy swap I/O, which is sustained work for the disk and pushes CPU and thermals up.

### 17 concurrent claude processes at ~108% combined CPU

```
claude processes: 17
total CPU%: ~108%
```

Individual claude processes are each consuming 8–20% CPU, running simultaneously. Combined with other heavy processes:

| Process | CPU% |
|---------|------|
| codex (OpenAI CLI) | 27% |
| Firefox | 24% |
| claude ×17 | ~108% total |
| sb cortex (sccache) | 12% each |
| Spotify renderer | 10% |
| gnome-shell | 6% |

Load average tells the story clearly:
```
1-min:  2.31
5-min:  10.63
15-min: 18.43
```

The 15-minute load of 18 means the machine was massively overloaded for an extended period — that sustained CPU + swap I/O is exactly what spikes fans.

### Current temps (sensors)

- CPU Package 0: 53°C, Package 1: 60°C — warm but within normal range (high = 82°C)
- GPU (amdgpu): edge 63°C, junction 64°C — normal
- NIC (i350bb): 68°C — elevated but within limits (high = 120°C)

Temps are coming down now (load average is dropping from 18 → 10 → 2), so fans were responding correctly to the earlier heat load.

## What Happened

The system had a sustained period of heavy load (load avg ~18 for 15+ minutes). The most likely trigger: opening many claude sessions concurrently while running codex + Firefox + Spotify, combined with a pre-existing swap exhaustion condition. The swap fullness means the OS has no buffer room and forces expensive swap I/O for any new allocations, compounding CPU load with disk I/O.

## What to Do

1. **Close idle claude sessions** — you have 17 running. Kill the ones you're not actively using.
2. **Investigate swap usage** — `smem -t` or `cat /proc/*/smaps | grep -i swap` to find what's holding swap. A machine restart would clear it entirely if that's acceptable.
3. **Watch for recurrence** — if fans spike again after closing sessions, the swap pressure alone may be the sustained driver.

Current state: load is trending down (2.31 now vs 18.43 fifteen minutes ago), temps are in normal range. The fans were doing their job.
