"""Tests for `inline.matcher`, run by `inline-token-matcher-test.sh`.

Not `pytest`: this tree ships no `pyproject.toml` for the hooks directory
(the repo's one prior Python hook, `rewrite-cd-read.py`, is tested from bash
too), so `unittest` keeps the suite dependency-free. `uv run pytest` is
still available on this machine and passes the same file, checked manually.
"""

from __future__ import annotations

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from inline.matcher import matches  # noqa: E402

_HOOKS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_REPO = os.path.abspath(os.path.join(_HOOKS_DIR, "..", "..", ".."))
_FIXTURES = os.path.join(
    _REPO,
    "docs",
    "design",
    "2026-09-17-dm-resolution-and-pipeline-glue-phase0",
    "inline-token",
    "fixtures.json",
)


def _slash_offset(context: str, token: str) -> int:
    """The offset of the `/` immediately before `token`'s first occurrence."""
    idx = context.index("/" + token)
    return idx


class InversionTest(unittest.TestCase):
    """The whole phase, per the design doc: a faithful `dSt` port scores
    zero on every slash-prefixed survivor, because `dSt` disqualifies a
    match preceded by `/`. This matcher REQUIRES it instead. This test is
    the one written first, against the pre-inversion matcher, to prove it
    fails red before the invert makes it pass green (see the phase report)."""

    def test_bump_after_prose_matches(self) -> None:
        context = "merge, pull main, /bump, install"
        token = "bump"
        offset = _slash_offset(context, token)
        self.assertTrue(matches(context, offset, token), "a faithful (un-inverted) port scores this zero")

    def test_bump_after_please_matches(self) -> None:
        context = "please /bump next"
        token = "bump"
        offset = _slash_offset(context, token)
        self.assertTrue(matches(context, offset, token))

    def test_bare_bump_is_not_a_candidate(self) -> None:
        # No leading slash at all: the design doc's bare-word case is out of
        # scope (parked for chunk F's WHOAMI vocabulary work), so this is
        # not something `matches` is ever asked about, only documented here
        # so the boundary of the phase is explicit.
        context = "please bump next"
        self.assertNotIn("/bump", context)


class BoundaryTest(unittest.TestCase):
    """Round 2's finding: requiring `/` alone accepts every slash-separated
    word list in prose. The character before the slash must be a boundary."""

    def test_slash_glued_to_a_path_does_not_match(self) -> None:
        context = "category/risk/status are spec enums"
        token = "status"
        offset = _slash_offset(context, token)
        self.assertFalse(matches(context, offset, token))

    def test_slash_after_whitespace_matches(self) -> None:
        context = "run /status now"
        token = "status"
        offset = _slash_offset(context, token)
        self.assertTrue(matches(context, offset, token))

    def test_slash_after_opening_paren_is_suppressed_by_the_bracket_span(self) -> None:
        # `_is_boundary` accepts an opening delimiter, per the design doc's
        # literal wording, but an opening paren ALSO always starts a
        # bracket span (matched or clipped-to-window), so this reads as
        # "inside a span" before the boundary check is ever reached. Same
        # reasoning that has to hold for the endpoints example below, so
        # this is the expected outcome, not a gap.
        context = "the three standard endpoints (/status, /deployed, /version)"
        token = "status"
        offset = _slash_offset(context, token)
        self.assertFalse(matches(context, offset, token))


class SpanExclusionTest(unittest.TestCase):
    def test_slash_inside_backticks_does_not_match(self) -> None:
        context = "run `bin/status` to check"
        token = "status"
        offset = _slash_offset(context, token)
        self.assertFalse(matches(context, offset, token))

    def test_slash_inside_a_url_does_not_match(self) -> None:
        context = "see https://example.com/status for the page"
        token = "status"
        offset = _slash_offset(context, token)
        self.assertFalse(matches(context, offset, token))

    def test_apostrophe_is_not_a_quote_open(self) -> None:
        context = "it isn't done, /status shows why"
        token = "status"
        offset = _slash_offset(context, token)
        self.assertTrue(matches(context, offset, token))


class TrailingNeighborTest(unittest.TestCase):
    def test_slash_immediately_followed_by_slash_does_not_match(self) -> None:
        context = "0% /run/credentials/systemd-journald.service"
        token = "run"
        offset = _slash_offset(context, token)
        self.assertFalse(matches(context, offset, token))

    def test_dot_extension_does_not_match(self) -> None:
        context = "the config lives at }/otto.yml today"
        token = "otto"
        offset = _slash_offset(context, token)
        self.assertFalse(matches(context, offset, token))


class AdversarialPhraseTest(unittest.TestCase):
    """Phase 5's own success criteria name these two phrases explicitly."""

    def test_standard_endpoints_produce_zero_matches(self) -> None:
        context = "the three standard endpoints (/status, /deployed, /version)"
        for token in ("status", "deployed", "version"):
            offset = _slash_offset(context, token)
            self.assertFalse(matches(context, offset, token), token)

    def test_help_arm_in_quotes_produces_zero_matches(self) -> None:
        context = 'a "name()/help arm,"'
        token = "help"
        offset = _slash_offset(context, token)
        self.assertFalse(matches(context, offset, token))


class StartsWithSlashTest(unittest.TestCase):
    def test_slash_at_offset_zero_never_matches(self) -> None:
        context = "/bump then install"
        token = "bump"
        self.assertFalse(matches(context, 0, token))


class FixturesTest(unittest.TestCase):
    """The pinned corpus: 2,004 records, 583 survivors, 1,421 false
    positives. Scored record-by-record at each record's own occurrence,
    never by re-scanning the window (435 of 2,004 records carry more than
    one `/token` in their window; a per-window reading gives different,
    unreachable numbers -- see the design doc and the phase0 README)."""

    @classmethod
    def setUpClass(cls) -> None:
        with open(_FIXTURES, encoding="utf-8") as fh:
            cls.records = json.load(fh)

    def test_fixture_count_is_pinned(self) -> None:
        self.assertEqual(len(self.records), 2004)
        by_label: dict[str, int] = {}
        for r in self.records:
            by_label[r["label"]] = by_label.get(r["label"], 0) + 1
        self.assertEqual(by_label.get("survivor"), 583)
        self.assertEqual(sum(v for k, v in by_label.items() if k != "survivor"), 1421)

    def test_zero_false_positives_match(self) -> None:
        false_positive_matches = [
            r
            for r in self.records
            if r["label"] != "survivor" and matches(r["context"], r["offset"], r["token"])
        ]
        self.assertEqual(
            false_positive_matches,
            [],
            f"{len(false_positive_matches)} of 1421 false positives matched",
        )

    def test_at_least_95_percent_of_survivors_match(self) -> None:
        survivors = [r for r in self.records if r["label"] == "survivor"]
        matched = [r for r in survivors if matches(r["context"], r["offset"], r["token"])]
        rate = len(matched) / len(survivors)
        self.assertGreaterEqual(
            rate,
            0.95,
            f"only {len(matched)} of {len(survivors)} survivors matched ({rate:.1%})",
        )


if __name__ == "__main__":
    unittest.main()
