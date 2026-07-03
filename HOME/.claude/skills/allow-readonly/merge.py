#!/usr/bin/env python3
"""
merge.py — additively merge Bash allow-rules into a Claude Code settings.json.

Reads candidate rules from stdin (one per line, as emitted by
`discover.py --rules-only`), adds any that are missing to
`permissions.allow`, and writes the file back. It is:

  - idempotent   : re-running adds nothing new
  - additive     : existing allow entries are never removed or reordered
  - scoped       : it only touches permissions.allow; deny/ask are never read
                   or modified
  - safe on shape: creates permissions/allow if absent, preserves 2-space
                   indentation and a trailing newline

Usage:
    discover.py <cli> --seed "..." --rules-only | merge.py <settings.json>

Prints a summary of what was added vs. already present. Makes a timestamped
`.bak` next to the settings file before writing.
"""
import json
import os
import shutil
import sys
import time


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: discover.py ... --rules-only | merge.py <settings.json>")
    path = os.path.expanduser(sys.argv[1])

    incoming = [ln.strip() for ln in sys.stdin if ln.strip()]
    if not incoming:
        sys.exit("merge.py: no rules on stdin — nothing to do.")

    with open(path) as f:
        data = json.load(f)

    perms = data.setdefault("permissions", {})
    allow = perms.setdefault("allow", [])
    existing = set(allow)

    added, already = [], []
    for rule in incoming:
        if rule in existing:
            already.append(rule)
        else:
            allow.append(rule)
            existing.add(rule)
            added.append(rule)

    if added:
        bak = f"{path}.{time.strftime('%Y%m%d-%H%M%S')}.bak"
        shutil.copy2(path, bak)
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        print(f"backup: {bak}")

    print(f"added {len(added)}, already present {len(already)}")
    for r in added:
        print(f"  + {r}")
    if already:
        print(f"  ({len(already)} already allowed, left as-is)")


if __name__ == "__main__":
    main()
