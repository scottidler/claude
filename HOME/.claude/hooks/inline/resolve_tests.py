"""Tests for `inline.resolve`, run by `inline-name-resolution-test.sh`.

Named `resolve_tests.py`, not `tests.py`: Phase 5 already claimed that
filename for `inline.matcher`'s suite, and a package cannot hold two files
of the same name. `unittest`, matching Phase 5's dependency-free precedent
(this directory ships no `pyproject.toml`).
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from inline.resolve import (  # noqa: E402
    GENERIC_DENY,
    enumerate_skills,
    off_skill_names,
    personal_skill_names,
    plugin_skill_names,
    resolve,
    resolvable_skills,
)


def _make_skill(root: Path, name: str) -> None:
    d = root / name
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(f"name: {name}\n")


class PersonalSkillNamesTest(unittest.TestCase):
    def test_dir_with_skill_md_counts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_skill(root, "babysit")
            self.assertEqual(personal_skill_names(root), {"babysit"})

    def test_dir_without_skill_md_is_not_a_skill(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "not-a-skill").mkdir()
            self.assertEqual(personal_skill_names(root), set())

    def test_missing_dir_is_empty(self) -> None:
        self.assertEqual(personal_skill_names(Path("/nonexistent/does/not/exist")), set())


class PluginSkillNamesTest(unittest.TestCase):
    def test_enabled_plugin_yields_namespaced_names(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_skill(root / "skills", "read")
            _make_skill(root / "skills", "publish")
            settings = {"enabledPlugins": {"marquee@tatari-skills": True}}
            installed = {"plugins": {"marquee@tatari-skills": [{"installPath": str(root)}]}}
            names = plugin_skill_names(settings, installed)
            self.assertEqual(names, {"marquee:read", "marquee:publish"})

    def test_disabled_plugin_is_not_enumerated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_skill(root / "skills", "read")
            settings = {"enabledPlugins": {"marquee@tatari-skills": False}}
            installed = {"plugins": {"marquee@tatari-skills": [{"installPath": str(root)}]}}
            self.assertEqual(plugin_skill_names(settings, installed), set())

    def test_enabled_plugin_missing_install_record_is_skipped_not_raised(self) -> None:
        settings = {"enabledPlugins": {"ghost@nowhere": True}}
        installed = {"plugins": {}}
        self.assertEqual(plugin_skill_names(settings, installed), set())

    def test_no_bare_alias_is_ever_emitted_for_a_plugin_skill(self) -> None:
        """Rule 3, by construction: the only name a plugin skill gets IS the
        namespaced one, so `argocd-ops` (bare) never appears alongside
        `platform:argocd-ops`."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_skill(root / "skills", "argocd-ops")
            settings = {"enabledPlugins": {"platform@tatari-skills": True}}
            installed = {"plugins": {"platform@tatari-skills": [{"installPath": str(root)}]}}
            names = plugin_skill_names(settings, installed)
            self.assertEqual(names, {"platform:argocd-ops"})
            self.assertNotIn("argocd-ops", names)


