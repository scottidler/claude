"""Inline `/token` matcher: the standalone scoring primitive for E7.

Ports the shipped `dSt` function's span and trailing-neighbor rules (url,
bracket, angle and code-span exclusion; the `/`, `\\`, `-`, `?` and
`.`+alphanumeric trailing disqualifiers) and INVERTS its leading-neighbor
rule: `dSt` was built to match a BARE keyword and exclude a slash-prefixed
one (`if(ye==="/"||ye==="\\"||ye==="-")continue` before the match, `ye`
being the character right before it). This matcher exists to find the
slash-prefixed form instead, so a `/` immediately before the token is
REQUIRED rather than disqualifying. A faithful, un-inverted port scores
zero on every survivor: `matches("merge, pull main, /bump, install", 19,
"bump")` would return `False` forever, since every candidate is preceded by
its own `/`.

The character before THAT slash must itself be a boundary (start of
string, whitespace, or an opening delimiter), or every slash-separated word
list in ordinary prose matches too: measured against the pinned fixtures,
561/583 survivors but 195/1,421 false positives with no boundary check,
560/583 and 7/1,421 with it.

Not wired to anything. Phase 7 imports `matches`/`find_matches` into the
`UserPromptSubmit` hook; this phase is the scoring logic alone.
"""

from __future__ import annotations

import logging
import re

logger = logging.getLogger(__name__)

TRACE = 5
logging.addLevelName(TRACE, "TRACE")

_CODE_FENCE = re.compile(r"```.*?```", re.S)
_CODE_INLINE = re.compile(r"`[^`\n]*`")
_URL = re.compile(r"https?://\S+")

_OPEN_TO_CLOSE = {"(": ")", "[": "]", "{": "}", "<": ">"}
_CLOSE_CHARS = set(_OPEN_TO_CLOSE.values())
_BOUNDARY_CHARS = set("([{<\"'")

# Ported unchanged from `dSt`: a path, an escape, a flag dash or a `?`
# right after the token disqualifies it, same as `.` followed by an
# alphanumeric (a filename extension, not an instruction).
_TRAILING_DISQUALIFIERS = ("/", "\\", "-", "?")

_CANDIDATE = re.compile(r"/([A-Za-z0-9][A-Za-z0-9_-]*)")


_FENCE_MARKER = re.compile(r"```")


def _code_spans(text: str) -> list[tuple[int, int]]:
    spans = [m.span() for m in _CODE_FENCE.finditer(text)]
    spans += [m.span() for m in _CODE_INLINE.finditer(text)]
    # A ``` fence marker with no partner in this 100-char window is one half
    # of a fence clipped by the window boundary (fixtures.json's own README
    # notes 375 of 832 code-span records have odd backtick parity), and we
    # cannot tell from the window alone whether it opens or closes. Treating
    # the WHOLE window as code either way is the conservative reading a
    # zero-false-positive requirement demands.
    markers = [m.start() for m in _FENCE_MARKER.finditer(text)]
    if len(markers) % 2 == 1 or (not spans and text.count("`") % 2 == 1):
        spans.append((0, len(text)))
    return spans


def _url_spans(text: str) -> list[tuple[int, int]]:
    return [m.span() for m in _URL.finditer(text)]


def _bracket_spans(text: str) -> list[tuple[int, int]]:
    stack: list[tuple[str, int]] = []
    spans: list[tuple[int, int]] = []
    for i, ch in enumerate(text):
        if ch in _OPEN_TO_CLOSE:
            stack.append((ch, i))
        elif ch in _CLOSE_CHARS:
            for j in range(len(stack) - 1, -1, -1):
                if _OPEN_TO_CLOSE[stack[j][0]] == ch:
                    spans.append((stack[j][1], i + 1))
                    del stack[j:]
                    break
    # Same clipped-window reasoning as the code fence and quote spans above.
    spans.extend((idx, len(text)) for _, idx in stack)
    return spans


def _within_any_span(start: int, end: int, spans: list[tuple[int, int]]) -> bool:
    return any(s <= start and end <= e for s, e in spans)


def _is_boundary(ch: str) -> bool:
    return ch == "" or ch.isspace() or ch in _BOUNDARY_CHARS


def _trailing_disqualifies(text: str, end: int) -> bool:
    nxt = text[end] if end < len(text) else ""
    if nxt in _TRAILING_DISQUALIFIERS:
        return True
    return nxt == "." and end + 1 < len(text) and text[end + 1].isalnum()


def matches(context: str, offset: int, token: str) -> bool:
    """True if the `/token` at `context[offset]` is a live invocation.

    Scores ONE occurrence, per the fixture scoring protocol: `offset` is the
    index of the `/` and `token` must equal `context[offset+1:offset+1+len(token)]`.
    This is never a whole-window scan (`find_matches` is, and calls this per
    candidate) -- decisions here log at TRACE rather than DEBUG for exactly
    that reason, per `rules/logging.md`'s tight-loop demotion.
    """
    if offset == 0:
        # The slash is the first character handed in: `dSt`'s own
        # `startsWith("/") -> no scan` bail, kept as-is, not inverted. This
        # is position-0 slash-command territory, already handled elsewhere.
        logger.log(TRACE, "matches: token=%s offset=0 result=False reason=starts-with-slash", token)
        return False
    if context[offset] != "/":
        raise ValueError(f"offset {offset} does not point at '/' in {context!r}")
    end = offset + 1 + len(token)
    if context[offset + 1 : end] != token:
        raise ValueError(f"token {token!r} does not start at offset+1 in {context!r}")

    # No quote-span exclusion, deliberately. Suppressing a token inside quoted
    # prose IS the lexical suppressor for the discussion class that the design
    # doc rejects (Alternative 6): mechanism A's wrong-match cost is one
    # ignorable line, so a quoted `/babysit` is accepted as a wrong fire rather
    # than designed away. It also cost 13 labeled survivors and put acceptance
    # criterion 7 out of reach at 551/571 against a floor of 554.
    spans = _url_spans(context) + _code_spans(context) + _bracket_spans(context)
    if _within_any_span(offset, end, spans):
        logger.log(TRACE, "matches: token=%s offset=%d result=False reason=in-span", token, offset)
        return False

    # INVERTED `dSt`: a `/` immediately before the token is REQUIRED rather
    # than disqualifying (already guaranteed by the offset contract above,
    # so nothing to check here), but the character before THAT slash must
    # be a boundary -- start of string, whitespace, or an opening delimiter
    # -- or a plain slash-separated word list in prose would match too.
    prev_of_slash = context[offset - 1] if offset > 0 else ""
    if not _is_boundary(prev_of_slash):
        logger.log(TRACE, "matches: token=%s offset=%d result=False reason=no-boundary", token, offset)
        return False

    if _trailing_disqualifies(context, end):
        logger.log(TRACE, "matches: token=%s offset=%d result=False reason=trailing-neighbor", token, offset)
        return False

    logger.log(TRACE, "matches: token=%s offset=%d result=True", token, offset)
    return True


def find_matches(text: str) -> list[tuple[int, str]]:
    """Every `(offset, token)` candidate in `text` that scores as a match.

    Entry/exit logged at DEBUG: this runs once per prompt, not per candidate.
    """
    logger.debug("find_matches: entry len(text)=%d", len(text))
    out = [(m.start(), m.group(1)) for m in _CANDIDATE.finditer(text) if matches(text, m.start(), m.group(1))]
    logger.debug("find_matches: exit matches=%d", len(out))
    return out
