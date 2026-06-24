---
name: sdv-verify
description: >-
  Report a Tatari hosted site's standard endpoints - Status, Deployed, Version
  (sdv) - for ANY *.tatari.dev / *.tatari.tv URL, via the `sdv` CLI
  (`sdv verify <url>`). Use when asked what version is live, is it up, did the
  rollout land, check test/prod, or to confirm a deploy. This is ONE command - do
  NOT cold-start, do NOT reach for aws-vault/kubectl/port-forward, do NOT build a
  verifier skill. (To verify a non-deployed code change at its runtime surface, use
  the generic `verify` skill.)
---

# sdv-verify

## Run the `sdv` CLI

For anything served at a Tatari URL (`*.tatari.dev`, `*.tatari.tv`
- marquee, persona, any platform service), the answer is the `sdv` CLI
(`~/.cargo/bin/sdv`, source `~/repos/tatari-tv/sdv`). The `sdv verify <url>`
subcommand probes the standard `/status`, `/deployed`, `/version` endpoints at the
host root and reports them. It carries its own Okta token, so it works from OUTSIDE
the cluster - no aws-vault, no `kubectl`, no port-forward.

```bash
sdv verify https://marquee.test.tatari.dev   # report status/deployed/version (yaml on tty, json piped)
sdv whoami                                     # cached auth email (is a token live?)
sdv login --device                             # headless Okta for SSH/agent shells: prints code+URL, approve anywhere
sdv token                                      # print a bearer for raw curl/scripts
sdv verify https://marquee.test.tatari.dev --format json | jq -r '.version.body.version'  # just the live version
```

- The public URL 302s to `tatari.okta.com` for a bare `curl` - that is expected;
  the CLI carries the token. If you must curl directly:
  `curl -H "Authorization: Bearer $(sdv token)" https://<host>/version`.
- Not logged in (`sdv whoami` empty / report 401)? In an interactive shell `sdv
  login` opens a browser; in a non-interactive/agent/SSH shell use `sdv login
  --device` and hand the user the printed code+URL. Then re-run.

That is the whole task. Paste the CLI's output as the evidence - don't paraphrase.

## Reading the output

`sdv verify` returns a `status`/`deployed`/`version` block per endpoint. The fields
that usually matter:

- `version.body.version` - the live build (`v1.6.1` clean tag vs `v1.6.0-2-gSHA`
  means N commits past the last tag at build time); `git_sha`/`branch` should match
  the commit you expect live.
- `deployed.body` - `deployed_at`, `deployer`, `environment`.
- `status.body` - `status` + `uptime` (a tiny uptime right after a rollout is the
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
