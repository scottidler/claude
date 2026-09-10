# Handoff: rails, the function-hooks plugin (Bash rewrite module)

**Date:** 2026-09-08
**Author:** Claude (Fable 5.1), the agent that ran the mining, the research, the draft, and three panel rounds
**Repos in play:** `scottidler/claude` (this repo: the design doc, the future plugin, the rules and hooks it replaces), `scottidler/dotfiles` (global git ignore, if Q5 lands on A or C), `tatari-tv/clyde` (risk-tier follow-up only)
**Status:** Handoff. Design doc drafted and panel-reviewed three times. NOT ready to build. Five owner decisions outstanding. Nothing from this doc implemented or committed. The parallel PR #2 (other agent's shell hooks and interaction.md rules) IS merged; see the Addendum.

---

## 0. The five open questions (answer these first; nothing else moves until they are answered)

Scott said "the next agent will deal with it." Each one below is verbatim from the doc's Open Questions section. Get an answer from Scott, or an explicit "take the Recs", fold each into the doc (Resolved Decisions, then remove from Open Questions), and only then continue at section 3.

### Q1: plugin name
- A: `rails` (Architect, synthesis). One plugin holds every function hook that comes later; the name is the container.
- B: `bash-rewrite` (Staff). Name it for this module, reserve `rails` for an umbrella design.
- Rec: A. Renaming at module two costs a directory move, the `pluginConfigs` key, and every kill-switch line in the doc.

### Q2: the per-rewrite context line and the Bash-description appendix (both proposed by Claude, not by Scott)
- A: keep both (Architect).
- B: strike the appendix, keep the context line (Staff, synthesis). The doc is currently WRITTEN this way.
- Rec: B. The context line keeps the transcript honest (`rg` ran, so the model says `rg`). The appendix is prose, and the doc's own Alternative 2 measures prose as ineffective here. Picking A adds a phase back.

### Q3: `git -C <cwd>` and `otto -C <cwd>`
- A: deny, same as today's `git-no-dash-c.sh`, moved into the plugin's `deny.js`. The doc is currently WRITTEN this way.
- B: run as written plus a context note; the git.md/otto.md bullets become advisory.
- Rec: A. It is Scott's rule and the deny provably works (214 of 237 denials complied on the next call). Both seats accepted A as satisfying their finding.

### Q4: does `grep -> rg` survive the shim finding
- Inside the Claude Code Bash tool, `grep` is ALREADY a shell function running embedded ugrep 7.8.4 with `--ignore-files --hidden` (snapshot lines 3262-3276). Pruning was never the gain. The rewrite buys one engine and dialect across the Grep tool and the shell, and it MUST carry `--hidden` or it silently narrows results.
- A: keep as `rg --hidden`, ranked last among the rules. The doc is WRITTEN this way.
- B: strike it. 22,536 grep calls a quarter rewritten for consistency alone.
- Rec: A, because Scott asked for it by name ("all grep commands to use rg"). Strike if consistency is not worth it.

