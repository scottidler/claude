---
name: mina
description: >-
  Talk to mina — Scott's personal hermes agent running on mini.lan — from
  anywhere (desk.lan, laptop over Tailscale), without installing or running
  hermes locally. Use this whenever Scott wants to ask mina something, send mina
  a message, check what mina thinks, resume the mina conversation, or open an
  interactive mina session. Also use to set up or repair the mina remote-control
  (the mina hermes profile, the persistent tmux session, or the desk wrapper
  scripts) when any piece is missing or broken. Trigger on phrases like "ask
  mina", "tell mina", "mina, …", "what does mina say", "talk to mina", "mina
  session", or "fix/set up mina" — even when hermes, ssh, or tmux aren't
  mentioned explicitly.
---

# mina

mina is a **named hermes agent** that lives on **mini.lan** (an Apple-Silicon
Mac on the home LAN). This skill is the **remote control** for it: it lets you
send messages to mina and hold conversations with it from another machine —
**without ever running hermes locally**. The engine stays on mini.lan on
purpose; the local machine only ever holds thin SSH wrapper scripts.

## The architecture (why it's shaped this way)

```
your machine (desk.lan / laptop)          mini.lan (the Mac)
─────────────────────────────────         ──────────────────────────
mina            ──ssh──▶  hermes -p mina -z "…"   (one-shot, scripted)
mina-session    ──ssh──▶  tmux session "mina" running `hermes -p mina chat`
```

- **Anchor = desk.lan.** It's reachable from anywhere via Tailscale and reaches
  mini.lan over the LAN, so the path is always one hop: *here → mini.lan*. When
  Scott travels, he Tailscales into desk and works from there.
- **No hermes on the local machine.** Deliberate. Everything executes on
  mini.lan; the local side is just `ssh`.
- **mina is a hermes profile** (`hermes -p mina`), cloned from `default`
  (model `claude-opus-4-6`). Invoked as `hermes -p mina …`.

## Key facts (verified — use these exact paths)

| Thing | Value |
| --- | --- |
| Host | `mini.lan` |
| hermes binary | `/Users/saidler/.local/bin/hermes` (on PATH only under **zsh** — see gotcha) |
| Profile invocation | `hermes -p mina …` |
| One-shot flag | `-z "PROMPT"` → prints only the final reply, no banner |
| tmux binary | `/opt/homebrew/bin/tmux` |
| Persistent session name | `mina` |
| tmux prefix (Scott's) | `C-q` (detach = `C-q d`) |
| Local scripts | `~/.local/bin/mina`, `~/.local/bin/mina-session` |

**PATH gotcha (important):** a non-interactive `ssh mini.lan hermes …` will
**fail** — `~/.local/bin` is added to PATH by `.zshrc`, which a non-interactive
shell skips. Always use the **absolute path** `/Users/saidler/.local/bin/hermes`
(and `/opt/homebrew/bin/tmux`) in remote commands, or run under `zsh -lc`.

## How to talk to mina

### One-shot question (default for most requests)

Prefer the installed script — it handles quoting (including apostrophes):

```bash
mina "what's on my calendar tomorrow?"
```

If the script isn't present, the equivalent direct call is:

```bash
ssh mini.lan "/Users/saidler/.local/bin/hermes -p mina -z 'what is on my calendar tomorrow?'"
```

Relay mina's reply back to Scott. The one-shot is stateless across calls (each
`-z` is its own turn) — for a continued back-and-forth, use the session.

### Interactive session (persistent conversation)

The session is a long-running tmux conversation on mini.lan that survives
detach/reattach. This is **interactive** — Claude can't drive it; tell Scott to
run it himself in his terminal:

```bash
mina-session    # attaches to the live mina chat (creates it if it died)
```

He detaches with `C-q d` and the conversation keeps running for next time.

## Setup / repair (idempotent)

Run these when a piece is missing or broken. Each step is safe to re-run.

1. **mina profile on mini.lan** — create only if absent (cloning `default` gives
   it the 4.6 model + working auth):
   ```bash
   ssh mini.lan "zsh -lc 'hermes profile list | grep -q \" mina \" || hermes profile create mina --clone --description \"Scott personal mina agent, remote-controlled\"'"
   ```

2. **Persistent tmux session** — create only if absent (never clobber a live one):
   ```bash
   ssh mini.lan "zsh -lc 'tmux has-session -t mina 2>/dev/null || tmux new-session -d -s mina \"/Users/saidler/.local/bin/hermes -p mina chat\"'"
   ```

3. **Local wrapper scripts** — `~/.local/bin/mina` and `~/.local/bin/mina-session`.
   See `scripts/` in this skill for the canonical copies; install with:
   ```bash
   install -m 755 scripts/mina ~/.local/bin/mina
   install -m 755 scripts/mina-session ~/.local/bin/mina-session
   ```

### Verify it works end-to-end

```bash
mina "reply with exactly: mina online"
```

A clean `mina online` (no banner, no spinner) means the whole chain — ssh →
mini.lan → hermes → mina profile → model auth — is healthy.

## Troubleshooting

- **`command not found: hermes` over ssh** → the PATH gotcha. Use the absolute
  path or `zsh -lc`.
- **`Host key verification failed`** → don't blindly clear it. If the box was
  reinstalled it's benign (`ssh-keygen -R mini.lan` then reconnect); if not,
  investigate before trusting the key. A *first* connection to an unknown host
  is the boring case — accept it.
- **mina answers but seems wrong/unconfigured** → check `ssh mini.lan "zsh -lc 'hermes profile show mina'"`; the profile may need `hermes -p mina setup`.
- **`can't change option: zle` / terminal warnings** under `zsh -lic` → cosmetic
  interactive-init noise; use `zsh -lc` (login, non-interactive) for scripting.
