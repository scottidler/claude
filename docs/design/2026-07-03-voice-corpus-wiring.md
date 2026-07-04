# Design Document: Voice Corpus Wiring

**Author:** Scott Idler (via Claude)
**Date:** 2026-07-03
**Status:** Draft — shape SUPERSEDED (see Status Update); interim wiring implemented; real automation method parked
**Review Passes Completed:** 3/5 (draft, correctness, edge-cases) + one review-panel round (findings below drove the pivot)

## Status Update (2026-07-04)

The `scottidler/cowork` checkout shape below was **abandoned** after the review
panel and a follow-on constraint analysis. Two hard facts collapsed it:
Cowork's sandbox will not follow a symlink out of `~/Claude`, and git-in-a-
bidirectionally-synced Syncthing folder corrupts at N=2 machines. No filesystem
link primitive (symlink/hardlink/bind-mount) crosses git + Syncthing + two
machines + Cowork's VM, so the only mechanism that works is **copying the bytes**.

Landed (interim, done):
- `keep` is the single source of truth (corpus + `VOICE.md`); nothing moved out.
- `~/Claude/writing/VOICE.md` is a plain REAL file, materialized (one-time `cp`)
  from `keep`; Syncthing carries it desk<->lappy. No symlink, no git, in Cowork's
  scope. The obsolete corpus symlink and the leaky scrub-map were removed from
  `~/Claude` (scrub-map recoverable, and its canonical copy stays in `keep`).
- `scottidler/cowork` was NOT created (fewer repos).

