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
| B | 5 | Hook preflight, heredoc-aware guard parser, git -C rewrite, branch-name guard, release-guard gaps, stale tag-first text, broken frontmatter | done | `docs/design/2026-09-13-guard-precision.md` | no PR, landed on main: [`8ee8f60..96e6a79`](https://github.com/scottidler/claude/compare/473fb6d...96e6a79) |
| C | 4 | review-panel round cap made mechanical, poll snippet removed, agent file shrunk | done | `docs/design/2026-09-14-panel-round-cap.md` | no PR, landed on main: [`bff72f2..a851a65`](https://github.com/scottidler/claude/compare/bff72f2...a851a65) |
| D | 6 | Intent guards: commit, Slack post, vault ingest, gh api writes, outward deletes, ln, public-repo; secret-guard vectors | next | | |
| E | 7, 8 | Inline /skill token hook, review-panel shim, one release chain, execute-a-plan synchronous + self-audit, pr-open helper | queued | | |
| F | 9, 10, 11 | Session recall rule + skill + grounding hook, own the handoff skill + resume, sleep -> Monitor deny + pr-babysitter agent | queued | | |
| G | 12, 13 | Agent definitions (house rules, dispatch.md, model defaults, worktree isolation, phase return contract), doc-gate + template | queued | | |
| H | 14, 15, 16 | security-guidance plugin, context budget + Read discipline + otto tail, always-on prefix trim and rule dedupe | queued | | |
| I | 17, 18 | MCP hygiene (auth recovery, per-service rule, scoping, persona contract), search/pkill/path rails rewrites | queued | | |
| J | 19, 20, 21, 22 | Delete dead skills/plugins/settings, stale pointers, per-repo CLAUDE.md, skill trigger fixes, small new skills | queued | | |

Status values: `queued` | `next` | `drafting` | `in review` | `approved` | `building` | `done` | `dropped (reason)`.

## Log

- 2026-09-14: chunk C done. Five phases landed as 9 commits pushed straight to main (`bff72f2..a851a65`); every acceptance criterion re-run through the production symlink path and recorded. Phase 0's spike proved the `Agent` PreToolUse seam that the design rests on and measured doc-path extraction at 97.4% over all 348 corpus dispatches, with all 9 misses being the docless Mode 2 audits already named as a Non-Goal. The round-1 implementation audit, dispatched under the guard it was auditing, found two live parser defects that CI could not see: the door opened from a marker at column 1 inside a fenced block (so quoting the design doc's own `:165` raised its own cap from 3 to 5), and mode detection grepped the whole file, so the (doc, mode) key failed to change when a status genuinely flipped. Both fixed with break-the-code evidence; matrix 95 to 108. Phase 3 had also silently dropped Step 4's four rejected-dogma examples, restored. One process rule for later chunks: a guard that parses prompts or docs must have its self-reference case tested in the form the artifact actually uses, because inline-backtick and indented cases passing is exactly what let a fenced bypass ship green. Two findings handed on: audit must-fix 3, that `review-panel.md` Step 3's "ONE foreground Bash call" is un-followable because chunk A put both seat scripts in `sandbox.excludedCommands` and the rails `tool.call` hook denies an excluded head compounded with any acting stage (fix designed, a single `panel-dispatch.sh` excluded head, blocked on write access to `HOME/.claude/agents/`); and `spec-review`'s independent prose "Max 3 rounds", now the odd one out. Chunk D marked `next`.

- 2026-09-14: chunk C doc drafted and reviewed. `docs/design/2026-09-14-panel-round-cap.md`, 5 passes then a rewrite then passes 2 and 4 re-run, panel round 1 folded (3 must-fix, 4 cheap wins, 2 findings rejected with code citations), Open Questions empty. Six phases. Committed on branch `panel-round-cap` when the chunk opened, per chunk B's lesson about a doc sitting untracked. Awaiting Scott's ready-to-build.
  - The design was rewritten once before the panel saw it. The obvious seam, a `PreToolUse(Bash)` guard on the reviewer seat scripts, cannot work: `review-panel.md:79-83` mints a fresh run dir per dispatch so the counter reads zero at round 4 for ~92% of dispatches, and a deny inside the panel subagent does not reach the caller, who is the party that overruns. It now sits on `PreToolUse(Agent)` keyed on (doc path, mode), counter in `~/.cache` because `/tmp` is tmpfs. The rejected design is kept as an Alternative so it is not re-proposed.
  - Two items the audit's change list prescribes are NOT built, both recorded as Non-Goals with citations: the reviewer wall-clock guard already exists (`architect/script.sh:198`, `staff-engineer/script.sh:195`) and an outer one was forbidden by Scott on 2026-08-04 after the TIMEOUT TIE incident; and freezing the doc during a round does not address the measured failure, which is growth across rounds. The panel agreed with both refusals.
  - Round distribution re-derived rather than inherited: 46 run dirs with round-paired evidence in `~/.claude/projects`, 17 over 3 rounds, 7 over 5, worst `8wLUyVus` at 14. Two independent panel derivations returned 47/17/7 and confirmed the max of 14.
  - Carried for later chunks: `spec-review/SKILL.md:13,213` holds an independent "Max 3 rounds" prose cap that will read as inconsistent once this one is mechanical; 9 of 346 dispatches are docless Mode 2 audits with no key, so they stay uncapped and are a named evasion path.

- 2026-09-14: chunk B done. Ten phases landed as 16 commits pushed straight to main (`473fb6d..96e6a79`, with one unrelated commit of Scott's riding along); every acceptance criterion re-run after the push and recorded. The round-1 implementation audit failed the branch as first built: the Phase 3 command-word anchor was a prefix regex and 22 measured deny verdicts had become allows for compound commands, `eval`, wrappers and process substitution. Folded in one fix commit with a shared wrapper-mutation harness (234 wrapped assertions), re-verified probe by probe. Two process rules for later chunks, both in the doc: a phase that adds a file another live hook depends on runs the link step in the SAME phase (four ported guards were failing open through the symlink path until Phase 7's preflight named it); and a parser refactor needs a differential replay plus a shape-mutation sweep, not only the pre-existing matrix. Three known limits handed on: variable verbs (unfixable statically), backslash-newline continuation (chunk I), single-quoted verb in the secret guard (chunk D). Chunk C marked `next`.
- 2026-09-14: chunk B building. Its design doc (5/5 passes, panel 3 of 3 rounds, zero open questions, 10 phases) was drafted 2026-09-13 but sat untracked through chunk A; committed now on branch `guard-precision`. Phase 0 is a zero-code harness spike whose results can change Phases 6 and 7.
- 2026-09-13: chunk A done. Phases 0 to 5 landed and Phase 6 ran live; every acceptance criterion passes except AC1b's `ssh -T` half, which cannot be checked from a session because it reads a private key the credential gate denies. Pushed straight to main as `0d252b8..5faca7d`; this repo takes no PRs, so the tracker's "PR merged" wording reads as "landed on main" here. No linker step was needed: `~/.claude/skills` and `~/.claude/hooks` symlink into this repo, so shell hooks go live on commit. The rails plugin does NOT: function-hook plugins load once at session start, so a rails change is only testable in a session started after it lands. That is the phasing rule for B through J.
- 2026-09-13: three findings carried out of A. (1) The excluded-command redirect hole is worse than recorded: an excluded command resolves `$TMPDIR` outside the sandbox namespace, so `cargo --version > $TMPDIR/x` writes to the host path. (2) The regenerable-anchor check is cwd-bound, so a `cd`-prefixed build clean archives instead of passing. (3) The bare-`manifest` guard fires on `manifest.yml` as a path argument, which belongs to chunk B.
- 2026-09-13: hazard for every later chunk. `git checkout <branch>` FAILS in this repo from a session whose own config is this repo: fenced paths under `HOME/.claude/` are read-only and `CLAUDE.md`/`settings.json` are busy, and a partial checkout leaves the working tree half-reverted. Land work with `git push origin <branch>:main`, which never touches the working tree.
- 2026-09-13: chunk B marked `next`.
- 2026-09-13: program opened. Chunk A chosen first because items 1 and 3 are coupled (the rm rewrite fails unless rkvr's archive dir is sandbox-writable) and item 2 is the first prose hook, whose mechanism later chunks build on.
- 2026-09-13: chunk A doc drafted (5/5 passes), review panel 3 of 3 rounds folded, 0 open findings; awaiting Scott's ready-to-build. Scott's ruling recorded in the doc: the rm rule is about intent; regenerable build output gets plain rm, everything else gets rkvr.
- 2026-09-13: chunk A ready-to-build given, building started. Phase 0 ran and changed the plan in three places, all recorded in `docs/design/2026-09-13-enforcement-core-phase0/evidence.md`. (1) The sandbox denies `socket(AF_UNIX)` creation outright, which killed the sccache unix-socket remedy and, by the same mechanism, made ssh-agent unreachable in-sandbox. (2) That forced OQ2, how a sandboxed commit gets signed; Scott ruled option D, mint a home signing-only key so both allowRead'd private keys are signing-only. Home never got the signing/auth split work received on 2026-07-16, and `home/id_ed25519` turned out to be scottidler's only GitHub auth key. (3) The Stop hook's prompt extraction was rewritten onto `last-prompt` transcript records after the original predicate was measured discarding every slash-command turn. Phase 1 is blocked on operator steps only Scott can run (mint the key, register it as a Signing key, which needs `admin:ssh_signing_key` that neither PAT carries today); Phase 2 started ahead of it because it is independent.
