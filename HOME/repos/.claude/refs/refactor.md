# Mechanical Refactors

- `replace` is a zsh shell function (in the user's dotfiles) for bulk search-and-replace across a directory tree
- Prefer it over per-file Edit calls when the same literal change must land in many files

## Signature

```
replace FIND [REPL] [DIR]
```

- `FIND` — sed pattern to match. Basic regex (BRE): `.` matches any char, `*` is zero-or-more. Escape literal `.` if false-positive risk is real
- `REPL` — replacement string, literal. Defaults to empty (deletes matches)
- `DIR` — root of the recursion. Defaults to `.` (the CWD)
- Under the hood:

```
find "$DIR" -path ./.git -prune -o -type f -exec sed -i "s|$FIND|$REPL|g" {} \;
```

- Uses `|` as the sed delimiter, so patterns containing literal `|` need escaping; `/`, `.`, `-`, `_`, spaces do not

## When to use

- Renaming a file and updating every reference across the tree (e.g. `v5-shape.md` -> `vision.md` across 25 docs)
- Renaming a symbol, module path, config key, or URL where the old string is unique enough to grep for
- Updating cross-references after moving files or restructuring directories
- Faster and more reliable than per-file Edit when the string is literal, unique, and the scope is well-bounded

## When NOT to use

- **Single-file change** — use Edit; recursion adds risk without benefit
- **Large files** (> 1500 lines) — see `dealing-with-large-files.md`; sed in an agent loop on big files is the exact failure mode that blew up `/tmp`. `replace` uses sed, so the same rule applies
- **Non-unique pattern** — if FIND also matches things you don't want changed, a sweep silently edits them all; grep first, confirm the count, then run
- **Too-broad DIR scope** — recursion is the gotcha (below); `replace foo bar /` is never the right call

## Recursion is the gotcha

- `replace` walks every file under `DIR` except `.git` — it ignores `.gitignore`, doesn't skip `target/`/`node_modules/`/`.venv/`, doesn't distinguish text from binary; sed rewrites anything it can open
- Before running, pick the narrowest `DIR` that contains all intended hits and nothing else:
  - Stay inside one repo: `replace foo bar ~/repos/scottidler/<repo>`
  - Scope to a subtree: `replace foo bar ~/repos/scottidler/<repo>/docs`
  - Keep memory files separate from repo files; invoke twice if both need the same change
- If DIR is `.` and CWD is the repo root that's usually correct — confirm with `pwd` first

## Verification workflow

1. **Grep first** — count occurrences of `FIND` under `DIR`; confirm the total matches expectation and no matches are in files you shouldn't touch
2. **Sanity-check `DIR`** — `ls $DIR` to be sure you aren't sweeping an unrelated tree
3. **Run `replace`**
4. **Grep again** — zero stragglers for `FIND` under `DIR`
5. **Verify downstream** — run the project's health check (`cargo check --workspace`, `uv run pytest`, `otto ci`); a mechanical rename can still break a reference outside `DIR`

## Related rules

- `dealing-with-large-files.md` - why sed on files over 1500 lines is dangerous in an agent loop; `replace` inherits that constraint per file
- `general.md` - naming conventions (so renames land consistently with the project's style)
