# Setup audit program: working the ranked list one design doc at a time

**Owner:** Scott Idler
**Started:** 2026-09-13
**Status:** In progress

## What this is

- On 2026-09-12 a 14-lens audit of every Claude Code session Jun 1 to Sep 12 produced 22 ranked changes to this setup.
- Scott's call: work the list in chunks, one design doc per chunk, each doc lands (merged, deployed via the dotfiles tool, verified) before the next opens.
- This file is the baton. A future agent picking this up reads it first, finds the next chunk marked `next`, and runs `/create-design-doc` for it. Update the table when a chunk changes state.

## Sources

- Ranked report (dense): https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-2026-09-12/
- Overview (one heading per change): https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-setup-audit-overview-2026-09-12/
- Raw findings, 14 lenses with session paths and quotes: https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-audit-findings-2026-09-12/
- Precursor: /insights post https://marquee.internal.tatari.dev/p/~scott-idler/claude-code-insights-2026-09-12/

## Rules for this program

- One chunk per design doc. Chunks stay small enough to count phases on one hand or two.
- Enforcement before prose: where the audit found a rule that hooks can carry, the doc builds the hook and deletes the duplicate rule text.
- Each doc's Phase 0 proves any unproven harness assumption (a hook event fires, a rewrite reaches the tool) with zero code before anything is built.
- A chunk is done when: PR merged, dotfiles applied on desk.lan, the acceptance criteria re-run against the live setup, and the row below flipped to `done` with the doc link and the PR URL.
- Do not reorder chunks without Scott. Do not fold a later chunk's item into an earlier doc.

## Chunks

| Chunk | Audit items | Scope in one line | Status | Design doc | PR |
|---|---|---|---|---|---|
| A | 1, 2, 3 | Sandbox config fixes, first prose hooks (Stop + em-dash deny), rm guard via rails | done | `docs/design/2026-09-13-enforcement-core.md` | no PR, landed on main: [`0d252b8..5faca7d`](https://github.com/scottidler/claude/compare/0d252b8...5faca7d) |
| B | 5 | Hook preflight, heredoc-aware guard parser, git -C rewrite, branch-name guard, release-guard gaps, stale tag-first text, broken frontmatter | building | `docs/design/2026-09-13-guard-precision.md` | |
| C | 4 | review-panel round cap made mechanical, poll snippet removed, agent file shrunk | queued | | |
| D | 6 | Intent guards: commit, Slack post, vault ingest, gh api writes, outward deletes, ln, public-repo; secret-guard vectors | queued | | |
| E | 7, 8 | Inline /skill token hook, review-panel shim, one release chain, execute-a-plan synchronous + self-audit, pr-open helper | queued | | |
| F | 9, 10, 11 | Session recall rule + skill + grounding hook, own the handoff skill + resume, sleep -> Monitor deny + pr-babysitter agent | queued | | |
| G | 12, 13 | Agent definitions (house rules, dispatch.md, model defaults, worktree isolation, phase return contract), doc-gate + template | queued | | |
| H | 14, 15, 16 | security-guidance plugin, context budget + Read discipline + otto tail, always-on prefix trim and rule dedupe | queued | | |
| I | 17, 18 | MCP hygiene (auth recovery, per-service rule, scoping, persona contract), search/pkill/path rails rewrites | queued | | |
| J | 19, 20, 21, 22 | Delete dead skills/plugins/settings, stale pointers, per-repo CLAUDE.md, skill trigger fixes, small new skills | queued | | |

Status values: `queued` | `next` | `drafting` | `in review` | `approved` | `building` | `done` | `dropped (reason)`.

## Log

- 2026-09-14: chunk B building. Its design doc (5/5 passes, panel 3 of 3 rounds, zero open questions, 10 phases) was drafted 2026-09-13 but sat untracked through chunk A; committed now on branch `guard-precision`. Phase 0 is a zero-code harness spike whose results can change Phases 6 and 7.
- 2026-09-13: chunk A done. Phases 0 to 5 landed and Phase 6 ran live; every acceptance criterion passes except AC1b's `ssh -T` half, which cannot be checked from a session because it reads a private key the credential gate denies. Pushed straight to main as `0d252b8..5faca7d`; this repo takes no PRs, so the tracker's "PR merged" wording reads as "landed on main" here. No linker step was needed: `~/.claude/skills` and `~/.claude/hooks` symlink into this repo, so shell hooks go live on commit. The rails plugin does NOT: function-hook plugins load once at session start, so a rails change is only testable in a session started after it lands. That is the phasing rule for B through J.
- 2026-09-13: three findings carried out of A. (1) The excluded-command redirect hole is worse than recorded: an excluded command resolves `$TMPDIR` outside the sandbox namespace, so `cargo --version > $TMPDIR/x` writes to the host path. (2) The regenerable-anchor check is cwd-bound, so a `cd`-prefixed build clean archives instead of passing. (3) The bare-`manifest` guard fires on `manifest.yml` as a path argument, which belongs to chunk B.
- 2026-09-13: hazard for every later chunk. `git checkout <branch>` FAILS in this repo from a session whose own config is this repo: fenced paths under `HOME/.claude/` are read-only and `CLAUDE.md`/`settings.json` are busy, and a partial checkout leaves the working tree half-reverted. Land work with `git push origin <branch>:main`, which never touches the working tree.
- 2026-09-13: chunk B marked `next`.
- 2026-09-13: program opened. Chunk A chosen first because items 1 and 3 are coupled (the rm rewrite fails unless rkvr's archive dir is sandbox-writable) and item 2 is the first prose hook, whose mechanism later chunks build on.
- 2026-09-13: chunk A doc drafted (5/5 passes), review panel 3 of 3 rounds folded, 0 open findings; awaiting Scott's ready-to-build. Scott's ruling recorded in the doc: the rm rule is about intent; regenerable build output gets plain rm, everything else gets rkvr.
- 2026-09-13: chunk A ready-to-build given, building started. Phase 0 ran and changed the plan in three places, all recorded in `docs/design/2026-09-13-enforcement-core-phase0/evidence.md`. (1) The sandbox denies `socket(AF_UNIX)` creation outright, which killed the sccache unix-socket remedy and, by the same mechanism, made ssh-agent unreachable in-sandbox. (2) That forced OQ2, how a sandboxed commit gets signed; Scott ruled option D, mint a home signing-only key so both allowRead'd private keys are signing-only. Home never got the signing/auth split work received on 2026-07-16, and `home/id_ed25519` turned out to be scottidler's only GitHub auth key. (3) The Stop hook's prompt extraction was rewritten onto `last-prompt` transcript records after the original predicate was measured discarding every slash-command turn. Phase 1 is blocked on operator steps only Scott can run (mint the key, register it as a Signing key, which needs `admin:ssh_signing_key` that neither PAT carries today); Phase 2 started ahead of it because it is independent.
