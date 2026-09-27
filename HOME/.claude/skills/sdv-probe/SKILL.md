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

For anything served at a Tatari URL (`*.tatari.dev` / `*.tatari.tv` - marquee,
persona, any platform service), the answer is the `sdv` CLI
(`sdv probe <url>`). The `sdv probe <url>` subcommand probes the standard
`/status`, `/deployed`, `/version` endpoints at the host root and reports them. It
carries its own Okta token, so it works from OUTSIDE the cluster - no aws-vault, no
`kubectl`, no port-forward.

The commands themselves - submit each via the Bash tool with
`run_in_background: true` and poll per "Always invoke `sdv` backgrounded"
below, never as a plain synchronous call:

```bash
sdv probe https://marquee.test.tatari.dev   # report status/deployed/version (yaml on tty, json piped)
sdv whoami                                     # cached account email (identity only, NOT proof the token is valid)
sdv login --device                             # headless Okta for SSH/agent shells: prints code+URL, approve anywhere
sdv token                                      # print a bearer for raw curl/scripts
set -o pipefail; sdv probe https://marquee.test.tatari.dev --format json | jq -er '.version.payload.version'  # live version; pipefail + jq -e surface a probe/parse failure
```

- The public URL 302s to `tatari.okta.com` for a bare `curl` - that is expected;
  the CLI carries the token. Prefer `sdv probe`; it never puts the token on a
  command line. If you must curl directly, avoid `$(sdv token)` in the argument
  list (it shows up in `ps`) - pass the bearer via a `curl --config` file you
  delete afterward, not inline.
- Auth failed (probe exit `2` / a `401`)? That - not `sdv whoami`, which only
  shows the cached account - is the liveness signal. Warm the cache with `sdv
  login --device` (see "Always invoke `sdv` backgrounded" below - that call can
  block on the device-code approval, so never run it synchronously), then
  re-run `sdv probe`.

**Always invoke `sdv` via the Bash tool with `run_in_background: true` and
poll, never as a plain synchronous call.** Any `sdv` command - `probe`,
`whoami`, `token`, `login` - can trigger or itself be a blocking Okta login
(browser redirect or a device-code grant that prints a code + URL and polls).
Already-authenticated calls finish almost immediately, so the poll adds
negligible latency; when a login is actually in progress, check the job's
accumulating output for the device code/URL and surface it to the user right
away. Keep polling for up to **5 minutes**; once the job exits, use its
captured output instead of re-running the command. If it is still running past
that window, stop polling and tell the user the login hasn't been approved yet
rather than waiting indefinitely - do not cancel the job (approving it late
still completes the original command).

That is the whole task. Paste the CLI's output as the evidence - don't paraphrase.

## In the Claude Code Bash sandbox: allow the two hosts

`sdv` makes two network calls: `tatari.okta.com` (to refresh the token it already
holds) and the target host. The Bash sandbox's egress proxy denies both unless the
Bash call lists them in `allowed_domains`:

```
allowed_domains: ["tatari.okta.com", "marquee.internal.tatari.dev"]   # Okta + whatever host you probe
```

Without them, `sdv` fails with one of two messages, and the tool result carries a
`<sandbox_violations>` block naming the denied host:

- `could not authenticate: Okta token is missing or expired and no controlling
  terminal is available` (the Okta call was denied)
- `target unreachable: connection refused or unreachable`, exit `3` (the target
  host was denied)

**Both are the sandbox, not an expired token or a down host.** Do not run
`sdv login`; re-run the same command with `allowed_domains` set.

## Waiting for a rollout to land

One backgrounded Bash call (with the `allowed_domains` above) that prints every
probe, so a failure is visible on the first line instead of hidden behind a pipe:

```bash
for i in $(seq 1 60); do
  raw=$(sdv probe marquee.internal.tatari.dev --format json 2>&1)
  line=$(printf '%s' "$raw" | jq -er '.version.payload | "\(.version) \(.revision)"' 2>/dev/null) \
    || line="PROBE FAILED: $(printf '%s' "$raw" | head -1)"
  echo "$(date +%T) $line"
  case "$line" in "v1.21.0 "*) break ;; esac
  sleep 60
done
```

- Read the output after the first minute. A `PROBE FAILED` line means stop the
  loop and fix the call; never let a probe loop run unread.
- Done means BOTH halves match: `version` is the tag, and `revision` equals
  `git rev-parse 'vX.Y.Z^{commit}'`. Observed on marquee v1.21.0 (2026-09-27): the
  new `revision` appeared one probe before `version` flipped from the old tag, so a
  match on either half alone is not done.
- A prod promotion runs after the tag's release workflow finishes its builds, so
  expect several minutes of the old version first. `gh run list` on the repo shows
  where the release is.

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
  (interactive) or `sdv login --device` (SSH/agent) - backgrounded and polled,
  per "Always invoke `sdv` backgrounded" above - then re-run.
- `3` - host unreachable (DNS/connect failed) - check the URL/host, not auth. In
  the Claude Code sandbox, check for a `<sandbox_violations>` block first.
- `4` - host reachable but no `/status`,`/deployed`,`/version` (all `absent`) - not
  a Tatari standard-endpoint service, or wrong host.
