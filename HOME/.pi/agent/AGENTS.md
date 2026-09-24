# Scott Idler

## This file is symlinked into place

- `~/.pi/agent/AGENTS.md` -> `~/repos/scottidler/claude/HOME/.pi/agent/AGENTS.md`
- Edit/commit the real path, never the symlink
- Companion to `~/.claude/CLAUDE.md`: same person, same conventions, different harness.
  When a convention changes, change it in `~/repos/.claude/rules/` (shared by both) rather than here.

## pi-specific notes

- pi has no `@file` include directive in context files. Anything that must always be
  in context is inlined by the `rules` extension at `before_agent_start`, not by an `@` line here.
- pi has no MCP. Every capability that runs over MCP under Claude Code has a CLI here;
  see the CLI section below and `~/repos/scottidler/claude/HOME/.claude/tools.md`.
- pi has no built-in subagents, plan mode, to-dos, or background bash. Subagents come
  from the `subagent` extension when it is installed; the rest are absent by design.

## Who I am

Read `~/.claude/WHOAMI.md` at session start. It carries the durable facts: devices
(Pixel, `desk.lan`, `ltl-7007.lan`), identity (Tatari, `scott.idler@tatari.tv`, work org
`tatari-tv`, personal GitHub `scottidler`), tooling (Obsidian via `sb`, Syncthing,
manifest-managed dotfiles), and my own shorthand vocabulary (rp, panel, rmrf, bkup,
lappy, desk, shipit, bump, sdv, handoff).

## voice

- Writing-voice profile: `~/Claude/writing/VOICE.md` (copied, not symlinked; `~/Claude`
  is the Cowork/Syncthing space)
- Read when: drafting prose as me (email, Slack, Confluence, design docs, announcements)
- Always-on trigger rule: `rules/voice.md`

## identity

- Identity profile: `~/Claude/IDENTITY.md` (companion to VOICE.md: voice is how I write,
  identity is who I am and why I work this way)
- Read when: making judgment calls about what I want or how I would decide, drafting
  anything as or about me beyond code, personalizing advice, or briefing another agent
- The personal-history sections are context only, never for outward-facing output

## Non-Negotiable: Root Cause Always

When something breaks or behaves unexpectedly, **never speculate, guess, or say "I don't
know"**. Go find the answer. Check logs, inspect state, read files, run commands, whatever
it takes. "I don't know", "probably", "likely", "fluke", "magic", or any hand-wavy
non-answer is never acceptable. If the cause isn't known yet, the correct response is to
go investigate until it is.

## Never estimate

- No time, effort, or cost estimates: no hours, days, story points, or t-shirt sizes
- No "small fix vs. large refactor" sizing framing
- You lack the calibration; a confidently wrong estimate is worse than none
- If asked "how long," answer with scope: files affected, steps required, unknowns that block progress
- Let the human do the sizing

## Non-Negotiable: `docs/` is markdown, nothing else

NEVER put a script, fixture, corpus, or data file anywhere under `docs/`, in any
repo. No `.py`, `.sh`, `.json`, `.tsv`, `.txt`, `.jsonl`. No `-phase0/` or
`-phase3/` artifact directory holding them. A measurement's numbers get pasted
verbatim INTO the `.md` that cites them; the harness that produced them does not
get committed beside it. Worth keeping means it is a tool and belongs in `bin/`
or next to the code it tests. Not worth keeping means it dies with the session
scratchpad. 37 such files accumulated in this repo by 2026-09-21, every one dead,
and they were deleted as a class. `otto lint` fails on any non-`.md` under `docs/`.
Full rule: `rules/general.md`, Documentation.

## Rules

`~/repos/.claude/rules/`, shared with Claude Code. The `rules` extension inlines the
always-on ones into the system prompt at session start and lists the rest for you to read
on demand.

Conventions (how I write code and config):
- `general`: naming, files, config, deps, CI, version control (always-on)
- `taste`: design/review judgment: pipeline discipline, quality bar, architecture and
  security instincts, phasing, evidence standards (always-on)
