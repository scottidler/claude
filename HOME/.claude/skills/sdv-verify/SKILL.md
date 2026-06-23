---
name: sdv-verify
description: >-
  Report a Tatari hosted site's standard endpoints - Status, Deployed, Version
  (sdv) - for ANY *.tatari.dev / *.tatari.tv URL, via the `verify` CLI. Use when
  asked what version is live, is it up, did the rollout land, check test/prod, or
  to confirm a deploy. This is ONE command - do NOT cold-start, do NOT reach for
  aws-vault/kubectl/port-forward, do NOT build a verifier skill. (To verify a
  non-deployed code change at its runtime surface, use the generic `verify` skill.)
---

# sdv-verify

## Run the `verify` CLI

For anything served at a Tatari URL (`*.tatari.dev`, `*.tatari.tv`
- marquee, persona, any platform service), the answer is the `verify` CLI
(`~/.cargo/bin/verify`, source `~/repos/tatari-tv/verify`). It probes the standard
`/status`, `/deployed`, `/version` endpoints at the host root and reports them. It
carries its own Okta token, so it works from OUTSIDE the cluster - no aws-vault, no
`kubectl`, no port-forward.

```bash
verify https://marquee.test.tatari.dev    # report status/deployed/version (yaml on tty, json piped)
verify --whoami                            # cached auth email (is a token live?)
verify --login --device                    # headless Okta for SSH/agent shells: prints code+URL, approve anywhere
verify --token                             # print a bearer for raw curl/scripts
```

- The public URL 302s to `tatari.okta.com` for a bare `curl` - that is expected;
  the CLI carries the token. If you must curl directly:
  `curl -H "Authorization: Bearer $(verify --token)" https://<host>/version`.
- Not logged in (`--whoami` empty / report 401)? In an interactive shell `verify
  --login` opens a browser; in a non-interactive/agent/SSH shell use `verify
  --login --device` and hand the user the printed code+URL. Then re-run.

That is the whole task. Paste the CLI's output as the evidence - don't paraphrase.

## Reading the output

`verify` returns a `status`/`deployed`/`version` block per endpoint. The fields
that usually matter:

- `version.body.version` - the live build (`v1.6.1` clean tag vs `v1.6.0-2-gSHA`
  means N commits past the last tag at build time); `git_sha`/`branch` should match
  the commit you expect live.
- `deployed.body` - `deployed_at`, `deployer`, `environment`.
- `status.body` - `status` + `uptime` (a tiny uptime right after a rollout is the
  new pod; a large one means you may be hitting the OLD binary).

A non-`ok` `state` on any endpoint, or a version/sha that doesn't match what you
shipped, is the finding - report it with the raw block.
