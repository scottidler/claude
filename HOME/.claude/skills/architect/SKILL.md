---
name: architect
description: Consult Gemini's Architect persona on a design doc. Supports two modes — Design Review (pre-implementation) and Implementation Audit (post-implementation). Gemini acts as a skeptical, read-only architectural reviewer with full codebase access.
user-invocable: true
allowed-tools: [Read, Bash, Glob, Grep, Write, Edit]
---

# Architect Consultation

Summon Gemini's Architect persona to review a design document. Two modes:
- **Design Review**: Evaluate whether the design is sound before implementation begins
- **Implementation Audit**: Judge whether the implementation actually delivered the spec

**Announce at start:** "Consulting the Architect via Gemini. Detecting mode..."

## Trigger

`/architect [path-to-design-doc] [optional: focused question or area]`

Examples:
- `/architect` — auto-detect doc and mode
- `/architect docs/design/2026-04-16-foo.md`
- `/architect docs/design/2026-04-16-foo.md focus on the FSM state transitions`
- `/architect docs/design/2026-04-16-foo.md what are the top three risks?`

## Gemini Architect Background

The Architect persona is defined in `persona.md` colocated with this skill and injected via `--policy` on every Gemini call. It enforces:
- Strictly read-only and consultative — never plans, edits files, or runs tests
- Highly skeptical — empirically verifies claims against the codebase before opining
- Humble — does not assume correctness of any syntax, structure, or claim without verification

## Step 1: Resolve the Design Doc

**If a path was provided**, use it directly. Resolve relative paths from `$PWD`.

**If no path was provided**, search for the most relevant doc:

```bash
find docs/design -name "*.md" -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -5 | awk '{print $2}'
```

- For **Mode 2 context** (just ran `/how-to-execute-a-plan`): prefer docs containing "Implemented"
- For **Mode 1 context** (just ran `/create-design-doc`): prefer the most recently modified doc
- Tell the user which doc was found before proceeding

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

This commit context will be embedded in the Gemini prompt alongside the design doc.

Note: If the user committed fixes or unrelated work after the implementation, the range will be slightly noisy — acceptable, the Architect should stay focused on what the design doc describes.

## Step 4: Call Gemini

**CRITICAL: ALWAYS call the script. NEVER construct a `gemini` command directly. Do not use `-m`, `--model`, or any gemini flags inline — the script enforces the correct model and policy.**

```bash
~/.claude/skills/architect/script.sh <doc-path> "<prompt>"
```

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

Identify:
1. Design requirements that appear unimplemented or only partially implemented
2. Implementation decisions that deviate from the spec — intentional or not
3. Code patterns that contradict the design's stated approach
4. Anything skipped, quietly deferred, or changed without acknowledgment

Be specific. Reference exact design sections and cross-check against the actual commits and code.
Do not praise without cause.
```

### Mode 2 — Implementation Audit (focused prompt):

```
Review this design document as the Architect, focusing specifically on: <user-provided focus>.

The implementation is COMPLETE. Commit context since last tag:

<git log + diff stat output from Step 3>

Be specific. Cross-check the design against what was actually committed.
```

Display the response as:

```
[ARCHITECT]
<gemini response>
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

**When the user provides a follow-up**, embed the full conversation history in the next Gemini call:

```bash
~/.claude/skills/architect/script.sh <doc-path> "
--- CONVERSATION SO FAR ---
[ARCHITECT ROUND 1]:
<prior architect response>

[CLAUDE ROUND 1]:
<prior claude response>

[USER]:
<user's follow-up or redirect>

--- CURRENT REQUEST ---
<new focused question derived from user's follow-up>
" --approval-mode plan -o text 2>&1
```

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

- If `gemini` is not found: `gemini` must be installed via `npm install -g @google/gemini-cli`
- If the doc path doesn't exist: stop and ask the user for the correct path
- If no design doc found in `docs/design/`: ask the user to provide the path explicitly
- If Gemini returns an empty or error response: show the raw output and ask the user how to proceed
- Never fabricate an Architect response — only display what Gemini actually returns

## What Claude Should NOT Do During This Skill

- Do not construct a `gemini` command directly — always use `~/.claude/skills/architect/script.sh`
- Do not modify the design doc unless explicitly asked after the consultation
- Do not resolve open questions on behalf of the Architect — surface them
- Do not pretend to be the Architect — keep Claude and Architect voices clearly separated
- Do not start implementing, fixing, or acting on any finding — the consultation is advisory only; the user decides what happens next
