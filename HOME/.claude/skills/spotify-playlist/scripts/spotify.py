#!/usr/bin/env python3
"""Spotify playlist tool: OAuth bootstrap + create-playlist-from-tracks.

Stdlib only (no pip installs). Credentials come from the environment:
  SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET   (hydrated from scottidler/secrets)
  SPOTIFY_REFRESH_TOKEN                       (after one-time bootstrap)

Subcommands:
  auth-url                 Print the authorize URL to open in a browser.
  exchange <code>          Exchange an authorization code for tokens; prints the
                           refresh token (store it as spotify-refresh-token.age).
  create --name NAME --tracks FILE [--public] [--description DESC]
                           Create a playlist and add the resolved tracks.

The gotcha this tool exists to handle: creating a playlist requires a USER access
token with playlist-modify scope. A client-credentials (app) token CANNOT do it.
We get a user token by refreshing SPOTIFY_REFRESH_TOKEN (no browser needed once
bootstrapped). Access tokens last ~1h, so we always mint a fresh one per run.

Tracks file is JSON: a list of objects with "title" (required) and optional
"artist". Order is preserved in the playlist.
  [{"title": "My Sharona", "artist": "The Knack"}, {"title": "Magic", "artist": "Pilot"}]
"""
import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.spotify.com/v1"
ACCOUNTS = "https://accounts.spotify.com"
# Must exactly match a Redirect URI registered on the Spotify app dashboard.
REDIRECT_URI = "https://github.com/scottidler"
SCOPES = "playlist-modify-public playlist-modify-private"


def log(msg):
    print(msg, file=sys.stderr)


def creds():
    cid = os.environ.get("SPOTIFY_CLIENT_ID")
    csec = os.environ.get("SPOTIFY_CLIENT_SECRET")
    if not cid or not csec:
        sys.exit("SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET not set "
                 "(they hydrate from scottidler/secrets at shell startup)")
    return cid, csec


def basic_auth_header():
    cid, csec = creds()
    raw = base64.b64encode(f"{cid}:{csec}".encode()).decode()
    return f"Basic {raw}"


def http(method, url, headers=None, data=None, form=False):
    if form and data is not None:
        body = urllib.parse.urlencode(data).encode()
    elif data is not None:
        body = json.dumps(data).encode()
    else:
        body = None
    req = urllib.request.Request(url, data=body, method=method)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode() or "{}"
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, {"raw": raw}


# ---- token flows ---------------------------------------------------------

def cmd_auth_url(_args):
    cid, _ = creds()
    q = urllib.parse.urlencode({
        "client_id": cid,
        "response_type": "code",
        "redirect_uri": REDIRECT_URI,
        "scope": SCOPES,
        "show_dialog": "true",
    })
    print(f"{ACCOUNTS}/authorize?{q}")
    log("\nOpen that URL, approve, then copy the `code` value from the address "
        "bar of the page you land on (it looks like https://github.com/"
        "scottidler/?code=XXXX). Run: spotify.py exchange XXXX")


def cmd_exchange(args):
    code, data = http("POST", f"{ACCOUNTS}/api/token",
                      headers={"Authorization": basic_auth_header(),
                               "Content-Type": "application/x-www-form-urlencoded"},
                      data={"grant_type": "authorization_code",
                            "code": args.code,
                            "redirect_uri": REDIRECT_URI},
                      form=True)
    if code != 200 or "refresh_token" not in data:
        sys.exit(f"exchange failed: {code} {data}")
    log("refresh token obtained. Store it as a secret, e.g.:")
    log("  cd ~/repos/scottidler/secrets/.secrets && \\")
    log("  manifest age encrypt SPOTIFY_REFRESH_TOKEN=<value> -o . && \\")
    log("  mv spotify-refresh-token.age . && git add spotify-refresh-token.age && git commit -m 'add spotify refresh token'")
    # Print ONLY the refresh token to stdout so it can be captured/piped.
    print(data["refresh_token"])


