#!/usr/bin/env python3
"""How far back does the authorization for a Slack post actually sit?

For every historical post, walk the typed turns backwards and record the
distance to the nearest turn that asks for a post. Distance 1 is the current
turn. That distribution is what says whether a 3-turn window is right-sized or
arbitrary.
"""
import json
import pathlib
import re
from collections import Counter

ROOT = pathlib.Path.home() / ".claude" / "projects"
WRITE_TOOLS = {
    "mcp__slack__chat_post_message",
    "mcp__slack__chat_update",
    "mcp__slack__chat_schedule_message",
}
RELAY = "Another Claude session sent a message:"
ASK = re.compile(
    r"(^|[^A-Za-z0-9])("
    r"post|posts|posted|posting|send|sends|sent|sending|share|shares|shared|sharing|"
    r"announce|announced|announcement|message|messages|messaged|msg|dm|dms|slack|"
    r"slackify|reply|replies|replied|ping|pings|notify|tell|thread|crosspost|"
    r"cross-post|missive|clipboard|mrkdwn"
    r")([^A-Za-z0-9]|$)", re.I)


def typed_turns(records, upto):
    out = []
    for rec in records[:upto]:
        if rec.get("type") != "user" or rec.get("isSidechain") is True:
            continue
        c = (rec.get("message") or {}).get("content")
        if not isinstance(c, str) or c.startswith(RELAY):
            continue
        if c.startswith("<") and not c.startswith("<command-"):
            continue
        out.append(c)
    return out


dist = Counter()
never = 0
total = 0
examples = {}
for path in ROOT.rglob("*.jsonl"):
    try:
        raw = path.read_text(errors="replace").splitlines()
    except Exception:
        continue
    if not any('"mcp__slack__chat_' in l or "slack write" in l for l in raw):
        continue
    records = []
    for line in raw:
        try:
            records.append(json.loads(line))
        except Exception:
            records.append({})
    for i, rec in enumerate(records):
        if rec.get("type") != "assistant":
            continue
        for b in (rec.get("message") or {}).get("content") or []:
            if not isinstance(b, dict) or b.get("type") != "tool_use":
                continue
            inp = b.get("input") or {}
            if b.get("name") in WRITE_TOOLS:
                pass
            elif b.get("name") == "Bash" and "slack write" in (inp.get("command") or ""):
                if "--help" in (inp.get("command") or ""):
                    continue
            else:
                continue
            turns = typed_turns(records, i)
            total += 1
            d = None
            for back, t in enumerate(reversed(turns), start=1):
                if ASK.search(t):
                    d = back
                    break
            if d is None:
                never += 1
                examples.setdefault("never", turns[-1][:70] if turns else "")
            else:
                dist[d] += 1
                if d >= 4:
                    examples.setdefault(d, turns[-d][:70])

print(f"posts={total}  no posting ask in the WHOLE session prefix={never}")
run = 0
for d in sorted(dist):
    run += dist[d]
    print(f"  distance {d:2d}: {dist[d]:4d}   cumulative {run:4d}  ({100*run/total:.1f}%)")
print()
for k in sorted(examples, key=str):
    print(f"  first ask at {k}: {examples[k]}")
