# Architect (Gemini) Limitations and Failure Modes

The Architect persona runs on the Gemini CLI. It is a useful skeptical reviewer
for *reasoning* about a design, but its ability to *verify claims against the
code* was historically unreliable because of sandboxing and missing tools. As of
2026-08-30 it has a read-only shell (see "The static seat" below), so counted and
history-based claims are now checkable. Anything it did NOT back with pasted
command output is still an inference - confirm it yourself.

**Verified against gemini-cli 0.49.0 on 2026-08-04; shell policy re-verified
2026-08-30.** The ripgrep section below
was root-caused against 0.45.2; re-verify it if the symptom returns.

## Measured failure rates (2026-07-13 .. 2026-08-03)

149 review-panel dispatches across 60 sessions, mined from the session
transcripts. This is what "the panel is flaky" actually was:

| Outcome | n | % |
|---|---|---|
| OK on the first attempt | 84 | 56% |
| **Scratch dir read-only under the Bash sandbox** (82-byte output) | 55 | **37%** |
| Gemini `Invalid stream` backend abort (full trace dumped) | 9 | 6% |
| Killed by a caller `timeout` that tied the script's own cap | 1 | 1% |

All four causes are now fixed structurally. The three worth knowing:

### 1. Scratch dir read-only (was 37% of all dispatches) -- FIXED 2026-08-04

- Symptom: both seats die in ~3 seconds. `architect rc=1 (82 bytes); staff rc=1 (86 bytes)`.
  The output is exactly `mktemp: Read-only file system (os error 30) at path "/tmp/architect-trace.XXXXXX"`.
- Root cause: the scripts hardcoded bare `/tmp` for their pidfile and trace
  files. The Claude Code Bash sandbox mounts `/tmp` READ-ONLY; only `$TMPDIR`
  and the paths in `settings.json` `sandbox.filesystem.allowWrite` are writable.
  Commit `3405d3d` (2026-07-02) allowlisted `/tmp/review-panel` for the panel's
  own run dir but not the scripts' scratch one directory up.
- Why it read as random: when the panel subagent happened to run with the
  sandbox off (or retried with `dangerouslyDisableSandbox`), it worked. Same
  doc, same command, different outcome.
- Mitigation in place: both scripts use `${TMPDIR:-/tmp}`, preflight that it is
  writable, and exit **3** with an actionable message instead of a cryptic
  mktemp error. `settings.json` also allowlists `~/.codex` and `~/.gemini`
  (both CLIs write their own state there and hit the same read-only mount) and
  exempts the two scripts via `sandbox.excludedCommands`.

### 2. `Invalid stream` backend abort -- MITIGATED 2026-08-04

- Symptom: `error: gemini failed (status 0, result=error) or produced no final message.`
  The terminal trace event is always:
  `{"type":"error","message":"Invalid stream: The model returned an empty response or malformed tool call."}`
- Note gemini exits **status 0** while its own result event says `error`, so the
  exit code alone cannot be trusted.
- It is non-deterministic in depth: observed dying after 1 tool call (11s) and
  after **1,093 tool calls / 1M input tokens (468s)** on the same model. The
  runaway-tool-call shape is worth watching on its own.
- Every observed instance succeeded on a plain retry, so `script.sh` now retries
  once automatically (`ARCHITECT_MAX_ATTEMPTS`, default 2). Credits/quota/auth
  are deliberately excluded so the panel's Step 3.5 substitute-model fallback
  still fires immediately.
- The failure path used to `cat` the whole trace to stderr, which hit 539 KB and
  blew out the calling agent's context. It now preserves the trace to disk,
  prints the path, and echoes only the last 4 KB.

### 3. Caller timeout tie -- FIXED 2026-08-04

- Symptom: a 110-byte output containing only the liveness banner, `rc=124`, a
  stale pidfile, and no diagnostic whatsoever.
- Root cause: `review-panel.md` wrapped the script in `timeout 600` while the
  script's own `WALL_CLOCK` was also `10m` == 600s. The outer kill won the race,
  so the EXIT trap and the diagnostic block never ran.
- Mitigation: the panel no longer wraps the scripts in `timeout` at all. The
  script owns the cap; the Bash tool's own `timeout` parameter is the backstop.

