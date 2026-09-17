#!/usr/bin/env python3
"""Replay every historical Slack post through slack-post-guard.sh, with the
turn's REAL typed prompt reconstructed the way the guard reads it.

Two numbers matter and the acceptance criteria measure neither:

  recall     do the guards deny the posts that were incidents
  precision  what share of the legitimate posts would they now deny

For each Slack write tool_use, this walks back through the transcript prefix the
hook would have seen, picks the turn's typed prompt with the corrected
extractor, writes a one-record transcript carrying it, and asks the guard.
"""
import json, os
import pathlib
import shutil
import subprocess
import sys
import tempfile
from collections import Counter

GUARD = sys.argv[2] if len(sys.argv) > 2 else str(pathlib.Path.home() / ".claude/hooks/slack-post-guard.sh")
ROOT = pathlib.Path.home() / ".claude" / "projects"
WRITE_TOOLS = {
    "mcp__slack__chat_post_message",
    "mcp__slack__chat_update",
    "mcp__slack__chat_schedule_message",
}
RELAY = "Another Claude session sent a message:"


WINDOW = 3


def typed_prompt(records, upto):
    """The last WINDOW qualifying typed turns, which is what the guard now
    reads. Returns them newest-last, one per element."""
    best = []
    for rec in records[:upto]:
        if rec.get("type") != "user" or rec.get("isSidechain") is True:
            continue
        content = (rec.get("message") or {}).get("content")
        if not isinstance(content, str):
            continue
        if content.startswith(RELAY):
            continue
        if content.startswith("<") and not content.startswith("<command-"):
            continue
        best.append(content)
    return best[-WINDOW:]


# PATCHED 2026-09-17, REWRITTEN after panel round 2 (M1). The round-1 patch was
# wrong four ways and is not the shape to return to. History, so nobody re-derives it:
#
#   original    rmtree'd $HOME/.cache/slack/sent-ledger once per row. That is the LIVE
#               ledger (slack-post-guard.sh:113), so a 216-row replay destroyed live
#               duplicate-post protection 216 times.
#   round-1 fix pointed a REPLAY_LEDGER env var at a scratch path. USELESS: the guard
#               hard-codes LEDGER at :113 and reads no such variable, so the guard kept
#               writing 216 reservations into the LIVE ledger while the per-row reset
#               stopped touching the ledger the guard actually used. It also turned
#               `REPLAY_LEDGER=` (set, empty) into rmtree('.'), and its lexical
#               equality check was bypassed by `..` or a symlinked parent.
#
# The guard touches $HOME in exactly three places: IDS (:112), LEDGER (:113) and a `~/`
# body-file expansion (:248). So HOME is the isolation seam the guard already has, and
# no env var it does not read, and no edit to the guard, is required. We hand the
# subprocess a scratch HOME holding a COPY of the ids cache. The ledger then lives and
# dies inside the scratch dir, and the live one is never opened.
#
# Note for whoever reads a count: the `~/` expansion at :248 moves with HOME, so a
# body-file path spelled `~/...` resolves differently under replay. The 17 known
# artifact rows are $S/$TMPDIR//tmp paths and are excluded from the TARGET count
# anyway; Phase 0a confirms the baseline still reproduces at 26 / 9 / 17.

REPLAY_HOME = pathlib.Path(tempfile.mkdtemp(prefix="replay-home-"))
(REPLAY_HOME / ".cache/slack").mkdir(parents=True, exist_ok=True)
_live_ids = pathlib.Path.home() / ".cache/slack/ids.json"
if _live_ids.exists():
    shutil.copy2(_live_ids, REPLAY_HOME / ".cache/slack/ids.json")
LEDGER = REPLAY_HOME / ".cache/slack/sent-ledger"
assert LEDGER != pathlib.Path.home() / ".cache/slack/sent-ledger"


def verdict(payload):
    # A fresh ledger per post. Replaying a year of traffic in one minute makes
    # every repeated body look like a resend, which it was not: those posts were
    # hours or weeks apart and the entries expire in an hour.
    shutil.rmtree(LEDGER, ignore_errors=True)
    env = dict(os.environ, HOME=str(REPLAY_HOME))
    out = subprocess.run(["bash", GUARD], input=json.dumps(payload),
                         capture_output=True, text=True, env=env).stdout
    # `{}` IS the guard's allow (slack-post-guard.sh:139 `allow() { echo '{}'; exit 0; }`),
    # so an absent hookSpecificOutput is a PASS, not a parse failure. The round-1 patch
    # raised on it and died on the first of the baseline's 190 allows.
    try:
        parsed = json.loads(out)
    except Exception:
        raise SystemExit(f"guard produced unparseable output: {out!r}")
    d = parsed.get("hookSpecificOutput")
    if d is None:
        return "allow", ""
    if d.get("permissionDecision") != "deny":
        return "allow", ""
    return "deny", d.get("permissionDecisionReason", "")


rows = []
tmp = pathlib.Path(tempfile.mkdtemp())
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
        for block in (rec.get("message") or {}).get("content") or []:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            name = block.get("name")
            inp = block.get("input") or {}
            if name in WRITE_TOOLS:
                kind, tool_input = "mcp", inp
            elif name == "Bash" and "slack write" in (inp.get("command") or ""):
                kind, tool_input = "bash", inp
            else:
                continue
            window = typed_prompt(records, i)
            txf = tmp / "tx.jsonl"
            txf.write_text("".join(
                json.dumps({
                    "type": "user", "isSidechain": False,
                    "promptId": "P1" if k == len(window) - 1 else f"P{k}",
                    "promptSource": "typed",
                    "message": {"content": c},
                }) + "\n" for k, c in enumerate(window)))
            payload = {
                "hook_event_name": "PreToolUse",
                "tool_name": name,
                "tool_input": tool_input,
                "transcript_path": str(txf),
                "prompt_id": "P1",
                "cwd": str(pathlib.Path.home()),
            }
            d, reason = verdict(payload)
            rows.append({
                "kind": kind,
                "tool": name,
                "target": tool_input.get("channel") or (tool_input.get("command") or "")[:60],
                "text": (tool_input.get("text") or tool_input.get("command") or "")[:90],
                "prompt": (window[-1] if window else "")[:90],
                "window": " || ".join(w[:60] for w in window),
                "decision": d,
                "rule": reason.split(":")[1].strip()[:44] if ":" in reason else reason[:44],
                "session": path.name,
            })

out = pathlib.Path(sys.argv[1])
out.write_text(json.dumps(rows, indent=1))
tally = Counter(r["decision"] for r in rows)
print(f"posts={len(rows)}  allow={tally['allow']}  deny={tally['deny']}")
for rule, n in Counter(r["rule"] for r in rows if r["decision"] == "deny").most_common():
    print(f"  {n:4d}  {rule}")
