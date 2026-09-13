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
| A | 1, 2, 3 | Sandbox config fixes, first prose hooks (Stop + em-dash deny), rm guard via rails | building | `docs/design/2026-09-13-enforcement-core.md` | |
| B | 5 | Hook preflight, heredoc-aware guard parser, git -C rewrite, branch-name guard, release-guard gaps, stale tag-first text, broken frontmatter | queued | | |
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

- 2026-09-13: program opened. Chunk A chosen first because items 1 and 3 are coupled (the rm rewrite fails unless rkvr's archive dir is sandbox-writable) and item 2 is the first prose hook, whose mechanism later chunks build on.
- 2026-09-13: chunk A doc drafted (5/5 passes), review panel 3 of 3 rounds folded, 0 open findings; awaiting Scott's ready-to-build. Scott's ruling recorded in the doc: the rm rule is about intent; regenerable build output gets plain rm, everything else gets rkvr.
- 2026-09-13: chunk A ready-to-build given, building started. Phase 0 ran and changed the plan in three places, all recorded in `docs/design/2026-09-13-enforcement-core-phase0/evidence.md`. (1) The sandbox denies `socket(AF_UNIX)` creation outright, which killed the sccache unix-socket remedy and, by the same mechanism, made ssh-agent unreachable in-sandbox. (2) That forced OQ2, how a sandboxed commit gets signed; Scott ruled option D, mint a home signing-only key so both allowRead'd private keys are signing-only. Home never got the signing/auth split work received on 2026-07-16, and `home/id_ed25519` turned out to be scottidler's only GitHub auth key. (3) The Stop hook's prompt extraction was rewritten onto `last-prompt` transcript records after the original predicate was measured discarding every slash-command turn. Phase 1 is blocked on operator steps only Scott can run (mint the key, register it as a Signing key, which needs `admin:ssh_signing_key` that neither PAT carries today); Phase 2 started ahead of it because it is independent.
