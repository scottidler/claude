---
name: staff-engineer
description: Consult a Staff Engineer persona (via OpenAI Codex) on a design doc. Supports two modes — Design Review (pre-implementation) and Implementation Audit (post-implementation). Codex acts as a skeptical, read-only reviewer that verifies claims by actually running grep/git and reading the code, with no cross-repo restriction.
user-invocable: true
allowed-tools: [Read, Bash, Glob, Grep, Write, Edit]
---

# Staff Engineer Consultation

Summon a Staff Engineer persona (running on OpenAI Codex) to review a design document. Two modes:
- **Design Review**: Evaluate whether the design is sound before implementation begins
- **Implementation Audit**: Judge whether the implementation actually delivered the spec

This is the codex-backed sibling of `/architect` (which runs on Gemini). Use `/staff-engineer` when you want a pragmatic, implementation-grounded reviewer that **verifies by executing** read-only `rg`/`git`/file reads, or a second independent opinion alongside `/architect`.

> **Running both reviewers?** When you want the Staff Engineer *and* the
> Architect on the same doc (the usual case), invoke the `review-panel` agent
> instead — it resolves doc/mode/dirs once, fans out both reviewers in parallel
> with monitoring, and returns one reconciled findings list. This skill remains
> the way to consult the Staff Engineer *alone* or to drive multi-round follow-up.

**Announce at start:** "Consulting the Staff Engineer via Codex. Detecting mode..."

## Trigger

`/staff-engineer [path-to-design-doc] [--dirs path1,path2] [optional: focused question or area]`

Examples:
- `/staff-engineer` — auto-detect doc and mode
- `/staff-engineer docs/design/2026-04-16-foo.md`
- `/staff-engineer docs/design/2026-04-16-foo.md focus on the failure modes under load`
- `/staff-engineer docs/design/2026-04-16-foo.md what are the top three risks?`
- `/staff-engineer ~/repos/other/docs/plan.md` — doc outside CWD is fine; codex can read it directly
- `/staff-engineer docs/plan.md --dirs ~/repos/other-svc,~/repos/shared-lib audit the wire format`

## Codex Staff Engineer Background

The Staff Engineer persona is defined in `persona.md` colocated with this skill and injected by `script.sh`, which **prepends it to the prompt** on every Codex call. (It is deliberately NOT placed in any global codex config or `AGENTS.md`, so plain `codex` calls stay neutral.) It enforces:
- Strictly read-only and consultative — never edits, writes, or "fixes" anything
- Pragmatic and implementation-grounded — failure modes, operability, maintainability, blast radius, the wiring that gets skipped
- Highly skeptical and **empirical by execution** — runs `rg`/`git`/reads to verify every claim before opining

### Why codex, and how it differs from `/architect`

`script.sh` runs `codex exec -s read-only`. That is a **read-only sandbox**, not a workspace jail: codex can run real shell commands (`rg`, `git log`, `git blame`, `sed`, `find`) and read **any file on disk**, but cannot write. Practical consequences vs the Gemini-based `/architect`:
- **No cross-repo jail.** Codex reads referenced repos by absolute path directly — `--dirs` is only a hint, not a sandbox boundary.
- **No ripgrep/shell limitations.** Codex actually executes `rg` and `git`, so "X is missing / zero instances" is far more trustworthy than the Architect's equivalent (still spot-check anything surprising).
- **It cannot run anything that writes** (tests that create files, builds) — read-only blocks that by design. That is correct for a reviewer.

See `notes.md` for operating notes and the few real caveats.

## Step 1: Resolve the Design Doc

**If a path was provided**, use it directly. Resolve relative paths from `$PWD`.

**If no path was provided**, search for the most relevant doc:

```bash
find docs/design -name "*.md" -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -5 | awk '{print $2}'
```

- For **Mode 2 context** (just ran `/how-to-execute-a-plan`): prefer docs containing "Implemented"
- For **Mode 1 context** (just ran `/create-design-doc`): prefer the most recently modified doc
- Tell the user which doc was found before proceeding

## Step 1.5: Collect Reference Paths (optional)

