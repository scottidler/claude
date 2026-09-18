"""Tally a session-recall replay and re-emit the fires.tsv rows.

Reads the frozen snapshot and the replay output produced by freeze.py and
replay.py, prints the bucket counts the fixture header records, and writes the
fire rows in fires.tsv's column order. This is the step that turns a replay into
the fixed left side acceptance criterion 2 compares against.

    python3 tally.py <snapshot.jsonl> <replay.jsonl> [rows-out.tsv]
"""
import collections
import json
import re
import sys

UUID = re.compile(r'(?<![/\w\-"\'])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![/\w\-"\'])')

snap_path, replay_path = sys.argv[1], sys.argv[2]
rows_out = sys.argv[3] if len(sys.argv) > 3 else None

prompts = {}
counts = collections.Counter()
with open(snap_path, encoding="utf-8") as fh:
    for line in fh:
        r = json.loads(line)
        prompts[r["id"]] = r["prompt"]
        counts[r["bucket"]] += 1
        if r["bucket"] == "human" and r["is_meta"]:
            counts["human-isMeta"] += 1

rows = []
fires = collections.Counter()
with open(replay_path, encoding="utf-8") as fh:
    for line in fh:
        r = json.loads(line)
        if r["rc"] != 0:
            fires["NONZERO-EXIT"] += 1
        if not r["fired"]:
            continue
        if r["bucket"] != "human":
            fires["non-human"] += 1
            rows.append((r["id"], "NON-HUMAN", r["ts"], ""))
            continue
        if r["is_meta"]:
            fires["human-isMeta"] += 1
            continue
        fires["human-non-meta"] += 1
        quoted = r["context"].split("quoted verbatim from it: ", 1)[1]
        quoted = quoted.rsplit(".\n\nDecide from", 1)[0]
        arm = "id" if UUID.search(prompts[r["id"]]) else "phrase"
        rows.append((r["id"], arm, r["ts"], quoted))

print("records:", dict(sorted(counts.items())))
print("fires:  ", dict(sorted(fires.items())))
rows.sort()
if rows_out:
    with open(rows_out, "w", encoding="utf-8") as out:
        for row in rows:
            out.write("\t".join(row) + "\n")
    print("wrote", len(rows), "rows to", rows_out)
else:
    for row in rows:
        print("\t".join(row))
