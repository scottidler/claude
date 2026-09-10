---
name: swap-alert
description: >
  Triage and fix a swap / memory-pressure alert on desk.lan. Fire this whenever the user
  says they got an ntfy (they often type "nfty") alert about swap, "swap at N%", "disk swap
  climbing/critical", "memory pressure critical", "risk of OOM", "swap is spiking", "why is
  swap full", or asks what is eating memory or swap. Runs one read-only triage script that
  answers: is this real pressure or stale pages parked in swap, which of the four known
  culprits (Firefox, rust-analyzer under a long-lived Claude session, the Claude/MCP fleet,
  dead swap after a pressure event) is responsible, and whether a swapoff/swapon drain is
  safe right now. Also covers reconstructing an alert that fired hours ago from atop logs,
  and tuning the alerter itself. Do NOT wait for the user to say "swap-alert".
---

# swap-alert

The alerter is `swap-watch.sh` (dotfiles `HOME/.local/bin/`, systemd user timer every 5 min,
ntfy topic `escote-alerts-b6810699`). It watches two things: bytes on `/swap.img` and PSI
full avg60. Read its header comment for current thresholds before saying what a number means.

## Mental model (read before interpreting anything)

- 94G RAM box. Swap is two tiers: `/dev/zram0` (16G logical, 8G physical cap, prio 100,
  compressed RAM) then `/swap.img` (16G disk, prio -1). `vm.swappiness=100` on purpose:
  parking idle anon pages in zram is cheaper than dropping ~45G of page cache.
- zram being full is by design and is not a problem. `/swap.img` taking pages means demand
  spilled past zram. Neither number is pressure. PSI full and `MemAvailable` are pressure.
- Zero kernel OOM kills since 2026-07-19 except one on 2026-08-22. Every other kill was
  systemd-oomd on PSI at the old 50% limit (now 80%, terminal slice marked avoid).
- Culprits, ranked by every past incident: Firefox (7 to 28G RSS, biggest every time);
  rust-analyzer instances spawned by long-lived `claude` sessions in herdr panes (2 to 5G each,
  never a cargo build); the claude + MCP fleet (about 4 to 6G total, rarely the driver);
  dead swap left behind after a spike (pages nothing will ever fault back in).
- `~/bin/memwatch` (cron, notify-send + `~/.cache/memwatch.log`) is a second alerter that
  fires nonstop at avail<8G or swap>2G. It is not the ntfy sender. Its log is useful history.

## Step 1: snapshot

Run the triage script with the sandbox DISABLED (the sandbox has its own PID namespace, so
inside it every per-process section is empty):

```bash
~/.claude/skills/swap-alert/scripts/swap-triage.sh
```

It prints headline numbers, a 5s swap-I/O sample, a verdict (REAL PRESSURE / ACTIVE THRASH /
BENIGN), whether a drain is safe, per-class totals, each rust-analyzer mapped to its owning
claude pid + age + cwd, top-by-swap, top-by-rss, oomd kills, and alerter state.

If the alert fired earlier and the moment has passed, reconstruct it:

```bash
~/.claude/skills/swap-alert/scripts/swap-triage.sh --at 07:50            # today
~/.claude/skills/swap-alert/scripts/swap-triage.sh --at 23:10 20260907   # another day
```

## Step 2: name the cause

State it in one line with the numbers: which class, how much RSS and swap, and whether PSI
was nonzero. Never say "rust builds" without `pgrep -c rustc` showing nonzero. Never blame
the MCP fleet without its swap total from the class table (historically 6% of swap).

## Step 3: fix ladder and what needs asking

Read-only diagnosis needs no confirmation. For changes:

| Action | Rule |
|---|---|
| `sudo swapoff -a && sudo swapon -a` (drain dead swap) | Do it, then report, but only when the script says drain is SAFE. Never when swap-in is active. |
| Kill a rust-analyzer | Ask first, naming the owning claude pid, age, and cwd. Killing the LSP is cheap; it respawns when that session next touches Rust. Killing the claude session is the user's call. |
| Firefox | Report total RSS and process count. The user closes or kills Firefox himself. Auto Tab Discard is installed and tuned (discard after 360 min idle over 40 tabs, work domains excepted); do not re-explain its settings. |
| Edit `swap-watch.sh` thresholds | Edit in the dotfiles repo and dry-run the script. Never commit or push without asking. |
| oomd / zram / sysctl changes | These live in dotfiles `manifest.yml` under `swap-tuning`. Propose the diff, do not apply. |

## Step 4: report

Four lines: verdict with PSI and available RAM; the culprit with numbers; what was done or
what needs a yes; whether the alerter fired correctly (a warn/crit with 50G+ available and
PSI 0 is a false positive and should be said so, with the threshold that tripped).

## Known gaps

- ntfy.sh keeps only 12h of topic history; nothing else logs alerts that were sent. Alert
  frequency has to come from `~/.cache/swap-watch/state` transitions or memwatch.log.
- `swap-triage.sh --at` relies on `atop.service` logs in `/var/log/atop/` (10-min samples,
  a few days retained). Nothing finer exists.
- Rust `tail` shadow rejects `tail -60`; use `tail -n 60` or `/usr/bin/tail`.
