---
paths:
  - "**/*.{rs,py,go,rb,c,h,cpp,hpp,cc,cs,java,kt,swift,ts,tsx,js,jsx,mjs,cjs,sh,bash,zsh,yml,yaml}"
---

# Code Comments: Name It, Don't Narrate It

## The rule

- A function, class, method, or enum name should say what it does. If the
  name is right, a comment restating it is redundant — delete the comment,
  not the clarity.
- Wrong: `// checks if the user is active` above `fn check_user(u: &User) -> bool`
- Right: `fn is_active(user: &User) -> bool` — no comment needed
- If you feel the pull to explain what a function does, that's a signal the
  function is misnamed. Rename it instead of commenting it.

## When a comment earns its place

Write a comment (or short block) only when the code cannot say the thing
itself:

- **Tricky:** a non-obvious algorithm, ordering requirement, or optimization
  that isn't visible from reading the code line-by-line
- **Subtle:** a workaround for a library quirk, platform edge case, or a
  constraint imposed by something outside this file
- **Scar tissue:** something that broke before — link the incident/PR if one
  exists, and say what actually failed, not just "be careful here"

## Style when you do write one

- Short. One line if one line covers it.
- Bullets over paragraphs when there's more than one point.
- State the non-obvious fact, not a restatement of the code below it.
- No multi-paragraph blocks, no docstring essays.

**Wrong (comment restates the name):**
```rust
// Returns true if the cache entry has expired
fn is_expired(entry: &CacheEntry) -> bool { ... }
```

**Right (name carries it, no comment):**
```rust
fn is_expired(entry: &CacheEntry) -> bool { ... }
```

**Right (comment earns its place — subtle + scar tissue):**
```rust
// Must run BEFORE the flush below: the driver silently drops writes
// issued after close() on some kernels (broke prod 2026-06-14, see #482).
conn.flush()?;
conn.close()?;
```

## Naming that removes the need for a comment

- Functions: verb-first, say the outcome (`is_expired`, `retry_with_backoff`,
  `flatten_nested_tags`) not the mechanism (`process`, `handle`, `do_thing`)
- Booleans: `is_`/`has_`/`can_`/`should_` prefixes so call sites read as
  English (`if is_expired(entry)`, not `if check(entry)`)
- Enums/variants: name the state, not a code (`Status::Retrying`, not
  `Status::S3`)
- Classes/structs: name the concept it models, not the pattern it implements
  (`RateLimiter`, not `RateLimiterManagerImpl`)
- If a name needs a comment to disambiguate what it means, the name is wrong
  — fix the name

## YAML

- Same rule applies to `#` comments in config: a well-named key needs no
  comment. Comment only a non-obvious default, a value tied to an external
  constraint (quota, SLA, a tool's required format), or something that broke
  before.
