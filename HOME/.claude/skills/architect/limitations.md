# Architect (Gemini) Limitations and Failure Modes

The Architect persona runs on the Gemini CLI. It is a useful skeptical reviewer
for *reasoning* about a design, but its ability to *verify claims against the
code* is unreliable because of sandboxing and missing tools. Treat its
file-search-based conclusions as suspect and confirm them yourself.

**Verified against gemini-cli 0.49.0 on 2026-08-04.** The ripgrep section below
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

### `run_shell_command` absent in plan mode - by design, persona aligned

- **2026-08-04 update: the real cost of this was ABSTENTION, now banned in the
  persona.** `--skip-trust` (added 2026-07-03, commit `1edfd2b`) made
  `--approval-mode plan` actually stick; before that gemini silently downgraded
  to `default` and had a shell. Once plan mode became real, Gemini started
  refusing to answer: 28 `ABSTAIN (cannot execute)` occurrences from 2026-07-13
  to 08-03, including whole verdicts reduced to *"My environment genuinely
  cannot execute shell commands in plan mode, so I must ABSTAIN."* Every one is
  dated after 2026-07-03.
- `persona.md` now carries a hard NEVER-ABSTAIN rule: the four read-only tools
  are declared the complete and sufficient toolset, a substantive verdict is
  always required, and anything needing execution gets ONE line labelled
  `REQUIRES EXECUTION: <command>` rather than collapsing the verdict.
- Note the asymmetry with the sibling seat: Codex runs `-s read-only` and CAN
  execute `rg`/`git`/`find`. Gemini cannot execute anything. That is why the
  Architect is weighted toward reasoning and the Staff Engineer toward
  code-grounded verification.
- Symptom: `Error executing tool run_shell_command: Tool "run_shell_command" not found`.
- Root cause (verified live): the skill runs Gemini with `--approval-mode plan`,
  which is `readonly: true`. Plan mode deliberately strips `run_shell_command`
  (and all write tools). This is correct - the Architect must stay read-only.
  The bug was that `persona.md` told Gemini to verify via `run_shell_command`, a
  tool that does not exist in that mode.
- Mitigation in place: `persona.md` now points only at the read-only tools that
  ARE present in plan mode - `grep_search` (ripgrep-backed after the fix above),
  `glob`, `read_file`, `list_directory` - and explicitly says not to attempt
  `run_shell_command`. Those tools are sufficient for in-workspace verification.
- Delivery note: `persona.md` is injected by `script.sh`, which **prepends it to
  the prompt**. The old `--policy persona.md` was dead code - gemini's `--policy`
  loads `*.toml` policy-engine files only and silently ignored the markdown. The
  persona used to leak in via the global `~/.gemini/GEMINI.md` (which forced it
  onto every unrelated `gemini` call and still carried the stale
  `run_shell_command` line); that global copy has been neutralized so `persona.md`
  is now the single source of truth. Note that Gemini still has no shell here -
  the skill's Step 3 runs `git log`/`git diff` on Claude's side and embeds the
  output in the prompt, so the audit never needed Gemini to shell out.

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
