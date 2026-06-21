---
name: relocate-targets
description: >-
  Move Rust build artifacts (target/ dirs) off a space-constrained drive onto a
  dedicated drive, leaving a symlink so cargo/rust-analyzer/CI keep working.
  Use this whenever a disk is filling from Rust builds, target/ dirs are eating
  space, `df` shows the OS/repo disk near full, or the user wants build output
  on a different drive (or migrated drive-to-drive or machine-to-machine). Also
  use to set up a brand-new repo so its first build lands on the dedicated drive,
  and to install the daily cron that keeps new repos relocated automatically.
  Trigger even if the user just says "my disk keeps filling up from cargo",
  "move my build dirs to the SSD", or "relocate target dirs" without naming this
  skill.
---

# relocate-targets

Keep Rust build output off a space-constrained drive by storing each repo's
`target/` on a dedicated drive and leaving a symlink behind. cargo, rust-analyzer,
task runners, and CI all follow the symlink and never know the difference.

## When this is the right tool

Reach for this when build artifacts are the disk problem, not stale-artifact
cleanup. If a disk fills because hot repos rebuild gigabytes of `target/` daily,
no amount of *sweeping old artifacts* keeps up — the fix is to stop writing build
output to the constrained drive at all. (For reclaiming genuinely stale artifacts
in place, that's `cargo-sweep`/`sweep-repos`, a complementary tool, not this one.)

Symptoms that point here: `/` or `/home` near full, `du` showing tens/hundreds of
GB under `target/debug` and `target/release`, a disk-full scare traced to cargo.

## The model (read this before running anything)

- **Per-repo target dirs, not one shared `CARGO_TARGET_DIR`.** cargo takes a build
  lock per target directory; a single shared target serializes concurrent
  cross-repo builds. Each repo keeps its *own* `target/`, physically on the
  dedicated drive via its own symlink, so parallel builds run lock-free.
- **Symlinks, not an env var.** A symlink lives in the filesystem, so the build
  lands on the dedicated drive no matter who launches it — your shell, a task
  runner, an orchestrator, cron, an IDE. A shell-set `CARGO_TARGET_DIR` only
  applies where it was set and silently regresses to the OS disk the moment a
  tool builds without it.
- **The whole `target/`, both profiles.** `target/debug` and `target/release`
  both live under `target/`; relocating `target/` moves debug AND release at once.
- **Idempotent.** A `target/` already symlinked to the dedicated drive is skipped,
  so re-running (or a cron) is safe and only picks up new work.

## The engine

`scripts/relocate-targets` is the single source of truth. The cron and any
`~/bin` symlink point at it. It handles every case:

| Situation | What it does |
|---|---|
| Repo with an existing `target/` dir | Migrates it to the drive (fastest correct transport), then symlinks back |
| Brand-new repo, no `target/` yet | Pre-creates the drive dir and symlinks `target/` so the **first** build lands there |
| Repo already symlinked to the drive | Skips (idempotent) |
| `target/` is a symlink pointing somewhere else | Warns, leaves it alone |

### Common invocations

```bash
# Relocate every repo under ~/repos (default), to the default drive:
scripts/relocate-targets

# Preview without touching anything (always do this first on a new setup):
scripts/relocate-targets --dry-run

# One repo only:
scripts/relocate-targets --repo ~/repos/scottidler/loopr-v5

# Different destination drive:
scripts/relocate-targets --dest /media/saidler/intel-480gb-ssd/cargo-target

# Migrate to another machine over ssh (uses rsync -aHX):
scripts/relocate-targets --repo ~/repos/foo/bar --remote user@host
```

The default destination is `/media/saidler/intel-480gb-ssd/cargo-target`. Change
it with `--dest` (or edit the default in the script if the drive is permanent).

### Safety the script enforces (so you don't have to babysit it)

- **Refuses to run onto an unmounted drive.** If the dedicated drive isn't
  mounted, writing to it would land on the OS disk under the empty mountpoint —
  the exact silent regression this skill exists to prevent. It aborts loudly
  (and toasts) instead.
- **Hardlink-preserving + verified.** cargo `target/` dirs are full of hardlinks;
  a naive copy shatters them and inflates size. Every transport preserves them,
  and the local tar pipe verifies entry counts before dropping the source — so a
  failed copy never leaves you with a missing `target/`.

## Choosing the migration transport

The script auto-selects; you rarely override it. The short version:

- **same filesystem** → `mv` (instant rename, no copy)
- **local, cross-filesystem** → tar pipe (fastest for many small files,
  hardlink-safe, no compression — there's no slow link to amortize it against)
- **cross-machine** → `rsync -aHX` over ssh (resumable; `-H` is mandatory or it
  shatters hardlinks)

For the full rationale and the benchmark that settled tar-pipe-vs-rsync, read
[`references/transports.md`](references/transports.md). Read it when a user asks
*why* a transport was chosen, wants to tune it, or is migrating across a network
where compression tradeoffs matter.

## Setting it up to stay fixed (cron)

A one-time relocation isn't enough — newly cloned repos build to the OS disk
until relocated. The durable setup is a daily cron that re-runs the script
(idempotent, so it only acts on new repos):

```
0 2 * * * /home/saidler/bin/relocate-targets >> /home/saidler/.cache/relocate-targets.log 2>&1
```

In this dotfiles/manifest setup, that's wired as a `relocate-targets-cron` entry
plus a `~/bin/relocate-targets` symlink to this script. Pair it with the existing
`sweep-repos` watermark cron: relocation keeps the OS disk empty of build output;
the sweep keeps the *dedicated* drive from growing without bound.

## New-machine bring-up checklist

1. Mount the dedicated drive with a stable `fstab` entry (`nofail` so a missing
   drive never blocks boot — but note the symlinks dangle and builds fail loudly
   if it's ever absent, which is the desired loud-not-silent failure).
2. `relocate-targets --dry-run` to preview, then run it for real.
3. Install the `~/bin` symlink + daily cron (via manifest).
