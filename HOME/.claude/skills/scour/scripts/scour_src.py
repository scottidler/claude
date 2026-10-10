#!/usr/bin/env python3
"""Fetch one source for a scour lane. Stdlib only.

Success: JSON on stdout, exit 0.
Failure: {"ok": false, "source": ..., "error": ..., "attempts": [...]} on stdout, exit 1.
Never returns partial or paywalled text as if it were the page.

  scour_src.py fetch <url>                 clean text; reader proxy, direct, then Wayback
  scour_src.py hn-search <query> [--days N] [--comments]
  scour_src.py hn-item <id>
  scour_src.py reddit-available            exit 0 only if Reddit credentials are in the env
  scour_src.py reddit-search <query> [--sub S]
  scour_src.py reddit-thread <post_id>

Reddit needs REDDIT_CLIENT_ID and REDDIT_CLIENT_SECRET (app-only OAuth). Without them
every reddit-* command fails; unauthenticated Reddit is blocked.
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

UA = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
TIMEOUT = 30
MIN_BODY_CHARS = 500
PAYWALL_MARKERS = (
    "subscribe to continue",
    "subscribers only",
    "to continue reading",
    "create a free account to continue",
    "sign in to read",
    "you have reached your",
    "enable javascript and cookies",
    "verify you are human",
)


class SourceError(Exception):
    def __init__(self, message, attempts=None):
        super().__init__(message)
        self.attempts = attempts or []


def http_get(url, headers=None, data=None):
    request = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})}, data=data)
    host = urllib.parse.urlparse(url).netloc
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        raise SourceError(f"HTTP {error.code} from {host}")
    except (urllib.error.URLError, TimeoutError) as error:
        raise SourceError(f"{type(error).__name__} from {host}: {getattr(error, 'reason', error)}")


class TextExtractor(HTMLParser):
    SKIPPED = {"script", "style", "noscript", "svg", "head"}

    def __init__(self):
        super().__init__()
        self.parts = []
        self.skip_depth = 0

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIPPED:
            self.skip_depth += 1

    def handle_endtag(self, tag):
        if tag in self.SKIPPED and self.skip_depth:
            self.skip_depth -= 1

    def handle_data(self, data):
        if not self.skip_depth and data.strip():
            self.parts.append(data.strip())


def html_to_text(body):
    if not body.lstrip().lower().startswith(("<!doctype", "<html")):
        return body
    extractor = TextExtractor()
    extractor.feed(body)
    return "\n".join(extractor.parts)


def blocked_reason(body):
    if len(body) < MIN_BODY_CHARS:
        return f"body under {MIN_BODY_CHARS} chars"
    low = body.lower()
    for marker in PAYWALL_MARKERS:
        if marker in low:
            return f"paywall or bot-wall marker: {marker!r}"
    return None


def wayback_snapshot(url):
    api = "https://archive.org/wayback/available?url=" + urllib.parse.quote(url, safe="")
    closest = json.loads(http_get(api)).get("archived_snapshots", {}).get("closest", {})
    if not closest.get("available"):
        raise SourceError("no Wayback snapshot")
    return closest["url"]


def fetch(url):
    ladder = [
        ("jina-reader", lambda: http_get("https://r.jina.ai/" + url)),
        ("direct", lambda: http_get(url)),
        ("wayback", lambda: http_get("https://r.jina.ai/" + wayback_snapshot(url))),
    ]
    attempts = []
    for name, step in ladder:
        try:
            body = html_to_text(step())
        except SourceError as error:
            attempts.append(f"{name}: {error}")
            continue
        reason = blocked_reason(body)
        if reason:
            attempts.append(f"{name}: {reason}")
            continue
        return {"ok": True, "source": "fetch", "via": name, "url": url, "text": body}
    raise SourceError("every fetch route failed or hit a paywall", attempts)


def hn_search(query, days, comments):
    params = {"query": query, "tags": "comment" if comments else "story", "hitsPerPage": 30}
    if days:
        params["numericFilters"] = f"created_at_i>{int(time.time()) - days * 86400}"
    body = http_get("https://hn.algolia.com/api/v1/search?" + urllib.parse.urlencode(params))
    hits = [
        {
            "id": hit["objectID"],
            "url": f"https://news.ycombinator.com/item?id={hit['objectID']}",
            "title": hit.get("title") or (hit.get("comment_text") or "")[:300],
            "points": hit.get("points"),
            "comments": hit.get("num_comments"),
            "date": hit.get("created_at"),
        }
        for hit in json.loads(body)["hits"]
    ]
    if not hits:
        raise SourceError(f"hn: no hits for {query!r}")
    return {"ok": True, "source": "hn-search", "hits": hits}


def hn_item(item_id):
    return {"ok": True, "source": "hn-item", "item": json.loads(http_get(f"https://hn.algolia.com/api/v1/items/{item_id}"))}


def reddit_token():
    client_id = os.environ.get("REDDIT_CLIENT_ID")
    client_secret = os.environ.get("REDDIT_CLIENT_SECRET")
    if not (client_id and client_secret):
        raise SourceError("reddit: REDDIT_CLIENT_ID and REDDIT_CLIENT_SECRET not set")
    basic = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    body = http_get(
        "https://www.reddit.com/api/v1/access_token",
        headers={"Authorization": f"Basic {basic}"},
        data=b"grant_type=client_credentials",
    )
    token = json.loads(body).get("access_token")
    if not token:
        raise SourceError("reddit: token request returned no access_token")
    return token


def reddit_get(path, params):
    headers = {"Authorization": f"Bearer {reddit_token()}"}
    return json.loads(http_get(f"https://oauth.reddit.com{path}?" + urllib.parse.urlencode(params), headers=headers))


def reddit_search(query, sub):
    path = f"/r/{sub}/search" if sub else "/search"
    params = {"q": query, "sort": "new", "limit": 25, "restrict_sr": "1" if sub else "0"}
    posts = [
        {
            "id": child["data"]["id"],
            "url": "https://www.reddit.com" + child["data"]["permalink"],
            "subreddit": child["data"]["subreddit"],
            "title": child["data"]["title"],
            "score": child["data"]["score"],
            "comments": child["data"]["num_comments"],
        }
        for child in reddit_get(path, params)["data"]["children"]
    ]
    if not posts:
        raise SourceError(f"reddit: no posts for {query!r}")
    return {"ok": True, "source": "reddit-search", "posts": posts}


def reddit_thread(post_id):
    return {"ok": True, "source": "reddit-thread", "thread": reddit_get(f"/comments/{post_id}", {"limit": 50, "depth": 4})}


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("fetch").add_argument("url")
    hn = sub.add_parser("hn-search")
    hn.add_argument("query")
    hn.add_argument("--days", type=int, default=0)
    hn.add_argument("--comments", action="store_true")
    sub.add_parser("hn-item").add_argument("id")
    sub.add_parser("reddit-available")
    rs = sub.add_parser("reddit-search")
    rs.add_argument("query")
    rs.add_argument("--sub")
    sub.add_parser("reddit-thread").add_argument("post_id")
    return parser


def run(args):
    if args.command == "fetch":
        return fetch(args.url)
    if args.command == "hn-search":
        return hn_search(args.query, args.days, args.comments)
    if args.command == "hn-item":
        return hn_item(args.id)
    if args.command == "reddit-available":
        reddit_token()
        return {"ok": True, "source": "reddit-available"}
    if args.command == "reddit-search":
        return reddit_search(args.query, args.sub)
    return reddit_thread(args.post_id)


def main():
    args = build_parser().parse_args()
    try:
        result = run(args)
    except SourceError as error:
        print(json.dumps({"ok": False, "source": args.command, "error": str(error), "attempts": error.attempts}))
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