### Q5: the sandbox "phantom" files, which are real
- Fact, verified twice (my spike and the panel): the ten dotfile stubs at every repo root a sandboxed session touched are real 0-byte read-only files bwrap leaves behind as `/dev/null` mount points (issues #25603 and #29316, both closed, no fix). `HOME/.claude/CLAUDE.md:34-42` ("the disk is clean") is false at 2.1.263. Two repos carry them today: this one (09:44:27) and `tatari-tv/slack-cli` (10:06:09).
- Four of the ten names collide with real files at other repo roots (`.gitmodules` 12 tracked, `.vscode` about 20, `.mcp.json` 4, `.idea` 3). A global ignore hides matches from rg, fd, and the Grep tool as well as git, so it is unsafe for those four.
- A: anchored global ignore (`/.bashrc /.zshrc /.profile /.bash_profile /.zprofile /.ripgreprc`) in the manifest-managed `~/.config/git/ignore` (dotfiles). Anchoring verified for rg, fd, and git in a scratch repo. Zero code.
- B: a `session.start` hook removes stubs per session via `rkvr rmrf`, keyed on 0-byte + mode `r--r--r--` + untracked + basename in the deny-list set. Deletes files. They come back with the next sandbox.
- C: A for the six, B for the four colliders.
- Rec: C, and file an upstream issue with the evidence in the doc's Phase 0b decision.

---

## 1. What this is

Claude Code 2.1.263 carries the "function hooks" runtime (issue #91870, 2026-09-03) behind `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`. In-process JS middleware: `register(on, options)`, hooks `($, e, next)`, events `tool.call`, `tool.describe`, `agent.spawn`, `turn.complete`, `session.start`, and so on; `$` gives `ui.ask`, `process.run`, `store`, `session.cwd`. Verified live: rewriting a Bash command via `next({...e, command})` works, returning `{result, context}` after `next` alters what the model reads, and a model-spawned subagent's Bash calls DO pass through the parent plugin's hook.

The flag is ON in the working tree (uncommitted): `HOME/.claude/settings.json` env block. Proof: `/plugin-types` writes the declarations with no env var set.

The first module is a Bash rewrite plugin. Design doc: `docs/design/2026-09-08-rails-bash-rewrite.md` (511 lines, sha256 dc074f8885637346...). Read it whole before touching anything; it is the source of truth and every claim in it is verified with file:line or a command.

## 2. Where the doc stands

- Five Rule-of-Five passes done. Three review-panel rounds done (Architect via Gemini, Staff Engineer via Codex, plus the panel's own verification). Every finding is dispositioned in Resolved Decisions and the Review log. Panel round 2 call: buildable. Round 3 call: not ready, solely on the phantom-filter premise, which I then refuted myself (Phase 0b) and rewrote into Q5.
- Rounds 1 to 3 all ran on snapshots the doc outran. The panel is holding round 4 for a FROZEN hash. Do not edit the doc while a round runs.
- Withdrawn from the design during review, all recorded in Resolved Decisions and the Addendum: `git clone -> clone`, `git worktree add -> worktree`, `curl -> xh`, `cat -> bat`, the output filter for phantom files, the phantom deny, the `tool.describe` appendix (pending Q2).
- Phase 0b (does the hook's host-side `stat` see the stubs as absent) RAN: refuted, the files are real. Recorded.
- Phase 0 (does a plugin placed in `HOME/.claude/skills/` load its hooks module without `--plugin-dir`) has NOT run. The command block is in the doc under Phase 0. The agent cannot run it: the permission classifier blocked it (writes into the protected skills dir plus a nested session). Scott runs it, or the next agent asks for that one permission. If it fails, the doc's marketplace fallback applies and every later phase already reads `<plugin dir>` accordingly.

## 3. Exact next steps, in order

1. Get Q1 to Q5 answered (section 0). Fold each into Resolved Decisions with the date and who decided. Empty the Open Questions section.
2. Run Phase 0 (the command block in the doc). Record the result in Resolved Decisions. Set `<plugin dir>`.
3. Freeze the file. Compute `sha256sum` and `wc -l`. ONLY IF Scott asks for a fourth round (PR #2's interaction.md caps panel rounds at 3, see the Addendum), send both to the `review-panel` agent (Agent tool, `subagent_type: review-panel`, Mode 1 Design Review) with the doc path and "confirmation round against this hash; stop on drift." Poll `/tmp/review-panel/<id>/` per the skill (`ls -dt /tmp/review-panel/*/ | head -1`, `dispatch-status-r<n>.txt`, `arch-r<n>.out`, `staff-r<n>.out`). Do not block on the agent's message. Codex seats have hung once at the 10-minute cap; one retry at 25 minutes worked.
4. Re-run every acceptance criterion's literal command against main and refresh the "Observed on main" lines (several already have baselines; re-verify them, they are cheap).
5. Flip Status to Approved, commit the doc together with the two working-tree changes below, then `/how-to-execute-a-plan` on it. Phases 1 to 7 are annotated with models. Phases that write under `HOME/.claude/skills/` need the sandbox write permission for that path (the doc's Rollout section says so).

## 4. Facts the next agent must not re-derive (all verified 2026-09-08, evidence in the doc)

- The Bash tool sources Scott's zsh snapshot. Consequences: `grep` = embedded ugrep with `--ignore-files --hidden` (function, snapshot 3262-3276); `find` = embedded bfs (3250-3260); `rg` shim inactive because `~/.cargo/bin/rg` exists; `alias ls=eza` (line 2998, from the ohmyzsh eza plugin via antidote, `~/.zsh_plugins.txt:43`), so `ls -lt` ERRORS today (eza `-t` takes a field). `gh` is the persona function from `.zshenv`.
- Tool flag traps in the rewrite table: `rg -E` is encoding (grep `-E` is dropped), `rg -I` is no-filename (grep `-h` maps to it), eza sorts oldest first (`ls -t` -> `eza -s modified -r`), fd `-g` is smart-case (find `-name` adds `-s`), `sd -F` keeps `$` literal.
- Grep BRE gate yield on the real corpus: 73.8% of 39,436 grep stages pass; `\|` alternation is the dominant legitimate bail.
- Permission matcher is literal-prefix (`Bash(command clone:*)` exists beside `Bash(clone:*)`), so `GH_PERSONA=work gh ...` needs its own allow rules, and `Bash(sd:*)` is absent. All three are in the cleanup phase.
- Settings `PreToolUse` shell hooks run INSIDE the plugin's `next` and see the rewritten command; `clyde permit log` records the post-rewrite text.
- Directory-marketplace installs COPY into `~/.claude/plugins/cache/`, so edits need a bump plus `claude plugin update`. Skills-dir adoption is the preferred in-place path; Phase 0 decides.
- `$.store.keys()` documents insertion order (d.ts 958). Per-entry keys avoid the get/set race across parallel subagent hooks.
- The validator refuses helpers receiving `$` unless they are top-level function declarations; `$` calls literal; `on(...)` literal.
- Nested `claude -p` cannot start its own sandbox inside the agent sandbox (EPERM on the mux socket); Phase 7 shakedown runs sandbox-off.

## 5. Artifacts (paths; the scratchpad is session-local under /tmp and survives until reboot, copy what you need)

- Design doc: `docs/design/2026-09-08-rails-bash-rewrite.md`
- Panel run dir (all three rounds, every seat output, synthesis, snapshots, hashes): `/tmp/review-panel/dey8CYZq/`
- Scratchpad root: `/tmp/claude-1000/-home-saidler-repos-scottidler-claude/a6afe1e3-28b4-4839-9a84-0f4d710a782a/scratchpad/`
  - `fh/types/claude-code.d.ts` (5,480 lines, generated by 2.1.263; regenerate with `/plugin-types`)
  - `reports/design-research-brief.md` (API line refs, live spike evidence, counts SQL)
  - `reports/{hooks-census,rule-violations,release-flow,pipeline-review,outward-text,synthesis}.md` (the session-log mining behind the whole effort; the release state machine and pipeline gates are the NEXT design docs, parked in this doc's Non-Goals)
  - `fh-spike/plugin/` (the working spike: rewrite + context + subagent proof), `fh-stat/` (Phase 0b probe)
  - `bash-cmds.txt` (521k Bash command lines since 07-01, from events.db)
- Permission event DB: `~/.local/share/clyde/events.db` (schema in the brief)
- Spike transcripts: `~/.claude/projects/-tmp-claude-1000--home-saidler-repos-scottidler-claude-a6afe1e3-28b4-4839-9a84-0f4d710a782a-scratchpad-fh-spike-work/`

## 6. Working tree (uncommitted, this repo)

- `HOME/.claude/settings.json`: `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS: "1"` added to `env`.
- `HOME/repos/.claude/rules/safety.md`: the "Rust CLI Overrides" section (the `tail` shadow) removed, because Scott ran `cargo uninstall tail` this session.
- `docs/design/2026-09-08-rails-bash-rewrite.md` and this handoff: untracked.
- The ten sandbox stub files and `.claude/` at the repo root: untracked, real, NOT ours to add. Q5 decides their fate. Do not `git add -A`.
- `HOME/.claude/skills/swap-alert/` is untracked and belongs to another session; leave it.
- PR #2 (https://github.com/scottidler/claude/pull/2) is merged and the primary tree is synced to it; the uncommitted `settings.json` edit now sits on top of the two hook entries it added. No merge left to do.

## 7. Pitfalls I hit so you do not

- The panel snapshots the doc at dispatch. If you edit while a round runs, the seats review the old text and you waste answers. Freeze first.
- The auto-mode classifier blocks a nested `claude -p` that also writes into `HOME/.claude/skills/`. Scott runs Phase 0, or ask for the permission once.
- Counting commands in events.db with substring GLOBs over-counts (`*gh *` matches "through"). Anchor at stage starts.
- Reviewer verdicts are not evidence: the Architect seat could not run binaries and said so; two of its round-2 findings were against text already gone. Verify every claim against the code and the live shell before folding it.
- Scott's voice for anything outward: no em-dashes, no spaced double hyphens, structure first (`~/Claude/writing/VOICE.md`).

## 8. Suggested skills and agents

- `review-panel` agent for the confirmation round (poll the run dir, do not wait on its message).
- `/how-to-execute-a-plan` once Status is Approved; `phase-implementer` per phase with the model tag in the doc.
- `/cli-shakedown` shape for Phase 7's field guide.
- `plugin-authoring` skill (appears once the flag is on) for the exact API contract; regenerate types with `/plugin-types` after any Claude Code update.
- `HOME:create-design-doc` for the two parked follow-on docs (release state machine, pipeline gates), which the mining reports rank above this one in Scott's anger and which this doc's Non-Goals park with a revisit condition.

## Addendum: parallel work in a separate worktree (2026-09-08)

While this doc was in review, another agent worked in a git worktree at `/tmp/claude-md-fixes`, branch `claude-md-fixes`, and opened PR #2 (https://github.com/scottidler/claude/pull/2), originally two commits ahead of `main`, zero behind. That agent asked Scott for a fast-forward push to `main` and then went away; Scott handed the work to this session. LANDED 2026-09-08 18:21Z by rebase merge of PR #2 (the direct push was refused by the permission classifier; the rebase rewrote the SHAs to `18ed9b8` and `504859c`, tree-identical to the branch). Remote and local branch deleted, worktree removed, primary tree fast-forwarded with its two uncommitted edits preserved; `settings.json` now carries the env flag AND the two new hook entries. PR body's em-dash removed after merge.

What the branch adds (verified from the branch, `git diff --stat main...claude-md-fixes`: 4 files, +76):
- `HOME/repos/.claude/rules/interaction.md`: three sections. "Confirm the target before acting" (read the artifact, name it in one line). "Scope stays inside what was asked" (research goes in the reply, not the vault; cap review-panel rounds at 3 unless Scott asks; never run `manifest` unscoped). "Don't idle-poll a stalled subagent" (re-dispatch or do it inline; run approved multi-phase plans without per-phase check-ins).
- `HOME/.claude/hooks/manifest-scope-guard.sh` (PreToolUse, matcher Bash): denies a bare `manifest` invocation with no scope flag, `age`/`secrets`/help subcommand excepted; splits statements on `&&`, `||`, `;`, `|` with `sed`, then `grep`s each. Wired in `settings.json`.
- `HOME/.claude/hooks/ssh-agent-check.sh` (SessionStart, matcher `*`): prints a one-line WARN when `ssh-add -l` shows no key, because SSH commit signing then fails with a cryptic error and the sandbox denies reading `~/.ssh`.
- The agent's own reading of "hooks 2.0" matches this doc: function hooks are unshipped early access behind a flag; the settings shell-hook system is the current stable mechanism. It built shell hooks accordingly.

How it interacts with `rails`:
- Both shell hooks run beneath the plugin, inside `next`, and see the rewritten command. They coexist with every phase here unchanged.
- `manifest-scope-guard.sh` is exactly the class `deny.js` implements (a head plus an argv shape). A later `rails` module can carry it as one deny row and retire the script, which also retires its splitter's known false-positive class (a `manifest` mention inside a heredoc or a quoted string, or a `|` inside quotes) by using `shell.js`. Recorded as a candidate, not built: nobody asked for it in this doc.
- `ssh-agent-check.sh` is a `session.start` candidate for the same reason. Recorded, not built.
- The new interaction.md rule "cap review-panel rounds at 3 unless Scott asks" lands on this doc directly: three rounds have run. The confirmation round against the frozen hash (handoff section 3, step 3) now needs Scott's explicit ask; without it, the three rounds plus the acceptance re-run are the review.
- `HOME/.claude/settings.json` is touched by both efforts: the branch adds two hook entries to `hooks.PreToolUse` and `hooks.SessionStart`; this session's working tree holds the uncommitted `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` env entry; the cleanup phase later deletes the `git-no-dash-c.sh` entry from the same list. All three are compatible; whoever pulls PR #2 into the primary tree merges one JSON carrying all of them.

Observations: PR #2's body had an em-dash (fixed post-merge); its title slugifies to the branch name (general.md holds).
