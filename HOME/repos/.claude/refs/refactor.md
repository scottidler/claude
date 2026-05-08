# Mechanical Refactors

`replace` is a zsh shell function defined in the user's dotfiles. It does bulk search-and-replace across a directory tree. Prefer it over per-file Edit calls when the same literal change needs to land in many files.

## Signature

```
replace FIND [REPL] [DIR]
```

- `FIND` - sed pattern to match. Basic regex (BRE), so `.` matches any single char, `*` is zero-or-more. Escape literal `.` if false-positive risk is real.
- `REPL` - replacement string. Literal. Defaults to empty (deletes matches).
- `DIR` - root of the recursion. Defaults to `.` (the CWD).

Implementation under the hood:

```
find "$DIR" -path ./.git -prune -o -type f -exec sed -i "s|$FIND|$REPL|g" {} \;
```

Uses `|` as the sed delimiter, so patterns containing literal `|` need escaping; patterns with `/`, `.`, `-`, `_`, spaces do not.

## When to use

- Renaming a file and updating every reference across the tree (e.g., `v5-shape.md` -> `vision.md` across 25 docs)
- Renaming a symbol, module path, config key, or URL where the old string is unique enough to grep for
- Updating cross-references after moving files or restructuring directories

Faster and more reliable than per-file Edit calls when the string is literal, unique, and the scope is well-bounded.

## When NOT to use

- **Single-file change.** Use Edit. Recursion adds risk without benefit.
- **Large files** (> 1500 lines). See `dealing-with-large-files.md` - sed in an agent loop on big files is the exact failure mode that blew up `/tmp`. `replace` uses sed; the same rule applies.
- **Non-unique pattern.** If FIND also matches things you don't want changed, a sweep silently edits them all. Grep first, confirm the count matches expectation, then run.
- **Too-broad DIR scope.** Recursion is the gotcha; see below. `replace foo bar /` is never the right call.

## Recursion is the gotcha

`replace` walks every file under `DIR` except `.git`. It does not respect `.gitignore`, does not skip `target/` / `node_modules/` / `.venv/`, does not distinguish text from binary. sed will happily rewrite anything it can open.

Before running, decide the narrowest `DIR` that contains all intended hits and nothing else. Common sharpening:

- Stay inside a single repo: `replace foo bar ~/repos/scottidler/<repo>`
- Scope further to a subtree: `replace foo bar ~/repos/scottidler/<repo>/docs`
- Keep memory files separate from repo files; invoke twice if both need the same change

If DIR is `.` and CWD is the repo root, that is usually correct, but confirm with `pwd` first.

## Verification workflow

1. **Grep first.** Count occurrences of `FIND` under `DIR`. Confirm the total matches your expectation and none of the matches are in files you shouldn't touch.
2. **Sanity-check `DIR`.** `ls $DIR` to be sure you aren't sweeping an unrelated tree.
3. **Run `replace`.**
4. **Grep again.** Zero stragglers for `FIND` under `DIR`.
5. **Verify downstream.** Run the project's health check (`cargo check --workspace`, `uv run pytest`, `otto ci`). A mechanical rename can still produce a broken reference if something outside `DIR` was holding the name.

## Related rules

- `dealing-with-large-files.md` - why sed on files over 1500 lines is dangerous in an agent loop; `replace` inherits that constraint per file
- `general.md` - naming conventions (so renames land consistently with the project's style)
