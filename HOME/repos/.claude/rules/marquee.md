---
alwaysApply: true
---

# Marquee

- Marquee posts live behind the Okta gateway. Any `https://marquee.*.tatari.dev/p/{space}/{slug}` URL (or bare `{space}/{slug}`) -> the `marquee:read` skill / `marquee read` CLI. NEVER WebFetch/curl a marquee URL -- it 302s to Okta and returns login HTML, never content.
- Publishing -> `marquee:publish`; updating an existing post -> `marquee:replace`; both via the `marquee` CLI.

## Sandbox

- The `marquee` CLI writes its token cache (`~/.config/marquee/tokens.json`), so it FAILS inside the command sandbox with `Read-only file system (os error 30)`. Always run `marquee` commands with sandbox disabled. Do not burn an attempt in-sandbox first.

## Auth (headless sessions)

- Token cache: `~/.config/marquee/tokens.json`. Expired/missing token in a non-interactive session -> run `marquee login --device` in the background, surface the `https://tatari.okta.com/activate?user_code=XXXX` link ONCE, and keep working on everything else while waiting. Retry the read after Scott approves.
- Do not re-ask or re-post the code; the login completes on its own. If Scott says "marquee is authd", retry immediately.

## Content

- Scott's marquee posts are frequently referenced as design/research inputs (decision reports, /last30days digests). When a task cites a marquee link, reading it via `marquee read` is step one -- do not proceed on the link's title alone.
