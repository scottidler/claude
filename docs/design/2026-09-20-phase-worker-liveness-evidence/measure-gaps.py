#!/usr/bin/env python3
"""Measure silent gaps inside phase-worker transcripts.

Reads every ~/.claude/projects/*/*/subagents/agent-*.jsonl whose .meta.json
mentions "phase", computes the longest gap between consecutive records, the
record kind that preceded it, and the kind of the final record. Run against
the live tree; the numbers in evidence.md were produced on 2026-09-20.

Usage: measure-gaps.py [--since YYYY-MM-DD]
"""
import collections
import datetime as dt
import glob
import json
import os
import sys

since = sys.argv[sys.argv.index("--since") + 1] if "--since" in sys.argv else "0000"


def kind(rec):
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, list):
        for part in content:
            if isinstance(part, dict) and part.get("type") in ("tool_use", "tool_result"):
                name = ":" + part.get("name", "") if part["type"] == "tool_use" else ""
                return part["type"] + name
    return rec.get("type")


def stamp(rec):
    return dt.datetime.fromisoformat(rec["timestamp"].replace("Z", "+00:00"))


rows = []
for meta_path in glob.glob(os.path.expanduser("~/.claude/projects/*/*/subagents/*.meta.json")):
    try:
        meta = json.load(open(meta_path))
    except (OSError, ValueError):
        continue
    if "phase" not in json.dumps(meta).lower():
        continue
    jsonl = meta_path.replace(".meta.json", ".jsonl")
    if not os.path.exists(jsonl):
        continue
    recs = []
    for line in open(jsonl):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if rec.get("timestamp"):
            recs.append(rec)
    if len(recs) < 2 or recs[0]["timestamp"] < since:
        continue
    gaps = [((stamp(b) - stamp(a)).total_seconds() / 60, kind(a)) for a, b in zip(recs, recs[1:])]
    longest = max(gaps)
    rows.append(
        dict(
            max_gap_min=longest[0],
            before=longest[1],
            last=kind(recs[-1]),
            model=meta.get("model"),
            mode=meta.get("permissionMode"),
            non_interactive=meta.get("requestNonInteractive"),
            started=recs[0]["timestamp"][:10],
            file=os.path.basename(jsonl),
        )
    )

rows.sort(key=lambda r: -r["max_gap_min"])
gaps = sorted(r["max_gap_min"] for r in rows)
print(f"phase-worker transcripts: {len(rows)} (since {since})")
if gaps:
    print(f"longest-gap median {gaps[len(gaps)//2]:.1f}m  p90 {gaps[int(len(gaps)*0.9)]:.1f}m")
for threshold in (5, 10, 15, 20, 30, 60):
    over = [r for r in rows if r["max_gap_min"] > threshold]
    bash = sum(1 for r in over if r["before"].startswith("tool_use:Bash"))
    print(f"  gap > {threshold:2d}m: {len(over):4d}  preceded by Bash tool_use: {bash}")
ended_open = [r for r in rows if r["last"].startswith("tool_use")]
print(f"ended on an unanswered tool_use: {len(ended_open)}")
print("\ntop 15:")
for r in rows[:15]:
    print(
        f"  {r['max_gap_min']:6.1f}m {r['started']} {r['model']} mode={r['mode']} "
        f"nonInteractive={r['non_interactive']} before={r['before']} last={r['last']} {r['file'][:45]}"
    )
