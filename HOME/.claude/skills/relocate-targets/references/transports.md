# Migration transports: how the fastest *correct* copy is chosen

Read this when deciding or explaining how `target/` gets moved to the dedicated
drive — especially the tar-pipe-vs-rsync question, or when migrating across a
network where compression actually matters.

## The correctness keystone: hardlinks

cargo `target/` dirs are full of **hardlinks** — a dependency's `.rlib` and the
final artifact frequently share one inode. Any copy method that doesn't preserve
hardlinks turns each link into a full second copy, which:

- **inflates size** (the dir balloons well past its real on-disk footprint), and
- can **break cargo's fingerprinting**, forcing needless rebuilds.

So "fast" is necessary but not sufficient. The transport must be **hardlink-safe**
*and* fast. That's the lens for everything below.

## The benchmark that settled it

Synthetic cargo-like tree: 20,000 small files + 8,000 hardlinks (~79M on disk,
20,000 unique inodes), copied from the OS disk (sda2, ext4) to the dedicated SSD
(sdc1, ext4) on the same host. A correct copy lands at ~79M / 20,000 inodes; a
hardlink-shattering copy balloons.

| Method | Time | On-disk | Unique inodes | Hardlinks |
|---|---|---|---|---|
| **tar pipe** | **0.90s** | 79M | 20000 | ✅ preserved |
| rsync -aH | 1.68s | 80M | 20000 | ✅ preserved |
| cp -a | 1.83s | 79M | 20000 | ✅ preserved |
| rsync -a (no `-H`) | 1.96s | **95M** | **24000** | ❌ **shattered** |
| mv | 2.29s | 79M | 20000 | ✅ preserved |

Takeaways:

- **tar pipe is ~2x faster than everything else and hardlink-safe.** For many
  small files it does one streaming read pass + one write pass with minimal
  per-file syscall overhead; rsync's stat/checksum/file-list machinery and mv's
  per-file copy loop both cost more.
- **rsync without `-H` silently corrupts the layout** (95M vs 79M, 24000 vs
  20000 inodes). This is the "bulletproof" trap: rsync *feels* safe but the
  default expands hardlinks. Always `-H` for cargo targets.
- **mv is correct but the slowest** — it's what the original prototype used.
  Fine for tiny repos, wasteful for big ones.

## The decision matrix the script implements

```
same filesystem?            -> mv            (instant rename, no bytes copied)
local, cross-filesystem?    -> tar pipe      (fastest, hardlink-safe, verified)
cross-machine (--remote)?   -> rsync -aHX    (resumable; -H mandatory)
```

### Why no compression locally

`tar | gzip | tar` (or `targz`) only helps when a **slow link** (a network) is the
bottleneck and CPU time spent compressing is cheaper than bytes sent. On a local
SSD-to-SSD copy there's no slow link — compression just burns CPU and *slows the
move down*. So the local tar pipe is raw (`tar -cf - . | tar -xpf -`), no `-z`.

### Why tar pipe locally but rsync cross-machine

Over a network you care about two things the local case doesn't have:

- **Resumability** — if the link drops mid-transfer, `rsync` picks up where it
  left off; a tar pipe starts over. For a multi-GB target over ssh that matters.
- **Integrity over an unreliable channel** — rsync verifies as it goes.

`rsync -aHAX --remove-source-files -e ssh` gives a clean, resumable, hardlink-safe
move. If the network is the bottleneck and you want max throughput on a fast,
reliable link, a `tar -cf - . | zstd | ssh host 'zstd -d | tar -xpf -'` pipe can
beat rsync — but it loses resumability, so it's an opt-in for big transfers over
good links, not the default.

### Why the local tar pipe is still "bulletproof"

The worry with tar (no resume) is a half-finished copy. The script removes the
source **only after** verifying the destination entry count matches the source.
A failed or partial tar leaves the source untouched, so you never end up with a
missing `target/`. Combined with recreatable build artifacts, that's as safe as
resumability in practice — without rsync's per-file overhead.
