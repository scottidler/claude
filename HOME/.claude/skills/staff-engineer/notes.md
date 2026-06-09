# Staff Engineer (Codex) operating notes

The Staff Engineer persona runs on `codex exec -s read-only`. Unlike the
Gemini-based `/architect`, codex's read-only mode is a true sandbox (no writes)
rather than a workspace jail, so most of the Architect's failure modes do not
apply here. These notes record what codex *can* do, the few real caveats, and
how the skill is wired.

## What codex read-only can and cannot do (verified 2026-06-09)

- **Reads any file on disk**, not just `$PWD`. A live test from `/tmp/setest`
  read `~/.claude/skills/architect/persona.md` in a different tree without any
  `--include-directories`-style flag. So there is **no cross-repo jail** — the
  reviewer verifies referenced repos by absolute path directly.
- **Runs real read-only shell**: `rg`, `git log`/`git blame`/`git show`, `sed`,
  `find`, `wc`, etc., executed in a sandbox that blocks writes and network. So
  the Architect's "ripgrep not available" and "run_shell_command not found"
  failure modes **do not exist** here — codex actually executes `rg`/`git`.
- **Cannot write anything**: no file edits, no file creation, no commands that
  mutate state. This is by design and correct for a reviewer. The practical
  limit: codex cannot run tests/builds that need to write (compile artifacts,
  temp files). It audits by reading and searching, not by running the suite.
- **Network is blocked** in read-only sandbox — no fetching remote refs, no
  package installs. Everything is local-only.

## How the skill is wired

- `script.sh` runs:
  `cat <doc> | codex exec -m gpt-5.5 -c model_reasoning_effort="high" -s read-only --skip-git-repo-check --color never -o <last-msg> "<prompt>"`.
- **Persona delivery**: `persona.md` is prepended to the prompt by `script.sh`.
  It is deliberately NOT placed in any global codex config or `AGENTS.md`, so
  plain `codex` invocations stay neutral. `persona.md` is the single source of
  truth for the persona. (This mirrors the fix made to `/architect` after its
  persona was found leaking through the global `~/.gemini/GEMINI.md`.)
- **Clean output**: `-o <file>` captures only the final synthesis, which the
  script prints on success. The verbose execution trace is captured separately
  and dumped to stderr only on failure, for diagnosis.
- **Doc on stdin**: the design doc is piped in and appears to codex as a
  `<stdin>` block; prompts refer to "the design document provided on stdin".

## Real caveats (still worth knowing)

- **Model / effort are pinned** in `script.sh` (`gpt-5.5`, `model_reasoning_effort=high`).
  If codex changes its model lineup, update the `-m` value there. `high` is a
  deliberate default for review depth; `xhigh` (the user's interactive default)
  is slower and rarely changes the verdict for a review pass.
- **It can still be wrong.** Read-only shell makes "X is missing / zero
  instances" far more trustworthy than the Architect's equivalent, but it is not
  infallible — spot-check any surprising negative against HEAD before acting on
  it, same discipline as always.
- **Reasoning trace is hidden by default.** On success you see only the final
  message. If you need to see exactly which commands the reviewer ran, resume
  the session (`codex resume`) or temporarily inspect the trace the script
  writes before it is cleaned up.
- **Trust/approval**: read-only exec runs fully non-interactively (no approval
  prompts) because it cannot do damage; `--skip-git-repo-check` lets it review
  docs that live outside a git repo.
