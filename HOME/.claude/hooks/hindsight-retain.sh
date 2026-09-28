#!/usr/bin/env bash
# Stop hook: fire-and-forget retain of the last exchange into the work or home
# Hindsight bank, routed by cwd. Never blocks, never fails the turn.
set -u

HINDSIGHT_API_URL="${HINDSIGHT_API_URL:-https://hindsight-api.escote.duckdns.org}"

# Authelia in front of hindsight-api takes base64 "hindsight-client:<password>".
# A shell started before the secret existed lacks it, so decrypt on demand.
if [ -z "${ESCOTE_HINDSIGHT_API_BASIC:-}" ]; then
  eval "$(manifest age decrypt "$HOME/repos/scottidler/keep/.secrets/escote-hindsight-api-basic.age" 2>/dev/null)"
fi
[ -z "${ESCOTE_HINDSIGHT_API_BASIC:-}" ] && exit 0

input="$(cat)"
cwd="$(echo "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null)"
transcript="$(echo "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("transcript_path",""))' 2>/dev/null)"

[ -z "$cwd" ] && exit 0
[ -z "$transcript" ] && exit 0
[ -f "$transcript" ] || exit 0

# Hard excludes: never retain from these regardless of cwd (comp/perf/HR/PII).
case "$cwd" in
  */comp*|*/perf-h1-2026*|*/perf-h2-2025*|*/ai-tools-hire*|*/sadie-resume*)
    exit 0
    ;;
esac

case "$cwd" in
  */tatari-tv/*|*/tatari-dev/*)
    bank=work
    ;;
  *)
    bank=home
    ;;
esac

payload="$(python3 - "$transcript" "$cwd" <<'PYEOF'
import json, sys

transcript_path, cwd = sys.argv[1], sys.argv[2]

lines = []
try:
    with open(transcript_path, "r") as f:
        lines = f.readlines()
except Exception:
    sys.exit(0)

# Grab the last user+assistant text turns (skip tool_use/tool_result noise).
texts = []
for line in reversed(lines):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    msg = obj.get("message") or {}
    role = msg.get("role")
    content = msg.get("content")
    if role not in ("user", "assistant"):
        continue
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        text = " ".join(
            b.get("text", "") for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        )
    else:
        text = ""
    text = text.strip()
    if text:
        texts.append(f"{role}: {text}")
    if len(texts) >= 4:
        break

if not texts:
    sys.exit(0)

texts.reverse()
body = "\n\n".join(texts)[-6000:]
content = f"[{cwd}]\n{body}"
print(json.dumps({"items": [{"content": content}]}))
PYEOF
)"

[ -z "$payload" ] && exit 0

# Fire-and-forget: background, no output, never blocks or fails the turn.
nohup curl -s -m 20 -X POST "${HINDSIGHT_API_URL}/v1/default/banks/${bank}/memories" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Basic ${ESCOTE_HINDSIGHT_API_BASIC}" \
  -d "$payload" >/dev/null 2>&1 &
disown 2>/dev/null

exit 0
