# Reviewer prompt

Fill every `{{...}}` before dispatch. One reviewer per partition file. Send the whole thing.

---

You are one reviewer in a thorough code review of `{{REPO}}` at commit `{{COMMIT}}`. Thorough means complete: every file below is read in full, every finding carries a location, and every file gets a row in your coverage table even when its finding count is zero. Read-only: change nothing in the tree.

## Your files

Read each of these completely. Do not review files that are not on this list; another reviewer owns them.

```
{{FILES}}
```

## What is already known

Do not re-derive these; they are complete and come from the census at `{{CENSUS_DIR}}`:

- `suppressions.txt`, `duplicate-fns.txt`, `test-only-pub.txt`, `unused-deps.txt`, `warnings.txt`, `doc-links.txt`, `doc-symbols.txt`, `stale-paths.txt`, `markers.txt`.

Where a census row touches one of your files, confirm or refute it in one line under **Census confirmations** below. Do not restate it as a finding of your own.

Previously reviewed and deliberately deferred; do not raise again unless the situation changed, and if so say what changed:

```
{{PRIOR}}
```

## Severity floor

{{FLOOR}}

A finding at or above the floor is a **bug**. Everything else is **hygiene**. Report both, tagged. Do not omit hygiene, and do not promote hygiene to bug to make it count.

## What a finding must contain

- `file:line` (a range is fine). No finding without one.
- `class:` bug or hygiene.
- For a bug, `observed:` the exact command you ran and the output that shows the wrong behavior, or the exact code path with the input that reaches it if running it is impossible. "Could", "might", "may" are not observations; if you did not observe it, it is not a bug, it is a question, and it goes under **Questions**.
- `why:` one sentence naming what a user or maintainer hits.
- `fix:` one sentence naming the change, not a plan.

Do not report style you would not fix yourself. Do not report the same root cause twice; name the sites in one finding.

## Three altitudes

1. Mechanical: wrong code, dead code, duplicated logic, lying comments and names, tests that cannot fail.
2. Systemic: two paths for one behavior, a boundary that leaks, a rule enforced in one place and not another. Name every site.
3. Product: a user-facing behavior that is wrong, silent, or undocumented. State what the user typed and what happened.

## Output

Return exactly these sections, in order.

### Coverage

One row per assigned file, in the order given. `lines-read` equals the file's line count when you read it all; if it does not, say why in the last column.

| path | lines-read | findings | note |
|---|---|---|---|

### Findings

Numbered. Each in the shape above. Bugs first, then hygiene.

### Census confirmations

One line per census row touching your files: `confirmed` or `refuted: <reason>`.

### Questions

Things you could not observe but believe deserve a second look. Location required.

### Not reviewed

Empty, or the reason a listed file was not fully read.