class EnumerateSkillsTest(unittest.TestCase):
    def test_union_of_personal_and_plugin(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            personal = root / "personal"
            _make_skill(personal, "babysit")
            plugin_root = root / "plugin"
            _make_skill(plugin_root / "skills", "read")
            settings = {"enabledPlugins": {"slack@tatari-skills": True}}
            installed = {"plugins": {"slack@tatari-skills": [{"installPath": str(plugin_root)}]}}
            names = enumerate_skills(skills_dir=personal, settings=settings, installed_plugins=installed)
            self.assertEqual(names, {"babysit", "slack:read"})


class OffSkillNamesTest(unittest.TestCase):
    def test_off_value_is_dropped_bare_and_namespaced(self) -> None:
        settings = {"skillOverrides": {"chisle-help": "off", "platform:argocd-ops": "off"}}
        self.assertEqual(off_skill_names(settings), {"chisle-help", "platform:argocd-ops"})

    def test_no_overrides_is_empty(self) -> None:
        self.assertEqual(off_skill_names({}), set())


class FlipOnAndOffTest(unittest.TestCase):
    """The design doc's own phrasing: "proven by flipping one on and off",
    not asserted once for a skill that was never going to resolve anyway."""

    def _skills(self) -> set[str]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_skill(root, "chisle-help")
            return personal_skill_names(root)

    def test_flip_on_then_off_changes_the_verdict(self) -> None:
        skills = self._skills()

        on_settings = {"skillOverrides": {}}
        on_result = skills - off_skill_names(on_settings)
        self.assertIn("chisle-help", on_result)

        off_settings = {"skillOverrides": {"chisle-help": "off"}}
        off_result = skills - off_skill_names(off_settings)
        self.assertNotIn("chisle-help", off_result)

    def test_resolve_end_to_end_flips_with_the_override(self) -> None:
        skills = {"chisle-help"}
        on = skills - off_skill_names({"skillOverrides": {}})
        off = skills - off_skill_names({"skillOverrides": {"chisle-help": "off"}})
        self.assertEqual(resolve("chisle-help", skills=on), ["chisle-help"])
        self.assertEqual(resolve("chisle-help", skills=off), [])


class ResolveExactlyOneTest(unittest.TestCase):
    """"exactly one" is the point of the criterion: an unscoped `babysit`
    and a differently-namespaced `HOME:babysit` coexisting must not double-
    match a bare `/babysit` token."""

    def test_bare_and_namespaced_collision_resolves_to_one(self) -> None:
        skills = {"babysit", "HOME:babysit"}
        self.assertEqual(resolve("babysit", skills=skills), ["babysit"])

    def test_bare_token_never_matches_a_namespaced_skill(self) -> None:
        skills = {"platform:argocd-ops"}
        self.assertEqual(resolve("argocd-ops", skills=skills), [])


class GenericDenyTest(unittest.TestCase):
    def test_run_and_status_are_denied_even_when_live_skill_names(self) -> None:
        skills = {"run", "status", "babysit"}
        self.assertIn("run", GENERIC_DENY)
        self.assertIn("status", GENERIC_DENY)
        filtered = {n for n in skills if n.lower() not in GENERIC_DENY}
        self.assertEqual(filtered, {"babysit"})

    def test_resolvable_skills_applies_the_deny_list(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _make_skill(root, "run")
            _make_skill(root, "status")
            _make_skill(root, "babysit")
            names = resolvable_skills(skills_dir=root, settings={"enabledPlugins": {}}, installed_plugins={})
            self.assertEqual(names, {"babysit"})
            self.assertEqual(resolve("run", skills=names), [])
            self.assertEqual(resolve("status", skills=names), [])
            self.assertEqual(resolve("babysit", skills=names), ["babysit"])


class LiveStateTest(unittest.TestCase):
    """Reads the real `HOME/.claude/settings.json` and skills tree (this
    repo, symlinked into place). Never writes to either, per the phase's
    constraint."""

    def test_babysit_resolves_to_exactly_one_skill(self) -> None:
        self.assertEqual(resolve("babysit"), ["babysit"])

    def test_run_and_status_resolve_to_nothing(self) -> None:
        self.assertEqual(resolve("run"), [])
        self.assertEqual(resolve("status"), [])

    def test_a_live_off_override_is_never_resolvable(self) -> None:
        """`platform:argocd-ops` is off in the live settings today (verified
        by reading, not asserted from memory): confirm the real file drives
        the same exclusion the injected tests exercise above."""
        with open(Path.home() / ".claude" / "settings.json", encoding="utf-8") as f:
            live_settings = json.load(f)
        self.assertEqual(live_settings.get("skillOverrides", {}).get("platform:argocd-ops"), "off")
        skills = resolvable_skills()
        self.assertNotIn("platform:argocd-ops", skills)


class AcceptanceCriterionSevenTest(unittest.TestCase):
    """The doc's acceptance criterion 7, which spans Phases 5 and 6.

    Neither phase owned it, so neither tested it, and the first cut failed it
    at 551/571 while both phases reported their own criteria green. It is
    scored here because the criterion is stated "with Phase 6's deny list
    applied". Per-record at its own occurrence, never across the window.
    """

    FIXTURES = (
        Path(__file__).resolve().parents[4]
        / "docs/design/2026-09-17-dm-resolution-and-pipeline-glue-phase0/inline-token/fixtures.json"
    )

    def _score(self) -> tuple[int, int, int]:
        from inline.matcher import matches

        with open(self.FIXTURES, encoding="utf-8") as f:
            records = json.load(f)
        kept = hit = false_positives = 0
        for record in records:
            if not resolve(record["token"]):
                continue
            matched = matches(record["context"], record["offset"], record["token"])
            if record["label"] == "survivor":
                kept += 1
                hit += bool(matched)
            elif matched:
                false_positives += 1
        return hit, kept, false_positives

    def test_survivors_clear_the_floor(self) -> None:
        hit, kept, _ = self._score()
        self.assertEqual(kept, 571, "the deny list must leave the doc's 571 survivors")
        self.assertGreaterEqual(hit, 554, f"criterion 7 floor is 554, got {hit}/{kept}")

    def test_at_most_the_two_permitted_false_positives(self) -> None:
        _, _, false_positives = self._score()
        self.assertLessEqual(false_positives, 2, "criterion 7 permits only the two clipped-window records")


if __name__ == "__main__":
    unittest.main()
