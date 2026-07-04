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
  - safe on shape: creates permissions/allow if absent, normalizes the file to
                   2-space indent with a trailing newline

No backup file is written: the intended target (the user's global settings.json)
lives in the git-tracked scottidler/claude repo, so `git` is the backout. The
merge is additive-only, so recovery is just `git checkout`.

Usage:
    discover.py <cli> --seed "..." --rules-only | merge.py <settings.json>

Prints a summary of what was added vs. already present.
"""
import json
import os
import sys


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
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")

    print(f"added {len(added)}, already present {len(already)}")
    for r in added:
        print(f"  + {r}")
    if already:
        print(f"  ({len(already)} already allowed, left as-is)")


if __name__ == "__main__":
    main()
