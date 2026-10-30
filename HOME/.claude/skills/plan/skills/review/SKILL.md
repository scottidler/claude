---
name: review
description: Cross-model review of a design doc. No argument runs the panel (Gemini Architect + Codex Staff Engineer in parallel, one reconciled findings list); `architect` or `staff-engineer` consults that one seat alone. Use after /plan:create's draft passes, or after /plan:build finishes every phase, or when the user says "get the reviewers on this", "have the panel look at it", "send it to review-panel", "run a design review", "run an implementation audit", "consult the architect", "ask the staff engineer", or "second opinion on this doc".
argument-hint: "[architect|staff-engineer] [doc-path] [--dirs path1,path2] [focus question]"
---

# Plan Review

One entry point for every cross-model review of a design doc.

| Invocation | What runs |
|---|---|
| `/plan:review` | The panel: the `plan:review-panel` agent fans both seats out in parallel and returns one reconciled findings list. Counted by the round cap. |
| `/plan:review architect` | The Architect seat alone (Gemini), script called directly. Not counted by the round cap. |
| `/plan:review staff-engineer` | The Staff Engineer seat alone (Codex), script called directly. Not counted by the round cap. |

The first word of the arguments picks the path: `architect` or `staff-engineer`
means seat mode, anything else (or nothing) means panel mode, and the rest of
the arguments carry through (doc path, `--dirs`, focus question, open questions).

## Doc location rule

New docs live in `docs/plan/`, older ones in `docs/design/`. Never assume one
directory. A doc path given by the caller is used as-is; with no path, scan both:

```bash
find docs/plan docs/design -name "*.md" -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -5 | awk '{print $2}'
```

A missing `docs/plan/` in an older repo is silent (`2>/dev/null`), and the pick
spans both. Tell the user which doc was found before proceeding.

---

# Panel mode (no seat argument)

