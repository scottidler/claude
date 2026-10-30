## Phase 0: Prove skills-dir loads skills and agents
### Design decisions
- (b) used a scratch settings file passed with `--settings` carrying a PreToolUse capture hook, never the committed `settings.json`; the scratch file and log were removed with `rkvr rmrf`.
- (e) judged by the `reason_type: "rule"` in the permission decision, because auto mode accepts the control call too and a denial cannot be produced under `defaultMode: auto`.
- (h) observed through pi's own `DefaultResourceLoader` against scratch agent dirs holding copies of `HOME/.pi/agent/settings.json` (pi has no list-skills command, and `pi -p` needs a model call).
- (i) driven in an interactive `claude` under tmux with pane capture, so it is verified, not UNVERIFIED.
- (j) `enable` removes the `enabledPlugins` key rather than writing `true`, so Phase 4's enumerator must treat an absent key as enabled.

### Deviations
- None.

### Tradeoffs
- Headless init events and a loader script prove load and registration. They do not prove `${CLAUDE_PLUGIN_ROOT}` expands inside a Bash command the model runs, only in skill and agent body text. Phase 1 can use it in bodies and should keep absolute paths at the head of Bash commands until Phase 5 proves it live.

### Open questions
- None.

## Phase 1: Skeleton, agents, seats, and the live-from-commit guards
### Design decisions
- Agent frontmatter `name:` stays bare (`review-panel`, not `plan:review-panel`) in `HOME/.claude/skills/plan/agents/*.md`: the plugin loader adds the `plan:` namespace itself, same as `tatari-skills/plugins/sre/agents/sre-deep-read-backlog.md`. The "agent names to `plan:*`" rewrite is therefore what the loader does, proven by the init event listing `plan:design-research`, `plan:phase-implementer`, `plan:release-driver`, `plan:review-panel`.
- `plan/agents/review-panel.md`: every Bash head and every file the agent reads is an absolute `/home/saidler/.claude/skills/plan/...` path (seat scripts at Step 3, the staff persona at Step 3.5, `refs/review-panel-prompts.md` at Step 2), per Phase 0 (f): `${CLAUDE_PLUGIN_ROOT}` is unproven inside a Bash command. The first incident-history citation names the absolute `refs/review-panel-notes.md`; the later `(incident: ...)` citations read `refs/review-panel-notes.md`.
- `plan/agents/review-panel.md` Step 1.1 newest-doc scan: `find docs/plan docs/design -name "*.md" ... 2>/dev/null`, so a missing `docs/plan/` in an older repo is silent and the pick spans both dirs (doc location rule).
- `plan/agents/release-driver.md`: description now says it is invoked by `/plan:release` with ENTRY `release` (gated, feature branch) or ENTRY `finish` (gated, PR merged), matching the doc's `/plan:release` branches 2 and 3; "babysit the PR" became "watch the PR" (description and step 4 heading); the `babysit/SKILL.md:80-91` `/loop` citation became `pr:watch`, described as it actually works (a `run_in_background` watcher that exits on the first event, read from `pr@tatari-skills` 0.6.0 `skills/watch/SKILL.md`), not as a `/loop` timer.
- `refs/review-panel-{notes,prompts}.md`: "Companion to `review-panel.md`" now reads `agents/review-panel.md`, since they no longer sit beside it.
- `hooks/panel-round-guard.sh`: the narrowing test is a `case` on `review-panel|plan:review-panel`; the entry log line names the actual `$subagent`. The counter key is untouched, so both names share one `(doc, mode)` entry.
- `.otto.yml` rollback-baseline check pins the full SHA `62dc65f2935efe78308bb87abd0d6eca0a12bb10` (this phase's parent) and prints `git diff --stat` on failure so the offending file is named.
- Bite-proofs, run 2026-10-29:
  - `panel-round-guard-test.sh` with the change: `pass=135 fail=0`. With `panel-round-guard.sh` stashed back to `62dc65f`: `pass=132 fail=3`, failing `plan:review-panel round 4`, `mixed round 4 as plan:review-panel`, `mixed round 4 as review-panel` (the bare name only reached round 3 because the two `plan:` dispatches were never counted). Restored: `pass=135 fail=0`.
  - Appended `bite probe` to `HOME/.claude/skills/shipit/SKILL.md`: `otto lint` rc=1, `The old pipeline files moved off the rollback baseline 62dc65f...` with `HOME/.claude/skills/shipit/SKILL.md | 1 +`. `git checkout --` of that file: rc=0.
  - Created untracked `HOME/.claude/skills/shipit/untracked-probe.md`: `otto lint` rc=1, `Untracked files under the old pipeline's rollback baseline`. `rkvr rmrf` of it: rc=0.
- Success criteria observed:
  - `claude plugin details plan@skills-dir` (fresh process, cwd `/tmp`): `Skills (0)`, `Agents (4)  review-panel, phase-implementer, release-driver, design-research`.
  - Fresh headless init event (`claude -p --output-format stream-json --verbose "reply OK"`, cwd `/tmp`): agents include `plan:design-research`, `plan:phase-implementer`, `plan:release-driver`, `plan:review-panel` beside the 4 bare old agents; `rg -c 'review-panel-notes|review-panel-prompts'` over the whole stream finds nothing; plugin `{"name":"plan","source":"plan@skills-dir","version":"0.1.0"}`.
  - Throwaway launch after the `settings.json` edit: `claude -p "reply OK"` from the scratchpad printed `OK`, rc=0.
  - pi, through its own `DefaultResourceLoader` against copies of the committed and the edited `HOME/.pi/agent/settings.json`: 136 skills each, 0 from `/skills/plan/`. Phase 1 ships no `skills/`, so this shows `agents/`, `refs/` and `seats/` register nothing in pi; the four exclusions' effect on real `skills/*` dirs is Phase 0 (h)'s measurement.

### Deviations
- `review-panel.md:139,151,229` are not rewritten. Each cites a specific existing doc (`docs/design/2026-09-15-intent-guards.md`, `docs/design/2026-09-14-panel-round-cap.md` twice) as incident provenance; those files stay in `docs/design/`, so pointing them at `docs/plan/` would break the citation. Only `:96`, the scan, is a reader the doc location rule governs.
- Five plan files stay out of the `.otto.yml` lint `FILES` list because their copies carry em dashes from the originals: `plan/agents/design-research.md` (14), `plan/agents/phase-implementer.md` (21), `plan/seats/architect/persona.md` (1), `plan/seats/staff-engineer/persona.md` (5), `plan/seats/staff-engineer/notes.md` (4). De-dashing them is a content edit outside the listed rewrites, and the two personas are prompt text piped to gemini and codex. The other ten plan files are in the list.
- `release-driver.md:168` (`review-panel.md:146-151`) is left as-is: it is a sibling reference that still resolves inside `plan/agents/`, and the rewrite list does not name it.

### Tradeoffs
- `cp -p` copies (mode and mtime kept) vs `git mv`: the old files are the rollback baseline and must stay byte-identical; the lint check now enforces that.
- Prose seat paths in `plan/agents/review-panel.md` (Who's on the panel bullets) are absolute rather than tilde, to match the Bash heads and leave no tilde form for the classifier to pattern on.

### Open questions
- Phase 3's criterion `rg -n babysit HOME/.claude/skills/plan` will hit `seats/architect/script.sh:76` and `seats/staff-engineer/script.sh:76` (`# PID handle so a babysitter can follow ...`), a generic word in a comment of scripts the doc says move intact. Either Phase 3 rewrites that comment in the copies or the criterion excludes `seats/`.
- `plan/agents/{design-research,phase-implementer,review-panel}.md` descriptions still name `/create-design-doc`, `/how-to-execute-a-plan`, `/architect`, `/staff-engineer`, since the `plan:*` skills do not exist yet. Phase 6's prose list does not name `plan/agents/*`; these need renaming by Phase 6 at the latest.
