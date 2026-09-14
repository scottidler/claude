# Implementation notes: guard-precision (chunk B)

Append-only record of how the implementation interprets or departs from
`2026-09-13-guard-precision.md`. One section per phase, four buckets each.

## Phase 0: prove the harness assumptions

### Design decisions
- The nested-session method is chunk A's, reused unchanged: scratch hooks behind `--settings` on `claude -p --model sonnet`, every hook appending its payload to its own log. Evidence: `2026-09-13-guard-precision-phase0/evidence.md`.
- 0a needed an interactive session because `SessionStart` never fires under `-p`. It was driven under a detached tmux server (`tmux -L p0a`), sandbox off, because tmux talks over a unix socket the sandbox denies. The transcript of that session (`a4faad78`) is the primary record.
- 0f was extended from the two orderings the doc asked for to seven runs, because two runs could not separate registration order from a completion race. The sleep variants are what settled it.

### Deviations
- The doc's plan changes are recorded INLINE in the design doc under `Phase 0 outcome` markers (Status line, problem 1, Overview, Architecture, Data Model masker table, API Design, Phase 5, Phase 6 rewritten, Phase 7, AC1, AC5, decision 9, Rollout Plan) rather than in a separate addendum, so a phase implementer reading its own section sees the current plan without cross-referencing.
- Phase 6 is rewritten wholesale: the `git -C` strip folds into `rewrite-cd-read.py` and `git-no-dash-c.sh` is deleted. This is the fallback the doc's Rollout Plan pre-committed to for a failed 0e, so it is a deviation the doc authorized in advance, not a new decision.

### Tradeoffs
- `additionalContext` over plain stdout for Phase 7, when 0a showed both reach the model. The documented field, and its rendering names itself as context rather than as a hook's stdout.
- AC5's observable became the hook's own log line rather than anything model-visible, because 0b proved a shell hook has no channel to tell the model a rewrite happened. The alternative was to keep a deny (visible, but the round trip the chunk exists to remove).

### Open questions
- None. 0a's finding that `ssh-agent-check.sh`'s WARN would have been heard changes nothing this chunk builds; it corrects the doc's stated cause for the zero-WARN audit finding.

## Phase 1: `hooks/lib.sh` and its tests

### Design decisions
- One awk program dispatched by a `mode` variable, not ten. Every function needs the same quote/heredoc scan, and keeping mask, match and slice in one process is the whole point of the Data Model's offset rule. `_lib_run` pins `LC_ALL=C` on every call.
- The single primitive is a per-byte class map (`scan()` in `lib.sh`): `.` plain, `q` a quote character, `S` single-quoted, `c` single-quoted AND a `-c` argument, `D` double-quoted, `E` a backslash-escaped `$`, `H` heredoc body or terminator, `#` comment, `P` command substitution body. Each masker is a set of classes over that map, so "which spans may be erased" is one table instead of five regex passes.
- A newline is NEVER masked by any masker, whatever its class. Line structure is load-bearing for line-oriented callers and a newline carries nothing matchable. A heredoc body's newlines still get class `H`, which is what keeps them from being statement separators; the newline ending the LAST terminator is plain, so the command on the next line stays a statement of its own.
- `stmts` neutralizes class `H` bytes in the pieces it emits and drops a piece that is all mask, so a heredoc body fragment can never be handed to a gate even when a caller splits before it masks. Without that, `cat <<EOF ... EOF` yields the body as a statement whenever the caller's order is stmts-then-mask.
- Nested statements are emitted breadth first: every top-level statement, then the bodies they yielded. Depth first would make a statement's index depend on how deeply an earlier sibling nested.
- A `-c` argument is yielded as a nested statement only when the statement's command word resolves to `bash`, `sh` or `zsh` (path and env-assignment prefixes allowed), so `git commit -c HEAD~1` is left alone.
- `--self-test` is gated on `BASH_SOURCE[0] = $0`, because a guard sourcing `lib.sh` inherits the guard's own `$1`, and `git-release-guard.sh --self-test` would otherwise exec the library's matrix instead of its own.
- The test matrix renders `\x01` as `@` and builds every expected mask with `mk()`, one `@` per byte of the span that must disappear, so no expectation is a hand-counted run and no fixture may contain a literal `@`.

### Deviations
- `cd_target` requires the `cd` to be in command position of its statement; `git-release-guard.sh:108-113` matched `cd <dir>` anywhere in the text. Identical for the `cd <worktree> && bump` shape the gates care about, stricter for prose that happens to contain the word. Same effect, correct seam.
- `flag_value` drops every quote character inside the value token rather than only a matched surrounding pair, which is the shell's own concatenation semantics (`--title 'a'"b"` yields `ab`).
- `mask_optarg` covers exactly the flag list in the Data Model, so a combined short form (`git commit -am "msg"`) is not masked. Stated rather than silently widened: widening it is Phase 4's call if a fixture needs it.
- The library is bash, not POSIX sh (`read -r -d ''` for the awk program, `BASH_SOURCE`). The Data Model already commits `manifest-scope-guard.sh` to bash in Phase 2 for the same reason.

### Tradeoffs
- awk over `python3`, per the Data Model. The cost is one awk process per function call, so a gate applying four maskers pays four. Rejected the alternative of one composite call returning every mask at once, because the per-gate masker sets differ and a combined call would hand each gate masks it must not use.
- `mask_dquote` leaves a `$( )` inside double quotes intact, so `echo "$(manifest -l x)"` still shows the inner command to a bare-word gate that masks but does not split. That is the "a masker may only erase a span the shell will never execute" rule winning over quieter output; `stmts` is what removes the span from the outer statement.
- Byte-length preservation is asserted per masker per case (every mask case carries a second `[byte length preserved]` assertion) rather than once in a dedicated case. It doubles the case count and catches a length regression on the exact fixture that produced it.

### Open questions
- `cd_at <n>` indexes the SAME sequence `stmts` emits, nested statements included. Phase 4's destructive-op gate must therefore number statements straight off `stmts` output; if it filters or reorders them first, the index it passes to `cd_at` no longer means what it means here. Flagging it for the phase that wires the gate, not as a change to the library.
