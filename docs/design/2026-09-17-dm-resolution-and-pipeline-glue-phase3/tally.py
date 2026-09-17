#!/usr/bin/env python3
"""Score the three Phase 3 replays against the decision rule.

The driver's own `deny_class` keys the TARGET family off the shipped deny text
("no typed turn in the last ..."). Variants B and C deny with a second, truthful
sentence ("nothing in the last 3 typed turns names ..."), which that classifier
files as `other`. Both are the TARGET rule firing, so the class is widened here
rather than by editing a prior phase's committed driver.

Usage: tally.py rows-a.json rows-b.json rows-c.json
"""
import json
import pathlib
import sys
from collections import Counter

TARGET_PREFIXES = (
    "no typed turn in the last",      # shipped: neither sufficient condition met
    "nothing in the last",            # variants B and C: the recipient is unnamed
)


def deny_class(rule):
    if rule.startswith(TARGET_PREFIXES):
        return "target"
    if rule.startswith("the body file"):
        return "artifact"
    if rule.startswith("this command carries"):
        return "multi-statement"
    return "other"


def key(row):
    """Identity of a post across replays. The rows keep the session file and the
    clipped target/text, which is unique within this corpus."""
    return (row["session"], row["tool"], row["target"], row["text"])


def main():
    arms = {}
    for path in sys.argv[1:]:
        rows = json.loads(pathlib.Path(path).read_text())
        arms[pathlib.Path(path).stem] = rows

    base_name = sys.argv[1]
    base = {key(r): r for r in arms[pathlib.Path(base_name).stem]}

    for name, rows in arms.items():
        classes = Counter(deny_class(r["rule"]) for r in rows if r["decision"] == "deny")
        tally = Counter(r["decision"] for r in rows)
        print(f"{name}: posts={len(rows)} allow={tally['allow']} deny={tally['deny']} "
              f"TARGET={classes['target']} artifact={classes['artifact']} "
              f"multi-statement={classes['multi-statement']} other={classes['other']}")

    for name, rows in arms.items():
        if name == pathlib.Path(base_name).stem:
            continue
        added = [r for r in rows
                 if r["decision"] == "deny"
                 and deny_class(r["rule"]) == "target"
                 and base.get(key(r), {}).get("decision") == "allow"]
        dropped = [r for r in rows
                   if r["decision"] == "allow"
                   and base.get(key(r), {}).get("decision") == "deny"]
        print(f"\n== {name}: {len(added)} TARGET denies introduced vs baseline, "
              f"{len(dropped)} baseline denies bought back")
        for i, r in enumerate(added, 1):
            print(f"  [{i}] target={r['target']!r}")
            print(f"      text={r['text']!r}")
            print(f"      window={r['window']!r}")
            print(f"      session={r['session']}")
        for i, r in enumerate(dropped, 1):
            print(f"  (-{i}) target={r['target']!r}  was: {base[key(r)]['rule']!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