def access_token():
    """Mint a fresh user access token from the stored refresh token."""
    rt = os.environ.get("SPOTIFY_REFRESH_TOKEN")
    if not rt:
        sys.exit("SPOTIFY_REFRESH_TOKEN not set. Run the one-time bootstrap: "
                 "`spotify.py auth-url`, approve, then `spotify.py exchange <code>` "
                 "and store the result as spotify-refresh-token.age.")
    code, data = http("POST", f"{ACCOUNTS}/api/token",
                      headers={"Authorization": basic_auth_header(),
                               "Content-Type": "application/x-www-form-urlencoded"},
                      data={"grant_type": "refresh_token", "refresh_token": rt},
                      form=True)
    if code != 200 or "access_token" not in data:
        sys.exit(f"token refresh failed: {code} {data}")
    return data["access_token"]


# ---- playlist creation ---------------------------------------------------

def search_track(token, title, artist):
    auth = {"Authorization": f"Bearer {token}"}
    queries = []
    if artist:
        queries.append(f'track:"{title}" artist:"{artist}"')
        queries.append(f"{title} {artist}")
    queries.append(f'track:"{title}"')
    queries.append(title)
    for q in queries:
        url = f"{API}/search?" + urllib.parse.urlencode(
            {"q": q, "type": "track", "limit": 1})
        code, data = http("GET", url, headers=auth)
        items = data.get("tracks", {}).get("items", []) if code == 200 else []
        if items:
            return items[0]
    return None


def cmd_create(args):
    token = access_token()

    with open(args.tracks) as f:
        tracks = json.load(f)
    if not isinstance(tracks, list) or not tracks:
        sys.exit("tracks file must be a non-empty JSON list")

    code, me = http("GET", f"{API}/me", headers={"Authorization": f"Bearer {token}"})
    if code != 200:
        sys.exit(f"/me failed: {code} {me}")
    user_id = me["id"]
    log(f"user: {user_id}")

    uris, missing = [], []
    for i, t in enumerate(tracks, 1):
        title = t.get("title") or t.get("name")
        artist = t.get("artist")
        if not title:
            missing.append(f"#{i} (no title)")
            continue
        hit = search_track(token, title, artist)
        if not hit:
            missing.append(f"{title}" + (f" - {artist}" if artist else ""))
            log(f"  [{i}] NOT FOUND: {title}" + (f" - {artist}" if artist else ""))
            continue
        uris.append(hit["uri"])
        got = hit["artists"][0]["name"]
        log(f"  [{i}] {hit['name']} - {got}  ({hit['uri']})")

    if not uris:
        sys.exit("no tracks resolved; aborting (nothing created)")

    code, pl = http("POST", f"{API}/users/{urllib.parse.quote(user_id)}/playlists",
                    headers={"Authorization": f"Bearer {token}",
                             "Content-Type": "application/json"},
                    data={"name": args.name,
                          "public": args.public,
                          "description": args.description or ""})
    if code not in (200, 201):
        sys.exit(f"create playlist failed: {code} {pl}")
    pid = pl["id"]
    log(f"created playlist: {pl['name']} ({pid})")

    # Spotify caps add at 100 URIs per request.
    for chunk_start in range(0, len(uris), 100):
        chunk = uris[chunk_start:chunk_start + 100]
        code, res = http("POST", f"{API}/playlists/{pid}/tracks",
                         headers={"Authorization": f"Bearer {token}",
                                  "Content-Type": "application/json"},
                         data={"uris": chunk})
        if code not in (200, 201):
            sys.exit(f"add tracks failed: {code} {res}")
    log(f"added {len(uris)} tracks" + (f" ({len(missing)} not found)" if missing else ""))

    result = {"id": pid, "name": pl["name"], "url": pl["external_urls"]["spotify"],
              "added": len(uris), "missing": missing}
    print(json.dumps(result, indent=2))


def main():
    p = argparse.ArgumentParser(description="Spotify playlist tool")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("auth-url").set_defaults(func=cmd_auth_url)

    ex = sub.add_parser("exchange")
    ex.add_argument("code")
    ex.set_defaults(func=cmd_exchange)

    cr = sub.add_parser("create")
    cr.add_argument("--name", required=True)
    cr.add_argument("--tracks", required=True, help="path to tracks JSON file")
    cr.add_argument("--public", action="store_true", help="make playlist public (default private)")
    cr.add_argument("--description", default="")
    cr.set_defaults(func=cmd_create)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
