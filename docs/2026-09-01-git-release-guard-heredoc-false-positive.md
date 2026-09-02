# Handoff: git-release-guard denies `git commit` when a heredoc line starts with "bump"

**Date:** 2026-09-01
**Status:** Fixed 2026-09-01 (`strip_heredocs()`, `git-release-guard.sh:318`)
**File:** `HOME/.claude/hooks/git-release-guard.sh`
**Deployed as:** `~/.claude/hooks/git-release-guard.sh`, wired at `HOME/.claude/settings.json:835`

## What happened

A plain `git add <file> && git commit -q -F - <<'MSG' ... MSG` was denied with:

```
bump stages everything (git add -A) and the target worktree
'/home/saidler/repos/otto-rs/otto' is dirty -- it would sweep
untracked/modified files into the version commit ...
```

No `bump` was invoked. The tree held exactly one modified tracked file and zero
untracked files, so the dirty premise was also false. Re-running with the same
message in a file (`-F $TMPDIR/msg.txt`) succeeded immediately.

## Root cause

`git-release-guard.sh:309-312`:

```sh
split=$(printf '%s' "$cmd" | sed -E 's/&&/\n/g; s/\|\|/\n/g; s/;/\n/g; s/\|/\n/g')
while IFS= read -r stmt; do
  check_stmt "$stmt"
```

The `sed` ADDS newlines for `&& || ; |`. It does not remove the newlines already
in `$cmd`, and `read` splits on those too. So every physical line of a heredoc
body is handed to `check_stmt` as if it were a statement.

The offending commit message wrapped like this:

```
  ... Adding an optional field does NOT
  bump it." Every key here is additive, so the generation would have gated
```

Line 2 is whitespace, then `bump`, then a space. That matches the
command-position anchor at `:204`:

```sh
'^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*([^[:space:]]*/)?bump([[:space:]]|$)'
```

The escape hatch at `:205` (`--gates|--dry-run|--help|--version|-n|-h|-V`) does
not apply to prose, so it falls through to the dirty-tree gate at `:225` and
denies.

## Why the existing comment did not prevent it

`:198-203` documents fixing this exact class once already:

> Match `bump` ONLY in command position -- the first token of the statement
> ... This is the fix for the substring false-positive that blocked unrelated
> commands merely *mentioning* bump ... A statement is already split on
> `&& || ; |`, so the command word is unambiguous here.

The anchoring is correct. The assumption underneath it is not: a heredoc body
line is not a statement, and the splitter never claimed to handle heredocs.

## Why it will keep recurring

It fires precisely when writing a commit message ABOUT releasing, which is when
the word is most likely to land at the start of a wrapped line. Anything that
reflows prose (an editor, a formatter, a different terminal width) changes
whether a given message trips it, so it looks intermittent.

## Fix shape

Strip heredoc bodies before splitting, then leave everything downstream alone:
the command-position anchor is right once "statement" means what it claims.

1. Scan `$cmd` for `<<-?['"]?WORD['"]?`.
2. Drop lines from that point through the matching terminator line (`WORD`, or
   optionally-indented `WORD` for `<<-`).
3. Split and check what remains.

Handle multiple heredocs in one command, and the `-F -` case specifically since
that is the shape that hit this.

## Test case to add

`HOME/.claude/hooks/git-release-guard-test.sh` already exists. Add: a
`git commit -F -` whose heredoc body contains a line beginning with `bump`
must PASS. Break-the-code check: with the heredoc stripping removed, that case
must fail, or the test is not pinning anything.

Also worth a case for the inverse, so the fix does not open a hole: a real
`bump` on a line AFTER a heredoc terminator must still be caught.

## What triggered this

Committing design-doc work in `otto-rs/otto` on 2026-09-01. The commit that had
to be retried is `b428680`. Nothing was lost; the workaround (`-F <file>`) is
reliable and does not route around any gate, since the guard's other checks all
still ran on the real command.

## Fix as landed

`strip_heredocs()` (`git-release-guard.sh:318-355`) runs `$cmd` through awk
before the statement split at `:357`. It queues every `<<`/`<<-` opener on a
line (multiple per line, in order), drops body lines through the matching
terminator (leading whitespace allowed only for `<<-`), and keeps the opener
line itself, which is a real command. `<<<` herestrings are neutralized before
the scan so they are not mistaken for openers.

`$cmd` is NOT modified: Gate D reads the `Release:` line out of the full
command, and PR bodies routinely arrive by heredoc.

Tests in `git-release-guard-test.sh` ("heredoc bodies are not statements"):
`git commit -F -` with a body line starting with `bump` PASSES, a real `bump -m`
after the terminator is still DENIED, and a `gh pr create` whose `Release:` line
lives inside a heredoc still PASSES Gate D. Break-the-code verified: with
`strip_heredocs` removed from the pipeline the first case fails (`pass=45 fail=1`);
with it, `pass=46 fail=0`.
