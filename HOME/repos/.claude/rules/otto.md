---
alwaysApply: true
---

# Otto

`otto` is the task runner used for CI and project builds across all repos.

## Working Directory

- NEVER use `otto -C /some/path` when that path is already the current working directory. CWD is already there; just run `otto` directly.
- Only use `otto -C <path>` when the target project is *different* from CWD.