Codex reads any path on disk, so there is no workspace assembly to do. You only need to tell the reviewer *where else to look* when the design compares against or depends on code in another repo.

Build a comma-separated `EXTRA_DIRS` from:
1. **`--dirs <comma-list>`** — explicit user-supplied dirs from the trigger args. Parse these out before treating the remainder as the focus question.
2. **Reference repos/paths mentioned in the prompt or doc** — absolute paths, `~/repos/<org>/<repo>`, or bare slugs that resolve to a local clone at `~/repos/<slug>`.

Validate existence and dedupe; pass the result as the script's third argument (or `""` if none). The script injects these into the prompt as read-only reference paths. If the doc itself lives outside `$PWD`, you do not need to add its dir — codex reads it via stdin regardless — but adding its repo root helps the reviewer find related code.

### Announce before calling

```
Reference paths passed to the Staff Engineer:
  - /home/saidler/repos/other-team/svc  (--dirs)
```

## Step 2: Detect Mode

Read the design doc and determine the mode:

**Mode 1 — Design Review**: Doc does NOT contain an "Implemented" status marker. The work has not been done yet. Evaluate whether the design is sound.

**Mode 2 — Implementation Audit**: Doc contains "Implemented" (or "Status: Implemented"). The work is done. Judge whether the code delivered the spec.

Announce the detected mode:
```
Detected mode: Design Review
```
or
```
Detected mode: Implementation Audit
```

If unclear, ask the user to confirm before proceeding.

## Step 3: For Mode 2 — Gather Commit Context

Get the implementation boundary — commits since the last tag:

```bash
PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null)
if [ -n "$PREV_TAG" ]; then
  echo "=== Commits since $PREV_TAG ==="
  git log $PREV_TAG..HEAD --oneline
  echo ""
  echo "=== Diff stat ==="
  git diff $PREV_TAG..HEAD --stat
else
  echo "=== No previous tag found — showing last 20 commits ==="
  git log --oneline -20
fi
```

This commit context will be embedded in the Codex prompt alongside the design doc. (Codex can also run git itself in the read-only sandbox, but providing the boundary keeps the audit scoped to the right range.)

## Step 4: Call Codex

**CRITICAL: ALWAYS call the script. NEVER construct a `codex` command directly — not for round 1, not for follow-ups, not for "just this once." Do not pass `-m`, `-s`, `-c`, `--cd`, or any codex flags inline. The script enforces the correct model, reasoning effort, read-only sandbox, and persona injection; bypassing it silently disables those guarantees.**

The script accepts the prompt in two forms:

- **Literal string** (round 1, short prompts):
  ```bash
  ~/.claude/skills/staff-engineer/script.sh "$DOC_PATH" "<prompt-string>" "$EXTRA_DIRS"
  ```
- **File path** (preferred for follow-up rounds, multiline prompts, or anything with embedded quotes/backticks):
  ```bash
  PROMPT_FILE="${TMPDIR:-/tmp}/staff-engineer-prompt.txt"
  cat > "$PROMPT_FILE" <<'EOF'
  <multi-line prompt body, no shell escaping needed inside a quoted heredoc>
  EOF
  ~/.claude/skills/staff-engineer/script.sh "$DOC_PATH" "$PROMPT_FILE" "$EXTRA_DIRS"
  ```
  The script detects that arg 2 is an existing file and reads the prompt from it.

  **Always `${TMPDIR:-/tmp}`, never bare `/tmp`.** The Claude Code Bash sandbox
  mounts `/tmp` read-only, so a bare `/tmp` heredoc fails with
  `Read-only file system (os error 30)` and the review never runs. This exact
  mistake, inside the scripts themselves, caused 37% of all review-panel
  failures from 2026-07-13 to 08-03.

Pass `""` as the third arg when there are no reference paths. The design doc is piped to codex on stdin and appears to the reviewer as a `<stdin>` block — prompts may refer to "the design document provided on stdin."

### Mode 1 — Design Review (default prompt):