## Sandbox jail (cannot read outside the workspace)

- Gemini restricts file access to `$PWD` (the current repo) plus its own temp
  dir. It refuses any path outside, e.g.
  `Path not in workspace: Attempted path "/home/saidler/repos/scottidler/obsidian/..." resolves outside the allowed workspace directories`.
- Consequence: anything in another repo (the Obsidian vault, a reference repo,
  a sibling service) is invisible. Gemini reports it as "unverifiable" or, worse,
  as a "gap" / "missing" - when it simply could not look.
- Mitigation: the skill passes `--include-directories` for the doc root and any
  `--dirs` / reference repos. If a finding is "unverifiable because outside
  workspace," that is a sandbox artifact, not a real gap - re-run with the path
  added to `--include-directories`, or verify it yourself.

## Ripgrep fallback (FIXED 2026-06-09) and the absent shell

### Ripgrep "not available" - root-caused and mitigated

- Symptom: Gemini logged `Ripgrep is not available. Falling back to GrepTool.`
  and used the weaker bundled JS grep instead of ripgrep.
- Root cause (gemini-cli 0.45.2 `resolveRipgrepPath`): there is no bundled
  `rg-linux-x64`, so Gemini falls back to the first `rg` on `$PATH`, resolves it
  to its **realpath**, then rejects it unless that realpath sits under a
  hardcoded trusted prefix (`/usr/bin`, `/bin`, `/usr/local/bin`, `/usr/sbin`,
  `/sbin`, homebrew). `~/.cargo/bin/rg` is not trusted -> returns null ->
  GrepTool fallback. A naive symlink at a trusted path does **not** help: the
  realpath check follows the symlink back to the untrusted cargo path.
- Mitigation in place: the real binary was moved to a trusted prefix and the
  cargo path symlinked to it -
  `sudo mv ~/.cargo/bin/rg /usr/local/bin/rg && ln -s /usr/local/bin/rg ~/.cargo/bin/rg`.
  Now `realpath $(which rg)` -> `/usr/local/bin/rg` (trusted), so Gemini
  registers RipGrepTool and the fallback warning is gone (verified with a live
  plan-mode run).
- Fragility: a future `cargo install ripgrep` rewrites a real file at
  `~/.cargo/bin/rg` and silently reverts this. If the "Ripgrep is not available"
  warning returns, re-apply the move+symlink above.

### The static seat - FIXED 2026-08-30 (the seat now has a read-only shell)

**This section previously said plan mode STRIPS `run_shell_command` and that the
seat is static by design. Both were wrong as of gemini-cli 0.49.0.** The
correction and the fix:

- What was actually happening: the tool is REGISTERED in plan mode and DENIED by
  two default-tier rules shipped in the CLI -
  `bundle/policies/plan.toml` (`toolName = "*"`, deny, priority 40, `modes = ["plan"]`)
  and `bundle/policies/write.toml` (`run_shell_command`, deny, priority 10,
  `interactive = false`). The old `Tool "run_shell_command" not found` symptom
  was a 0.45.2-era registry strip; on 0.49.0 the message is
  `Tool execution denied by policy`.
- Policy priority is tiered - default `1.x` < extension `2.x` < workspace `3.x`
  < user `4.x` < admin `5.x`, with each file's own `priority` as the fraction.
  Those two denies land at `1.040` and `1.010`. A file passed via `--policy`
  loads in the USER tier, so `priority = 100` in it resolves to `4.100`.
- Fix in place: `policy.toml` in this directory, wired into `script.sh` as
  `--policy "$SCRIPT_DIR/policy.toml"`. It allows `run_shell_command` for a
  fixed list of read-only command prefixes (`rg`, `wc`, `jq`, `git log`,
  `git diff`, ...) and nothing else.
- Read-only is still enforced, verified live 2026-08-30 on 0.49.0:
  - `git rev-parse --short HEAD` -> `f9cb0e2`, matching the same command run
    outside gemini. Pipelines work: `rg -c gemini script.sh | head -1` -> `21`,
    also matching an independent run.
  - `curl https://example.com` -> denied. Anything the policy does not name
    still hits plan mode's catch-all.
  - `rg --version && curl ...` -> denied. The engine extracts every root command
    from a pipeline and checks each, so an allowlisted prefix cannot carry a
    denied command in behind `&&` or `|`.
  - `write_file` -> reported absent from the tool schema, and the target file
    was never created. Plan mode omits write tools entirely; `policy.toml` also
    denies them as a backstop.
