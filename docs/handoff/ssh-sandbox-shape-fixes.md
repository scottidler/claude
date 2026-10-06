# ssh sandbox shape fixes

Branch: main

Written 2026-10-06 from a session in `/tmp` (not a repo session). HEAD of this repo at writing: `e0f0d8e`. No commits were made by that session; this file is uncommitted.

## Next action

Add an ssh section to `rules/secrets.md` (next to the git-over-SSH section) stating the measured shape rule below, then decide whether `intent-guard.sh` should deny the failing shapes. Do the rule first; the guard is optional.

## Read first, in order

1. This file.
2. `/home/saidler/repos/.claude/rules/secrets.md` lines 56-90: the existing "git over SSH ... ONLY outside the sandbox" section. It documents the same class of bug for `git push`, with measured shapes.
3. `/home/saidler/repos/scottidler/claude/HOME/.claude/settings.json`, the `sandbox` block: `excludedCommands` includes `"ssh *"`; `network.allowedDomains` has no `.lan` host and no `marquee.internal.tatari.dev`.
4. `/home/saidler/repos/scottidler/claude/HOME/.claude/skills/rails/hooks/index.ts`: source of the message `"<cmd>" would run unsandboxed because "ssh" is in sandbox.excludedCommands; run them as separate Bash calls`.
5. `/home/saidler/repos/scottidler/claude/HOME/.claude/CLAUDE.md`, the "Sandbox phantom files" section: it contains two rules that conflict (see Conflict below).

## Cause (measured 2026-10-06, host desk, target ripr.lan)

`ssh *` in `sandbox.excludedCommands` makes the command run unsandboxed only when the harness reads the whole line as a simple command. A `$(...)` inside the quoted remote command, or a `<` stdin redirect, makes it read as compound. It then runs sandboxed, where there is no DNS and no network route, so it fails with `Could not resolve hostname ripr.lan: Temporary failure in name resolution` (and `Network is unreachable` when given the IP).

Same host, same flags, only the remote string changed:

| Remote command shape | Result |
|---|---|
| `ssh -o BatchMode=yes -o ConnectTimeout=8 ripr.lan hostname` | works |
| `... ripr.lan 'hostname; hostname'` | works |
| `... ripr.lan 'lsblk -d -o NAME,MODEL | grep -v loop'` | works |
| `... ripr.lan 'for n in a b; do echo $n; done'` | works |
| `... ripr.lan 'echo $(hostname)'` | FAILS (resolve error) |
| `... ripr.lan 'bash -s' < script.sh` | FAILS (resolve error) |
| `... ripr.lan 'grep -H . /sys/class/nvme/nvme*/device/current_link_speed'` (remote glob, no `$(`) | works |

Re-prove it in two calls (run each as its own Bash call, no other commands in the line):

```
ssh -o BatchMode=yes -o ConnectTimeout=8 ripr.lan 'echo $(hostname)' 2>&1
ssh -o BatchMode=yes -o ConnectTimeout=8 ripr.lan 'echo hostname' 2>&1
```

Expected: first fails with the resolve error, second prints `hostname`.

Evidence the failing runs were sandboxed: inside the sandbox `ip route` printed nothing, and `ssh -v` read no `~/.ssh/config` (only `/etc/ssh/ssh_config`). Outside the sandbox, `ping -c 2 10.10.10.76` succeeded (0.6 ms).

Related, separate behavior: the `rails` hook rejects any Bash call that puts another command in the same line as an `ssh` call (e.g. `getent ...; ssh ...`, `ip route; ssh ...`). Message: `run them as separate Bash calls`. Not a bug, but it burned several calls.

## Not proven (do not state as fact)

- Which exact tokens the harness treats as "compound". Confirmed: `$(...)` and `<` redirect. Confirmed NOT: quoted `;`, quoted `|`, quoted `for ... do ... done`, trailing `2>&1`. Backticks, `&&`, `||` and heredocs in the remote string are untested.
- Why the first ssh call in the session (turn 1) worked: it fits the table (quoted `;` and `|`, no `$(`), but this was reasoned after the fact.
- Whether adding `ripr.lan` / `10.10.10.0/24` to `sandbox.network` would let sandboxed ssh resolve and connect. Untested; DNS fails inside the sandbox, so likely not enough on its own.

## Conflict to resolve

- `CLAUDE.md` says a command failing with `Operation not permitted` or `Read-only file system` is retried unsandboxed once, silently.
- `CLAUDE.md` also says never set `dangerouslyDisableSandbox` on a command whose head is in `sandbox.excludedCommands`.
- Prior sessions did run ssh to ripr with the sandbox off. Session `15c13695-95bd-46ed-819d-1dac9acbb6e7` (msg 15): "my sandbox can't resolve `ripr.lan` (no DNS), so I'll run the ssh calls unsandboxed, one command at a time." Session `c8b92da7-eb3f-4881-a57e-eb21146d9979` (msg 6) recorded the identical resolve failure.
- Resolution proposed in the session: an `ssh` resolve or unreachable error means the shape is wrong; simplify it (no `$(`, no `<`; use remote globs, `grep -H`, or a script already on ripr called bare). Do not override the sandbox. Get Scott's decision on this wording before writing it.

## Related finding: marquee is not in the network allowlist

`marquee list --tags` inside the sandbox fails with `client error (Connect): tunnel error: unsuccessful` against `https://marquee.internal.tatari.dev/api/tags`. `marquee publish` worked when the Bash call passed `allowed_domains: ["marquee.internal.tatari.dev"]` (published `https://marquee.internal.tatari.dev/p/~scott-idler/desk-lan-vs-ripr-lan-spec-sheet/`). Candidate fix: add `marquee.internal.tatari.dev` to `sandbox.network.allowedDomains` in `settings.json`, or add `marquee *` to `excludedCommands`. Not decided.

## Proposed fixes (none applied)

1. `rules/secrets.md`: new ssh shape section (see Next action).
2. `intent-guard.sh`: deny ssh lines containing `$(`, backticks, or `<`, the way its GIT-NET rule already denies sandboxed `git push` shapes. Not inspected; read the hook first.
3. `settings.json`: marquee host (above).

## Time-sensitive / session-scoped

- Sandbox state (no routes, no DNS) is per Bash call; it is not a persistent session fault.
- `/tmp` scratch files from the originating session (`ripr-disks.sh`, `specsheet/index.html`) are session-scoped and may be gone.
- `settings.json` and `rules/` are denied-write inside the sandbox; edits need the normal approval path.

## Suggested skills

- `update-config` for the `settings.json` change.
- `fewer-permission-prompts` only if the allowlist route is chosen.
- `shipit` / `bump` per this repo's normal release path once changes land.

## Context from the originating session

Task was a desk.lan vs ripr.lan comparison. Ripr: Threadripper 9970X (32c/64t), 122 GB, 1x Radeon AI PRO R9700 (second arrives Friday), 2x Samsung 9100 PRO NVMe (4 TB, 1 TB) at PCIe 5.0 x4. Desk: 2x8-core Intel Xeon-class, 94 GB, RX 6500 XT class 4 GB, SATA disks only.
