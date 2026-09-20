# sccache vs. the Claude Code Bash sandbox

**Read when:** any cargo/otto build inside a Claude session dies with
`sccache: error: Operation not permitted (os error 1)`, or any tool in the
sandbox fails on a unix socket (ssh agent, gpg agent, docker, playwright,
`systemctl --user`, dotnet/msbuild).

**One-line fix:** `sandbox.network.allowAllUnixSockets: true` in
`~/.claude/settings.json`, then restart Claude Code. Then delete
`target/.rustc_info.json` in any repo that still fails.

## Symptom

```
error: process didn't exit successfully:
  `/home/saidler/.cargo/bin/sccache .../bin/rustc -vV` (exit status: 2)
--- stderr
sccache: error: Operation not permitted (os error 1)
```

Cargo dies before compiling anything: the wrapper probe (`rustc -vV`) is the
first thing cargo runs.

## Root cause

The sandbox's seccomp BPF filter denies **every** `socket(AF_UNIX, ...)` call.
Proved with strace inside the sandbox:

```
socket(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC, 0) = -1 EPERM (Operation not permitted)
```

sccache is a client/server design: it connects to its server, and spawns one if
absent. Both need a socket. So no sccache client can run inside the sandbox
until the filter is lifted.

Second reason TCP does not save you: the sandbox has its own network namespace,
so a host sccache server on `127.0.0.1:4227` is invisible from inside
(`ss -ltnp | grep 4227` finds nothing there). `SCCACHE_SERVER_UDS` does not help
either: the client still calls `socket(AF_UNIX)` to connect.

## How it got this way (2026)

| Date | Change | Effect |
|------|--------|--------|
| 2026-06-09 | `scottidler/claude` `c86d65d` "enable the Bash command sandbox, excluding cargo and otto" | Sandbox on. Builds still fine. |
| 2026-06-10 | `scottidler/dotfiles` `5ed6248` "add sccache systemd user service" | Host-side server. Irrelevant inside the sandbox (separate netns). |
| 2026-06-24, 06-28 09:38 | Claude-run cargo builds compile clean (session transcripts) | Baseline: sandbox on, no sccache in the agent shell. |
| **2026-06-28 14:20** | `scottidler/dotfiles` `d05a454` "track cargo config (mold linker + sccache wrapper)" | **The break.** `~/.cargo/config.toml` sets `build.rustc-wrapper`, which applies to *every* shell on the box, including the sandboxed one. |
| 2026-07-03 | `scottidler/dotfiles` `2173d86` "move ... sccache to .zshenv" | Second path to the same thing: `.zshenv` is read by non-interactive shells, so `RUSTC_WRAPPER` now reaches the agent shell too. |
| 2026-07-05 18:23 | First `sccache: ... Operation not permitted` in a session transcript | Broken from here until 2026-09-20. |
| 2026-09-20 | `sandbox.network.allowAllUnixSockets: true` | Fixed. `otto ci` green with the wrapper in place. |

Before 06-28 the wrapper lived only in `HOME/.shell-exports.d/rust.env`, which
the interactive shell sources and the agent's shell does not. That is why "it
worked before": sccache was never inside the sandbox, not that the sandbox ever
allowed it.

## The fix

`~/.claude/settings.json` (real file:
`~/repos/scottidler/claude/HOME/.claude/settings.json`):

```json
"sandbox": {
  "enabled": true,
  "network": {
    "allowedDomains": ["tatari-tv.github.io"],
    "allowAllUnixSockets": true
  }
}
```

Apply and restart:

```bash
f=~/repos/scottidler/claude/HOME/.claude/settings.json
jq '.sandbox.network.allowAllUnixSockets = true' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
```

The flag is real on Linux despite what the open GitHub issues say. Claude Code
2.1.278's own settings schema, read out of the binary:

```
allowUnixSockets:    "macOS only: Unix socket paths to allow. Ignored on Linux
                      (seccomp cannot filter by path)."
allowAllUnixSockets: "If true, allow all Unix sockets (disables blocking on
                      both platforms)."
```

and the Linux bwrap command builder destructures it next to `bwrapPath`,
`socatPath`, `seccompConfig`. Verify in a future version with:

