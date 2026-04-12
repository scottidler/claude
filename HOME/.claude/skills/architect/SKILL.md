---
name: architect
description: Consult Gemini's Architect persona on a design doc. Gemini acts as a skeptical, read-only architectural reviewer. Enables live back-and-forth between Claude and the Architect, with the user able to interject or redirect at any point.
user-invocable: true
allowed-tools: [Read, Bash]
---

# Architect Consultation

Summon Gemini's Architect persona to review a design document. The Architect is strictly read-only and consultative — it reviews designs, identifies risks, asks hard questions, and never touches code.

**Announce at start:** "Consulting the Architect via Gemini. Loading design doc..."

## Trigger

`/architect <path-to-design-doc> [optional: focused question or area]`

Examples:
- `/architect docs/design/2026-04-11-foo.md`
- `/architect docs/design/2026-04-11-foo.md focus on the FSM state transitions`
- `/architect docs/design/2026-04-11-foo.md what are the top three risks?`

## Gemini Architect Background

The Architect persona lives in `~/.gemini/GEMINI.md` and is loaded automatically by the Gemini CLI. It is:
- Strictly read-only and consultative — never plans, edits files, or runs tests
- Highly skeptical — empirically verifies claims against the codebase before opining
- Humble — does not assume correctness of any syntax, structure, or claim without verification

Do NOT inject the persona manually. It loads from `~/.gemini/GEMINI.md` automatically.

## Step 1: Load the Design Doc

Read the design doc at the provided path. If the path is relative, resolve it from the current working directory. If the file does not exist, tell the user and stop.

## Step 2: Initial Consultation

Call Gemini with the full doc content piped via stdin and the review request as the `-p` prompt:

```bash
cat <doc-path> | gemini -p "<prompt>" --approval-mode plan -o text 2>&1
```

**Default prompt** (when no focused question given):
```
Review this design document as the Architect. Identify:
1. The top architectural risks and why they concern you
2. Assumptions that are unverified or could break under load
3. Missing design decisions that should be explicit
4. Your hardest question for the author

Be specific. Reference exact sections and claims. Do not praise without cause.
```

**Focused prompt** (when user provides a focus area):
```
Review this design document as the Architect, focusing specifically on: <user-provided focus>.

Be specific. Reference exact sections and claims. Verify before asserting.
```

Display the response as:

```
[ARCHITECT]
<gemini response>
```

## Step 3: Claude's Response

After displaying the Architect's response, add your own perspective labeled:

```
[CLAUDE]
<your analysis>
```

Your response should:
- Agree with Architect findings you find well-grounded
- Push back on any Architect claims that contradict what you know from the codebase
- Highlight where Claude and the Architect diverge and why
- Identify which of the Architect's concerns you think warrant action vs. can be deferred

Keep it concise. This is a dialogue, not an essay.

## Step 4: Continue the Conversation

After the initial exchange, invite the user:

```
What would you like to explore further? You can:
- Ask a follow-up question for the Architect
- Direct the Architect to a specific section or concern
- Override or dismiss a finding
- Ask me (Claude) to dig into something before bringing it back to the Architect
```

**When the user provides a follow-up**, construct the next Gemini call with the full conversation history embedded so the Architect has context:

```bash
cat <doc-path> | gemini -p "
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

## Step 5: Wrapping Up

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

Ask the user if they want to capture this summary anywhere (e.g., append to the design doc's Open Questions section).

## Error Handling

- If `gemini` is not found: `gemini` must be installed via `npm install -g @google/gemini-cli`
- If the doc path doesn't exist: stop and ask the user for the correct path
- If Gemini returns an empty or error response: show the raw output and ask the user how to proceed
- Never fabricate an Architect response — only display what Gemini actually returns

## What Claude Should NOT Do During This Skill

- Do not modify the design doc unless explicitly asked after the consultation
- Do not resolve open questions on behalf of the Architect — surface them
- Do not pretend to be the Architect — keep Claude and Architect voices clearly separated
