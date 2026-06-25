---
alwaysApply: true
---

# Otto

- `otto` is the task runner for CI and project builds across all repos

## Working Directory

- NEVER use `otto -C /some/path` when that path is already the current working directory — just run `otto` directly
- Only use `otto -C <path>` when the target project is *different* from CWD

## Never touch otto's files

- otto OWNS everything it writes under `~/.otto/`. NEVER create, move, delete, or "clear" anything in `~/.otto/` (or any `.otto/` path), and NEVER `rm`/`rm -rf` an otto run dir. It was never requested, it destroys CI history, and it violates the rkvr-only safety rule.
- There is NO "stale run dir" problem to clean: otto writes every run to a fresh **timestamped** directory (`~/.otto/<proj-hash>/<unix-ts>/tasks/<task>/...`) and prints that exact path. To inspect a result, READ the path otto just printed — never delete prior runs to "get a clean state."
- Verify a run by its **exit code** (`otto ci; echo $?` → 0) and the final `✅ All CI checks passed!` line. Reading logs is for diagnosing a non-zero exit, not routine.
