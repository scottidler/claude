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

## Phase 2: Skills create, build, review
### Design decisions
- `skills/*/SKILL.md` frontmatter `name:` is bare (`create`, `build`, `review`); the loader adds `plan:`, same as Phase 1's agent finding. The init event lists `plan:build`, `plan:create`, `plan:review` and no bare `create`, `build`, `review`.
- `skills/create/SKILL.md`: the dispatch names the agent as `subagent_type: "plan:design-research"`, `Skill(review-panel)` became `Skill(plan:review)`, output is `docs/plan/`. `template.md` and `example.md` are copied byte-for-byte (`cp -p`).
- `skills/build/SKILL.md`: the seven `docs/design` write and read sites became `<doc-dir>`, the directory of the doc the caller passed, defined once in a new "Doc location rule" section before Step 2.5 (notes path, Status `sed`, `git add`, `Design doc:` lines of both commit templates, the finalization notes summary, the status commit). Step 1's `cat docs/<feature>-design.md` became `cat <doc-path>`. The delegated dispatch names `subagent_type: "plan:phase-implementer"`. `/create-design-doc` became `/plan:create` (4 places), the `/bump` integration row became `/plan:release`, and the merge wait names `plan:release-driver` (via `/plan:release`) and `pr:watch` in place of "babysitting".
- `skills/build/SKILL.md` finalization Steps 4-5 still describe the `bump release` / `bump finish` verbs and their ungated/gated behavior. Only the routing nouns were renamed; the release flow itself is Phase 3's `/plan:release`, and rewriting the finalization to call it is a behavior change the doc does not list for Phase 2.
- `skills/review/SKILL.md` is one skill with two paths keyed on the first argument word: `architect` | `staff-engineer` runs that seat script directly, anything else is the panel dispatch (`subagent_type: "plan:review-panel"`). Seat mode merges the two old entries into one flow with a per-seat table (script, persona, reach, announce text, output label, notes file) and per-seat prompts. Every seat script path is the absolute `/home/saidler/.claude/skills/plan/seats/<seat>/script.sh` at the head of the Bash command (Phase 0 (f)).
- The newest-doc `find` in `skills/review/SKILL.md` is `find docs/plan docs/design ... 2>/dev/null`, so a repo without `docs/plan/` is silent.
- The three agent files' `/create-design-doc`, `/how-to-execute-a-plan` renames (Phase 1's open question) are done in the plan copies only: `agents/design-research.md:3,11` -> `/plan:create`; `agents/phase-implementer.md:3,11` -> `/plan:build`; `agents/review-panel.md:3` -> `/plan:create`, `/plan:build`, and "Replaces running `/plan:review architect` then `/plan:review staff-engineer` by hand". The old agents under `HOME/.claude/agents/` and the old skill dirs are untouched; `otto lint`'s rollback-baseline check passed.
- `.otto.yml` lint `FILES` gained `skills/create/SKILL.md`, `skills/create/example.md`, `skills/build/SKILL.md`, `skills/review/SKILL.md`.

### Deviations
- `skills/create/template.md` stays out of lint `FILES`: the copy carries 9 em dashes from the original (lines 25, 26, 52, 53, 64, 77, 83, 110, 116). Same disclosed approach as Phase 1; de-dashing is a content edit outside the listed renames. Together with Phase 1's five files, six plan files are out of the list.
- `skills/review/SKILL.md` is a condensed merge, not a verbatim concatenation of the three sources: the two seat entries share one set of steps, the seat-specific prompt wording for focused prompts and the Mode 2 default prompt is carried as one template with the Staff Engineer differences named in a lead-in, and the original em dashes are replaced with commas and colons. The seat behavior (script-only, no direct CLI, `${TMPDIR:-/tmp}`, probes in Step 4.5, advisory stop) is unchanged.
- `skills/build/SKILL.md` still shows `docs/claude-code-parity-design.md` in the commit-message example and the Example Session (lines 342, 381, 414). They are illustrative sample text from another repo, not sites that read or write this repo's docs; left as copied.

