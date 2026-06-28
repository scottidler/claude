# Load Investigation — desk.lan

**Captured:** 2026-06-28 ~13:48 local

## Load Averages

```
13:48:22 up 28 days,  3:19 — load avg: 6.87 (1m), 10.63 (5m), 18.02 (15m)
```

32 logical CPUs. Current 1m load (6.87) is already dropping from the prior peak (18.59 seen earlier). The spike was real but is now unwinding.

## What Caused It

No Rust compilation is happening right now. No `cargo build`, `rustc`, or `cc` processes are running. `sccache` is idle at 12% — it's running but not being fed work.

The load was driven by a pile-on of concurrent AI agent processes, all launched around the same time window:

### Biggest contributors (aggregated)

| Category | Approx CPU% |
|---|---|
| 17 x `claude` processes | ~158% |
| `codex` (Staff Engineer reviewer) | ~56% |
| Firefox | ~37% |
| `sb cortex` daemon | ~26% |
| `sccache` (idle/standby) | ~12% |
| Spotify | ~14% |
| Slack | ~12% |
| `localsearch-extractor-3` | ~60% burst |
| `rust-analyzer` | ~5% |

### Root cause: the `codex` / Staff Engineer process

The single biggest non-browser offender is PID 1212187 — a `codex exec -m gpt-5.5` invocation running the Staff Engineer persona review agent. It was spawned at 13:45 and has been sitting at ~27–30% CPU continuously since then. It's doing a deep read-only codebase audit against a Rust repo and burning significant CPU on the codex binary itself.

### Secondary cause: 17 simultaneous `claude` sessions

There are 17 `claude` processes running in parallel (most with `--model opus`), collectively consuming ~158% CPU. These were started across the morning (as early as 08:44) and several are still actively running. No single session is a runaway, but the aggregate is substantial.

### `localsearch-extractor-3` (GNOME Tracker)

This spiked to ~60% in one sample — it's the GNOME file indexer (Tracker 3) waking up, likely triggered by new files being written by the claude/codex sessions. It's transient and already dropping.

### `sb cortex` daemon

Running since 13:42 at ~13–21% CPU. This is the second-brain cortex daemon doing embedding/classification work on the Obsidian vault, probably triggered by recent vault writes.

## Is It a Rust Build?

No active Rust compilation. `sccache --show-stats` shows 1164 completed compilations with 50% cache hit rate on Rust — those happened earlier (likely during cargo installs or builds triggered by the claude sessions), not right now. The `rust-analyzer` process (PID 398682) is running at ~2.5% and consuming 4.1% RAM (4GB), which is normal background indexing.

## Summary

The load spike (peak 18.59 at 15m) was caused by the simultaneous launch of many claude agent sessions + the `codex` Staff Engineer reviewer process all competing for CPU at once. Not a Rust compile. The 1m average is already recovering (6.87). The remaining pressure is the `codex` process still running its review and the `sb cortex` daemon classifying new vault content.
