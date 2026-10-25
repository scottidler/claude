---
name: share
description: Summarize a YouTube video, GitHub repo, blog post, doc, or website and post it to Slack as the link plus 3-5 bullets on what it is and why to click. Usage `/share <url> <#channel>... [--at <when>]`.
disable-model-invocation: true
argument-hint: "<url> <#channel>... [--at <when>]"
---

# share

Post one URL to one or more Slack channels, now or at a future time, with 3-5 bullets that answer: what is this, and why should I click on it?

## Steps

1. Take the URL, one or more channels, and an optional `--at <when>` from the arguments. If no channel is given, ask for one. Never guess a channel. If `--at` is absent, post now.
2. Fetch the source:

   ```bash
   ~/.claude/skills/share/scripts/fetch.sh '<url>'
   ```

   The script prints `TYPE:` (`youtube | github | web`), then metadata, then the transcript, README, or page text, capped at 30k characters. Quote the URL, because `&` is a shell operator.
3. If the fetch fails or returns a login wall or empty text, stop and report the error line. Do not summarize from the URL alone.
4. Read `~/Claude/writing/VOICE.md` and write the message in the Slack one-liner register.
5. Post the same message to every channel through the `slack:write` skill with `--markdown-to-mrkdwn`, so the link and bullets render as Slack mrkdwn. With `--at`, pass it through to `slack:write` so each post is scheduled, not sent.
6. Report one line per channel: the permalink for a sent post, the scheduled id and send time for a scheduled one. Those lines are the proof of done.

## Message shape

```
<url>
- what it is: one concrete sentence naming the thing
- why click: the payoff for the reader
- 1-3 more bullets: a specific claim, number, or moment from the source
```

- The URL goes on the first line alone, so Slack unfurls the preview.
- 3 bullets minimum, 5 maximum. Every bullet is one line.
- Each bullet carries a fact from the fetched text: a number, a name, a timestamp, a design choice. Generic praise ("great deep dive") fails the bar.
- Say who it is for, or who can skip it, in one bullet when the source makes that clear.

## By type

- **youtube**: cite the length and the channel. Put one `mm:ss` timestamp in a bullet only when the transcript carries it.
- **github**: cite the language, the last push, and what the README says it does. Say if the repo looks stale or has no license.
- **web**: name the author or site, and the one argument or finding the page makes.

## Limits

- A summary comes only from fetched text. If the transcript is missing or the page is truncated at the cap, say so in a closing bullet.
- Summarize once per invocation, then post that one message to each channel. Re-running posts again.
- If one channel fails, still post to the rest, then report the failure line for that channel.
- A `--at` time that is not in the future is an error. Report it and post nothing.
- The post goes out signed as agent-written. `slack:write` enforces that; do not try to remove it.

## Requirements

- `ytx`, `yt-dlp` (youtube), `gh` (github), `curl` (web via r.jina.ai), the `slack` CLI with an Okta login.
