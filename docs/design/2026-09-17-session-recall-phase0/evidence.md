# Phase 0 evidence: session recall

Run 2026-09-18 on desk.lan. Design doc: `docs/design/2026-09-17-session-recall.md`.
Harness version under test: **2.1.276** (`claude --version` -> `2.1.276 (Claude Code)`).

Every block below is observed output pasted from the run, never an inference. The
throwaway spike lived at `/tmp/claude-1000/claude-1000/session-recall-phase0/`. Its hook
is copied into this directory as `spike-hook.sh` so the run is reproducible;
`.gitignore:26` ignores `settings.local.json` repo-wide, so the registration is quoted
below instead of copied. **Nothing was written to `HOME/.claude/`**: no hook, no skill,
no rule, no `settings.json` edit. `spike-hook.sh` here is a record at mode 644,
registered nowhere.

The scratch project's `.claude/settings.local.json`, verbatim:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "/tmp/claude-1000/claude-1000/session-recall-phase0/.claude/spike-hook.sh" }
        ]
      }
    ]
  }
}
```

## Verbatim-fidelity caveat, read before linting this file

Probe 2's recorded model response **contains one em-dash** (U+2014), on the line that
opens `` Door: `PANEL_ROUNDS_ORDERED_BY_SCOTT=<int>` `` (evidence.md:228). It is
preserved because this phase's deliverable is a verbatim record and editing a quoted
response is the one thing an evidence file may not do. `.otto.yml`'s em-dash `FILES` list
is enumerated, so this file is not linted today and `otto ci` is green with it present.
**Phase 2 must not add this file to that list without first deciding what to do about
that character.** Every line this phase authored is em-dash free.

## The mechanism under test

`additionalContext` arrives as harness-supplied context, not as user text, so pasting the
candidate string into a prompt tests nothing. The spike registers a `UserPromptSubmit`
hook in a scratch project's `.claude/settings.local.json`, and the probes are headless
`claude -p` runs with that scratch directory as cwd.

**First finding, incidental but load-bearing for the method: a project-local
`settings.local.json` hook fires under headless `claude -p` with no trust prompt.** The
very first probe attempt died on a blocked API call and the hook log still carried one
payload line, which is how this was established rather than assumed.

The spike's emitted text names the clyde MCP tools **directly**, not
`Skill(session-recall)`: that skill does not exist until Phase 1, so a skill-invocation
criterion would be satisfied by an unresolvable attempt. The emitted string:

```
session-recall hook: this prompt names a prior session, quoted verbatim from it: {quoted}.

Decide from the prompt's own wording:
- asking about that session's content (what was decided, what was built, where a file went) -> resolve it with clyde's MCP session tools (mcp__clyde__sessions_search, mcp__clyde__session_grep, mcp__clyde__session_read; run ToolSearch with select: on those names first if they are not already loaded) before answering, and cite path:line.
- naming it in passing (a statistic, an aside, a session you are already reading) -> resolve nothing. This line is context, not an order.
```

### The spike predicate, smoke-tested before any model run

Four payloads piped straight into the hook, exit codes and stdout observed:

```
prompt: what did we decide in session 0aa23bbf-8c16-4fc0-bf57-b18649f8542e
  -> FIRED arm=id quoted=0aa23bbf-8c16-4fc0-bf57-b18649f8542e
prompt: find the session where we reworked the panel round cap
  -> FIRED arm=phrase quoted=the session where
prompt: clyde session search 0aa23bbf-8c16-4fc0-bf57-b18649f8542e
  -> exit 0, no stdout (bail 4, names clyde)
prompt: look at image-cache/0aa23bbf-8c16-4fc0-bf57-b18649f8542e/1.png
  -> exit 0, no stdout (id regex lookaround rejects the `/`-adjacent match)
```

## Probe 1, id arm: does the injected line draw a prompt-injection refusal?

**Verdict: PASS. No refusal. The model ran the retrieval the injected line pointed at.**

Target session `0aa23bbf-8c16-4fc0-bf57-b18649f8542e` is a live id under
`~/.claude/projects/-home-saidler-repos-scottidler-claude/`, 1,491 records, the
2026-09-12 setup-audit research session.

Command, run from the scratch cwd:

```
claude -p "what did we decide in session 0aa23bbf-8c16-4fc0-bf57-b18649f8542e about the always-on rules budget?" \
  --output-format stream-json --verbose \
  --allowedTools ToolSearch mcp__clyde__sessions_search mcp__clyde__session_grep \
                 mcp__clyde__session_read mcp__clyde__sessions_ls