- `voice`: outward-facing prose goes out in my voice via `~/Claude/writing/VOICE.md` (always-on)
- `cli`: CLI flag behavior: space-separated, no commas (always-on)
- `logging`: function-level debug logging (always-on)
- `python` / `rust` / `js-ts` / `yaml`: language-specific (read when touching that language)
- `comments`: name it, don't narrate it (read when writing code or yaml, not json)

Tool rules (hard constraints on specific tools):
- `git`: tag/push/working-dir safety (always-on)
- `otto`: task-runner usage (always-on)

Safety:
- `safety`: file deletion; applies to all files (always-on)
- `secrets`: age-encrypted secrets via `manifest age`; gh token picked by repo org (always-on)

## My CLIs

Custom binaries in `~/.cargo/bin`, built from `~/repos`. Run `<tool> --help` for detail.
The full roster is in `~/repos/scottidler/claude/HOME/.claude/tools.md`; read it when you
need a tool you do not already know. The ones that carry most of the work:

- `otto` - CI pipeline. `otto ci` is the green gate on every phase.
- `bump` - semantic version bump, commit, tag. Never hand-edit a version.
- `marquee` - publish artifacts to Okta-gated URLs (`publish`, `replace`, `read`, `search`, `list`).
- `clyde` - catalog, search, and resume Claude Code sessions (`session search`, `session read`).
- `sb` - second brain: `borg` (ingest), `cortex` (vault governance), `oracle` (retrieval).
- `manifest` - deploy dotfiles and config from `manifest.yml`. Always scope with `-l <glob>`.
- `slack` - Slack over Okta (`read`, `search`, `write`, `watch`).
- `persona` - Tatari employee and org directory (`whois`, `team`, `chain`, `reports`).
- `sdv` - probe a Tatari site's `/status`, `/deployed`, `/version`.
- `gws` - Google Workspace.
- `acli` - Atlassian CLI for Jira and Confluence.
- `rkvr` - `rmrf` (archive then delete) and `bkup` (archive only). The safe delete.
- `worktree` - create, switch, list, prune git worktrees in a bare-container repo.

### MCP substitutions

Under Claude Code these run as MCP servers. Under pi, call the CLI:

| Claude Code MCP | pi equivalent |
|---|---|
| `mcp__clyde__*` | `clyde session search`, `clyde session read` |
| `mcp__marquee__*` | `marquee publish\|replace\|read\|search\|list` |
| `mcp__slack__*` | `slack read\|search\|write\|users\|usergroups` |
| `mcp__persona__*` | `persona whois\|team\|teammates\|chain\|reports\|search` |
| `mcp__oracle__*` | `sb oracle` (check `sb oracle --help` for the query path) |
| `mcp__atlassian__*` | `acli jira`, `acli confluence` |

Two known gaps: `slack watch` is long-lived and pi has no background bash, so run it under
tmux rather than blocking a turn; and `sb oracle` may expose retrieval only over its MCP
server, in which case say so rather than inventing a flag.

## References

On-demand docs in `~/repos/.claude/refs/`, read when the scenario calls for it.

- `environment.md` - hostnames, Obsidian vault, dotfiles, `manifest` conventions.
  Read when: referencing machines, obsidian, dotfiles, or manifest.
- `personas.md` - home/work identity, GitHub accounts, SSH keys, Jira/Confluence.
  Read when: GitHub, Jira, Slack, or identity-sensitive work, or when asked who I am.
- `slack.md` - Slack mrkdwn, posting patterns, ID reference. Read when: posting to Slack.
- `jira.md` - issue types, ticket naming, acceptance criteria. Read when: working a Jira ticket.
- `design-exemplars.md` - worked examples of my design and review judgment with verbatim
  quotes. Read when: authoring or reviewing a design doc, running an implementation audit,
  or making a judgment call `rules/taste.md` does not settle.
- `dealing-with-large-files.md` - safe decomposition of large source files.
  Read when: splitting files over the size threshold.
- `refactor.md` - bulk search-and-replace with the `replace` shell function.
  Read when: mechanical cross-file renames.
