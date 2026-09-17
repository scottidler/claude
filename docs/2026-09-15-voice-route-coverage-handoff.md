# Handoff: consistent voice checks across publishing routes

- **Next action:** read the [setup audit baton](design/2026-09-13-setup-audit-program.md), then replay the hook-only probe below against the current hook. Record where this finding belongs in the existing program before changing its implementation sequence.
- **Status:** evaluated and reproduced on 2026-09-15; implementation not started.
- **Baseline:** local branch `intent-guards`, commit `3815d7b`. This is a dated observation; inspect current HEAD and working changes before proceeding.
- **Goal:** the same outbound draft receives the same mechanical voice checks through inline CLI arguments, referenced files, and MCP calls. Claude Code is the daily driver.

## Finding and proposed change

- The Bash branch of [emdash.sh](../HOME/.claude/hooks/emdash.sh) recognizes selected git/gh commands and scans command text. It does not read a referenced body file; Slack and Marquee CLI publishing are outside its predicate.
- Reproduced: inline `gh pr create --body` was denied; the same prose via `--body-file`, `slack write`, and a Marquee publish file was allowed. `Write` of the same draft was denied. No publishing command was executed.
- A prior Write check only covers content that passed through that tool. Existing files and shell-generated drafts still reach these routes.
- [settings.json](../HOME/.claude/settings.json) also omitted `chat_schedule_message` from the em-dash MCP matcher at inspection time. Recheck before treating it as open.
- Extract the actual outbound prose for supported routes, including file bodies, scheduled messages, edits, follow-ups, and rich-text blocks. Reuse parsing from the [intent-guards design](design/2026-09-15-intent-guards.md) where the contracts align.
- Make file-resolution and unreadable-file behavior explicit. Do not broaden a prose rule into an indiscriminate ban on quoted source material or code.
- Keep subjective voice evaluation with the private voice corpus. Its deployed profile is `~/Claude/writing/VOICE.md`; this public repo should not acquire private examples.

## Recheck the evidence

Run from this repo root. Only the hook executes; command strings are inert inputs.

```bash
python3 - <<'PY'
import json, pathlib, subprocess, tempfile
hook = pathlib.Path('HOME/.claude/hooks/emdash.sh').resolve()
with tempfile.TemporaryDirectory(prefix='voice-route-probe-') as tmp:
    draft = pathlib.Path(tmp) / 'draft.md'
    text = 'The build passed ' + chr(0x2014) + ' ready to ship.'
    draft.write_text(text)
    commands = {
        'gh inline': f"gh pr create --body '{text}'",
        'gh file': f'gh pr create --body-file {draft}',
        'slack inline': f"slack write '#clipboard' '{text}'",
        'marquee file': f'marquee publish {draft}',
    }
    for label, command in commands.items():
        payload = {'hook_event_name': 'PreToolUse', 'tool_name': 'Bash',
                   'tool_input': {'command': command}}
        result = subprocess.run(['bash', str(hook)], input=json.dumps(payload),
                                text=True, capture_output=True, check=True)
        print(label, result.stdout.strip())
PY
```

## Acceptance and continuation

- Add a route matrix with paired clean/violating drafts. A clean draft must remain usable through every supported route.
- Cover inline/file parity, scheduled MCP messages, follow-ups, rich text, quoting, and preserved fixture exceptions.
- Run the existing hook fixtures and verify deployed-path behavior separately from source behavior. Hooks and plugins have different reload semantics; follow the audit's Phase 0 discipline.
- Keep audit chunks A-C as completed work. This handoff does not reorder chunks D-J or imply the in-review design has shipped.
- For setup-effectiveness instrumentation, the companion work item is Clyde's `docs/2026-09-15-setup-effectiveness-handoff.md`: record effective setup changes so later comparisons can measure whether these guards help.
- **Suggested skills:** `/handoff` to resume; `/create-design-doc` within the existing audit program; `/tdd` for the failing route matrix.