```

Raw `UserPromptSubmit` payload as the hook received it, keys sorted:

```json
{
  "cwd": "/tmp/claude-1000/claude-1000/session-recall-phase0",
  "hook_event_name": "UserPromptSubmit",
  "permission_mode": "auto",
  "prompt": "what did we decide in session 0aa23bbf-8c16-4fc0-bf57-b18649f8542e about the always-on rules budget?",
  "prompt_id": "4e47041c-a4a4-4d70-a534-fa121c421d0b",
  "session_id": "a5c725af-f3f4-4912-8a21-662d0b9c30d3",
  "transcript_path": "/home/saidler/.claude/projects/-tmp-claude-1000-claude-1000-session-recall-phase0/a5c725af-f3f4-4912-8a21-662d0b9c30d3.jsonl"
}
```

Hook fire log: `FIRED arm=id quoted=0aa23bbf-8c16-4fc0-bf57-b18649f8542e`.

Tool calls the run made, in order, `name` plus the head of `input`:

```
ToolSearch  {"query":"select:mcp__clyde__sessions_search,mcp__clyde__session_grep,mcp__clyde__session_read","max_results":5}
ToolSearch  {"query":"select:mcp__clyde__sessions_search,mcp__clyde__session_grep,mcp__clyde__session_read","max_results":5}
ToolSearch  {"query":"session grep search read clyde","max_results":10}
ToolSearch  {"query":"clyde session catalog resume","max_results":10}
Bash  {"command":"which clyde && clyde --help 2>&1 | head -50","description":"Check for clyde CLI and show help"}
ToolSearch  {"query":"select:mcp__clyde__session_grep,mcp__clyde__session_read,mcp__clyde__sessions_search","max_results":5}
mcp__clyde__session_grep  {"id":"0aa23bbf-8c16-4fc0-bf57-b18649f8542e","query":"always-on rules budget","context_lines":5,"limit":20}
mcp__clyde__session_grep  {"id":"0aa23bbf-8c16-4fc0-bf57-b18649f8542e","query":"budget","context_lines":5,"limit":20}
mcp__clyde__session_grep  {"id":"0aa23bbf-8c16-4fc0-bf57-b18649f8542e","query":"always-on","context_lines":5,"limit":20}
mcp__clyde__session_grep  {"id":"0aa23bbf-8c16-4fc0-bf57-b18649f8542e","query":"KB always-on rules","context_lines":5,"limit":20}
mcp__clyde__session_grep  {"id":"0aa23bbf-8c16-4fc0-bf57-b18649f8542e","query":"ruling","context_lines":5,"limit":20}
mcp__clyde__session_grep  {"id":"0aa23bbf-8c16-4fc0-bf57-b18649f8542e","query":"always-on rules","context_lines":4,"limit":20}
Bash  {"command":"find ~/repos/scottidler/claude/docs/design -iname \"*setup-audit*\" -o -iname \"*2026-09-13*\" 2>/dev/null","description":"Locate setup-au
Bash  {"command":"grep -n -i \"budget\\|always-on rules\\|46KB\\|rules budget\" /home/saidler/repos/scottidler/claude/docs/design/2026-09-13-setup-audit-pro
Read  {"file_path":"/home/saidler/repos/scottidler/claude/docs/design/2026-09-13-setup-audit-program.md"}
mcp__clyde__session_grep  {"id":"0aa23bbf-8c16-4fc0-bf57-b18649f8542e","query":"prefix trim","context_lines":5,"limit":10}
```

**The first tool call is the injected line's own text, executed.** `ToolSearch` with
`select:mcp__clyde__sessions_search,mcp__clyde__session_grep,mcp__clyde__session_read` is
the exact `select:` form and the exact three names the hook emitted, which makes the
retrieval attributable to the injection rather than to the prompt alone. The run then
reached `mcp__clyde__session_grep` on the quoted id six times.

Refusal scan over every assistant text block, case-insensitive, for
`prompt.injection|injection policy|refus|cannot act on|not acting on|flagging per`:

```
(no refusal language found)
```

Final response, verbatim:

```
**Session 0aa23bbf** (2026-09-12 14-lens audit) measured the fixed prefix at ~100KB: **46KB is always-on rules** (plus 15KB skill listing). It ranked "context budget + Read discipline + otto ci tail, always-on prefix trim and rule dedupe" as audit item 15/16, no cap number or fix decided there, just the measurement and the ranking.

Per the baton (`docs/design/2026-09-13-setup-audit-program.md:41`), that work is **chunk H**, status **queued**, no design doc drafted, no ruling made yet. The most recent data point since, chunk F1's log (2026-09-18), shows the prefix grown to **50,738 bytes**, with F1 adding +1,200 bytes "with no offset."

So: nothing was decided on a rules budget, it's still an open, unstarted chunk.
```

## Probe 2, phrase arm: is the uncorroborated form refused?

**Verdict: PASS, and the phrase arm SURVIVES. No refusal.** The doc allowed for a refusal
narrowing the shipped trigger to the id arm; that branch is not taken.

Command, run from the scratch cwd:

```
claude -p "pull up the session where we argued about the panel round cap and tell me what we landed on" \
  --output-format stream-json --verbose \
  --allowedTools ToolSearch mcp__clyde__sessions_search mcp__clyde__session_grep \
                 mcp__clyde__session_read mcp__clyde__sessions_ls
```

Raw payload as the hook received it, keys sorted:

```json
{
  "cwd": "/tmp/claude-1000/claude-1000/session-recall-phase0",
  "hook_event_name": "UserPromptSubmit",
  "permission_mode": "auto",
  "prompt": "pull up the session where we argued about the panel round cap and tell me what we landed on",
  "prompt_id": "a2c6d8e8-d0e8-495d-ac19-8c56d87d4254",
  "session_id": "4fef9585-e079-45b2-bfed-86b56f98d6a3",
  "transcript_path": "/home/saidler/.claude/projects/-tmp-claude-1000-claude-1000-session-recall-phase0/4fef9585-e079-45b2-bfed-86b56f98d6a3.jsonl"
}
```

Hook fire log: `FIRED arm=phrase quoted=the session where`. The quoted fragment names no
target, which is exactly the shape the doc worried about: the hook can quote `the session
where` and nothing more.

Tool calls the run made, in order:

```
ToolSearch  {"query":"select:mcp__clyde__sessions_search,mcp__clyde__session_grep,mcp__clyde__session_read","max_results":5}
ToolSearch  {"query":"select:mcp__clyde__sessions_search,mcp__clyde__session_grep,mcp__clyde__session_read","max_results":5}
ToolSearch  {"query":"session search grep sessions","max_results":10}
ToolSearch  {"query":"clyde session recall history","max_results":10}
ToolSearch  {"query":"clyde sessions_search","max_results":10}
mcp__clyde__sessions_search  {"query":"panel round cap"}
mcp__clyde__sessions_search  {"query":"panel round cap design doc how many rounds should the cap be","limit":15}
mcp__clyde__session_grep  {"id":"0aa23bbf-8c16-4fc0-bf57-b18649f8542e","query":"cap the rounds","limit":20,"context_lines":3}
mcp__clyde__sessions_search  {"query":"PANEL_ROUNDS_ORDERED_BY_SCOTT override cap three rounds argument","limit":15}
mcp__clyde__sessions_search  {"query":"create-design-doc panel round cap review-panel round inflation stop","limit":10}
mcp__clyde__session_grep  {"id":"f0d60440-a9bc-437d-a3c7-077db2269cea","query":"3-round cap mechanical","limit":10,"context_lines":4}
mcp__clyde__session_read  {"id":"f0d60440-a9bc-437d-a3c7-077db2269cea","offset":0,"limit":20}
Bash  {"command":"find /home/saidler/repos/scottidler/claude/docs/design -iname \"*panel-round-cap*\" 2>/dev/null","description":"Find panel round cap desig
Bash  {"command":"find /home/saidler/repos/scottidler/claude/docs/design -iname \"*panel-round-cap*\" 2>/dev/null","description":"Find panel round cap desig
Bash  {"command":"grep -n -A3 \"^\\*\\*Status\" /home/saidler/repos/scottidler/claude/docs/design/2026-09-14-panel-round-cap.md | head -20; echo ---; grep -
Read  {"file_path":"/home/saidler/repos/scottidler/claude/docs/design/2026-09-14-panel-round-cap.md","offset":16,"limit":62}
```

Refusal scan over every assistant text block, same pattern as probe 1 plus
`session-recall hook`:

```
(no refusal language found)
```

Final response, verbatim:

```
Found it and confirmed against the shipped doc (Status: Implemented).

**Session:** `f0d60440-a9bc-437d-a3c7-077db2269cea`, "Work chunks A and B status" (2026-09-14, `scottidler/claude`). This is where chunk C (the panel-round-cap work) got hashed out, with you pushing back twice on jargon and scope before the doc was written.

**What we landed on** (`docs/design/2026-09-14-panel-round-cap.md`, now Implemented):

- The 3-round cap moves from prose in `rules/interaction.md` to a `PreToolUse` hook (`panel-round-guard.sh`) that denies the `Agent` dispatch itself, not agent-prose discipline. Same enforcement class as the AskUserQuestion hook that took violations 557→0.
- Keyed on **(doc, mode)**, not the run dir: run dirs reset every round (fresh `mktemp -d`), so a run-dir counter couldn't have worked. Doc-mode identity is the actual invariant.
- Door: `PANEL_ROUNDS_ORDERED_BY_SCOTT=<int>` — you can raise the ceiling explicitly, per dispatch, and the guard is fenced-code-block-aware so a doc that quotes its own door section can't self-open it.
- Wall-clock kill and abstain-record were **rejected as new work**: both already existed in the seat scripts (`timeout --kill-after=30s`), and an outer timeout was explicitly re-rejected (you'd killed that idea on 2026-08-04 after it ate a script's EXIT trap twice).
- Freezing the doc mid-round was rejected too: the actual failure mode is growth *across* rounds, not concurrent edits within one.
- Housekeeping: poll snippet deleted from `create-design-doc`, `review-panel.md` split from 26KB down to contract-only with lore moved to a side notes file.

Shipped on branch `panel-round-cap`, 13 commits, verified in later sessions firing correctly (denies at cap, opens on the override token).
```

### The confound, stated rather than hidden

The probe prompt is **itself** an explicit recall ask ("pull up the session where we
argued about..."), so the model would have searched sessions with no hook at all. That
means the probe does not prove the injected line *caused* the retrieval. It does not have
to: the doc fixes the signal as "refusal versus no-refusal", and the doc's stated risk was
that an injected line naming no target reads as hostile. It did not.

Two things do make the injection's footprint visible even here:

- The first tool call is again `ToolSearch` with the injected
  `select:mcp__clyde__sessions_search,mcp__clyde__session_grep,mcp__clyde__session_read`,
  a three-name `select:` list the prompt never mentions.
- `0b-3a`'s refusal (`docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/evidence.md:167-173`)
  fired on a bare nonce referencing nothing typed. The phrase arm quotes a fragment that
  IS in the prompt, so it sits on the corroborated side of that line after all. The doc
  classed it as uncorroborated because it names no *target*; measured, quoting a present
  fragment is enough.

## Probe 4, payload keys at 2.1.276: is there a provenance field?

**Verdict: PASS. Seven keys, unchanged, and still no provenance field.** The design's
"no provenance" claim holds at the running version, so the decline branch stays
load-bearing.

`jq -S 'keys'` over the raw payload the throwaway hook logged:

```json
[
  "cwd",
  "hook_event_name",
  "permission_mode",
  "prompt",
  "prompt_id",
  "session_id",
  "transcript_path"
]
```

Identical to the 2.1.274 and 2.1.272 measurements the doc cites. No `source`, no
`promptSource`, no `isMeta`, nothing distinguishing a typed prompt from a
harness-submitted one. `permission_mode` carries the session's mode (`"auto"` here), not
the prompt's origin.

## Probe 3, slash commands: does bail 1 eat them?

**Verdict: PASS, and bail 1 needs NO `<command-` carve-out. The live `prompt` does NOT
begin with `<`; it carries the raw pre-expansion slash text.** The `<command-name>`
wrapper is a transcript artifact, which is the branch round 3 measured as leaving the
counts unchanged under both arms.

Three headless runs from the scratch cwd, each with the hook log cleared first. Left
column is what was typed, right column is the `prompt` value the hook received:

```
### typed: [/doctor]
{"prompt":"/doctor"}
### typed: [/probe-nonexistent-xyz]
{"prompt":"/probe-nonexistent-xyz"}
### typed: [/doctor in the last session]
{"prompt":"/doctor in the last session"}
```

A resolvable command, a nonexistent one, and one carrying arguments: all three raw.

### The interactive TUI is settled too, and not by this spike

Headless `claude -p` could in principle differ from the TUI, where a slash command is
intercepted locally before submission. It does not, and the proof is the **live**
`inline-skill-tokens.py` log at `~/.cache/claude/inline-skill-tokens.log`, which records
field 4 as the payload's `prompt`. Its `starts-with-slash` bails from interactive TUI
sessions over the last 16 hours:

```
2026-09-17T17:30:01	BAIL	starts-with-slash	/cli-shakedown
2026-09-17T18:24:08	BAIL	starts-with-slash	/handoff enough of what is needed in tatari-skills to fix the skill
2026-09-17T21:36:25	BAIL	starts-with-slash	/babysit those rabbit comments. let me know when its ready to merge
2026-09-17T22:30:19	BAIL	starts-with-slash	/create-design-doc F1
2026-09-18T05:56:58	BAIL	starts-with-slash	/how-to-execute-a-plan docs/design/2026-09-17-session-recall.md
2026-09-18T06:00:04	BAIL	starts-with-slash	/babysit let me know when its ready to merge
```

31 `starts-with-slash` bails in the log, 0 entries anywhere in it whose `prompt` begins
with `/` after expansion and 0 beginning `<command-`. The `05:56:58` line is the
interactive prompt that launched this very phase, typed in the TUI with arguments, and
the live payload carried the raw slash text.

### Bail 1's class does reach the hook live, which the same log confirms

54 entries in that log have a `prompt` beginning with `<`:

```
2026-09-17T19:20:32	BAIL	no-candidate	<task-notification> <task-id>b0dj9lrhl</task-id> <tool-use-id>toolu_01XjjGmKAh6TNSQYuaxjgv
2026-09-17T22:02:40	BAIL	no-candidate	<task-notification> <task-id>bg84950zu</task-id> <summary>Monitor event: "CodeRabbit PENDI
2026-09-17T22:31:09	BAIL	no-candidate	<agent-message from="a367fe50607ac4d7e"> [Subagent hand-back] The text below is the final
```

So bail 1 has live work to do and, per probe 3, costs no slash command. Separately: **0
entries in this log window begin `Another Claude session sent a message:`**, so bail 2's
class is corroborated by the corpus replay the doc cites and not by this log. Recorded as
an observation, not a finding: a 16-hour window is not evidence against 2,351 corpus
records.

## What Phase 2 is held to

| probe | question | verdict |
|---|---|---|
| 1 | id arm refused? | **NO refusal.** PASS |
| 2 | phrase arm refused? | **NO refusal.** PASS, arm survives |
| 4 | provenance field at 2.1.276? | **None.** Seven keys, unchanged. PASS |
| 3 | live slash `prompt` begins with `<`? | **NO.** Raw slash text. No carve-out. PASS |

**Both arms ship.** Phase 2's corpus-replay criterion is the both-arms figure: **46**
non-meta human fires and 0 across all 6,820 non-human records. The id-only 38 branch is
not taken, and the `<command-` carve-out branch (47 fires over 11,226 human records) is
not taken either.

## Cleanup

The scratch project at `/tmp/claude-1000/claude-1000/session-recall-phase0/` is throwaway
and is left in place for reproduction; it is outside every repo and outside
`HOME/.claude/`. The hook log it wrote is `~/.cache/session-recall-phase0.log` plus
`.fires`, also throwaway. Nothing was registered in any production settings file.
