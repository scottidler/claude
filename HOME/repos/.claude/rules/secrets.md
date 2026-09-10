---
alwaysApply: true
---

# Secrets and multi-persona credentials

Scott's secrets are age-encrypted, one value per file, in
`~/repos/scottidler/keep/.secrets/*.age`. Decrypt on demand. NEVER print,
echo, log, or commit a decrypted value, and never write one into a rule, doc,
config, memory file, or commit message. Companion repo docs:
`~/repos/scottidler/keep/CLAUDE.md`.

## The scheme

- One secret per `.age` file (age x25519). Filename `my-secret-name.age` maps to
  the env var `$MY_SECRET_NAME` (lowercase-kebab becomes UPPER_SNAKE).
- Identity key: `~/.config/manifest/identity.txt` (an age key, NOT an SSH key).
  Lose it and every secret is unrecoverable.
- Decrypt with the `manifest` CLI, never hand-rolled `age`:
  - one secret: `manifest age decrypt ~/repos/scottidler/keep/.secrets/<name>.age`
  - all: `manifest age decrypt ~/repos/scottidler/keep/.secrets`
  - Output is `export NAME='value'` lines; `eval "$(...)"` to load, or capture
    only the single value you need.
- An interactive shell already `eval`s the full decrypt at startup (via dotfiles),
  so most secrets are present as env vars there. A spawned / agent / cron session
  may NOT have them, and may have the WRONG ones (see GitHub below). When a call
  fails on a missing or wrong token, decrypt the specific secret explicitly.
- List available secret names:
  `ls ~/repos/scottidler/keep/.secrets/*.age | sed 's:.*/::;s:\.age$::'`

## GitHub: pick the token by repo org (the recurring trap)

`gh-token.age` and `github-token.age` are symlinks to `github-pat-work.age`, so
the ambient `$GH_TOKEN` / `$GITHUB_TOKEN` resolve to the WORK account
(`escote-tatari`). Those two env vars OVERRIDE gh's own per-account switching, so
a raw `gh` command acts as work even on a personal repo, and `gh pr create` on a
`scottidler/*` repo fails with "must be a collaborator".

Choose the token from the repo's org under `~/repos/<org>/`:

- `~/repos/scottidler/*` (home persona) uses `github-pat-home` (login `scottidler`)
- `~/repos/tatari-tv/*` (work persona) uses `github-pat-work` (login `escote-tatari`, the ambient default)

Run gh as the home persona on a `scottidler/*` repo:

```bash
eval "$(manifest age decrypt ~/repos/scottidler/keep/.secrets/github-pat-home.age)"
GH_TOKEN="$GITHUB_PAT_HOME" GITHUB_TOKEN= gh <args>   # clear the work token so home wins
unset GITHUB_PAT_HOME
```

Confirm identity without leaking the token: append `api user --jq .login` (prints
just `scottidler` or `escote-tatari`). `github-pat-service` is a third,
service-account PAT; use it only when a task explicitly calls for the bot identity.

`git push` / pull already use the correct per-org SSH key (`clone` resolves it via
`GIT_SSH_COMMAND`), so pushes carry the right identity regardless of the gh token.
Only the gh API surface (PRs, issues, comments, API calls) needs the token
override above.

### The live mechanism: the `gh()` function keyed on `$PWD` (plus `GH_PERSONA`)

`.zshenv` wraps `gh` in a function that picks the persona automatically:
`~/repos/tatari-tv/*` -> work, everything else -> home. This is per-invocation
(an env-var swap, not `gh auth switch`), so it is safe under the many parallel
shells / cron / agent sessions Scott runs: no shared mutable state that one
context can flip out from under another. Do NOT replace it with
`gh auth login` / `gh auth switch` without solving that concurrency problem.

The explicit override is `GH_PERSONA`, a plain `work`/`home` toggle that beats
the `$PWD` guess for a single call:

```bash
GH_PERSONA=work gh api repos/tatari-tv/marquee   # force work, regardless of $PWD
GH_PERSONA=home gh api user                      # force home
gh-work api repos/tatari-tv/marquee              # terse wrappers, same effect
gh-home api user
```

`GH_PERSONA` is deliberately not a token/secret-shaped name, so it reads clearly
in transcripts and does not trip `secret-echo-guard.sh`.

### Troubleshooting: a gh call 404s or authenticates as the wrong account

The `$PWD` heuristic answers "which dir am I in," but the real question is "which
org does this call target." They diverge whenever a call hits a `tatari-tv`
resource from OUTSIDE `~/repos/tatari-tv/*` (a notes folder, a scratch dir,
anywhere) -- the function takes the home branch, forces the home token, and a
private work repo comes back `404 Not Found`, which looks exactly like "no
access" rather than "wrong identity."

When a `gh` call inexplicably 404s or acts as the wrong account, FIRST suspect
this PWD miss and prepend `GH_PERSONA=work` (or `GH_PERSONA=home`). Confirm with
`gh api user --jq .login`. Do NOT start guessing at raw tokens or cycling auth
methods -- rapid-fire auth attempts trip Claude Code's auto-mode credential
classifier. One hypothesis, one deliberate test.

### The rails plugin now does this for you (do not hand-roll it)

`~/.claude/skills/rails` is a function-hooks plugin (`rails@skills-dir`). Its
`tool.call` hook injects `GH_PERSONA=work|home` into every `gh` invocation the
Bash tool runs, so a session never has to remember the persona:

- cwd under `/repos/tatari-tv` -> `work`; anywhere else -> `home`.
- An org named in the gh arguments BEATS the cwd, which is exactly the PWD miss
  above: `gh api repos/tatari-tv/philo` from `/tmp` gets `work`.
- A command that names both orgs, or that already sets `GH_PERSONA`, `GH_TOKEN`
  or `GITHUB_TOKEN`, is left alone.
- The transcript shows the prefixed command, and the model gets one context line
  saying which persona was injected and why.

So do NOT wrap `gh` in a manual `eval "$(... decrypt ...)"` + `GH_TOKEN=` dance,
and do not prepend `GH_PERSONA=` yourself: the hook has it. Setting it by hand
still wins (the hook stands down), which is the escape hatch.

Off switch: `claude plugin disable rails@skills-dir`, or
`pluginConfigs.rails.options.gh_persona: false` in settings.json.
Verbose decisions: same options block, `debug: true`.