- Why it mattered: with no shell, every "verified" claim was an inference from
  source dressed as an observation. That produced fabricated counts ("exactly 7
  ENV_LOCK declarations" - actual 5; "43 tests in `tests.rs`" - actual 31) and
  28 `ABSTAIN (cannot execute)` verdicts between 2026-07-13 and 08-03, including
  whole reviews reduced to *"My environment genuinely cannot execute shell
  commands in plan mode, so I must ABSTAIN."*
- `persona.md` now requires pasted command output for every counted or
  behavioral claim, and requires the seat to distinguish what it RAN from what
  it READ. The NEVER-ABSTAIN rule stays, and `REQUIRES EXECUTION: <command>` is
  now reserved for the narrow things the allowlist genuinely cannot settle
  (test suite, builds, benchmarks, live services).
- Deliberately still out of reach: `cargo` and `otto`. Running builds in the
  repo under review mutates `target/`, contends on the cargo file lock, and can
  burn the 10m wall clock. Test execution stays with the Codex seat, which runs
  `-s read-only` in a real sandbox.
- Residual asymmetry with the sibling seat: Codex's sandbox permits arbitrary
  read-only execution; the Architect's is a fixed allowlist. The Architect is
  still weighted toward reasoning, but its counts and history claims are now
  checkable rather than asserted.
- Delivery note: `persona.md` is injected by `script.sh`, which **prepends it to
  the prompt**. The old `--policy persona.md` was dead code - gemini's `--policy`
  loads `*.toml` policy-engine files only and silently ignored the markdown. The
  persona used to leak in via the global `~/.gemini/GEMINI.md` (which forced it
  onto every unrelated `gemini` call and still carried the stale
  `run_shell_command` line); that global copy has been neutralized so `persona.md`
  is now the single source of truth. Note that `--policy` is no longer dead
  code: it loads `policy.toml` in this directory, which is what gives the seat
  its read-only shell. The skill's Step 3 still runs `git log`/`git diff` on
  Claude's side and embeds the output in the prompt; that is now belt-and-braces
  rather than the only path.

## Concrete example (2026-06-09 codebase-review-remediation audit)

- Gemini's headline finding: *"Phase 4 Browser Extension Wiring: MISSING ... a
  codebase scan of `borg/clients/extension/**/*.js` confirms zero instances of
  token or Authorization handling."*
- Reality: the wiring was implemented and committed (`options.html` input,
  `options.js` load/save of `authToken`, `popup.js` `Authorization: Bearer`
  header). The diff stat showed the line changes.
- Root cause: that same run logged "Ripgrep is not available" and repeated
  `run_shell_command not found` - its extension scan never actually ran. The
  "zero instances" was an empty result from a tool that failed, not from the code.
- Status: both underlying failures are now mitigated (see above), but the
  lesson stands - an empty search result is not proof of absence. Keep verifying
  negatives (see below), especially for anything outside the workspace, which
  ripgrep still cannot reach.

## How to use the Architect despite this

- **Weight its reasoning, not its file-search claims.** Architectural risks,
  unverified assumptions, "what's your hardest question" - valuable. "X is
  missing / zero instances / unverifiable" - verify before believing.
- **Verify every negative finding** with your own `rg`/`git show`/Read against
  HEAD before acting on it. A "MISSING" from Gemini is a hypothesis, not a fact.
- **Add external repos explicitly** via the skill's `--dirs` so cross-repo
  claims are not phantom gaps.
- Do not let a confidently-worded Gemini false negative drive a real change.
- **2026-08-30 update, now that the seat has a shell.** The line to hold is
  sourced vs. unsourced, not reasoning vs. file search. A claim carrying pasted
  command output can be spot-checked. A claim without one is a hypothesis
  however confidently worded, and should be re-run before it reaches a
  synthesis. `REQUIRES EXECUTION:` should now appear only for test runs, builds,
  benchmarks, and live services; if it shows up for a count or a git-history
  question, the seat skipped the tools it has.
