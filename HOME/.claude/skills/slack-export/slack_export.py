#!/usr/bin/env python3
"""Full-fidelity export of a Slack channel: messages, threads, and files.

Usage:
    slack_export.py CHANNEL DURATION [--outdir DIR] [--files-only]

    CHANNEL    channel name (with or without leading #) or ID (Cxxxxxxxxxx)
    DURATION   how far back to export: 2y | 18m | 12w | 90d | all
    --outdir   output directory (default: ~/slack-exports/<channel-name>)
    --files-only  re-download files from an existing files-index.json only
                  (resume a run once a files:read-scoped token is available)

Reads SLACK_XOXP_TOKEN from the environment (a user token), so it can see any
channel the user belongs to. Downloading file *bytes* additionally requires the
token to carry the `files:read` OAuth scope (checked at preflight; without it
messages/threads still export fully and file metadata + links are recorded).

Rate limits (https://docs.slack.dev/apis/web-api/rate-limits): tiers are
1 (1+/min), 2 (20+/min), 3 (50+/min), 4 (100+/min); on overage Slack returns
HTTP 429 with a Retry-After header, which we honor. Effective 2025-05-29, newly
created non-Marketplace apps face a special ~1 req/min, 15-objects/request cap on
conversations.history / conversations.replies. We don't assume that cap but ADAPT
into it: the first 429 on either method flips it to 15 objects/page + >=60s spacing.

Output layout (OUTDIR):
  export-meta.json   run metadata + counts
  users.json         { user_id: {name, real_name, is_bot, ...} }
  messages.json      [ top-level message, each with .replies[] and inline .files[] ]
  files-index.json   { file_id: {title, name, permalink, external_url, local_path, ...} }
  files/<file_id>__<safe_name>   downloaded file bytes (Slack-hosted files only)
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

API = "https://slack.com/api/"
TOKEN = os.environ.get("SLACK_XOXP_TOKEN")
SLACK_IDS_YML = os.path.expanduser("~/repos/.claude/slack-ids.yml")

# Methods under the 2025-05-29 special non-Marketplace limit.
SPECIAL = {"conversations.history", "conversations.replies"}
STRICT = {}            # method -> True once clamped after a 429
PAGE_SIZE = {}         # method -> current objects-per-request
MIN_INTERVAL = {}      # method -> min seconds between calls
LAST_CALL = {}         # method -> ts of last call
DEFAULT_INTERVAL = 1.2


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


# ---------------------------------------------------------------- rate limiting
def page_size(method):
    return PAGE_SIZE.get(method, 15 if STRICT.get(method) else 200)


def clamp_strict(method):
    if not STRICT.get(method):
        STRICT[method] = True
        PAGE_SIZE[method] = 15
        MIN_INTERVAL[method] = 60
        log(f"  -> {method} clamped to strict mode (15 objects/page, >=60s spacing)")


def throttle(method):
    interval = MIN_INTERVAL.get(method, DEFAULT_INTERVAL)
    last = LAST_CALL.get(method)
    if last is not None:
        wait = interval - (time.time() - last)
        if wait > 0:
            time.sleep(wait)
    LAST_CALL[method] = time.time()


def api_get(method, params):
    for attempt in range(8):
        throttle(method)
        url = API + method + "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.load(resp)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                wait = int(e.headers.get("Retry-After", "30"))
                log(f"  429 on {method}; Retry-After={wait}s")
                if method in SPECIAL:
                    clamp_strict(method)
                time.sleep(wait + 1)
                continue
            raise
        if not data.get("ok"):
            err = data.get("error", "")
            if err == "ratelimited":
                if method in SPECIAL:
                    clamp_strict(method)
                time.sleep(30)
                continue
            raise RuntimeError(f"{method} failed: {err}")
        return data
    raise RuntimeError(f"{method} exhausted retries")


def paginate(method, params, key="messages"):
    cursor = None
    while True:
        p = dict(params)
        p["limit"] = page_size(method)
        if cursor:
            p["cursor"] = cursor
        data = api_get(method, p)
        for item in data.get(key, []):
            yield item
        cursor = data.get("response_metadata", {}).get("next_cursor", "")
        if not cursor:
            break


# -------------------------------------------------------------- input parsing
def parse_duration(s):
    """Return an `oldest` unix timestamp (string) from a duration like 2y/18m/12w/90d/all."""
    s = (s or "").strip().lower()
    if s in ("all", "0", "", "everything"):
        return "0"
    m = re.fullmatch(r"(\d+)\s*([ymwd])", s)
    if not m:
        sys.exit(f"bad duration {s!r}; use forms like 2y, 18m, 12w, 90d, or all")
    n, unit = int(m.group(1)), m.group(2)
    days = {"y": 365, "m": 30, "w": 7, "d": 1}[unit] * n
    return f"{time.time() - days * 86400:.6f}"


def load_channel_names():
    """Reverse-map {name: id} from slack-ids.yml if present (no YAML dep needed)."""
    out = {}
    if not os.path.exists(SLACK_IDS_YML):
        return out
    in_channels = False
    for line in open(SLACK_IDS_YML):
        if re.match(r"^channels:\s*$", line):
            in_channels = True
            continue
        if in_channels:
            if re.match(r"^\S", line):  # next top-level key
                break
            m = re.match(r"\s+(C[A-Z0-9]+):\s*(\S+)", line)
            if m:
                out[m.group(2)] = m.group(1)
    return out


def resolve_channel(token_channel):
    """Accept a channel ID (Cxxxx) or name; return (channel_id, channel_name)."""
    raw = token_channel.lstrip("#").strip()
    if re.fullmatch(r"[CGD][A-Z0-9]+", raw):
        info = api_get("conversations.info", {"channel": raw}).get("channel", {})
        return raw, info.get("name", raw)
    names = load_channel_names()
    if raw in names:
        cid = names[raw]
        return cid, raw
    # Fall back to the API channel list (public + private).
    log(f"Resolving channel name {raw!r} via conversations.list...")
    for c in paginate("conversations.list",
                      {"types": "public_channel,private_channel", "exclude_archived": "false"},
                      key="channels"):
        if c.get("name") == raw:
            return c["id"], raw
    sys.exit(f"could not resolve channel {token_channel!r} to an ID")


# ------------------------------------------------------------------- crawling
def build_user_map():
    log("Fetching user directory (users.list)...")
    users = {}
    for u in paginate("users.list", {}, key="members"):
        prof = u.get("profile", {})
        users[u["id"]] = {
            "name": u.get("name"),
            "real_name": u.get("real_name") or prof.get("real_name"),
            "display_name": prof.get("display_name"),
            "is_bot": u.get("is_bot", False),
            "deleted": u.get("deleted", False),
        }
    log(f"  {len(users)} users")
    return users


def safe_name(name):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", name or "file")[:120]


def collect_files(msg, file_index):
    for f in msg.get("files", []) or []:
        fid = f.get("id")
        if not fid:
            continue
        file_index[fid] = {
            "id": fid,
            "name": f.get("name"),
            "title": f.get("title"),
            "pretty_type": f.get("pretty_type"),
            "mimetype": f.get("mimetype"),
            "filetype": f.get("filetype"),
            "size": f.get("size"),
            "created": f.get("created"),
            "user": f.get("user"),
            "url_private_download": f.get("url_private_download") or f.get("url_private"),
            "permalink": f.get("permalink"),
            "external_url": f.get("external_url"),
            "external_type": f.get("external_type"),
            "mode": f.get("mode"),
            "is_external": f.get("is_external", False),
        }


def download_file(f, files_dir):
    url = f.get("url_private_download") or f.get("url_private")
    if not url or f.get("is_external") or f.get("mode") in ("hidden_by_limit", "tombstone"):
        return None
    local = f"{f['id']}__{safe_name(f.get('name'))}"
    dest = os.path.join(files_dir, local)
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return os.path.join("files", local)
    for attempt in range(5):
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                body = resp.read()
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(int(e.headers.get("Retry-After", "5")) + 1)
                continue
            log(f"  file {f['id']} HTTP {e.code}")
            return None
        if body[:15].lower().startswith(b"<!doctype html") and (f.get("size") or 0) > 2000:
            log(f"  file {f['id']} looks like an HTML error page (files:read missing?)")
            return None
        with open(dest, "wb") as fh:
            fh.write(body)
        return os.path.join("files", local)
    return None


def download_all(file_index, outdir):
    files_dir = os.path.join(outdir, "files")
    os.makedirs(files_dir, exist_ok=True)
    log(f"Downloading {len(file_index)} files...")
    downloaded = 0
    for n, (fid, f) in enumerate(file_index.items(), 1):
        path = download_file(f, files_dir)
        f["local_path"] = path
        if path:
            downloaded += 1
        if n % 25 == 0:
            log(f"  {n}/{len(file_index)} files processed ({downloaded} saved)")
        time.sleep(0.3)
    with open(os.path.join(outdir, "files-index.json"), "w") as fh:
        json.dump(file_index, fh, indent=2)
    return downloaded


def enrich_inline_files(file_index, outdir):
    """Splice local_path + download_status onto the inline files[] on each message."""
    path = os.path.join(outdir, "messages.json")
    msgs = json.load(open(path))

    def status_for(idx):
        if idx and idx.get("local_path"):
            return "downloaded"
        if idx and idx.get("is_external"):
            return "external"   # bytes live outside Slack (e.g. Google Drive)
        return "unavailable"

    def walk(m):
        for f in m.get("files", []) or []:
            idx = file_index.get(f.get("id"))
            f["local_path"] = idx.get("local_path") if idx else None
            f["download_status"] = status_for(idx)
        for r in m.get("replies", []) or []:
            walk(r)

    for m in msgs:
        walk(m)
    with open(path, "w") as fh:
        json.dump(msgs, fh, indent=2)


def token_scopes():
    req = urllib.request.Request(API + "auth.test", headers={"Authorization": f"Bearer {TOKEN}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.headers.get("x-oauth-scopes", "")
    return {s.strip() for s in raw.split(",") if s.strip()}


# ----------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description="Export a Slack channel to JSON + files.")
    ap.add_argument("channel", help="channel name (with/without #) or ID (Cxxxx)")
    ap.add_argument("duration", help="how far back: 2y | 18m | 12w | 90d | all")
    ap.add_argument("--outdir", default=None, help="output dir (default ~/slack-exports/<name>)")
    ap.add_argument("--files-only", action="store_true", help="re-download files from existing index")
    args = ap.parse_args()

    if not TOKEN:
        sys.exit("SLACK_XOXP_TOKEN not set")

    channel_id, channel_name = resolve_channel(args.channel)
    oldest = parse_duration(args.duration)
    outdir = args.outdir or os.path.expanduser(f"~/slack-exports/{channel_name}")
    os.makedirs(os.path.join(outdir, "files"), exist_ok=True)
    log(f"channel={channel_name} ({channel_id})  oldest={oldest}  outdir={outdir}")

    scopes = token_scopes()
    can_files = "files:read" in scopes
    if not can_files:
        log("WARNING: token lacks 'files:read' -- file BYTES will be skipped "
            "(metadata/links still captured). Re-run with --files-only once scoped.")

    if args.files_only:
        idx_path = os.path.join(outdir, "files-index.json")
        if not os.path.exists(idx_path):
            sys.exit("--files-only set but files-index.json not found -- run a full export first")
        if not can_files:
            sys.exit("--files-only set but token lacks files:read")
        file_index = json.load(open(idx_path))
        download_all(file_index, outdir)
        enrich_inline_files(file_index, outdir)
        log("DONE (files-only)")
        return

    users = build_user_map()
    with open(os.path.join(outdir, "users.json"), "w") as fh:
        json.dump(users, fh, indent=2)

    log(f"Fetching channel history (oldest={oldest})...")
    top = list(paginate("conversations.history",
                        {"channel": channel_id, "oldest": oldest, "inclusive": "true"}))
    top.sort(key=lambda m: float(m["ts"]))
    log(f"  {len(top)} top-level messages")

    file_index = {}
    n_threads = sum(1 for m in top if m.get("reply_count", 0) > 0)
    log(f"  {n_threads} threads to expand")
    for i, m in enumerate(top):
        collect_files(m, file_index)
        if m.get("reply_count", 0) > 0:
            replies = list(paginate("conversations.replies",
                                    {"channel": channel_id, "ts": m["ts"]}))
            child = sorted((r for r in replies if r.get("ts") != m["ts"]),
                           key=lambda r: float(r["ts"]))
            for r in child:
                collect_files(r, file_index)
            m["replies"] = child
            if (i + 1) % 25 == 0:
                log(f"  expanded {i+1}/{len(top)} messages, {len(file_index)} files so far")

    with open(os.path.join(outdir, "messages.json"), "w") as fh:
        json.dump(top, fh, indent=2)
    log(f"Wrote messages.json ({len(top)} top-level)")

    if can_files:
        downloaded = download_all(file_index, outdir)
    else:
        with open(os.path.join(outdir, "files-index.json"), "w") as fh:
            json.dump(file_index, fh, indent=2)
        downloaded = 0
    enrich_inline_files(file_index, outdir)

    total_replies = sum(len(m.get("replies", [])) for m in top)
    meta = {
        "channel_id": channel_id,
        "channel_name": channel_name,
        "duration": args.duration,
        "oldest": oldest,
        "top_level_messages": len(top),
        "total_replies": total_replies,
        "total_messages": len(top) + total_replies,
        "files_referenced": len(file_index),
        "files_downloaded": downloaded,
        "files_external": sum(1 for f in file_index.values() if f.get("is_external")),
        "earliest_ts": top[0]["ts"] if top else None,
        "latest_ts": top[-1]["ts"] if top else None,
    }
    with open(os.path.join(outdir, "export-meta.json"), "w") as fh:
        json.dump(meta, fh, indent=2)
    log("DONE")
    log(json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
