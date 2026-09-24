---
description: Publish an artifact to marquee and return the Okta-gated URL
argument-hint: "<title>"
---
Publish to marquee with the `marquee` CLI. pi has no MCP, so drive the binary directly.

Title: ${@:-derive a short title from the content}

Build a directory with exactly one entry document (`index.html` or `index.md`); sibling
assets ride along and are served same-origin, so a data-driven page can fetch its own
`data.json`. Then:

    marquee publish --title "<title>" --description "<one or two plain sentences>"

Write the `--description` yourself: it is the Slack unfurl blurb, plaintext only, under
about 200 characters, saying what the artifact is and why someone would open it. Add
`--space <name>` for a shared space and `--tags a b c` (space separated, never commas).
The printed URL is the handle for `marquee replace` and `marquee delete`; keep it.
