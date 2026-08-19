#!/usr/bin/env python3
"""Audit single-token entity hubs in an Obsidian vault for prose ambiguity.

The problem this measures: cortex's auto-linker turns any entity-hub stem into a
link target. When the stem is also an ordinary English word (`every`, `brief`,
`database`), every prose occurrence becomes a wikilink, which is noise that
carries no information and pollutes the edge graph.

The discriminator is NOT whether the word is in a dictionary - `Rust`, `Obsidian`
and `Signal` are all dictionary words that are unambiguous proper nouns in this
vault. It is how the word is USED in the corpus:

    proper-noun ratio = capitalized, non-sentence-initial occurrences
                        ---------------------------------------------
                        all occurrences outside code and frontmatter

`Rust` scores high (people write it capitalized mid-sentence), `every` scores
~zero. Sentence-initial capitals are excluded because they say nothing about the
word's status.

Usage:
    hub_audit.py [--vault PATH] [--json OUT] [--min-occurrences N]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, asdict
from pathlib import Path

DICT_PATHS = [
    Path("/usr/share/dict/american-english"),
    Path("/usr/share/dict/words"),
]

FRONTMATTER_RE = re.compile(r"\A---\n.*?\n---\n", re.S)
CODE_FENCE_RE = re.compile(r"^```")
WIKILINK_RE = re.compile(r"\[\[([^\[\]|#^]+)(?:[#^][^\[\]|]*)?(?:\|[^\[\]]*)?\]\]")
SENTENCE_START_RE = re.compile(r"(?:^|[.!?:]\s+|\n\s*[-*>]?\s*|\|\s*)$")

# Judgment thresholds. Deliberately wide REVIEW band: a wrong PURGE deletes a
# real hub, and a wrong KEEP leaves link spam - both cost more than a human
# glance at a handful of borderline words.
KEEP_RATIO = 0.50
PURGE_RATIO = 0.20


@dataclass
class HubStat:
    name: str
    ontotype: str
    stub: bool
    created: str
    inbound_links: int
    tag_notes: int
    prose_total: int
    prose_proper: int
    prose_lower: int
    proper_ratio: float
    in_dictionary: bool
    verdict: str
    reason: str


def load_dictionary() -> set[str]:
    for path in DICT_PATHS:
        if path.exists():
            words = {w.strip().lower() for w in path.read_text(errors="ignore").splitlines()}
            return {w for w in words if w and "'" not in w}
    print("warning: no system word list found; in_dictionary will be False", file=sys.stderr)
    return set()


def is_dictionary_word(token: str, words: set[str]) -> bool:
    """Token, or its obvious singular, appears in the system word list."""
    if token in words:
        return True
    for suffix, trim in (("s", 1), ("es", 2), ("ies", 3)):
        if token.endswith(suffix) and len(token) > trim + 2:
            stem = token[:-trim]
            if stem in words or (suffix == "ies" and stem + "y" in words):
                return True
    return False


def strip_frontmatter(text: str) -> str:
    return FRONTMATTER_RE.sub("", text, count=1)


def prose_lines(text: str) -> list[str]:
    """Body lines outside fenced code blocks and outside wikilink markup."""
    out = []
    in_fence = False
    for line in strip_frontmatter(text).splitlines():
        if CODE_FENCE_RE.match(line.strip()):
            in_fence = not in_fence
            continue
        if in_fence or line.startswith("    "):
            continue
        out.append(WIKILINK_RE.sub(" ", line))
    return out


def read_frontmatter_field(text: str, field: str) -> str:
    m = re.search(rf"^{re.escape(field)}:\s*(.+)$", text, re.M)
    return m.group(1).strip().strip('"') if m else ""


def collect(vault: Path, min_occurrences: int) -> list[HubStat]:
    words = load_dictionary()

    hubs: dict[str, dict] = {}
    for path in sorted((vault / "entities").glob("*.md")):
        name = path.stem
        if "-" in name or not name.isalnum():
            continue  # single-token hubs only: multi-word stems are unambiguous
        text = path.read_text(errors="ignore")
        hubs[name] = {
            "ontotype": read_frontmatter_field(text, "ontotype") or "unknown",
            "stub": "stub-body" in text,
            "created": read_frontmatter_field(text, "date"),
        }
    if not hubs:
        return []

    lower_names = {n.lower(): n for n in hubs}
    inbound: dict[str, int] = defaultdict(int)
    tag_notes: dict[str, int] = defaultdict(int)
    proper: dict[str, int] = defaultdict(int)
    lower: dict[str, int] = defaultdict(int)

    token_re = re.compile(r"\b(" + "|".join(re.escape(n) for n in sorted(lower_names)) + r")\b", re.I)

    for path in vault.rglob("*.md"):
        rel = path.relative_to(vault)
        if rel.parts[0] not in ("notes", "inbox", "journal"):
            continue
        text = path.read_text(errors="ignore")

        for target in WIKILINK_RE.findall(text):
            stem = target.rsplit("/", 1)[-1].lower()
            if stem in lower_names:
                inbound[lower_names[stem]] += 1

        for tag in re.findall(r"^\s*-\s*([a-z0-9-]+)\s*$", read_tags_block(text), re.M):
            if tag in lower_names:
                tag_notes[lower_names[tag]] += 1

        for line in prose_lines(text):
            for m in token_re.finditer(line):
                surface = m.group(1)
                name = lower_names[surface.lower()]
                before = line[: m.start()]
                sentence_initial = bool(SENTENCE_START_RE.search(before)) or not before.strip()
                if surface[0].isupper() and not sentence_initial:
                    proper[name] += 1
                elif surface.islower():
                    lower[name] += 1

    stats = []
    for name, meta in sorted(hubs.items()):
        p, l = proper[name], lower[name]
        total = p + l
        ratio = (p / total) if total else 0.0
        in_dict = is_dictionary_word(name, words)
        verdict, reason = judge(name, meta, total, ratio, in_dict, min_occurrences)
        stats.append(
            HubStat(
                name=name,
                ontotype=meta["ontotype"],
                stub=meta["stub"],
                created=meta["created"],
                inbound_links=inbound[name],
                tag_notes=tag_notes[name],
                prose_total=total,
                prose_proper=p,
                prose_lower=l,
                proper_ratio=round(ratio, 3),
                in_dictionary=in_dict,
                verdict=verdict,
                reason=reason,
            )
        )
    return stats


def read_tags_block(text: str) -> str:
    m = re.search(r"^tags:\s*\n((?:\s*-\s*.+\n)+)", text, re.M)
    return m.group(1) if m else ""


def judge(name, meta, total, ratio, in_dict, min_occurrences) -> tuple[str, str]:
    """Keep / purge / review, with the reason spelled out for the report."""
    if not in_dict:
        return "KEEP", "not an English word, so a prose occurrence always means the entity"
    if total < min_occurrences:
        return "KEEP", f"only {total} prose occurrence(s): too little evidence to purge on"
    if ratio >= KEEP_RATIO:
        return "KEEP", f"written capitalized mid-sentence {ratio:.0%} of the time: proper noun in practice"
    if ratio <= PURGE_RATIO:
        detail = "stub body" if meta["stub"] else "has a body"
        return "PURGE", f"ordinary word, capitalized only {ratio:.0%} of {total} uses ({detail})"
    return "REVIEW", f"ambiguous: capitalized {ratio:.0%} of {total} uses"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--vault", type=Path, default=Path.home() / "repos/scottidler/obsidian")
    ap.add_argument("--json", type=Path, help="write the full table here")
    ap.add_argument("--min-occurrences", type=int, default=5)
    args = ap.parse_args()

    stats = collect(args.vault, args.min_occurrences)
    if args.json:
        args.json.write_text(json.dumps([asdict(s) for s in stats], indent=2))

    by_verdict = defaultdict(list)
    for s in stats:
        by_verdict[s.verdict].append(s)

    print(f"{len(stats)} single-token hubs audited\n")
    for verdict in ("PURGE", "REVIEW", "KEEP"):
        rows = by_verdict[verdict]
        print(f"== {verdict} ({len(rows)}) ==")
        rows.sort(key=lambda s: (-s.inbound_links, s.name))
        for s in rows:
            print(
                f"  {s.name:<22} {s.ontotype:<11} links={s.inbound_links:<5} "
                f"prose={s.prose_total:<5} cap={s.proper_ratio:<6} stub={str(s.stub):<5} {s.reason}"
            )
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
