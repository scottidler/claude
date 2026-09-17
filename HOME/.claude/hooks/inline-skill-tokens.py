#!/usr/bin/env python3
"""inline-skill-tokens.py (UserPromptSubmit): turns an inline `/name` into an
explicit, declinable instruction.

Claude Code expands a slash command at position 0 and nowhere else, and the
expansion runs BEFORE any prompt hook, so a `/name` typed mid-sentence is
plain text that invokes nothing. No mechanism in 2.1.274 makes it fire the
skill on the current turn (measured: `$.command.run` is refused from
`prompt.submit`, there is no `$.skill.*` API). This hook is mechanism A from
the design doc: it cannot fire the skill, so it names the token to the model
as context and lets the model decide.

It composes the two prior phases and adds no scoring of its own:
  - `inline/matcher.py`  find_matches -> every `(offset, token)` in the prompt
  - `inline/resolve.py`  resolve      -> the live skills a bare token names

It reads the prompt and writes `additionalContext`. It cannot deny, and it
cannot alter what the user typed.

Design doc: docs/design/2026-09-17-dm-resolution-and-pipeline-glue.md
(Part 2 (E7), Phase 7). Evidence: the same doc's `-phase0/evidence.md`, 0b.
"""

from __future__ import annotations

import json
import os
import sys

# `realpath`, not `dirname(__file__)`: the live registration is the
# `~/.claude/hooks/inline-skill-tokens.py` symlink, and `inline/` sits beside
# the symlink TARGET in the repo, never beside the link.
HOOKS_DIR = os.path.dirname(os.path.realpath(__file__))
if HOOKS_DIR not in sys.path:
    sys.path.insert(0, HOOKS_DIR)

from inline.matcher import find_matches  # noqa: E402
from inline.resolve import resolve, resolvable_skills  # noqa: E402

LOG = os.environ.get("INLINE_SKILL_TOKENS_LOG") or os.path.expanduser("~/.cache/claude/inline-skill-tokens.log")


def log(decision: str, detail: str, prompt: str, tokens: str = "") -> None:
    """Append one tab-separated line per invocation, so "is it working?" is a
    question the log answers instead of an inference.

    Columns: iso-time, decision, detail, prompt preview, tokens.
      decision  INJECT (additionalContext emitted; `tokens` lists what it named)
                BAIL   (nothing emitted; `detail` is the reason)

    `rules/logging.md`'s sensitive-payload clause applies to the prompt: it is
    previewed at 200 characters, never written whole. Best-effort and silent,
    for the same reason the caller swallows every other error here: a hook that
    failed on its own logging would break prompt submission.
    """
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        flat = prompt.replace(chr(10), " ")[:200]
        stamp = __import__("datetime").datetime.now().isoformat(timespec="seconds")
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(f"{stamp}\t{decision}\t{detail}\t{flat}\t{tokens}\n")
    except Exception:
        pass


def instruction(tokens: list[str]) -> str:
    """The injected text, for the tokens found in THIS prompt.

    The wording is load-bearing, and it is measured rather than styled. Phase
    0b-1b injected an instruction naming a token that was actually present in
    the typed prompt and the model produced a real `Skill` call from it. Phase
    0b-3a injected a bare nonce that referenced nothing the user had typed, and
    the model flagged it as prompt injection and refused: "Flagging per
    prompt-injection policy rather than acting on it." That is the correct
    reaction to an uncorroborated injected instruction, so the text has to stay
    corroborable: it quotes the tokens VERBATIM, exactly as they appear in the
    prompt the model can see. Never replace them with a count or a paraphrase.

    The instruction is also conditional, never a flat "invoke Skill(name)".
    34% of matched tokens are discussion rather than invocation and no lexical
    rule separates the two (the design doc rejects a lexical suppressor as
    Alternative 6), so the only thing that CAN separate them is the model
    reading the prompt it was given. That needs room to decline, which is what
    the second branch below is, and Phase 7's two discussion criteria test it.
    """
    quoted = ", ".join(f"`/{t}`" for t in tokens)
    return (
        f"inline-skill-tokens hook: the user's prompt contains these inline tokens, quoted "
        f"verbatim from it: {quoted}. Each one names an installed skill. Claude Code expands a "
        f"slash command only at position 0, so these arrived as plain text and invoked nothing.\n\n"
        f"Decide per token, from the prompt's own wording:\n"
        f"- asked for (an imperative, a step in a list of steps) -> invoke it with the Skill tool "
        f"now, in the order the tokens appear, before answering the rest of the message.\n"
        f"- only talked about (a question about the skill, a statistic, a name in passing) -> "
        f"invoke nothing. This line is context, not an order."
    )


def tokens_in(prompt: str) -> list[str]:
    """Every live skill name the prompt invokes inline, in order of first
    appearance. Empty for a prompt this hook must leave alone.
    """
    if prompt.startswith("/"):
        # `dSt`'s own `if(e.startsWith("/")) return []`, at PROMPT scope rather
        # than per-occurrence. The matcher's offset-0 bail only drops the
        # leading token, so without this a prompt like `/bump then
        # /cli-shakedown` would have its trailing token injected on top of the
        # slash command the harness already expanded. Measured: the payload's
        # `prompt` carries the raw slash text pre-expansion (evidence 0b-3), so
        # this is decidable here.
        log("BAIL", "starts-with-slash", prompt)
        return []

    candidates = find_matches(prompt)
    if not candidates:
        log("BAIL", "no-candidate", prompt)
        return []

    # Enumerated once and shared across tokens: `resolvable_skills` walks the
    # skills tree and reads settings.json, and this runs on every prompt.
    skills = resolvable_skills()
    out: list[str] = []
    for _, token in candidates:
        for name in resolve(token, skills=skills):
            if name not in out:
                out.append(name)
    if not out:
        log("BAIL", "no-live-skill", prompt, ",".join(t for _, t in candidates))
    return out


def main() -> None:
    # There is no provenance field to filter on. Phase 0b-2 measured the whole
    # `UserPromptSubmit` payload at 2.1.274 and it is seven keys (cwd,
    # hook_event_name, permission_mode, prompt, prompt_id, session_id,
    # transcript_path), none of them carrying a source. So this hook fires on
    # EVERY prompt, including ones injected by a harness or a nested
    # `claude -p`. That is written in rather than designed away: it is 0b's
    # accepted-cost branch, and mechanism A's cost for a wrong fire is one
    # ignorable line of context.
    try:
        payload = json.load(sys.stdin)
    except Exception as exc:
        # Swallowed on purpose, and it is the one place this file departs from
        # `taste.md`'s fail-loudly default: the failure mode of a raising
        # UserPromptSubmit hook is a prompt that will not submit. This hook
        # only ever ADDS context, so going quiet costs exactly the feature and
        # nothing else. The log line is how it stays diagnosable.
        log("BAIL", f"unreadable-payload:{type(exc).__name__}", "")
        return

    prompt = payload.get("prompt") or ""
    if not prompt.strip():
        log("BAIL", "empty-prompt", prompt)
        return

    try:
        tokens = tokens_in(prompt)
    except Exception as exc:
        log("BAIL", f"scan-failed:{type(exc).__name__}", prompt)
        return
    if not tokens:
        return

    log("INJECT", f"count={len(tokens)}", prompt, ",".join(tokens))
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "UserPromptSubmit",
                    "additionalContext": instruction(tokens),
                }
            }
        )
    )


if __name__ == "__main__":
    main()
