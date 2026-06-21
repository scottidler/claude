---
name: architect-agy
description: Consult the Architect persona — powered by Antigravity (agy) on its latest Gemini Pro reasoning model — on a design doc. Supports two modes — Design Review (pre-implementation) and Implementation Audit (post-implementation). The Architect is a skeptical, read-only architectural reviewer with full codebase access.
user-invocable: true
allowed-tools: [Read, Bash, Glob, Grep, Write, Edit]
---

# Architect Consultation

Summon the Architect persona to review a design document. Two modes:
- **Design Review**: Evaluate whether the design is sound before implementation begins
- **Implementation Audit**: Judge whether the implementation actually delivered the spec

**Announce at start:** "Consulting the Architect via Antigravity (agy). Detecting mode..."

## Trigger

`/architect-agy [path-to-design-doc] [--dirs path1,path2] [optional: focused question or area]`

Examples:
- `/architect-agy` — auto-detect doc and mode
- `/architect-agy docs/design/2026-04-16-foo.md`
- `/architect-agy docs/design/2026-04-16-foo.md focus on the FSM state transitions`
- `/architect-agy docs/design/2026-04-16-foo.md what are the top three risks?`
- `/architect-agy ~/repos/other/docs/plan.md` — doc outside CWD; the doc's repo root is auto-included
- `/architect-agy docs/plan.md compare the queue model to how ~/repos/scottidler/loopr-v5 handles batching` — reference repo auto-detected from the prompt
- `/architect-agy docs/plan.md --dirs ~/repos/other-service,~/repos/shared-lib audit the wire format` — explicitly include reference repos

## agy Architect Background