```bash
strings -n 6 ~/.local/share/claude/versions/<ver> | grep -c allowAllUnixSockets
```

**Cost:** it lifts AF_UNIX blocking wholesale, so a sandboxed command can reach
the docker socket, the ssh/gpg agent sockets, and anything else those expose.
There is no path-scoped option on Linux (see citations).

## The second trap: cargo caches the failed probe

After the setting is live, cargo can *still* replay the old error, because the
wrapper probe result is cached per target dir:

```bash
rm -f target/.rustc_info.json   # regenerable
```

This cost 20 minutes on 2026-09-20: `sccache --show-stats` worked in the
sandbox while `cargo check` in the same directory kept printing the EPERM. An
strace showed cargo never even exec'd sccache, it was replaying
`.rustc_info.json`.

## Things that do NOT work (do not retry these)

- **`sandbox.excludedCommands`**: `"cargo *"`, `"otto *"`, `"systemctl *"` are
  all listed, and all three still run under seccomp. `systemctl --user status`
  fails `Failed to connect to user scope bus via local transport: Operation not
  permitted`; cargo fails as above. Confusingly the permission rails *do* honor
  the list and will refuse a compound command with
  `rails: "touch" would run unsandboxed because "cargo" is in sandbox.excludedCommands`.
  Reported upstream, closed as not planned (citation below).
- **Running the sccache server on the host** (systemd unit or `--start-server`):
  invisible inside the sandbox's netns.
- **`SCCACHE_SERVER_UDS=<path>`**: dies on the same `socket(AF_UNIX)`.
- **`sandbox.network.allowUnixSockets: [...]`**: macOS only, ignored on Linux.
- **Ripping the wrapper out** (`env -u RUSTC_WRAPPER CARGO_BUILD_RUSTC_WRAPPER= otto ci`,
  or deleting `rustc-wrapper` from `~/.cargo/config.toml`): works, but throws
  away the cache. Only a stopgap; the flag above is the fix.

## Probes

```bash
# Is the block in force? (exit 0 = fixed, exit 2 + EPERM = still blocked)
sccache /home/saidler/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin/rustc -vV

# Which syscall is denied?
strace -f -e trace=socket sccache --show-stats 2>&1 | grep AF_UNIX

# Is sccache actually serving the build? Stats are per-sandbox-instance, so the
# build and the stats read must be in ONE Bash call:
touch vault/src/lib.rs && env RUSTC_WRAPPER=$(which sccache) cargo check -p vault; sccache --show-stats | head -3

# Is the sandbox still on at all?
touch /etc/sandbox-probe    # expect: Read-only file system
```

Note `cargo check` shows `Compile requests 1 / executed 0`: sccache forwards
`--emit=metadata` without caching it. Use `cargo build` to see hits/misses.

## Citations

- [claude-code#44180](https://github.com/anthropics/claude-code/issues/44180) - Linux bwrap has no per-path unix-socket allowance; states the seccomp filter blocks all `socket(AF_UNIX,...)`.
- [claude-code#16076](https://github.com/anthropics/claude-code/issues/16076) - `excludedCommands` and `allowUnixSockets` not respected; closed as not planned; `dangerouslyDisableSandbox` named as the only workaround.
- [claude-code#41817](https://github.com/anthropics/claude-code/issues/41817) - feature request for path-scoped unix socket bind support.
- [claude-code#20263](https://github.com/anthropics/claude-code/issues/20263) - security guardrails for unix socket access (why a blanket allow is a tradeoff).
- [codex#16910](https://github.com/openai/codex/issues/16910) - same class of problem in Codex, names sccache explicitly.
- [nx sandbox unix sockets](https://nx.dev/docs/troubleshooting/nx-sandbox-unix-sockets) - third-party writeup of the identical failure mode.
- [sccache](https://github.com/mozilla/sccache) - `SCCACHE_SERVER_PORT`, `SCCACHE_SERVER_UDS`, `--start-server`, `--show-stats`.

## Environment at time of fix

Claude Code 2.1.278, sccache 0.10.0, rustc 1.98.0, Linux 7.0.0-31-generic,
`desk.lan`. Cache at `~/.cache/sccache` (21G, shared between host and sandbox
builds since the filesystem is bind-mounted; only the server is per-namespace).
