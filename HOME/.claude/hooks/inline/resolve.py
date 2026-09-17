"""Skill name resolution: does a matched `/token` name a skill that would
actually resolve?

Four rules, from the design doc's Phase 6:

1. Enumerate live skills: personal skills under `~/.claude/skills` (bare
   names) plus every enabled plugin's skills (namespaced `plugin:skill`,
   read from `settings.json`'s `enabledPlugins` and
   `plugins/installed_plugins.json`'s resolved `installPath`, never a
   marketplace-cache heuristic).
2. Drop `skillOverrides: "off"` entries. Measured (Phase 0b-6): an "off"
   skill does not degrade, it burns the turn on a hard harness error, so
   this is a hard exclusion, not a soft one.
3. Drop bare aliases for plugin skills. A namespaced skill is enumerated
   ONLY in its `plugin:name` form (see rule 1), so a bare token can never
   equal it; there is no separate alias to strip.
4. Enforce the generic-word deny list: the 17 short installed names the
   design doc names verbatim, because raw inline counts show them firing
   on ordinary prose (`otto` 551, `config` 322, ...), not on an invocation.

Not wired to anything. Phase 7 imports `resolve`/`resolvable_skills` into
the `UserPromptSubmit` hook alongside Phase 5's `matcher`.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

PERSONAL_SKILLS_DIR = Path.home() / ".claude" / "skills"
SETTINGS_PATH = Path.home() / ".claude" / "settings.json"
INSTALLED_PLUGINS_PATH = Path.home() / ".claude" / "plugins" / "installed_plugins.json"

# The 45-installed-names-of-8-chars-or-fewer set the design doc names
# verbatim (Part 2, "Name resolution drops what must not match").
GENERIC_DENY = frozenset(
    {
        "run",
        "status",
        "config",
        "help",
        "auto",
        "update",
        "setup",
        "seed",
        "pm",
        "qa",
        "welcome",
        "cancel",
        "ooo",
        "evolve",
        "evaluate",
        "tutorial",
        "unstuck",
        "ralph",
    }
)


def load_json(path: Path) -> dict:
    """Empty dict for a missing or unparseable file: an absent settings.json
    or installed_plugins.json means "nothing to enumerate", not a crash."""
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        logger.warning("load_json: unreadable path=%s, treating as empty", path)
        return {}


def personal_skill_names(skills_dir: Path = PERSONAL_SKILLS_DIR) -> set[str]:
    """Bare names of every entry under `skills_dir` holding a `SKILL.md`.

    Matches `docs/design/.../phase0/inline-token/m4.py`'s `user_skills`:
    `os.path.isfile(...)` follows symlinks, so a plugin-sourced personal
    skill (`agentic-tdd -> .../skills/agentic-tdd`) counts the same as a
    real directory.
    """
    if not skills_dir.is_dir():
        return set()
    return {d.name for d in skills_dir.iterdir() if (d / "SKILL.md").is_file()}


def plugin_skill_names(settings: dict, installed_plugins: dict) -> set[str]:
    """Namespaced `plugin:skill` names for every plugin `settings["enabledPlugins"]`
    marks `True`, read from that plugin's resolved `installPath`.

    `installed_plugins.json` is the harness's own resolved-install record
    (`plugin@marketplace -> [{"installPath": ...}]`), not a marketplace
    layout this module re-derives: crawling `marketplace.json`/cache-hash
    directories directly would re-implement version resolution the harness
    already did, and get it wrong on every marketplace type it didn't
    account for.
    """
    out: set[str] = set()
    enabled = settings.get("enabledPlugins", {})
    installs = installed_plugins.get("plugins", {})
    for key, on in enabled.items():
        if not on:
            continue
        plugin_name = key.split("@", 1)[0]
        records = installs.get(key, [])
        if not records:
            logger.warning("plugin_skill_names: enabled plugin=%s has no installed_plugins.json record", key)
            continue
        for record in records:
            install_path = record.get("installPath")
            if not install_path:
                continue
            skills_dir = Path(install_path) / "skills"
            if not skills_dir.is_dir():
                continue
            for d in skills_dir.iterdir():
                if (d / "SKILL.md").is_file():
                    out.add(f"{plugin_name}:{d.name}")
    return out


def enumerate_skills(
    *,
    skills_dir: Path = PERSONAL_SKILLS_DIR,
    settings: dict | None = None,
    installed_plugins: dict | None = None,
) -> set[str]:
    """Rule 1. Every live skill name, personal (bare) and plugin (namespaced).

    `settings`/`installed_plugins` default to the real live files when
    omitted; tests inject a dict instead of mutating either file.
    """
    logger.debug("enumerate_skills: entry skills_dir=%s", skills_dir)
    if settings is None:
        settings = load_json(SETTINGS_PATH)
    if installed_plugins is None:
        installed_plugins = load_json(INSTALLED_PLUGINS_PATH)
    names = personal_skill_names(skills_dir) | plugin_skill_names(settings, installed_plugins)
    logger.debug("enumerate_skills: exit count=%d", len(names))
    return names


def off_skill_names(settings: dict) -> set[str]:
    """Rule 2. Every name `skillOverrides` maps to the literal string `"off"`."""
    overrides = settings.get("skillOverrides", {})
    return {name for name, value in overrides.items() if value == "off"}


def resolvable_skills(
    *,
    skills_dir: Path = PERSONAL_SKILLS_DIR,
    settings: dict | None = None,
    installed_plugins: dict | None = None,
    deny: frozenset[str] = GENERIC_DENY,
) -> set[str]:
    """Rules 1, 2 and 4 composed: every name a bare `/token` could resolve to.

    Rule 3 needs no separate step here: `enumerate_skills` never emits a
    bare alias for a namespaced skill in the first place (see
    `plugin_skill_names`), so there is nothing to drop.
    """
    logger.debug("resolvable_skills: entry skills_dir=%s", skills_dir)
    if settings is None:
        settings = load_json(SETTINGS_PATH)
    names = enumerate_skills(skills_dir=skills_dir, settings=settings, installed_plugins=installed_plugins)
    names -= off_skill_names(settings)
    names = {n for n in names if n.lower() not in deny}
    logger.debug("resolvable_skills: exit count=%d", len(names))
    return names


def resolve(token: str, *, skills: set[str] | None = None, **kwargs: object) -> list[str]:
    """Every resolvable skill a bare `/token` names -- exactly the bare
    name, never a `plugin:token` namespaced match (rule 3).

    `skills` defaults to a fresh `resolvable_skills()` call; pass it
    explicitly to resolve many tokens against one enumeration.
    """
    logger.debug("resolve: entry token=%s", token)
    if skills is None:
        skills = resolvable_skills(**kwargs)  # type: ignore[arg-type]
    matched = sorted(n for n in skills if n == token)
    logger.debug("resolve: exit token=%s matched=%d", token, len(matched))
    return matched
