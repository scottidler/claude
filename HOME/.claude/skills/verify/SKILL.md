---
name: verify
description: >-
  Verify that a code change actually does what it's supposed to by running the app
  and observing real behavior. Use when asked to verify a PR/fix/change works,
  confirm a deploy, check what version is live, or validate behavior before
  pushing. FOR ANY TATARI HOSTED SITE (a *.tatari.dev / *.tatari.tv URL), this is
  one command - the `verify` CLI - do NOT cold-start, do NOT reach for
  aws-vault/kubectl/port-forward, do NOT build a verifier skill.
---

# verify

## FIRST: is the target a Tatari hosted site? Run the `verify` CLI.

If you're verifying anything served at a Tatari URL (`*.tatari.dev`, `*.tatari.tv`
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

That is the whole task for a Tatari site. Capture the CLI's output as the evidence
and report it. Everything below is for changes that are NOT a Tatari hosted site.

## Otherwise: observe the running app at its surface

Verification is runtime observation - build the app, run it, drive it to where the
changed code executes, capture what you see. That capture is the evidence. Do NOT
run tests or typecheck as a substitute - that proves CI works, not that the change
does.

1. **Find the change** - establish the diff scope (`git diff @{u}..`,
   `git diff HEAD`, `gh pr diff`). State the commit count. The diff is ground
   truth; any description is a claim about it.
2. **Find the surface** - where a user meets the change: CLI -> the terminal;
   server/API -> the socket (send the request); GUI -> the pixels (drive it,
   screenshot); library -> the public export; CI workflow -> dispatch it, read the
   run. An internal function is not a surface - follow it to the CLI/request/render
   that reaches it. No runtime surface (docs/types/tests-only) -> report SKIP.
3. **Get a handle** - check `.claude/skills/` for a repo `verifier-*`/`run-*`
   skill first; else cold-start from README/Makefile, timeboxed (~15min).
4. **Drive it** - the smallest path that makes the changed code execute (the flag,
   the route, the error trigger).
5. **Push on it** - one probe off the happy path (empty/dup/conflicting input,
   wrong method, malformed body, Ctrl-C, stale state). At least one.
6. **Capture & report** - raw output is evidence; paste it, don't paraphrase.

### Report

```
## Verification: <one-line what changed>
**Verdict:** PASS | FAIL | BLOCKED | SKIP
**Claim:** <your read of the diff / stated claim; note mismatch>
**Method:** <CLI run, or how you got a handle>
### Steps
1. ✅/❌/⚠️/🔍 <what you did to the running app> -> <what you observed> + evidence
### Findings
<surprises, friction, claim/diff mismatch; lead ⚠️ for must-know>
```

- **PASS** - you ran it and it does what it should at its surface.
- **FAIL** - you ran it and it doesn't, or it breaks something else.
- **BLOCKED** - couldn't reach an observable state (say exactly where it stopped).
- **SKIP** - no runtime surface. One line why.

When in doubt, FAIL with the raw capture attached - a false PASS ships broken code.
