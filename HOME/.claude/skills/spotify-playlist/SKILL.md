---
name: spotify-playlist
description: Create a Spotify playlist on SCOTT'S OWN Spotify account (never the requesting user's) from a list of songs, using Scott's stored credentials. Use this whenever the user wants to build, make, generate, or save a Spotify playlist from a list of tracks, a "top N" / countdown list, a screenshot or image of songs, a theme ("70s one-hit wonders", "workout mix"), or any set of songs they want turned into a real playlist on Spotify. Trigger even if the user just pastes a list of songs and says "make this a playlist" or "put these on Spotify" without naming the API. The target is always Scott's account, so confirm the user intends that before creating. Handles the OAuth/token gotcha (playlist creation needs a USER token, not an app token) automatically via a long-lived refresh credential.
allowed-tools: Bash
permissions:
  - network
  - env
  - file_write
---

# Spotify Playlist

Create a real playlist on Scott's Spotify account from a list of songs: resolve
each song to a Spotify track, create a named playlist, and add the tracks in
order. All Spotify Web API plumbing lives in `scripts/spotify.py` (stdlib only,
no installs).

## Whose account, and what this does (read before running)

- **This always writes to Scott's own Spotify account**, using Scott's stored
  credentials — never the requesting user's account. If whoever is driving the
  agent is not Scott (or expected the playlist on their own account), STOP and
  confirm before doing anything.
- **Playlist creation is persistent and not auto-undoable.** The playlist stays
  on the account until someone deletes it by hand. Treat it like a real write.
- **`--public` exposes the playlist to the world.** Default is private; only add
  `--public` when the user explicitly asks for a public playlist.
- **Confirm before creating.** Show the user the resolved track list and the
  intended playlist name/visibility, and get an explicit go-ahead before the
  `create` call.

## The one thing that bites people

Creating a playlist acts on a user's account, so it needs a **user bearer token
(OAuth) with `playlist-modify-public` / `playlist-modify-private` scope**. A
client-credentials (app) token built from just the client id/secret **cannot**
create playlists — it'll 401/403. This skill mints a user bearer token by
refreshing a long-lived **refresh credential**, so no browser is needed per run.

## Credentials (already in the environment)

- `$SPOTIFY_CLIENT_ID`, `$SPOTIFY_CLIENT_SECRET` — the "mashup" app, hydrated
  from `scottidler/secrets` at shell startup.
- `$SPOTIFY_REFRESH_TOKEN` — set after the one-time bootstrap (below). The script
  uses it to mint a fresh ~1h bearer token on every run.

If `$SPOTIFY_REFRESH_TOKEN` is missing, do the **one-time bootstrap** first.

## Normal workflow (refresh token already set)

1. **Gather the songs.** From the user's list, image, or theme. For accuracy,
   resolve the **artist** for each title yourself before searching — bare titles
   are ambiguous (e.g. "Magic" matches dozens of songs; "Magic" by Pilot does
   not). For "top N one-hit wonders" style lists, the artist is the whole point.

2. **Write a tracks JSON file** — a list preserving the order you want in the
   playlist. `title` is required, `artist` is strongly recommended:

   ```json
   [
     {"title": "Spirit in the Sky", "artist": "Norman Greenbaum"},
     {"title": "Seasons in the Sun", "artist": "Terry Jacks"}
   ]
   ```

   Order note: the user's list may be a countdown (#10 → #1). Decide whether they
   want it played best-first (#1 first) or as a building countdown (#10 first); if
   ambiguous, default to the list's printed order and say which you used.

3. **Run it:**

   ```bash
   python "$HOME/.claude/skills/spotify-playlist/scripts/spotify.py" create \
     --name "Top 10 One-Hit Wonders of the 1970s" \
     --tracks /tmp/tracks.json \
     --description "Countdown of the top 10 one-hit wonders of the 1970s."
   ```

   Add `--public` to make it public (default is private). The script prints each
   resolved track to stderr and a JSON result `{id, name, url, added, missing}`
   to stdout. **Always show the user the `url`** and report anything in `missing`
   (those titles didn't resolve — offer to retry with a corrected artist).

## One-time bootstrap (only if `$SPOTIFY_REFRESH_TOKEN` is unset)

This needs the user to approve in a browser once; after that it's automatic forever.

1. Print the authorize URL and give it to the user:
   ```bash
   python "$HOME/.claude/skills/spotify-playlist/scripts/spotify.py" auth-url
   ```
2. User opens it, approves, and lands on `https://github.com/scottidler/?code=XXXX`
   (the registered redirect URI isn't a real callback server, so the code just
   sits in the address bar). Ask them to paste the `code` value.
3. Exchange it for a refresh token:
   ```bash
   python "$HOME/.claude/skills/spotify-playlist/scripts/spotify.py" exchange XXXX
   ```
   The token is a **long-lived credential** that grants ongoing write access to
   Scott's account until it is manually revoked. The script does **not** print it
   to stdout — it writes it to `$HOME/.config/spotify/refresh-token` (mode 0600) and
   prints only that path. **Never `cat`/`echo`/paste the token into chat, logs, or
   a transcript.** Encrypt it into the secret store and shred the plaintext:
   ```bash
   cd ~/repos/scottidler/secrets/.secrets
   manifest age encrypt "SPOTIFY_REFRESH_TOKEN=$(cat $HOME/.config/spotify/refresh-token)" -o .
   git add spotify-refresh-token.age && git commit -m "add spotify refresh token"
   shred -u $HOME/.config/spotify/refresh-token
   ```
   It hydrates as `$SPOTIFY_REFRESH_TOKEN` on the next shell. For the current
   session, export it inline (reading from the file, not by pasting the value) so
   you can proceed without restarting. If the token is ever exposed, revoke it at
   developer.spotify.com and re-run this bootstrap.

## Notes

- Search uses `track:"X" artist:"Y"` first, then looser fallbacks, taking the top
  hit. A deluxe/remaster edition of the right song by the right artist is fine.
- Adds are chunked at 100 URIs/request (the API max), so large lists work.
- Registered redirect URI is `https://github.com/scottidler`. If the bootstrap
  ever fails with a redirect mismatch, confirm that exact URI is still on the app
  at developer.spotify.com (the "mashup" app).
