# Architect (Gemini) Limitations and Failure Modes

The Architect persona runs on the Gemini CLI. It is a useful skeptical reviewer
for *reasoning* about a design, but its ability to *verify claims against the
code* is unreliable because of sandboxing and missing tools. Treat its
file-search-based conclusions as suspect and confirm them yourself.

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