```
Review this design document as the Staff Engineer. The design document is provided on stdin. Implementation has NOT started yet.

Identify:
1. The top risks to correctness, operability, and maintainability — and why they concern you
2. Assumptions that are unverified or that break on the unhappy path / under load
3. Missing design decisions that should be made explicit (failure handling, migration, rollback, observability)
4. Your hardest question for the author

Verify against the actual codebase before asserting — run rg/git/read the relevant files. Be specific; reference exact sections, files, and line numbers. Do not praise without cause.
```

### Mode 1 — Design Review (focused prompt):

```
Review this design document (provided on stdin) as the Staff Engineer, focusing specifically on: <user-provided focus>.

Verify against the actual code before asserting (rg/git/read). Be specific; cite files and lines.
```

### Mode 2 — Implementation Audit (default prompt):

```
Review this design document (provided on stdin) as the Staff Engineer. The implementation is COMPLETE.

Here is the commit log and diff summary since the last release tag:

<git log + diff stat output from Step 3>

Your job is to audit whether the implementation actually delivered what the design specified.

**COMPLETENESS IS REQUIRED.** Walk the Implementation Plan section of the design doc phase by phase, bullet by bullet. For every bullet, verify it was actually implemented by reading the code — run rg to find the symbol, read the file, confirm the wiring. A bullet that says "add X to Y" means read Y and confirm X is there. Do not assume a bullet was done because related work was done. Cross-module wiring, config loading/deserialization hooks, daemon/service integration points, and registration steps are the most commonly skipped — check these explicitly.

Identify:
1. **Completeness gaps** — every Implementation Plan bullet not implemented or only partially implemented. This is the primary finding. Name the exact bullet and the file/function where the implementation is missing.
2. Design requirements that appear unimplemented or only partially implemented (beyond the phase bullets)
3. Implementation decisions that deviate from the spec — intentional or not
4. Code patterns that contradict the design's stated approach, and any correctness/operability risk in what was built
5. Anything skipped, quietly deferred, or changed without acknowledgment
6. **Behavioral regressions — a first-class finding, and the one you are best placed to catch.** You have git in the read-only sandbox: for every commit that changes runtime behavior, read the PRE-change version of the touched function with `git show <PREV_TAG>:<path>` (or `git show <commit>^:<path>`) and compare it to the current one. Identify any input, command, config, or file that was accepted or produced result A before and now errors, hangs, or produces result B. Two shapes to hunt specifically: (a) a commit message claiming to fix a CLASS ("every X", "all Y forms", "handles Z") that fixes one instance — name the cases in the class still broken; (b) a change whose target is reached by an unrelated code path the phase never touched (a converter still emitting what a new loader rejects; a default another caller reads). The design doc's stated behavior changes are the ALLOWED set; anything a user could have relied on that changed and is NOT called out there is a regression. For each, emit a concrete differential probe on its own line, prefixed `PROBE:` — the exact command or input, what the previous release did (quote the base-version code you read), and what the current tree does.

Be specific. Cite exact design sections and cross-check against the actual commits and code (rg/git/read). Report what you verified and how. Do not praise without cause.
```

### Mode 2 — Implementation Audit (focused prompt):

```
Review this design document (provided on stdin) as the Staff Engineer, focusing specifically on: <user-provided focus>.

The implementation is COMPLETE. Commit context since last tag:

<git log + diff stat output from Step 3>

**COMPLETENESS IS REQUIRED.** Walk the Implementation Plan section phase by phase, bullet by bullet, and verify each against the actual code (rg/read). Cross-module wiring, config loading, and integration points are the most commonly skipped — check these explicitly. Cite files and lines for what you verified.
```

Display the response as:

```
[STAFF-ENGINEER]
<codex final message>
```

## Step 4.5: For Mode 2 — Run the differential probes (Claude, not the Staff Engineer)

Codex runs read-only: it can read the base version with `git show` and reason about divergence, but it cannot build or run a binary. So it can name a suspected regression; it cannot confirm one. You are not sandboxed, so you close it.

For every `PROBE:` the Staff Engineer emitted — and every behavior-changing commit in the range it did NOT probe — actually run it both ways:

- Build the current tree once.
- Get the previous-release binary: usually the installed one (`which <tool>`, confirm `<tool> --version` against `$PREV_TAG`); otherwise `git worktree add <tmp> $PREV_TAG` and build there. Never compare the new tree against itself.
- Run the probe against both binaries and capture both outputs verbatim.

Report under `[CLAUDE]`: a difference the design doc does not call out is a confirmed regression — show the command and both outputs. A probe that behaves identically is a cleared suspicion, worth one line. This step, not the reading, is what catches the class: in the 2026-09-03 audit of otto PR #3, three of four regressions were invisible to every read-only reviewer and fell out of the first old-vs-new run. Running a read-only probe is verification, not fixing — it does not violate the "do not act on findings" rule below.

## Step 5: Claude's Response

After displaying the Staff Engineer's response, add your own perspective:

```
[CLAUDE]
<your analysis>
```

Your response should:
- Agree with findings you find well-grounded
- Push back on any claim that contradicts what you know from the codebase
- Highlight where Claude and the Staff Engineer diverge and why
- Identify which concerns warrant action vs. can be deferred

Keep it concise. This is a dialogue, not an essay.

**After giving your take, STOP. Do not start implementing, fixing, or acting on any finding. Wait for the user to direct next steps.**

## Step 6: Continue the Conversation

After the initial exchange, invite the user:

```
What would you like to explore further? You can:
- Ask a follow-up question for the Staff Engineer
- Direct the Staff Engineer to a specific section or concern
- Override or dismiss a finding
- Ask me (Claude) to dig into something before bringing it back to the Staff Engineer
```

**When the user provides a follow-up**, embed the full conversation history in the next Codex call. Reuse the same `$EXTRA_DIRS`. **Always use the file-based prompt form for follow-ups** — the prompt contains prior output and the user's words, which can include quotes, backticks, and shell metacharacters.

```bash
ROUND=<N>
PROMPT_FILE="${TMPDIR:-/tmp}/staff-engineer-prompt-r${ROUND}.txt"
cat > "$PROMPT_FILE" <<'EOF'
--- CONVERSATION SO FAR ---
[STAFF-ENGINEER ROUND 1]:
<prior response>

[CLAUDE ROUND 1]:
<prior claude response>

[USER]:
<user's follow-up or redirect>

--- CURRENT REQUEST ---
<new focused question derived from user's follow-up>
EOF

~/.claude/skills/staff-engineer/script.sh "$DOC_PATH" "$PROMPT_FILE" "$EXTRA_DIRS"
```

Display each subsequent exchange as `[STAFF-ENGINEER - Round N]` and `[CLAUDE - Round N]`.

## Step 7: Wrapping Up

When the user signals they're done, summarize:

```
[SUMMARY]
Key findings from this consultation:
- <finding 1>
...

Open questions worth tracking:
- <question 1>
...

Next actions (if any):
- <action 1>
```

Ask the user if they want to append this summary to the design doc's Open Questions section. If yes, use the Edit tool to append it.

## Error Handling

- If `codex` is not found: it must be installed (`npm install -g @openai/codex` or the user's usual install path); verify with `codex --version`
- If the doc path doesn't exist: stop and ask the user for the correct path
- If no design doc found in `docs/design/`: ask the user to provide the path explicitly
- If the script exits non-zero: it prints the full codex trace to stderr — show that and ask the user how to proceed
- Never fabricate a Staff Engineer response — only display what codex actually returns

## What Claude Should NOT Do During This Skill

- **Do not construct a `codex` command directly — always use `~/.claude/skills/staff-engineer/script.sh`.** If a prompt is too long to inline, write it to `${TMPDIR:-/tmp}/staff-engineer-prompt*.txt` (never bare `/tmp`, which the sandbox mounts read-only) and pass the file path as arg 2.
- Do not modify the design doc unless explicitly asked after the consultation
- Do not resolve open questions on behalf of the Staff Engineer — surface them
- Do not pretend to be the Staff Engineer — keep Claude and Staff Engineer voices clearly separated
- Do not start implementing, fixing, or acting on any finding — the consultation is advisory only; the user decides what happens next