`review-panel` is an **agent** (`/home/saidler/.claude/skills/plan/agents/review-panel.md`,
reached as `plan:review-panel`). This skill dispatches it and relays what comes
back. **It replaces every "send it to the review-panel agent" instruction
elsewhere** (e.g. `/plan:create`'s Pass 5), so there is one entry point, not two
signals for the same action.

The agent is the whole point: it fans the **Architect** (Gemini) and **Staff
Engineer** (Codex) out in parallel, monitors both, and writes one reconciled
findings list. Never substitute your own review for theirs.

## What to do

1. **Gather what the agent needs**, from the caller or the current context:
   - **DOC_PATH**, the design doc, absolute path.
   - **Open questions**, numbered, if the caller has any; the agent answers
     each one explicitly.
   - **Scope for this round**: "full design review", "review only the
     deltas since round N", "implementation audit", etc. Pass it literally;
     the agent's Step 0 decides the round number and mode from the doc itself.
2. **Spawn the agent** (Agent tool, `subagent_type: "plan:review-panel"`)
   with DOC_PATH, the open questions, and the scope. Don't pre-chew the
   doc or summarize it, the agent re-snapshots and re-hashes it itself.
3. **Relay its report as-is**: the synthesis file path, the findings, and any
   UNANSWERED verdicts. The consensus loop (fold in agreements, push back
   with rationale, escalate only what can't be closed) is the caller's job,
   not this skill's, this skill's job ends at the dispatch and the relay.

## Another round runs ONLY on open items or disputes

After a round, fold in every finding you agree with and push back on the rest.
Then:

- **Nothing open, nothing disputed**: the doc is ready. Tell Scott so. Do not
  dispatch. "Verify the fixes", "the doc changed", "the fixes are big", and
  "rounds remain under the cap" are not reasons.
- **Something open or disputed**: dispatch the next round with each item on a
  line of its own, `OPEN: <item>` or `DISPUTE: <finding> | <your pushback>`,
  and scope the round to exactly those.

`panel-round-guard.sh` denies a round-2+ dispatch with no such line. Scott's
`PANEL_ROUNDS_ORDERED_BY_SCOTT=<n>` counts as his reason.

## The round cap is enforced at dispatch, not here

`panel-round-guard.sh` (a `PreToolUse` hook on the Agent dispatch, matched on
`tool_input.subagent_type` being `review-panel` or `plan:review-panel`) denies a
round past the cap in `rules/interaction.md`. A denial comes back in place of a
report: fold the existing findings into the doc and build, or get Scott's
explicit `PANEL_ROUNDS_ORDERED_BY_SCOTT=<n>` per that rule. Don't retry the
dispatch to work around a denial, that is exactly the silent overrun the guard
exists to stop.

## Rules that never bend

- **Never** review the doc yourself and call it a panel round. The value is
  the two *different models*; this skill exists only to reach them.
- **Never** dispatch again because the first round "seemed incomplete" or
  because the doc changed. Read what came back, fold it in, and dispatch again
  only for items still open or disputed.

---

# Seat mode (`architect` or `staff-engineer`)

Consult one reviewer alone, or drive a multi-round follow-up with it. For both
reviewers on the same doc, use panel mode instead: it resolves doc, mode and
dirs once and runs the seats in parallel with monitoring.

| | `architect` | `staff-engineer` |
|---|---|---|
| Model | Gemini | OpenAI Codex |
| Script | `/home/saidler/.claude/skills/plan/seats/architect/script.sh` | `/home/saidler/.claude/skills/plan/seats/staff-engineer/script.sh` |
| Persona | `seats/architect/persona.md`, prepended by `script.sh` on every call | `seats/staff-engineer/persona.md`, prepended by `script.sh` on every call |
| Reach | workspace-jailed to `$PWD` plus `--include-directories` | read-only sandbox, reads any path on disk |
| Announce | "Consulting the Architect via Gemini. Detecting mode..." | "Consulting the Staff Engineer via Codex. Detecting mode..." |
| Output label | `[ARCHITECT]` | `[STAFF-ENGINEER]` |
| Operating notes | `seats/architect/limitations.md` | `seats/staff-engineer/notes.md` |

Both personas are strictly read-only and consultative, skeptical, and verify
claims against the codebase before opining. The persona is deliberately not
delivered through a global config (`~/.gemini/GEMINI.md`, codex `AGENTS.md`),
so unrelated calls to either CLI stay neutral. The Architect cannot run
anything; the Staff Engineer runs `rg`/`git`/file reads in a read-only sandbox
but cannot write or build.

Examples:
- `/plan:review architect docs/plan/2026-04-16-foo.md`
- `/plan:review staff-engineer docs/plan/2026-04-16-foo.md focus on the failure modes under load`
- `/plan:review architect docs/plan/foo.md --dirs ~/repos/other-service,~/repos/shared-lib audit the wire format`
- `/plan:review staff-engineer` (auto-detect doc and mode)

## Step 1: Resolve the doc

If a path was given, use it (relative paths resolve from `$PWD`). Otherwise use
the doc-location scan above.

- **Mode 2 context** (just ran `/plan:build`): prefer docs containing "Implemented".
- **Mode 1 context** (just ran `/plan:create`): prefer the most recently modified doc.

## Step 1.5: Resolve extra directories

Build `EXTRA_DIRS`, a comma-separated list, from:

1. **Doc root (auto)**, if the doc is outside `$PWD`: its repo root.
2. **`--dirs <comma-list>`**: parse these out of the arguments before treating the remainder as the focus question.
3. **Reference repos named in the prompt, the doc, or the conversation** (absolute paths, `~/repos/<org>/<repo>`, or bare slugs with a local clone at `~/repos/<slug>`). If several clones plausibly match, ask once which one.

```bash
DIRS=()
DOC_ABS=$(realpath "$DOC_PATH")
PWD_ABS=$(realpath "$PWD")
case "$DOC_ABS" in
  "$PWD_ABS"/*) ;;
  *)
    DOC_DIR=$(dirname "$DOC_ABS")
    DIRS+=("$(git -C "$DOC_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$DOC_DIR")")
    ;;
esac

# Append each path from sources 2 and 3 with $HOME, not ~ (a variable does not expand ~):
#   DIRS+=("$HOME/repos/scottidler/loopr-v5")

EXTRA_DIRS=$(
  for d in "${DIRS[@]}"; do
    d="${d/#\~/$HOME}"
    abs=$(realpath -e "$d" 2>/dev/null) || { echo "warn: skipping missing dir: $d" >&2; continue; }
    echo "$abs"
  done | awk 'NF && !seen[$0]++' | paste -sd, -
)
```

- Architect: Gemini refuses files outside `$PWD`, so `EXTRA_DIRS` becomes `--include-directories`. Print what is included before the call so the user can correct it. Empty is fine: pass `""`.
- Staff Engineer: codex reads any path, so `EXTRA_DIRS` is only a hint injected into the prompt as read-only reference paths. Empty is fine: pass `""`.

## Step 2: Detect mode

- **Mode 1, Design Review**: the doc has no "Implemented" status marker. Judge whether the design is sound.
- **Mode 2, Implementation Audit**: the doc contains "Implemented". Judge whether the code delivered the spec.

Announce `Detected mode: Design Review` or `Detected mode: Implementation Audit`.
If unclear, ask the user to confirm.

## Step 3: Mode 2 only, gather commit context

```bash
PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null)
if [ -n "$PREV_TAG" ]; then
  echo "=== Commits since $PREV_TAG ==="
  git log $PREV_TAG..HEAD --oneline
  echo ""
  echo "=== Diff stat ==="
  git diff $PREV_TAG..HEAD --stat
else
  echo "=== No previous tag found, showing last 20 commits ==="
  git log --oneline -20
fi
```

Embed this in the prompt next to the doc. A range polluted by later unrelated commits is acceptable; the seat stays on what the doc describes.

## Step 4: Call the seat script

**CRITICAL: ALWAYS call the script. NEVER construct a `gemini` or `codex` command directly, not for round 1, not for follow-ups, not for "just this once" debugging. Do not pass `-m`, `--model`, `-s`, `-c`, `--cd`, `--include-directories` or any CLI flag inline. The script enforces the model, policy, sandbox and persona; bypassing it silently disables those guarantees.**

Two argument forms, with the script path from the table above at the head of the Bash command:

- Literal prompt (round 1, short):
  ```bash
  /home/saidler/.claude/skills/plan/seats/<seat>/script.sh "$DOC_PATH" "<prompt-string>" "$EXTRA_DIRS"
  ```
- Prompt file (follow-ups, multiline, anything with quotes or backticks):
  ```bash
  PROMPT_FILE="${TMPDIR:-/tmp}/<seat>-prompt.txt"
  cat > "$PROMPT_FILE" <<'EOF'
  <multi-line prompt body, no shell escaping needed inside a quoted heredoc>
  EOF
  /home/saidler/.claude/skills/plan/seats/<seat>/script.sh "$DOC_PATH" "$PROMPT_FILE" "$EXTRA_DIRS"
  ```
  The script detects that arg 2 is an existing file and reads the prompt from it.

**Always `${TMPDIR:-/tmp}`, never bare `/tmp`.** The Bash sandbox mounts `/tmp`
read-only, so a bare `/tmp` heredoc fails with `Read-only file system (os error 30)`
and the review never runs.

Architect only: a prompt starting with `-` characters (`--- CONVERSATION SO FAR ---`)
once broke gemini's parser (`Not enough arguments following: p`); the script now
passes `--prompt="$PROMPT"` in equals form, so that failure is closed.
Staff Engineer only: the doc is piped to codex on stdin and shows up to the
reviewer as a `<stdin>` block, so prompts say "the design document provided on stdin."

### Mode 1 prompts

Architect, default:

```
Review this design document as the Architect. Implementation has NOT started yet.

Identify:
1. The top architectural risks and why they concern you
2. Assumptions that are unverified or could break under load
3. Missing design decisions that should be made explicit
4. Your hardest question for the author

Be specific. Reference exact sections and claims. Verify against the codebase before asserting.
Do not praise without cause.
```

Staff Engineer, default:

```
Review this design document as the Staff Engineer. The design document is provided on stdin. Implementation has NOT started yet.

Identify:
1. The top risks to correctness, operability, and maintainability, and why they concern you
2. Assumptions that are unverified or that break on the unhappy path / under load
3. Missing design decisions that should be made explicit (failure handling, migration, rollback, observability)
4. Your hardest question for the author

Verify against the actual codebase before asserting: run rg/git/read the relevant files. Be specific; reference exact sections, files, and line numbers. Do not praise without cause.
```

Focused (either seat; Staff Engineer adds "(provided on stdin)" after "this design document" and "(rg/git/read)" after "verify"):

```
Review this design document as the <Architect|Staff Engineer>, focusing specifically on: <user-provided focus>.

Be specific. Reference exact sections and claims. Verify before asserting.
```

### Mode 2 prompts

Default, either seat (the Staff Engineer variant names `rg`/`git`/read for every verification, and its regression item uses `git show <PREV_TAG>:<path>` to read the pre-change version of each touched function):

```
Review this design document as the <Architect|Staff Engineer>. The implementation is COMPLETE.

Here is the commit log and diff summary since the last release tag:

<git log + diff stat output from Step 3>

Your job is to audit whether the implementation actually delivered what the design specified.

**COMPLETENESS IS REQUIRED.** Walk the Implementation Plan section of the design doc phase by phase, bullet by bullet. For every bullet point, verify it was actually implemented by reading the code. A bullet that says "add X to Y" means read Y and confirm X is there. Do not assume a bullet was done because related work was done. Cross-module wiring steps, config loading hooks, daemon integration points, and registrations are the most commonly skipped, check these explicitly.

Identify:
1. **Completeness gaps**: every bullet in the Implementation Plan that was not implemented or was only partially implemented. This is the primary finding. Name the exact bullet and the file/function where the implementation is missing.
2. Design requirements that appear unimplemented or only partially implemented (beyond the phase bullets)
3. Implementation decisions that deviate from the spec, intentional or not
4. Code patterns that contradict the design's stated approach
5. Anything skipped, quietly deferred, or changed without acknowledgment
6. **Behavioral regressions, a first-class finding.** For every commit that changes runtime behavior, ask what a user could observe that changed against the PREVIOUS release: an input, command, config, or ottofile that was accepted or produced result A before, and now errors, hangs, or produces result B. Two shapes to hunt: (a) a commit message that claims to fix a CLASS ("every X", "all Y forms") but fixes one instance, name the cases still broken; (b) a change whose target is reached by an unrelated code path the phase never touched. The design doc's stated behavior changes are the ALLOWED set; anything else a user could have relied on that changed is a regression. For each, emit a concrete differential probe on its own line, prefixed `PROBE:`: the exact command or input, what the previous release did, and what the current tree does.

Be specific. Reference exact design sections and cross-check against the actual commits and code.
Do not praise without cause.
```

Focused: the Mode 1 focused prompt, then "The implementation is COMPLETE. Commit context since last tag:", the Step 3 output, and the **COMPLETENESS IS REQUIRED** paragraph (phase by phase, bullet by bullet, cross-module wiring first).

Display the response as `[ARCHITECT]` or `[STAFF-ENGINEER]` followed by exactly what the script returned.

## Step 4.5: Mode 2, run the differential probes (Claude, not the seat)

Neither seat can run the binary: the Architect only reasons from code, and codex
runs read-only (it can read the base version with `git show` and name a
suspected regression, not confirm one). You are not sandboxed, so you close the gap.

For every `PROBE:` the seat emitted, and every behavior-changing commit in the
range it did NOT probe, run it both ways:

- Build the current tree once.
- Get the previous-release binary: the installed one is usually it (`which <tool>`, confirm `<tool> --version` against `$PREV_TAG`); otherwise `git worktree add <tmp> $PREV_TAG` and build there. Never compare the new tree against itself.
- Run the probe against both and capture both outputs verbatim.

Report under `[CLAUDE]`: a difference the doc does not call out is a confirmed
regression (show the command and both outputs); a probe that behaves
identically is a cleared suspicion, one line. Running a read-only probe is
verification, not fixing.

## Step 5: Claude's response

After the seat's response, add:

```
[CLAUDE]
<your analysis>
```

- Agree with findings that are well grounded
- Push back on claims that contradict what you know from the codebase
- Highlight where Claude and the seat diverge and why
- Say which concerns warrant action and which can be deferred

Keep it concise, a dialogue and not an essay. **Then STOP. Do not implement, fix, or act on any finding. Wait for the user.**

## Step 6: Continue the conversation

Invite the user to ask the seat a follow-up, point it at a section, override or
dismiss a finding, or have you dig in first. For a follow-up, embed the full
conversation history in the next call, reuse the same `$EXTRA_DIRS`, and ALWAYS
use the prompt-file form (the history carries quotes, backticks and shell
metacharacters):

```bash
ROUND=<N>
PROMPT_FILE="${TMPDIR:-/tmp}/<seat>-prompt-r${ROUND}.txt"
cat > "$PROMPT_FILE" <<'EOF'
--- CONVERSATION SO FAR ---
[<SEAT> ROUND 1]:
<prior seat response>

[CLAUDE ROUND 1]:
<prior claude response>

[USER]:
<user's follow-up or redirect>

--- CURRENT REQUEST ---
<new focused question derived from the user's follow-up>
EOF

/home/saidler/.claude/skills/plan/seats/<seat>/script.sh "$DOC_PATH" "$PROMPT_FILE" "$EXTRA_DIRS"
```

The quoted `<<'EOF'` disables shell expansion, so prior responses pass through
untouched. Display later exchanges as `[<SEAT> - Round N]` and `[CLAUDE - Round N]`.

## Step 7: Wrapping up

When the user is done, summarize key findings, open questions worth tracking,
and next actions, then ask whether to append the summary to the doc's Open
Questions section (Edit tool, only on a yes).

## Error handling

- `gemini` missing: `npm install -g @google/gemini-cli`. `codex` missing: install it and verify with `codex --version`.
- Doc path does not exist: stop and ask for the correct path.
- No doc found in `docs/plan/` or `docs/design/`: ask for the path explicitly.
- Architect returns empty or an error: show the raw output and ask how to proceed. Staff Engineer script exits non-zero: it prints the full codex trace to stderr, show that and ask.
- Never fabricate a seat's response, only display what the CLI returned.

## What Claude must NOT do in seat mode

- Do not construct a `gemini` or `codex` command directly, always use the seat script. If a prompt is too long to inline, write it to `${TMPDIR:-/tmp}/<seat>-prompt*.txt` and pass the file path as arg 2.
- Do not modify the doc unless asked after the consultation.
- Do not resolve open questions on behalf of the seat, surface them.
- Do not pretend to be the seat, keep the voices separated.
- Do not start implementing, fixing or acting on any finding, the consultation is advisory.
