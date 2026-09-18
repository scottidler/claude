"""Freeze a corpus snapshot for the Phase 2 replay.

One JSON object per line: {"id": "<session>.jsonl:<lineno>", "bucket": ...,
"is_meta": bool, "ts": str, "prompt": str}. The snapshot is frozen because the
corpus grows during the run and a live re-walk is not reproducible.
"""
import json, glob, os, sys

ROOT = "/home/saidler/.claude/projects"
OUT = sys.argv[1]


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return None
        parts = [b.get("text") or "" for b in content
                 if isinstance(b, dict) and b.get("type") == "text"]
        return "\n".join(parts) if parts else None
    return None


def bucket(t):
    if t.startswith("<"):
        return "tagged"
    if t.startswith("Another Claude session sent a message:"):
        return "another"
    if t.startswith("Review this change for security"):
        return "secrev"
    if t.startswith("Caveat:"):
        return "caveat"
    return "human"


n = 0
with open(OUT, "w", encoding="utf-8") as out:
    for path in sorted(glob.iglob(ROOT + "/**/*.jsonl", recursive=True)):
        base = os.path.basename(path)
        with open(path, encoding="utf-8", errors="replace") as fh:
            for lineno, line in enumerate(fh, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if d.get("type") != "user" or d.get("isSidechain"):
                    continue
                t = text_of((d.get("message") or {}).get("content"))
                if t is None:
                    continue
                out.write(json.dumps({
                    "id": "%s:%d" % (base, lineno),
                    "path": path,
                    "bucket": bucket(t),
                    "is_meta": bool(d.get("isMeta")),
                    "ts": d.get("timestamp") or "",
                    "prompt": t,
                }, ensure_ascii=False) + "\n")
                n += 1
print("frozen records:", n)
