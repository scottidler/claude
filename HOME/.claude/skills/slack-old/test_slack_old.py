#!/usr/bin/env python3
"""Tests for slack_old.py's regex-heavy text transforms. Pure stdlib, no deps:

    python3 ~/.claude/skills/slack-old/test_slack_old.py        # or: python3 -m unittest -v

The markdown->mrkdwn converter (to_mrkdwn) is the fragile part - one ordering bug
already turned a heading into italics instead of bold. These lock the behavior in.
"""
import importlib.util
import os
import unittest

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("slack", os.path.join(_here, "slack_old.py"))
slack = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(slack)


class ToMrkdwn(unittest.TestCase):
    def eq(self, md, expected):
        self.assertEqual(slack.to_mrkdwn(md), expected)

    # bold
    def test_bold_stars(self):
        self.eq("**bold**", "*bold*")

    def test_bold_unders(self):
        self.eq("__bold__", "*bold*")

    def test_bold_inline(self):
        self.eq("a **b** c", "a *b* c")

    # italic
    def test_italic_star_becomes_underscore(self):
        self.eq("*italic*", "_italic_")

    def test_existing_underscore_italic_kept(self):
        self.eq("_italic_", "_italic_")

    def test_bold_not_eaten_by_italic(self):
        # the classic ordering trap: **b** must stay bold, not collapse to _b_
        self.eq("**b** and *i*", "*b* and _i_")

    # strikethrough
    def test_strike(self):
        self.eq("~~gone~~", "~gone~")

    # links / images
    def test_link(self):
        self.eq("[the PR](https://x/pull/1)", "<https://x/pull/1|the PR>")

    def test_image(self):
        self.eq("![alt](https://x/i.png)", "<https://x/i.png|alt>")

    def test_bare_url_untouched(self):
        self.eq("see https://x.com now", "see https://x.com now")

    # headings -> bold (regression: was becoming italic)
    def test_heading_h1(self):
        self.eq("# Title", "*Title*")

    def test_heading_h3(self):
        self.eq("### Title", "*Title*")

    def test_heading_trailing_hashes(self):
        self.eq("## Title ##", "*Title*")

    # bullets
    def test_bullet_dash(self):
        self.eq("- one", "• one")

    def test_bullet_star(self):
        self.eq("* one", "• one")

    def test_bullet_plus(self):
        self.eq("+ one", "• one")

    def test_numbered_list_kept(self):
        self.eq("1. one", "1. one")

    # code is protected from all transforms
    def test_inline_code_protected(self):
        self.eq("use `**x**` here", "use `**x**` here")

    def test_fenced_code_protected(self):
        src = "```\n**x** and [a](b)\n```"
        self.eq(src, src)

    def test_snake_case_not_italicized(self):
        self.eq("call snake_case_var now", "call snake_case_var now")

    # combined, Claude-style blob
    def test_blob(self):
        src = "# H\n\n**Done:** see [PR](https://x/1).\n\n- ~~old~~ new\n- *watch* it\n\n`raw_**kept**`"
        out = slack.to_mrkdwn(src)
        self.assertIn("*H*", out)
        self.assertIn("*Done:*", out)
        self.assertIn("<https://x/1|PR>", out)
        self.assertIn("• ~old~ new", out)
        self.assertIn("• _watch_ it", out)
        self.assertIn("`raw_**kept**`", out)          # code span untouched


class RenderText(unittest.TestCase):
    """Slack -> readable direction: mention resolution + <url|label> unwrapping."""
    DATA = {"channels": {}, "users": {"U1": "alice"}, "groups": {}}

    def test_mention_resolved_from_cache(self):
        self.assertEqual(slack.render_text("hi <@U1>", self.DATA), "hi @alice")

    def test_link_unwrapped(self):
        self.assertEqual(slack.render_text("see <https://x|the site>", self.DATA), "see the site")


if __name__ == "__main__":
    unittest.main(verbosity=2)
