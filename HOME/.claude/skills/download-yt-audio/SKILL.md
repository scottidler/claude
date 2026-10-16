---
name: download-yt-audio
description: Download the audio only of one or more YouTube videos to opus, m4a, or mp3 files with yt-dlp and ffmpeg, through a bundled script that checks dependencies first and prints install commands for anything missing. Use whenever Scott pastes a youtube.com or youtu.be URL and wants the sound, the song, the audio, an mp3, or "no video", even if he says "rip", "grab", or "save this track" and never names yt-dlp. Not for transcripts (use ytx or fabric) and not for downloading video.
---

# download-yt-audio

All work goes through one script. It checks the dependencies, downloads each URL as a single video, retries once on HTTP 403, and prints one result line per URL.

```bash
S=~/.claude/skills/download-yt-audio/scripts/download_yt_audio.py
python3 -I $S check
python3 -I $S get '<url>' ['<url>' ...] [--format native|opus|m4a|mp3] [--out-dir DIR]
```

## Steps

1. Pick the format from Scott's words:
   - "mp3" -> `--format mp3` (re-encodes at best VBR quality)
   - "m4a" -> `--format m4a`
   - anything else -> omit `--format`. `native` keeps YouTube's own audio stream (usually opus) with no re-encode, so there is no quality loss.
2. Run `get` with every URL in one call. Quote each URL, because pasted links carry `&list=...&index=...` and `&` is a shell operator.
3. Report each `ok <size> <path>` line, and each `fail <url> <reason>` line verbatim. The `ok` lines are the proof of done.

The default output dir is `~/Downloads/yt-audio`. Use `--out-dir` only when Scott names another place.

## What the script handles, so you don't

- **Single video only.** The script always passes `--no-playlist`, so a `list=RD...` mix param never pulls the whole playlist. Scott wants the one video. Do not strip URL params by hand.
- **Dependencies.** `get` runs `check` first. If `yt-dlp`, `ffmpeg`, `ffprobe`, or `deno` is missing, it prints `MISS` lines with a `fix:` install command and downloads nothing. Show Scott those lines; do not install anything without his go-ahead.
- **Soft warnings.** A yt-dlp build over 90 days old or a missing `~/.config/yt-dlp/config` prints a `warn` line, and the download still runs. Stale yt-dlp caused widespread 403s in September 2026. If downloads then fail with 403, relay the warning and ask before running `uv tool upgrade yt-dlp`.
- **403 retry.** On `HTTP Error 403` the script waits 10 seconds and retries once. Intermittent 403s run about 6% in borg, so one failure is not a reason to change anything.

## Hard limits

- Never add `-v`/`--verbose` to a yt-dlp run, and never run yt-dlp by hand with it, without Scott's explicit permission. The config uses his signed-in Firefox cookies, and a request burst already triggered a YouTube bot-check on 2026-10-16. The script's own `--debug` flag is safe: it logs the script's steps, not yt-dlp's.
- Audio only. Never download or keep video files.
- Do not loop the script in parallel over URLs. One sequential `get` call keeps the request rate low.

## Exit codes

- `check`: 0 when every required dependency is present, 1 otherwise.
- `get`: 0 when every URL produced a file, 1 when any URL failed or a dependency is missing.
