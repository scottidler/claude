# WHOAMI: basic facts about Scott Idler

Durable, load-bearing facts about me. Read at session start (included from
`CLAUDE.md`). Add to this as you learn more; never guess these, they are facts.

## Devices

- **Phone: Google Pixel (Android).** I hate iOS and would NEVER own an iPhone.
  Do not assume a screenshot is iOS; if you see a phone screenshot, it is my
  Pixel unless I say otherwise.
- **Desktop:** `desk.lan` (primary workstation, where daemons run).
- **Laptop:** `ltl-7007.lan` (`lappy`/`laptop`), used over Tailscale.

## Identity

- Work: Tatari, `scott.idler@tatari.tv`. Work GitHub org: `tatari-tv`.
- Personal GitHub: `scottidler`. Personal repos are the home persona.
- Repos live at `~/repos/<org|user>/<repo>`.

## Tools & workflow

- Heavy Obsidian user; my second brain runs through `sb` (borg/cortex/oracle),
  vault at `~/repos/scottidler/obsidian/`.
- Vault syncs across machines via **Syncthing**; I also pay for **Obsidian
  Sync** for the phone.
- Dotfiles/config are `manifest`-managed and symlinked from
  `~/repos/scottidler/{dotfiles,claude}/HOME/`.

## Vocabulary

Scott's own shorthand, so an agent stops guessing what these mean.

- **rp**: bare-word shorthand for `review-panel` (the design-doc review agent/skill at `HOME/.claude/agents/review-panel.md` / `HOME/.claude/skills/review-panel/`). No slash, so the `/token` matcher in `inline-skill-tokens.py` cannot catch it (parked non-goal, `docs/design/2026-09-17-dm-resolution-and-pipeline-glue.md:97`).
- **panel**: the `review-panel` agent/skill itself, dispatches review rounds against a design doc, capped mechanically by `panel-round-guard.sh`.
- **rmrf**: `rkvr rmrf`, the archival-then-delete subcommand of the `rkvr` CLI. Archives to a three-week recovery bin before removing; the one for anything not regenerable (see `rules/safety.md`).
- **bkup**: `rkvr bkup`, the archive-without-deleting subcommand of the same `rkvr` CLI. `filter-ref` stages candidates for either `rmrf` or `bkup`.
- **lappy**: the laptop, `ltl-7007.lan`, reached over Tailscale (see Devices above).
- **desk**: the desktop, `desk.lan`, the primary workstation where daemons run (see Devices above).
- **shipit**: the `/shipit` skill, commit, bump the version, push, and install in one go, handed to the `release-driver` agent.
- **bump**: the `bump` CLI, bumps semantic versions, commits, and tags a git repo; `bump --gates` reports branch-protection status; `bump --no-tag` / `bump --tag-only` split the bump for gated repos.
- **sdv**: the `sdv` CLI, reports a Tatari-hosted site's standard endpoints (`/status`, `/deployed`, `/version`) via `sdv probe`.
- **handoff**: the `handoff` skill (`HOME/.claude/skills/handoff/SKILL.md`), which writes a session handoff and resumes from one. It is built and live; F2 still owes the resume *trigger* (`docs/design/2026-09-13-setup-audit-program.md:39`), not the skill.
