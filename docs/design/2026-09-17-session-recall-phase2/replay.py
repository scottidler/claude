"""Replay session-recall-guard.sh over the frozen snapshot.

Invokes the REAL hook once per record (no reimplementation of the predicate),
and records fire / no-fire plus the emitted additionalContext.
"""
import json, subprocess, sys, os
from concurrent.futures import ThreadPoolExecutor

SNAP = sys.argv[1]
HOOK = sys.argv[2]
OUT = sys.argv[3]

records = []
with open(SNAP, encoding="utf-8") as fh:
    for line in fh:
        records.append(json.loads(line))


def run(rec):
    payload = json.dumps({
        "cwd": "/home/saidler/repos/scottidler/claude",
        "hook_event_name": "UserPromptSubmit",
        "permission_mode": "auto",
        "prompt": rec["prompt"],
        "prompt_id": "replay",
        "session_id": "replay",
        "transcript_path": rec["path"],
    })
    p = subprocess.run(["bash", HOOK], input=payload, capture_output=True, text=True)
    out = p.stdout.strip()
    fired = bool(out)
    ctx = ""
    if fired:
        ctx = json.loads(out)["hookSpecificOutput"]["additionalContext"]
    return {
        "id": rec["id"],
        "bucket": rec["bucket"],
        "is_meta": rec["is_meta"],
        "ts": rec["ts"],
        "rc": p.returncode,
        "fired": fired,
        "context": ctx,
        "stderr": p.stderr.strip()[:200],
    }


with ThreadPoolExecutor(max_workers=int(os.environ.get("WORKERS", "16"))) as ex:
    results = list(ex.map(run, records))

with open(OUT, "w", encoding="utf-8") as out:
    for r in results:
        out.write(json.dumps(r, ensure_ascii=False) + "\n")
print("replayed", len(results))
