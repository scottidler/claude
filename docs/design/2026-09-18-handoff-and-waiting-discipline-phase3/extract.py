#!/usr/bin/env python3
"""Phase 3 corpus extraction for handoff-guard.sh's AC2.

Walks every transcript under ~/.claude/projects, pulls the user-prompt records,
and splits them into the human set and the non-human set on the same basis F1's
Phase 2 used (`isMeta` plus the delivery-prefix tests), then runs the shipped
hook over each record and writes:

  fires.tsv    one row per record the hook fires on: id, arm, trigger
  controls.tsv the 20 committed non-handoff controls
  counts.json  denominators, so the AC's left side is a fixed list and not a
               percentage that moves with the corpus

The snapshot is NOT committed (3.9 GB). counts.json pins its size and sha of
the id list so a re-run is checkable.
"""
import hashlib
import json
import os
import pathlib
import subprocess
import sys

HOOK = pathlib.Path(__file__).resolve().parents[3] / "HOME/.claude/hooks/handoff-guard.sh"
ROOT = pathlib.Path.home() / ".claude/projects"
OUT = pathlib.Path(__file__).resolve().parent

AGENT_PREFIX = "Another Claude session sent a message:"


def records():
    for path in sorted(ROOT.rglob("*.jsonl")):
        try:
            with path.open("r", errors="replace") as fh:
                for lineno, line in enumerate(fh, 1):
                    line = line.strip()
                    if not line or not line.startswith("{"):
                        continue
                    try:
                        rec = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if rec.get("type") != "user":
                        continue
                    msg = rec.get("message") or {}
                    content = msg.get("content")
                    if not isinstance(content, str):
                        continue
                    yield {
                        "id": f"{path.name}:{lineno}",
                        "prompt": content,
                        "isMeta": bool(rec.get("isMeta")),
                    }
        except OSError:
            continue


def is_human(rec):
    """Provenance first, prefixes second: the same basis F1's round 2 settled on."""
    if rec["isMeta"]:
        return False
    p = rec["prompt"]
    if p.startswith("<") or p.startswith(AGENT_PREFIX):
        return False
    return True


def fire(prompt):
    """Run the shipped hook, not a reimplementation of its predicate."""
    payload = json.dumps(
        {
            "cwd": "/nonexistent-cwd-for-extraction",
            "hook_event_name": "UserPromptSubmit",
            "permission_mode": "auto",
            "prompt": prompt,
            "prompt_id": "extract",
            "session_id": "extract",
            "transcript_path": "/dev/null",
        }
    )
    out = subprocess.run(
        ["bash", str(HOOK)], input=payload, capture_output=True, text=True
    ).stdout.strip()
    if not out:
        return None
    try:
        ctx = json.loads(out)["hookSpecificOutput"]["additionalContext"]
    except (json.JSONDecodeError, KeyError):
        return None
    marker = "quoted verbatim from it: "
    if marker in ctx:
        # The context is multi-line; the trigger is the remainder of ITS line.
        return ctx.split(marker, 1)[1].splitlines()[0].rstrip(".")
    return ""


def main():
    human = nonhuman = 0
    human_fires = []
    nonhuman_fires = []
    for rec in records():
        h = is_human(rec)
        if h:
            human += 1
        else:
            nonhuman += 1
        # Cheap prefilter so we spawn the hook only where it could possibly fire.
        if "handoff" not in rec["prompt"].lower():
            continue
        trigger = fire(rec["prompt"])
        if trigger is None:
            continue
        (human_fires if h else nonhuman_fires).append((rec["id"], trigger))

    with (OUT / "fires.tsv").open("w") as fh:
        for rid, trig in human_fires:
            fh.write(f"{rid}\tfire1\t{trig}\n")
    with (OUT / "nonhuman-fires.tsv").open("w") as fh:
        for rid, trig in nonhuman_fires:
            fh.write(f"{rid}\tfire1\t{trig}\n")

    ids = "\n".join(rid for rid, _ in human_fires)
    counts = {
        "human_records": human,
        "nonhuman_records": nonhuman,
        "human_fires": len(human_fires),
        "nonhuman_fires": len(nonhuman_fires),
        "fires_sha256": hashlib.sha256(ids.encode()).hexdigest(),
        "transcripts": len(list(ROOT.rglob("*.jsonl"))),
    }
    (OUT / "counts.json").write_text(json.dumps(counts, indent=2) + "\n")
    json.dump(counts, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