The Architect runs on **Antigravity (`agy`)** using its latest Gemini Pro reasoning model. The persona is defined in `persona.md` colocated with this skill and injected by `script.sh`, which prepends it to the prompt (along with the inlined design doc) on every `agy` call. The persona is the **sole** enforcer of read-only behavior — unlike the old gemini path there is no `--approval-mode plan` hard-block (agy has no headless read-only mode; open feature request [#45](https://github.com/google-antigravity/antigravity-cli/issues/45)), so the script relies on agy auto-granting read tools while gating writes, plus the persona's instructions. It enforces:
- Strictly read-only and consultative — never plans, edits files, runs tests, or executes shell commands
- Highly skeptical — empirically verifies claims against the codebase before opining
- Humble — does not assume correctness of any syntax, structure, or claim without verification

**How the model is selected:** `script.sh` drives the model via `~/.gemini/antigravity-cli/settings.json` — it snapshots that file, forces the model label, runs agy, and restores the original on exit — so your global agy default is left untouched. (agy *did* add a `--model` flag in 1.0.5, per [#83](https://github.com/google-antigravity/antigravity-cli/issues/83), but it takes the **exact display label** and **silently falls back to the default model** on any mismatch — so the script pins the label in settings.json rather than trusting the flag.) Because settings.json is global state for the duration of a call, **do not run two Architect consultations concurrently.** See `agy-failure-log.md` for the full, cited list of agy print-mode pathologies (buffering/hang #76, model-label downgrade #83, `--print-timeout` #266).

## Step 1: Resolve the Design Doc

**If a path was provided**, use it directly. Resolve relative paths from `$PWD`.

**If no path was provided**, search for the most relevant doc:

```bash
find docs/design -name "*.md" -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -5 | awk '{print $2}'
```

- For **Mode 2 context** (just ran `/how-to-execute-a-plan`): prefer docs containing "Implemented"
- For **Mode 1 context** (just ran `/create-design-doc`): prefer the most recently modified doc
- Tell the user which doc was found before proceeding

## Step 1.5: Resolve Workspace Directories

agy restricts file access to the current workspace (`$PWD`) by default and cannot read files outside it. To let the Architect verify claims against any code that lives elsewhere — the doc's repo, a **reference repo being compared against**, or the codebase under audit — build a comma-separated list of extra directories. The script splits this list into repeated `--add-dir` flags for agy.

### Sources to collect from

1. **Doc root (auto)** — if the design doc is outside `$PWD`, include its repo root.
2. **`--dirs <comma-list>`** — explicit user-supplied dirs from the slash command. Parse these out of the trigger args before treating the remainder as the focus question.
3. **Reference repos mentioned in the prompt or doc.** This is the common case — the user asks the Architect to compare against another repo, or the design doc cites a reference implementation. Scan:
   - The user's focus question / follow-up prompt
   - The design doc body (especially "Prior art / Reference / Modeled after" sections, and links to local paths)
   - The conversation immediately before `/architect-agy` was invoked

   Patterns to catch:
   - Absolute paths like `/home/saidler/repos/<org>/<repo>` or `~/repos/<org>/<repo>` → include the repo root
   - Bare slugs like `tatari-tv/philo` or `scottidler/loopr-v5` → if a local clone exists at `~/repos/<slug>`, include it
   - Code references like `~/repos/X/src/foo.rs` → include `git rev-parse --show-toplevel` of that dir

   When the user mentions "repo X" without a path **and** multiple clones could plausibly match, ask once which clone they mean. When the path or slug is unambiguous, just proceed.

### Assemble `EXTRA_DIRS`

Run this block, appending every path you collected into the `DIRS` array. It normalizes, validates existence, dedupes, and joins with commas:

```bash
DIRS=()

# Source 1: doc root (auto) — only if doc is outside CWD
DOC_ABS=$(realpath "$DOC_PATH")
PWD_ABS=$(realpath "$PWD")
case "$DOC_ABS" in
  "$PWD_ABS"/*) ;;
  *)
    DOC_DIR=$(dirname "$DOC_ABS")
    DIRS+=("$(git -C "$DOC_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$DOC_DIR")")
    ;;
esac

# Sources 2 & 3: append each path you collected, one per line.
# Use $HOME instead of ~ because variable strings do not expand ~:
#   DIRS+=("$HOME/repos/scottidler/loopr-v5")
#   DIRS+=("/absolute/path/to/other-svc")

EXTRA_DIRS=$(
  for d in "${DIRS[@]}"; do
    d="${d/#\~/$HOME}"
    abs=$(realpath -e "$d" 2>/dev/null) || { echo "warn: skipping missing dir: $d" >&2; continue; }
    echo "$abs"
  done | awk 'NF && !seen[$0]++' | paste -sd, -
)
```

### Announce before calling

Print what's being included so the user can correct before agy runs:

```
Including extra workspace directories:
  - /home/saidler/repos/scottidler/loopr-v5  (reference repo from your prompt)
  - /home/saidler/repos/other-team/svc       (--dirs)
```

If no extra dirs were collected, `EXTRA_DIRS` will be empty — that is fine, pass `""` as the third arg. The script adds no `--add-dir` flags in that case (the cwd is still the workspace).

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

This commit context will be embedded in the agy prompt alongside the design doc.

Note: If the user committed fixes or unrelated work after the implementation, the range will be slightly noisy — acceptable, the Architect should stay focused on what the design doc describes.

## Step 4: Call agy

**CRITICAL: ALWAYS call the script. NEVER construct an `agy` command directly under any circumstances — not for round 1, not for follow-ups, not for "just this once" debugging. Do not use `--model`, `--add-dir`, `-p`, or any agy flags inline. The script enforces the Pro model (via scoped settings.json), inlines the doc, builds `--add-dir` flags, and orders `-p` correctly; bypassing it silently disables those guarantees and is the most common failure mode of this skill.**

The script accepts the prompt in two forms:

- **Literal string** (round 1, short prompts):
  ```bash
  ~/.claude/skills/architect-agy/script.sh "$DOC_PATH" "<prompt-string>" "$EXTRA_DIRS"
  ```
- **File path** (preferred for follow-up rounds, multiline prompts, or anything with embedded quotes/backticks):
  ```bash
  cat > /tmp/architect-agy-prompt.txt <<'EOF'
  <multi-line prompt body, no shell escaping needed inside a quoted heredoc>
  EOF
  ~/.claude/skills/architect-agy/script.sh "$DOC_PATH" /tmp/architect-agy-prompt.txt "$EXTRA_DIRS"
  ```
  The script detects that arg 2 is an existing file and reads the prompt from it.

`$EXTRA_DIRS` is the variable from Step 1.5. Pass `""` when empty — the script adds no `--add-dir` flags for empty input. Use the file-based form whenever the prompt contains conversation history, code blocks, or any character that bash would have to escape.

**Note on agy's `-p` prompt parsing:** agy's `-p` consumes the *single token immediately after it* as the prompt. If any flag (e.g. `--add-dir`) follows `-p`, that flag string becomes the "prompt" and the real prompt is silently dropped — agy then replies to garbage or wanders off researching the flag name. The script guards against this by placing every flag (`--add-dir`, `--print-timeout`) **before** `-p` and passing the prompt as the final token. This is exactly why you must never hand-roll the agy call — get the ordering wrong and the review is meaningless.

### Mode 1 — Design Review (default prompt):

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

### Mode 1 — Design Review (focused prompt):

```
Review this design document as the Architect, focusing specifically on: <user-provided focus>.

Be specific. Reference exact sections and claims. Verify before asserting.
```

### Mode 2 — Implementation Audit (default prompt):

```
Review this design document as the Architect. The implementation is COMPLETE.

Here is the commit log and diff summary since the last release tag:

<git log + diff stat output from Step 3>

Your job is to audit whether the implementation actually delivered what the design specified.

**COMPLETENESS IS REQUIRED.** Walk the Implementation Plan section of the design doc phase by phase, bullet by bullet. For every bullet point, verify it was actually implemented by reading the code. A bullet that says "add X to Y" means read Y and confirm X is there. Do not assume a bullet was done because related work was done. Cross-crate wiring steps, config loading hooks, daemon integration points, and IPC registrations are the most commonly skipped — check these explicitly.

Identify:
1. **Completeness gaps** — every bullet in the Implementation Plan that was not implemented or was only partially implemented. This is the primary finding. Name the exact bullet and the file/function where the implementation is missing.
2. Design requirements that appear unimplemented or only partially implemented (beyond the phase bullets)
3. Implementation decisions that deviate from the spec — intentional or not
4. Code patterns that contradict the design's stated approach
5. Anything skipped, quietly deferred, or changed without acknowledgment

Be specific. Reference exact design sections and cross-check against the actual commits and code.
Do not praise without cause.
```

### Mode 2 — Implementation Audit (focused prompt):

```
Review this design document as the Architect, focusing specifically on: <user-provided focus>.

The implementation is COMPLETE. Commit context since last tag:

<git log + diff stat output from Step 3>

**COMPLETENESS IS REQUIRED.** Walk the Implementation Plan section phase by phase, bullet by bullet. For every bullet, verify it was actually implemented by reading the code. Cross-crate wiring, config loading, and daemon integration points are the most commonly skipped — check these explicitly.

Be specific. Cross-check the design against what was actually committed.
```

Display the response as:

```
[ARCHITECT]
<agy response>
```

## Step 5: Claude's Response

After displaying the Architect's response, add your own perspective:

```
[CLAUDE]
<your analysis>
```

Your response should:
- Agree with Architect findings you find well-grounded
- Push back on any Architect claims that contradict what you know from the codebase
- Highlight where Claude and the Architect diverge and why
- Identify which concerns warrant action vs. can be deferred

Keep it concise. This is a dialogue, not an essay.

**After giving your take, STOP. Do not start implementing, fixing, or acting on any finding. Wait for the user to direct next steps.**

## Step 6: Continue the Conversation

After the initial exchange, invite the user:

```
What would you like to explore further? You can:
- Ask a follow-up question for the Architect
- Direct the Architect to a specific section or concern
- Override or dismiss a finding
- Ask me (Claude) to dig into something before bringing it back to the Architect
```

**When the user provides a follow-up**, embed the full conversation history in the next agy call. Reuse the same `$EXTRA_DIRS` from Step 1.5 so workspace access stays consistent across rounds. If the follow-up itself mentions a new reference repo, append it to `DIRS` and re-run the assembly block before this call.

**Always use the file-based prompt form for follow-ups** — the prompt contains prior Architect output, Claude output, and the user's words, all of which can include quotes, backticks, and shell metacharacters. Inlining this as a string is the bug that caused round-4 to fail in past sessions.

```bash
ROUND=<N>
PROMPT_FILE="/tmp/architect-agy-prompt-r${ROUND}.txt"
cat > "$PROMPT_FILE" <<'EOF'
--- CONVERSATION SO FAR ---
[ARCHITECT ROUND 1]:
<prior architect response>

[CLAUDE ROUND 1]:
<prior claude response>

[ARCHITECT ROUND 2]:
...

[USER]:
<user's follow-up or redirect>

--- CURRENT REQUEST ---
<new focused question derived from user's follow-up>
EOF

~/.claude/skills/architect-agy/script.sh "$DOC_PATH" "$PROMPT_FILE" "$EXTRA_DIRS"
```

The quoted `<<'EOF'` heredoc disables all shell expansion inside the body, so backticks, `$VAR`, and quote characters in the prior responses pass through untouched.

Display each subsequent exchange as `[ARCHITECT - Round N]` and `[CLAUDE - Round N]`.

## Step 7: Wrapping Up

When the user signals they're done (or the conversation reaches a natural conclusion), summarize:

```
[SUMMARY]
Key findings from this consultation:
- <finding 1>
- <finding 2>
...

Open questions worth tracking:
- <question 1>
- <question 2>
...

Next actions (if any):
- <action 1>
```

Ask the user if they want to append this summary to the design doc's Open Questions section. If yes, use the Edit tool to append it.

## Error Handling

- If `agy` is not found: install Antigravity from https://antigravity.dev, then run `agy` once to complete sign-in
- If agy returns `Authentication required` (with an OAuth URL): the user must run `agy` interactively and sign in — Claude cannot complete the browser login
- If the doc path doesn't exist: stop and ask the user for the correct path
- If no design doc found in `docs/design/`: ask the user to provide the path explicitly
- If agy returns an empty or error response: show the raw output and ask the user how to proceed
- Never fabricate an Architect response — only display what agy actually returns

## What Claude Should NOT Do During This Skill

- **Do not construct an `agy` command directly — always use `~/.claude/skills/architect-agy/script.sh`.** This is the most common failure mode. If a prompt is too long to inline as a string, write it to `/tmp/architect-agy-prompt*.txt` and pass the file path as arg 2 — the script reads it. There is no situation where bypassing the script is correct. If you find yourself typing `agy -p ...` in a Bash call, stop — you will get the flag ordering or the model wrong.
- Do not modify the design doc unless explicitly asked after the consultation
- Do not resolve open questions on behalf of the Architect — surface them
- Do not pretend to be the Architect — keep Claude and Architect voices clearly separated
- Do not start implementing, fixing, or acting on any finding — the consultation is advisory only; the user decides what happens next