### Tradeoffs
- `<doc-dir>` placeholder with one defining paragraph vs. spelling `docs/plan` or `docs/design` at each site: the placeholder cannot drift to one directory and matches the doc location rule ("derives the directory from the input doc's path"). Cost: the example lines no longer show a literal path.
- One review skill with argument routing vs. three files: the doc's Architecture lists a single `skills/review/SKILL.md`.
- Rename-only `build` finalization vs. calling `/plan:release` there: kept the proven text, left routing to Phase 3 (see Design decisions).

### Success criteria
- `claude plugin details plan@skills-dir` (fresh process, cwd scratchpad): `Skills (3)  build, create, review`, `Agents (4)  review-panel, phase-implementer, release-driver, design-research`. `claude plugin validate --strict` passes.
- `rg -n -e '"(design-research|phase-implementer|review-panel|release-driver)"' -e '/create-design-doc' -e '/how-to-execute-a-plan' -e 'skills/(architect|staff-engineer)/' HOME/.claude/skills/plan/skills` prints nothing (rc=1).
- Every `docs/design` hit in `HOME/.claude/skills/plan/skills`, by line (run as `rg -n -e docs/design ...`; the bare `rg -n docs/design <path>` form printed nothing in this sandbox session even against a file the same pattern matches under `-e` and under `grep`, so the `-e` form was used. Cause not found, recorded rather than guessed):
  - `skills/review/SKILL.md:23`: reader/writer rule text, names `docs/plan/` and `docs/design/` together (derives from caller path, scans both).
  - `skills/review/SKILL.md:27`: the newest-doc `find docs/plan docs/design`, a reader that names both dirs.
  - `skills/review/SKILL.md:373`: error-handling line, names `docs/plan/` and `docs/design/` together.
  - `skills/build/SKILL.md:61`: historical provenance citation (`docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md`, carried from the original line 61).
  - `skills/build/SKILL.md:185`: the Doc location rule, names `docs/plan/` and `docs/design/` and defines `<doc-dir>`.
  - `skills/build/SKILL.md:189`: same rule paragraph, names both dirs.
  - No hit remains in `skills/create/` (its writer is now `docs/plan/`). No write site in `build` hardcodes `docs/design`.
- `otto ci`: exit 0, `All CI checks passed!` (test task includes `claude plugin validate --strict` and the rollback-baseline lint).
- Throwaway launch: `claude -p "reply OK"` from the scratchpad printed `OK`, rc=0. A fresh init event lists `plan:build`, `plan:create`, `plan:review` and the four `plan:*` agents.
- pi, through its own `DefaultResourceLoader` (`SettingsManager.create(dir, dir)`, `reload()`, `getSkills()`) against a copy of the committed `HOME/.pi/agent/settings.json`: 136 skills, 0 from `/skills/plan/`. Control (same copy with the four `plan/skills/*` exclusions removed): 139 skills, 3 from `/skills/plan/` (`build create review`). So the exclusions are what hide the three real skills; `release` has no `SKILL.md` yet, so its entry is untested until Phase 3.

### Open questions
- The seat scripts and refs still name the old skills in comments and prose (`seats/architect/script.sh:7,33`, `seats/staff-engineer/script.sh:7,34,37`, `seats/staff-engineer/notes.md:4,33`, `refs/review-panel-prompts.md:8`: `/architect`, `/staff-engineer`). The doc says seat scripts move intact and Phase 6's prose list does not name them. Rename in Phase 3, 4 or 6, or leave?
- Bare `rg -n docs/design <path>` returned nothing here while `rg -n -e docs/design <path>` and `grep` matched. If the Phase 2 criterion is rerun as written in another session it may print nothing and read as a false PASS; the `-e` form is the reliable one.
