---
name: run-via
description: >-
  Run a literal shell command or script file through codex's or gemini's own
  CLI execution environment and return the result, instead of running it in
  Claude's own Bash tool. Use when the user says "run this via codex", "have
  gemini run this script", "execute this in codex", "run this command with
  codex/gemini", or wants a second, independent runtime to execute a command
  and confirm its real behavior. This is distinct from the codex/gemini
  skills that ask those CLIs a question or hand them an open-ended task —
  this skill exists purely to execute one specific command or script and
  hand back its stdout, stderr, and exit code. DO NOT TRIGGER for "ask codex
  to review this" or "what does gemini think" (that's an opinion/analysis
  request, not an execution request) or for plain command execution that
  doesn't name codex or gemini.
---

# run-via

Delegate running one specific command or script to codex or gemini, and get back
what actually happened — not an opinion about the code, an execution result.

## Why this is a different tool than the codex/gemini skills

The `codex` and `gemini` skills exist to ask those CLIs a question or hand them an
open-ended task ("review this file", "refactor this function"). This skill is
narrower: the user already knows exactly what command or script they want run —
they just want another agent's CLI to be the one that executes it, instead of
Claude's own Bash tool. Reach for it when the user specifically wants a second
runtime to run something and report back what happened.

## The two backends behave differently — pick deliberately

**codex is deterministic.** `codex sandbox -- <command>` runs the literal command
directly inside codex's own Linux sandbox — no LLM reasoning in the loop at all.
The exit code, stdout, and stderr you get back are exactly what the command
produced. Use codex whenever the user wants a real, trustworthy exit code.

**gemini is agentic.** There is no non-agentic "just run this" mode in the gemini
CLI — every invocation goes through the model, which decides how to invoke the
shell tool. The script handles this by giving gemini a strict verbatim-execution
instruction and running with `--approval-mode yolo` so it doesn't stall on a
confirmation prompt, but the "exit code" gemini reports back is the model's own
transcription of what it saw, not a value the shell process itself returns to you.
Use gemini when the user explicitly asks for it, or wants a second, differently-
sandboxed environment to compare against codex — not when exact exit-code fidelity
matters.

If the user hasn't named a backend and exit-code fidelity matters, prefer codex.

## Running it

```bash
scripts/run-via.sh --backend codex -- pytest -q
scripts/run-via.sh --backend gemini -- pytest -q
scripts/run-via.sh --backend codex --script ./build.sh
```

Full flag reference: `scripts/run-via.sh --help`.

## codex sandbox levels — ask before escalating

`codex sandbox` defaults to **read-only, no network, no writes anywhere** (verified:
even writing to `/tmp` fails). That's the safe default — use it for anything that
only reads or inspects (tests that don't need to write, linters, `--version`
checks, diagnostics).

If the command needs to write files, add `--write` (`sandbox_mode=workspace-write`
— writes allowed under the cwd, network still blocked). If it needs network too,
that requires `--danger-full-access`, which removes sandboxing entirely — **always
confirm with the user before passing this flag**; don't infer that a command needs
full access just because it failed under a lighter mode without checking first
whether `--write` alone would have been enough.

## Scripts vs inline commands

`--script <path>` runs a script file (executed directly if it's executable,
otherwise via `bash <path>`); anything after `--` runs as a literal command with
its own arguments. Don't mix the two in one call — pick whichever matches what the
user handed you.

## Reading back the result

For codex, the script's own exit code IS the command's real exit code (`exec`'d
straight through) — just report it.

For gemini, read the labeled `stdout:` / `stderr:` / `exit code:` sections the
prompt asks it to print, and tell the user plainly that this is gemini's report of
what happened, not a shell-guaranteed exit code, if precision matters to what
they're doing next.
