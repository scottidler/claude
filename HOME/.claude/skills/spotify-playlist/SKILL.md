---
name: spotify-playlist
description: Create a Spotify playlist programmatically from a list of songs on Scott's account. Use this whenever the user wants to build, make, generate, or save a Spotify playlist from a list of tracks, a "top N" / countdown list, a screenshot or image of songs, a theme ("70s one-hit wonders", "workout mix"), or any set of songs they want turned into a real playlist on Spotify. Trigger even if the user just pastes a list of songs and says "make this a playlist" or "put these on Spotify" without naming the API. Handles the OAuth/token gotcha (playlist creation needs a USER token, not an app token) automatically via a stored refresh token.
---

# Spotify Playlist

Create a real playlist on Scott's Spotify account from a list of songs: resolve
each song to a Spotify track, create a named playlist, and add the tracks in
order. All Spotify Web API plumbing lives in `scripts/spotify.py` (stdlib only,
no installs).

## The one thing that bites people

Creating a playlist acts on a user's account, so it needs a **user access token
with `playlist-modify-public` / `playlist-modify-private` scope**. A
client-credentials (app) token built from just the client id/secret **cannot**
create playlists — it'll 401/403. This skill gets a user token by refreshing a
long-lived **refresh token** stored as a secret, so no browser is needed per run.

## Credentials (already in the environment)

- `$SPOTIFY_CLIENT_ID`, `$SPOTIFY_CLIENT_SECRET` — the "mashup" app, hydrated
  from `scottidler/secrets` at shell startup.
- `$SPOTIFY_REFRESH_TOKEN` — set after the one-time bootstrap (below). The script
  uses it to mint a fresh ~1h access token on every run.

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
   python ~/.claude/skills/spotify-playlist/scripts/spotify.py create \
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
   python ~/.claude/skills/spotify-playlist/scripts/spotify.py auth-url
   ```
2. User opens it, approves, and lands on `https://github.com/scottidler/?code=XXXX`
   (the registered redirect URI isn't a real callback server, so the code just
   sits in the address bar). Ask them to paste the `code` value.
3. Exchange it for a refresh token:
   ```bash
   python ~/.claude/skills/spotify-playlist/scripts/spotify.py exchange XXXX
   ```
   The refresh token prints to stdout. **Store it as a secret** so it persists and
   hydrates as `$SPOTIFY_REFRESH_TOKEN`:
   ```bash
   cd ~/repos/scottidler/secrets/.secrets
   manifest age encrypt SPOTIFY_REFRESH_TOKEN=<token>
   git add spotify-refresh-token.age && git commit -m "add spotify refresh token"
   ```
   It's a secret — don't echo it into chat; pipe/redirect it into the encrypt step.
   The new env var loads on the next shell; for the current session export it
   inline so you can proceed without restarting.

## Notes

- Search uses `track:"X" artist:"Y"` first, then looser fallbacks, taking the top
  hit. A deluxe/remaster edition of the right song by the right artist is fine.
- Adds are chunked at 100 URIs/request (the API max), so large lists work.
- Registered redirect URI is `https://github.com/scottidler`. If the bootstrap
  ever fails with a redirect mismatch, confirm that exact URI is still on the app
  at developer.spotify.com (the "mashup" app).
