#!/usr/bin/env python3
"""Slack toolkit: export a channel, and keep a local id<->name cache fresh.

Usage:
    slack.py export CHANNEL DURATION [--outdir DIR] [--files-only]
    slack.py refresh                        # rebuild the channel cache from the API
    slack.py add    CHANNEL                  # add/update one channel (by ID or name)
    slack.py find   SUBSTR                   # fuzzy-search the local cache (no API)

    CHANNEL    channel name (with or without leading #) or ID (Cxxxxxxxxxx)
    DURATION   how far back to export: 2y | 18m | 12w | 90d | all

Reads TATARI_SLACK_TOOLKIT_API_TOKEN from the environment (falls back to
SLACK_XOXP_TOKEN), a *user* token, so it sees any channel the user belongs to -
including private ones - with no bot to invite.
`find` is pure-local and needs no token. Downloading file *bytes* additionally
requires the token to carry the `files:read` OAuth scope (checked at preflight;
without it messages/threads still export fully and file metadata + links are kept).

Pure stdlib: no venv, no third-party deps. Run it with system python3.

The cache lives at ~/repos/.claude/slack-ids.json (personal, out-of-repo,
gitignore it). Shape: {"channels": {id: name}, "users": {id: username},
"groups": {id: [members]}}. refresh/add rewrite ONLY "channels"; users/groups
are preserved untouched. A private channel's NAME is confidential; its ID is not,
so this file must never be committed.

Rate limits (https://docs.slack.dev/apis/web-api/rate-limits): tiers are
1 (1+/min), 2 (20+/min), 3 (50+/min), 4 (100+/min); on overage Slack returns
HTTP 429 with a Retry-After header, which we honor. Effective 2025-05-29, newly
created non-Marketplace apps face a special ~1 req/min, 15-objects/request cap on
conversations.history / conversations.replies. We don't assume that cap but ADAPT
into it: the first 429 on either method flips it to 15 objects/page + >=60s spacing.

Export output layout (OUTDIR):
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
TOKEN = os.environ.get("TATARI_SLACK_TOOLKIT_API_TOKEN") or os.environ.get("SLACK_XOXP_TOKEN")
SLACK_IDS = os.path.expanduser("~/repos/.claude/slack-ids.json")
CHANNEL_TYPES = "public_channel,private_channel"  # group DMs (mpim)/DMs (im) excluded by design

# Methods under the 2025-05-29 special non-Marketplace limit.
SPECIAL = {"conversations.history", "conversations.replies"}
STRICT = {}            # method -> True once clamped after a 429
PAGE_SIZE = {}         # method -> current objects-per-request
MIN_INTERVAL = {}      # method -> min seconds between calls
LAST_CALL = {}         # method -> ts of last call
DEFAULT_INTERVAL = 1.2


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", file=sys.stderr, flush=True)


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


def api_request(method, params, post=False):
    for attempt in range(8):
        throttle(method)
        if post:
            body = urllib.parse.urlencode(params).encode()
            req = urllib.request.Request(
                API + method, data=body,
                headers={"Authorization": f"Bearer {TOKEN}",
                         "Content-Type": "application/x-www-form-urlencoded"})
        else:
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


def api_get(method, params):
    return api_request(method, params, post=False)


def api_post(method, params):
    return api_request(method, params, post=True)


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


# -------------------------------------------------------------- name rendering
USER_NAMES = {}                                    # uid -> display, memoized per run
MENTION = re.compile(r"<@([UW][A-Z0-9]+)>")        # inline <@U123> mentions
LINK = re.compile(r"<(https?://[^|>]+)\|([^>]+)>")  # <url|label> -> label


def user_name(uid, data=None):
    """Resolve a user id to a display name, seeding from the cache then users.info."""
    if not uid:
        return "?"
    if uid in USER_NAMES:
        return USER_NAMES[uid]
    if data and uid in data.get("users", {}):
        USER_NAMES[uid] = data["users"][uid]
        return USER_NAMES[uid]
    try:
        info = api_get("users.info", {"user": uid}).get("user", {})
        prof = info.get("profile", {})
        name = prof.get("display_name") or info.get("real_name") or info.get("name") or uid
    except Exception:
        name = uid
    USER_NAMES[uid] = name
    return name


def render_text(text, data):
    """Make Slack message text human-readable: resolve @mentions, unwrap <url|label>."""
    text = MENTION.sub(lambda m: "@" + user_name(m.group(1), data), text or "")
    return LINK.sub(lambda m: m.group(2), text)


# ------------------------------------------------------------- id<->name cache
def load_ids():
    """Load the cache; always return the three expected sections."""
    log(f"load_ids: reading {SLACK_IDS}")
    if not os.path.exists(SLACK_IDS):
        log("  cache absent; starting empty")
        return {"channels": {}, "users": {}, "groups": {}}
    with open(SLACK_IDS) as fh:
        data = json.load(fh)
    for k in ("channels", "users", "groups"):
        data.setdefault(k, {})
    log(f"  channels={len(data['channels'])} users={len(data['users'])} groups={len(data['groups'])}")
    return data


def save_ids(data):
    """Write the cache, channels sorted by name for stable diffs. Preserves users/groups."""
    data["channels"] = dict(sorted(data["channels"].items(), key=lambda kv: (kv[1], kv[0])))
    os.makedirs(os.path.dirname(SLACK_IDS), exist_ok=True)
    with open(SLACK_IDS, "w") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    log(f"save_ids: wrote {len(data['channels'])} channels to {SLACK_IDS}")


def name_to_id(data):
    """Reverse the channels map: {name: id}."""
    return {name: cid for cid, name in data["channels"].items()}


def fetch_channels(all_workspace=False):
    """Channels -> {id: name}.

    Default: only channels YOU belong to (users.conversations) - fast and relevant.
    all_workspace=True: every public+private channel in the workspace
    (conversations.list) - the rare case where you need one you're not in.
    """
    method = "conversations.list" if all_workspace else "users.conversations"
    log(f"fetch_channels: {method} types={CHANNEL_TYPES} all_workspace={all_workspace}")
    out = {}
    for c in paginate(method,
                      {"types": CHANNEL_TYPES, "exclude_archived": "false"},
                      key="channels"):
        name = c.get("name")
        if name:
            out[c["id"]] = name
    log(f"  {len(out)} channels {'in the workspace' if all_workspace else 'you belong to'}")
    return out


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


def resolve_channel(token_channel):
    """Accept a channel ID (Cxxxx) or name; return (channel_id, channel_name)."""
    raw = token_channel.lstrip("#").strip()
    log(f"resolve_channel: {raw!r}")
    if re.fullmatch(r"[CGD][A-Z0-9]+", raw):
        info = api_get("conversations.info", {"channel": raw}).get("channel", {})
        return raw, info.get("name", raw)
    names = name_to_id(load_ids())
    if raw in names:
        cid = names[raw]
        log(f"  cache hit -> {cid}")
        return cid, raw
    log(f"  cache miss; resolving {raw!r} via conversations.list...")
    for c in paginate("conversations.list",
                      {"types": CHANNEL_TYPES, "exclude_archived": "false"},
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


def _md_transform(t):
    """Convert the non-code parts of markdown to Slack mrkdwn."""
    t = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", r"<\2|\1>", t)   # image -> labeled link
    t = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"<\2|\1>", t)     # [label](url) -> <url|label>
    t = re.sub(r"(?m)^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$", "\x01\\1\x01", t)  # heading -> bold line (sentinel)
    t = re.sub(r"(?m)^(\s*)[-*+]\s+", r"\1• ", t)            # bullet -> •
    t = re.sub(r"(\*\*|__)(.+?)\1", "\x01\\2\x01", t)        # **bold**/__bold__ -> sentinel
    t = re.sub(r"~~(.+?)~~", r"~\1~", t)                     # ~~strike~~ -> ~strike~
    t = re.sub(r"(?<!\w)\*(?=\S)(.+?)(?<=\S)\*(?!\w)", r"_\1_", t)  # *italic* -> _italic_
    return t.replace("\x01", "*")                            # sentinel -> *bold*


def to_mrkdwn(md):
    """Best-effort markdown -> Slack mrkdwn, leaving code spans/fences untouched.

    Handles the common cases Claude emits: **bold**->*bold*, *italic*->_italic_,
    ~~strike~~->~strike~, [label](url)-><url|label>, # headings->*bold* lines,
    -/*/+ bullets->•. Slack has no headings/tables/nested lists, so those flatten.
    """
    protected = []

    def stash(m):
        protected.append(m.group(0))
        return f"\x00{len(protected) - 1}\x00"

    tmp = re.sub(r"```.*?```", stash, md, flags=re.DOTALL)   # fenced code
    tmp = re.sub(r"`[^`\n]+`", stash, tmp)                   # inline code
    tmp = _md_transform(tmp)
    return re.sub(r"\x00(\d+)\x00", lambda m: protected[int(m.group(1))], tmp)


def token_scopes():
    req = urllib.request.Request(API + "auth.test", headers={"Authorization": f"Bearer {TOKEN}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.headers.get("x-oauth-scopes", "")
    return {s.strip() for s in raw.split(",") if s.strip()}


# ------------------------------------------------------------------ subcommands
def cmd_refresh(args):
    log(f"cmd_refresh: rebuilding channel cache (all_workspace={args.all})")
    data = load_ids()
    before = len(data["channels"])
    fetched = fetch_channels(all_workspace=args.all)
    new = [cid for cid in fetched if cid not in data["channels"]]
    data["channels"].update(fetched)   # upsert; never drop channels you've left/archived
    save_ids(data)
    log(f"refresh done: {len(fetched)} fetched, {len(new)} new, {len(data['channels'])} total (was {before})")


def cmd_add(args):
    raw = args.channel.lstrip("#").strip()
    log(f"cmd_add: {raw!r}")
    data = load_ids()
    if re.fullmatch(r"C[A-Z0-9]+", raw):
        info = api_get("conversations.info", {"channel": raw}).get("channel", {})
        name = info.get("name")
        if not name:
            sys.exit(f"{raw} has no channel name (DMs/group DMs aren't cached)")
        cid = raw
    else:
        cid = None
        for c in paginate("conversations.list",
                          {"types": CHANNEL_TYPES, "exclude_archived": "false"},
                          key="channels"):
            if c.get("name") == raw:
                cid, name = c["id"], raw
                break
        if not cid:
            sys.exit(f"could not resolve channel name {raw!r}")
    existed = cid in data["channels"]
    data["channels"][cid] = name
    save_ids(data)
    log(f"add done: {cid} -> {name} ({'updated' if existed else 'added'})")


def cmd_find(args):
    q = args.query.lower().lstrip("#")
    data = load_ids()
    hits = sorted(((name, cid) for cid, name in data["channels"].items() if q in name.lower()))
    if not hits:
        log(f"no channel matching {args.query!r} in cache -- try: slack.py refresh")
        return
    for name, cid in hits:
        print(f"{cid}  {name}")


def cmd_read(args):
    cid, cname = resolve_channel(args.channel)
    log(f"cmd_read: {cname}({cid}) thread={args.thread} since={args.since} limit={args.limit}")
    data = load_ids()
    if args.thread:
        msgs = list(paginate("conversations.replies", {"channel": cid, "ts": args.thread}))
    elif args.since:
        msgs = list(paginate("conversations.history",
                             {"channel": cid, "oldest": parse_duration(args.since), "inclusive": "true"}))
    else:
        msgs = api_get("conversations.history", {"channel": cid, "limit": args.limit}).get("messages", [])
    msgs.sort(key=lambda m: float(m.get("ts", 0)))
    for m in msgs:
        ts = time.strftime("%Y-%m-%d %H:%M", time.localtime(float(m["ts"])))
        who = user_name(m.get("user") or m.get("bot_id") or "", data)
        print(f"[{ts}] {who}: {render_text(m.get('text', ''), data)}")
        rc = m.get("reply_count", 0)
        if rc and not args.thread:
            print(f"    +{rc} replies (thread ts {m['ts']})")


def cmd_send(args):
    cid, cname = resolve_channel(args.channel)
    text = args.text if args.raw else to_mrkdwn(args.text)   # markdown -> Slack mrkdwn by default
    log(f"cmd_send: {cname}({cid}) thread={args.thread} raw={args.raw} chars={len(text)}")
    params = {"channel": cid, "text": text}
    if args.thread:
        params["thread_ts"] = args.thread
    resp = api_post("chat.postMessage", params)
    log(f"send done: channel={cname}({cid}) ts={resp.get('ts')}")
    print(resp.get("ts", ""))


def cmd_search(args):
    log(f"cmd_search: {args.query!r} count={args.count}")
    resp = api_get("search.messages", {"query": args.query, "count": args.count, "sort": "timestamp"})
    matches = resp.get("messages", {}).get("matches", [])
    data = load_ids()
    log(f"  {len(matches)} matches")
    for m in matches:
        ts = time.strftime("%Y-%m-%d %H:%M", time.localtime(float(m["ts"])))
        ch = (m.get("channel") or {}).get("name") or (m.get("channel") or {}).get("id", "")
        who = m.get("username") or user_name(m.get("user") or "", data)
        text = render_text(m.get("text", ""), data).replace("\n", " ")
        print(f"[{ts}] #{ch} {who}: {text}")
        if m.get("permalink"):
            print(f"    {m['permalink']}")


def cmd_export(args):
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


# ----------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(prog="slack.py",
                                 description="Slack toolkit: export channels + manage the id<->name cache.")
    sub = ap.add_subparsers(dest="mode", required=True)

    pe = sub.add_parser("export", help="export a channel's full history to JSON + files")
    pe.add_argument("channel", help="channel name (with/without #) or ID (Cxxxx)")
    pe.add_argument("duration", help="how far back: 2y | 18m | 12w | 90d | all")
    pe.add_argument("--outdir", default=None, help="output dir (default ~/slack-exports/<name>)")
    pe.add_argument("--files-only", action="store_true", help="re-download files from existing index")
    pe.set_defaults(func=cmd_export)

    prd = sub.add_parser("read", help="print recent messages (or a thread) from a channel")
    prd.add_argument("channel", help="channel name (with/without #) or ID (Cxxxx)")
    prd.add_argument("--limit", type=int, default=50, help="messages to show (default 50; ignored with --since)")
    prd.add_argument("--since", default=None, help="pull everything since a duration: 2y|18m|12w|90d")
    prd.add_argument("--thread", default=None, help="a parent message ts to read that thread instead")
    prd.set_defaults(func=cmd_read)

    ps = sub.add_parser("send", help="post a message (converts markdown -> Slack mrkdwn by default; --raw to skip)")
    ps.add_argument("channel", help="channel name (with/without #) or ID (Cxxxx)")
    ps.add_argument("text", help="message text (markdown; auto-converted to Slack mrkdwn)")
    ps.add_argument("--thread", default=None, help="parent message ts to reply under")
    ps.add_argument("--raw", action="store_true", help="send text verbatim; skip markdown -> mrkdwn conversion")
    ps.set_defaults(func=cmd_send)

    psr = sub.add_parser("search", help="keyword search messages across the workspace")
    psr.add_argument("query", help="search query (Slack search syntax works, e.g. in:#foo from:@bar)")
    psr.add_argument("--count", type=int, default=20, help="max results (default 20)")
    psr.set_defaults(func=cmd_search)

    pr = sub.add_parser("refresh", help="cache the channels you belong to (--all for the whole workspace)")
    pr.add_argument("--all", action="store_true", help="pull every public+private channel in the workspace, not just yours")
    pr.set_defaults(func=cmd_refresh)

    pa = sub.add_parser("add", help="add/update one channel in the cache (by ID or name)")
    pa.add_argument("channel", help="channel ID (Cxxxx) or name")
    pa.set_defaults(func=cmd_add)

    pf = sub.add_parser("find", help="fuzzy-search the local cache for a channel (no API, no token)")
    pf.add_argument("query", help="substring of the channel name")
    pf.set_defaults(func=cmd_find)

    args = ap.parse_args()
    if args.mode != "find" and not TOKEN:
        sys.exit("no token: set TATARI_SLACK_TOOLKIT_API_TOKEN (or SLACK_XOXP_TOKEN)")
    args.func(args)


if __name__ == "__main__":
    main()
