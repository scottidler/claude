---
name: sdv-probe
description: >-
  Report a Tatari hosted site's standard endpoints - Status, Deployed, Version
  (sdv) - for ANY *.tatari.dev / *.tatari.tv URL, via the `sdv` CLI
  (`sdv probe <url>`). Use when asked what version is live, is it up, did the
  rollout land, check test/prod, or to confirm a deploy. This is ONE command - do
  NOT cold-start, do NOT reach for aws-vault/kubectl/port-forward, do NOT build a
  verifier skill. (To verify a non-deployed code change at its runtime surface, use
  the generic `verify` skill.)
---

# sdv-probe

## Run the `sdv` CLI

For anything served at a Tatari URL (`*.tatari.dev`, `*.tatari.tv`
- marquee, persona, any platform service), the answer is the `sdv` CLI
(`~/.cargo/bin/sdv`, source `~/repos/tatari-tv/sdv`). The `sdv probe <url>`
subcommand probes the standard `/status`, `/deployed`, `/version` endpoints at the
host root and reports them. It carries its own Okta token, so it works from OUTSIDE
the cluster - no aws-vault, no `kubectl`, no port-forward.

```bash
sdv probe https://marquee.test.tatari.dev   # report status/deployed/version (yaml on tty, json piped)
sdv whoami                                     # cached auth email (is a token live?)
sdv login --device                             # headless Okta for SSH/agent shells: prints code+URL, approve anywhere
sdv token                                      # print a bearer for raw curl/scripts
sdv probe https://marquee.test.tatari.dev --format json | jq -r '.version.payload.version'  # just the live version
```

- The public URL 302s to `tatari.okta.com` for a bare `curl` - that is expected;
  the CLI carries the token. If you must curl directly:
  `curl -H "Authorization: Bearer $(sdv token)" https://<host>/version`.
- Not logged in (`sdv whoami` empty / report 401)? In an interactive shell `sdv
  login` opens a browser; in a non-interactive/agent/SSH shell use `sdv login
  --device` and hand the user the printed code+URL. Then re-run.

That is the whole task. Paste the CLI's output as the evidence - don't paraphrase.

## Reading the output

`sdv probe` returns a `status`/`deployed`/`version` block per endpoint, each with a
`state` and the server's `payload` (passed through untouched). When a payload carries
RFC-3339 timestamps, sdv adds a sibling `local` block rendering them in your machine's
timezone. The fields that usually matter:

- `version.payload.version` - the live build (`v1.6.1` clean tag vs `v1.6.0-2-gSHA`
  means N commits past the last tag at build time); `revision`/`branch` should match
  the commit you expect live.
- `deployed.payload` - `deployed_at`, `deployer`, `environment` (with
  `deployed.local.deployed_at` for the deploy time in your timezone).
- `status.payload` - `status` + `uptime` (a tiny uptime right after a rollout is the
  new pod; a large one means you may be hitting the OLD binary).

A non-`ok` `state` on any endpoint, or a version/sha that doesn't match what you
shipped, is the finding - report it with the raw block.

## Exit codes (read the failure, don't just paste it)

- `0` - at least one endpoint responded (report on stdout).
- `1` - bad input / local error (malformed URL, etc.) - fix the invocation.
- `2` - auth failure (edge bounced / not authorized). Warm the cache: `sdv login`
  (interactive) or `sdv login --device` (SSH/agent), then re-run.
- `3` - host unreachable (DNS/connect failed) - check the URL/host, not auth.
- `4` - host reachable but no `/status`,`/deployed`,`/version` (all `absent`) - not
  a Tatari standard-endpoint service, or wrong host.
