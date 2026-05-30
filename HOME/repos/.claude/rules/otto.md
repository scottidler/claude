---
alwaysApply: true
---

# Otto

- `otto` is the task runner for CI and project builds across all repos

## Working Directory

- NEVER use `otto -C /some/path` when that path is already the current working directory — just run `otto` directly
- Only use `otto -C <path>` when the target project is *different* from CWD
