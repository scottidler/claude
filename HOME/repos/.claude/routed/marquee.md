---
alwaysApply: true
load:
  prompt: ['marquee']
  tools:
    - { match: '^mcp__marquee__' }
  bash:
    - '^marquee\b'
---

# Marquee

- Marquee posts live behind the Okta gateway. Any `https://marquee.*.tatari.dev/p/{space}/{slug}` URL (or bare `{space}/{slug}`) -> the `marquee:read` skill / `marquee read` CLI. NEVER WebFetch/curl a marquee URL -- it 302s to Okta and returns login HTML, never content.
- Publishing -> `marquee:publish`; updating an existing post -> `marquee:replace`; both via the `marquee` CLI.

## Sandbox

- Run `marquee` inside the sandbox. Measured 2026-10-06: `marquee list --tags` succeeds there, and `~/.config/marquee/` is writable (a `touch` probe worked), because `~/.config` is in the sandbox write allowlist.
- The network half is the allowlist: `marquee.internal.tatari.dev` (prod) and `marquee.test.tatari.dev` (test) are in `sandbox.network.allowedDomains`. Before they were added, the same call died with `client error (Connect): tunnel error: unsuccessful`. A tunnel error means the host is missing from the allowlist, not that the sandbox bars the CLI.
- Token refresh needs `tatari.okta.com` in the allowlist too. Measured 2026-10-06: with the cache forced expired and that host absent, the call died with `deny network-outbound tatari.okta.com:443` then `Okta token is missing or expired ... non-interactive session`. With it present, the sandboxed call refreshed and rewrote the cache.
- The old claim here (`Read-only file system (os error 30)` on the token-cache write, so always disable the sandbox) did not reproduce. Only if that exact error recurs, retry once with the sandbox off and record the failing command here.
- Not measured: a `marquee login --device` write from inside the sandbox.

## Auth (headless sessions)

- Token cache: `~/.cache/okta/tokens.json` (shared `okta_auth` cache; `~/.config/marquee/tokens.json` is a dead leftover the CLI no longer reads). Expired/missing token in a non-interactive session -> run `marquee login --device` in the background, surface the `https://tatari.okta.com/activate?user_code=XXXX` link ONCE, and keep working on everything else while waiting. Retry the read after Scott approves.
- Do not re-ask or re-post the code; the login completes on its own. If Scott says "marquee is authd", retry immediately.

## Content

- Scott's marquee posts are frequently referenced as design/research inputs (decision reports, /last30days digests). When a task cites a marquee link, reading it via `marquee read` is step one -- do not proceed on the link's title alone.