Parked (Scott's call, "we'll think on the real method"):
- The **materialize automation** (a `keep` git hook vs alternatives) — for now
  it's a manual `cp` when `VOICE.md` changes.
- The **Code-side rule** (`rules/voice.md` pointing at `~/Claude/writing/VOICE.md`)
  — still parked; needs the review-panel gate before it goes live.

The phased plan below describes the superseded `cowork` shape. It stays for the
road-not-taken record; it will be rewritten against the materialize shape when
the real automation method is chosen. Do not build from the phases as written.

## Summary

Wire Scott's writing voice into both Claude Code and Claude Cowork from a single
source of truth, without recreating the two-way symlink that ripgrep walked into
an unbounded traversal and locked the machine on 2026-07-03. The voice profile
(`VOICE.md`) lives as a real file inside Cowork's connected scope (`~/Claude`);
Claude Code reaches into that same file via an always-on rule pointer. The raw,
leaky corpus stays in `keep`, out of both agents' reach.

## Problem Statement

### Background

- The voice corpus was briefly committed to the PUBLIC `scottidler/claude` repo
  (commit `9e4caa7`) where the anonymizer LEAKED several real employee names and
  a vendor name (the specific strings are recorded privately in `keep`, never
  inlined in a public doc). That
  commit was purged (history rewritten, force-pushed, gc'd) and the corpus
  relocated to the PRIVATE `scottidler/keep` repo (renamed from `secrets`).
- On 2026-07-03 a prior agent wired the voice in via a **two-way symlink**: the
  in-repo corpus path pointed out to `~/Claude/...` while `~/Claude/...` was
  linked back into the repo. The resolved path never terminated. `rg` (Claude
  Code shells out to it on nearly every turn) followed the loop into an
  unbounded walk and pinned CPU/RAM. Root cause on record: symlink cycle, not
  "startup config" in the abstract.
- Two consumers, two different access models:
  - **Claude Code** (`~/.claude`, rules in `~/repos/.claude/`): no filesystem
    scope limit; reads any local path; follows symlinks.
  - **Claude Cowork**: a local desktop agent on the Claude Agent SDK, running in
    an isolated VM, that "can only read and write files in folders you've
    connected" (default workspace base `~/Documents/Claude` or `~/Claude`). A
    symlink inside `~/Claude` pointing OUT to `~/repos/...` targets a path
    outside the connected scope and will not resolve. Sources: [Get started with
    Claude Cowork](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork),
    [Use Claude Cowork safely](https://support.claude.com/en/articles/13364135-use-claude-cowork-safely).

### Problem

Deliver one canonical `VOICE.md` to both agents such that: Code reads it, Cowork
reads it (inside its sandbox), the graph is acyclic (can never loop `rg` again),
and the un-scrubbed raw corpus never enters either agent's reach.

### Goals

- Single physical `VOICE.md` consumed by both Claude Code and Cowork.
- Cowork reads it as a REAL file inside its connected scope (`~/Claude`).
- Claude Code reads it via a single always-on rule pointer (no per-skill copies).
- The symlink graph stays a DAG: real files in sources, one-way `$HOME -> source`
  edges only. A repeat of the 2026-07-03 cycle is structurally impossible.
- Raw corpus + scrub-map stay in `keep`, local-only, outside both agents' scope.

### Non-Goals

- **Excluded:** putting the raw corpus (or scrub-map) into Cowork's scope. It is
  source material, it still carries residual real names, and Cowork feeds what
  it reads to the API. Out by construction.
- **Parked (revisit condition):** fixing the anonymizer scrubber. Tracked
  separately; required BEFORE the raw corpus is ever exposed in readable form
  again, but not on this doc's path (only clean `VOICE.md` ships here).
- **Parked (revisit condition):** using `scottidler/cowork` for OTHER `~/Claude`
  workspace content. Only the voice ships now; the repo exists as the seam.

## Proposed Solution

### Overview

Anchor the shared file in the more-constrained consumer's territory. Cowork can
only see `~/Claude`; Code can see everything. So `VOICE.md` lives in `~/Claude`
and Code reaches in. No copy, no symlink-out, no cycle.

### Architecture

```
SOURCE MATERIAL (private, local-only, out of both agents' reach)
  scottidler/keep
    HOME/Claude/writing/voice/   raw corpus (leaky) + voice-scrub-map.yml
        └─ regenerates VOICE.md (build input; never auto-read by an agent)

CANONICAL VOICE (real files, git-versioned, in Cowork's connected scope)
  scottidler/cowork  ── cloned AS ~/Claude ──►  ~/Claude/writing/VOICE.md
        ▲                                            ▲
        │ Cowork reads IN-SCOPE                       │ Code reads it (no scope
        │ (via ~/Claude/CLAUDE.md hook)               │ limit) via the always-on
        │                                             │ rule's pointer
CLAUDE CODE HOOK
  scottidler/claude
    HOME/repos/.claude/rules/voice.md  ──► symlinked to ~/repos/.claude/rules/voice.md
        mechanics card + "for a full pass read ~/Claude/writing/VOICE.md"
```

- `VOICE.md`'s single home = `~/Claude/writing/VOICE.md` (working tree of
  `scottidler/cowork`). It moves there from `keep`; the raw corpus does NOT move
  (stays in `keep`). Only the one derived file relocates.
- Edges are one-way `$HOME -> source` for Code's rule (a single FILE symlink),
  and `~/Claude` IS the cowork checkout (no symlink at all on the Cowork side).
- The two always-on hooks (Code's rule, Cowork's `CLAUDE.md`) are thin pointers,
  not copies of the voice. The substance stays single-sourced in `VOICE.md`.

### Data Model

- `keep/HOME/Claude/writing/voice/` — raw corpus dirs + `voice-scrub-map.yml`.
  Unchanged from current state MINUS `VOICE.md`.
- `cowork` working tree (== `~/Claude`): `writing/VOICE.md` (flattened from
  `writing/voice/VOICE.md`), plus `CLAUDE.md` at the root as the Cowork hook,
  plus `.stignore` containing `.git`.
- `claude/HOME/repos/.claude/rules/voice.md` — the mechanics card, its "Full
  treatment" pointer updated from a keep path to `~/Claude/writing/VOICE.md`.

### API Design

Not applicable (filesystem wiring, no code interfaces). The "interface" is three
pointers, all resolving to one file:
- Cowork: `~/Claude/CLAUDE.md` says "voice: read `writing/VOICE.md`" (relative).
- Code: `~/repos/.claude/rules/voice.md` says "read `~/Claude/writing/VOICE.md`".
- Both land on the same real file.

### Implementation Plan

#### Phase 0: Prove the three environmental assumptions (zero code)
**Model:** sonnet
- Drop a real `VOICE.md` at `~/Claude/writing/VOICE.md`; open a Cowork session
  scoped to `~/Claude` and confirm it can read the file (in-scope real file).
- Confirm Cowork picks up guidance from a `CLAUDE.md`/`AGENTS.md` at the
  connected-folder root (which hook file it honors, and that it does).
- From a throwaway Claude Code session, confirm a subagent (Task tool) either
  DOES or does NOT inherit `~/repos/.claude/rules/*` — determines whether
  prose-drafting agents need an explicit pointer.
- **Success criteria:** Cowork reads `~/Claude/writing/VOICE.md` (observed in a
  session); the specific Cowork root-hook filename is identified; subagent
  rule-inheritance is answered yes/no with evidence. No code committed.

#### Phase 1: Create `scottidler/cowork`, relocate VOICE.md, make ~/Claude the checkout
**Model:** sonnet
- Create private `scottidler/cowork`. Seed `writing/VOICE.md` (the current
  clean profile from `keep`), add `.stignore` with `.git`, add root `CLAUDE.md`
  hook pointing at `writing/VOICE.md`.
- Replace the current `~/Claude/writing/voice` symlink so `~/Claude` becomes the
  `cowork` working tree with real files. `.git` stignored so Syncthing
  (desk<->lappy) never syncs it.
- Remove `VOICE.md` from `keep` (its home is now `cowork`); the raw corpus and
  scrub-map remain in `keep`.
- **Success criteria:** `~/Claude/writing/VOICE.md` is a REAL file (`test -f` and
  not `-L`), byte-identical to the profile that was in `keep`; `.git` is listed
  in `~/Claude/.stignore`; `keep` no longer tracks `VOICE.md`; `git -C ~/Claude
  status` clean.

#### Phase 2: Arm the Claude Code rule (single file symlink), gated by cycle check
**Model:** sonnet
- Update `claude/HOME/repos/.claude/rules/voice.md` "Full treatment" pointer to
  `~/Claude/writing/VOICE.md`.
- Arm it as a SINGLE FILE symlink: `~/repos/.claude/rules/voice.md` ->
  `~/repos/scottidler/claude/HOME/repos/.claude/rules/voice.md`. NOT via
  `manifest`'s recursive `HOME: $HOME` dir-linking.
- Gate: run the bounded cycle check (`find -L ~/Claude`, `find -L
  ~/repos/.claude`, `namei -l`, never `rg --follow`) and confirm zero "Too many
  levels". Then a throwaway-launch Claude Code session in a scratch dir with the
  rule present, confirming an `rg`-heavy operation completes bounded.
- **Success criteria:** `find -L ~/Claude` and `find -L ~/repos/.claude` emit
  zero "Too many levels of symbolic links"; the throwaway session's `rg` scan
  returns in bounded time; a prose-as-Scott task in that session resolves and
  reads `~/Claude/writing/VOICE.md`.

#### Phase 3: Single-source the hooks — delete redundant snippets, wire what Phase 0 requires
**Model:** sonnet
- Delete the hardcoded inline voice snippets from `slack`, `slackify`,
  `slack-clipboard` SKILL.md (the always-on rule now covers them).
- If Phase 0 showed subagents do NOT inherit the rule, add the pointer line to
  the frontmatter/body of any agent that drafts prose-as-Scott (verify which, if
  any — the technical agents need nothing).
- **Success criteria:** `grep -rniE 'as scott|no em-dash|slack-native' <skills>`
  returns zero inline voice snippets; every prose-drafting surface (skills via
  the rule; agents per Phase 0) has exactly one path to `VOICE.md`.

## Acceptance Criteria

- [ ] `~/Claude/writing/VOICE.md` is a real file (`test -f` true, `test -L`
      false) and byte-identical to the profile formerly in `keep`.
- [ ] `find -L ~/Claude -type f` and `find -L ~/repos/.claude -type f` both
      complete with ZERO "Too many levels of symbolic links" (no cycle).
- [ ] A throwaway Claude Code session with the armed rule completes an
      `rg`-heavy file scan in bounded time (no runaway).
- [ ] the scrub-map's real-name set (its `people:` keys, kept in `keep`) does
      not appear anywhere under `~/Claude` (raw corpus/leaks never entered Cowork scope).
- [ ] After cleanup, `grep -rniE 'as scott|no em-dash|slack-native'` across the
      `slack`/`slackify`/`slack-clipboard` skills returns zero (single-sourced).
- [ ] `.git` is present in `~/Claude/.stignore`.

## Resolved Decisions

- **2026-07-03 (Scott):** `VOICE.md` only goes to `cowork`; the raw corpus stays
  in `keep`. Rationale: Cowork needs the profile, not 2,900 raw prompts; keeping
  the corpus out of scope means the un-scrubbed material never rides to the API.
- **2026-07-03 (Scott):** `~/Claude` is the `cowork` checkout (real files), NOT a
  deploy-copy from `keep`. Cleaner: one git home, no artifact/source split.
- **2026-07-03 (Scott):** flatten `writing/voice/VOICE.md` -> `writing/VOICE.md`
  (the `voice/` subdir only earns its keep as a corpus container, which now lives
  in `keep`).
- **2026-07-03 (Scott):** anchor the shared file in Cowork's scope and let Code
  reach in, rather than the reverse. Constrained consumer dictates location.

## Alternatives Considered

### Alternative 1: Symlink `~/Claude/writing/voice` out to `keep` (the current state)
- **Description:** one-way symlink from `~/Claude` into the `keep` clone.
- **Pros:** zero copy; single git home in `keep`.
- **Cons:** Cowork's VM is scoped to `~/Claude`; a link out to `~/repos` leaves
  scope and will not resolve inside Cowork. Delivers nothing to Cowork.
- **Why not chosen:** fails the primary consumer.

### Alternative 2: Keep VOICE.md in `keep`, deploy a real-file COPY into `~/Claude`
- **Description:** `keep` stays the git home; a `manifest` script copies
  `VOICE.md` one-way into `~/Claude`.
- **Pros:** nothing leaves `keep`; source-of-truth unambiguous.
- **Cons:** two physical files (source + artifact) that can drift; a deploy step
  that goes stale; still needs a pointer from Code to the deployed copy.
- **Why not chosen:** Scott preferred a single git home in `cowork` over a
  source/artifact split. Recorded, not re-litigated.

### Alternative 3: Move the WHOLE corpus into `cowork`/`~/Claude`
- **Description:** the entire corpus (raw + VOICE.md) becomes the cowork checkout.
- **Pros:** everything voice-related in one repo.
- **Cons:** puts the leaky raw material in Cowork's scope and thus in reach of
  the API; ships far more than the agent needs.
- **Why not chosen:** violates the "raw corpus out of agent reach" goal.

## Technical Considerations

### Dependencies
- `manifest` (for the Code-side single-file symlink only, NOT recursive linking).
- Syncthing (`~/Claude` folder syncs desk<->lappy; `.git` stignored).
- `git`, `find`, `namei`, `rkvr` (for the symlink swap in Phase 1).

### Performance
- The always-on rule is a small mechanics card; `VOICE.md` is read on demand, not
  auto-loaded, so no per-session token cost beyond the card.

### Security
- Raw corpus + scrub-map (the real->fake name map) never leave `keep`; they are
  outside both agents' scope by construction, so residual leaks cannot reach the
  API. `cowork` is private. `VOICE.md` is verified clean (not in the leak set).

### Testing Strategy
- Phase 0 spikes prove the three assumptions before any wiring.
- Cycle detection (`find -L` bounded, `namei`) is the regression guard against
  the 2026-07-03 failure class; it runs as a Phase 2 gate and is an acceptance
  criterion. Prove it bites: introduce a deliberate two-way link in a scratch
  dir and confirm `find -L` reports "Too many levels", then remove it.

### Rollout Plan
- Ship order forced by dependency: `cowork` (VOICE.md must exist at `~/Claude`)
  -> `claude` (rule points at it, armed behind the gate) -> skill cleanup ->
  `keep` (drop VOICE.md) last. Cowork's `CLAUDE.md` hook lands with Phase 1.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Symlink cycle recurs, `rg` locks the machine | Low | High | DAG invariants; single FILE symlink only; no recursive `manifest` deploy; bounded cycle-check + throwaway-launch gate before global |
| `git` + Syncthing corrupt `~/Claude` (.git synced) | Med | High | `.git` in `.stignore`; each machine keeps its own `.git`, Syncthing carries only working files |
| Cowork honors a different root hook than assumed | Med | Med | Phase 0 identifies the exact hook file before wiring |
| Subagents don't inherit the rule; a prose agent goes voiceless | Med | Low | Phase 0 answers inheritance; hand-wire the rare prose-drafting agent |
| `VOICE.md` drifts from its `keep`-corpus source | Low | Low | `VOICE.md` has ONE home (`cowork`); regeneration reads `keep` and writes `cowork`; no second copy exists to drift |

## Open Questions

(none — the three unknowns are Phase 0 gates, and the scope decisions are in
Resolved Decisions)

## References
- `~/repos/scottidler/keep/CLAUDE.md` (keep repo purpose + secrets flow)
- Marquee page: https://marquee.internal.tatari.dev/p/~scott-idler/voice-corpus-wiring (the current-vs-old-cycle DAG)
- Memory: `project-voice-corpus`, `feedback-no-untested-startup-config`
- [Get started with Claude Cowork](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork), [Use Claude Cowork safely](https://support.claude.com/en/articles/13364135-use-claude-cowork-safely)
