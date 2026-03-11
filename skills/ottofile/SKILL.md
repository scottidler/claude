---
name: ottofile
description: Create or standardize a .otto.yml file for any project. Auto-detects project type (Rust crate/workspace/service, Python package/service, full-stack, TypeScript/JavaScript) and generates best-practice CI configuration. Use when setting up a new repo or auditing an existing ottofile.
user-invocable: true
allowed-tools: [Bash, Read, Write, Edit, Glob, Grep, Agent]
argument-hint: "[--type <rust-crate|rust-workspace|rust-service|python-package|python-service|fullstack|typescript>] [--frontend-dir <path>]"
---

# Ottofile

Create or standardize `.otto.yml` files following established conventions.

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--type <type>` | No | Override auto-detection. One of: `rust-crate`, `rust-workspace`, `rust-service`, `python-package`, `python-service`, `fullstack`, `typescript` |
| `--frontend-dir <path>` | No | Frontend directory name (default: `web/`). Only relevant for fullstack projects |

## Step 1: Detect Project Type

If `--type` was not specified, auto-detect by inspecting the repo root:

```
Detection priority (first match wins):

1. Cargo.toml exists?
   a. Contains [workspace] section?           -> rust-workspace
   b. Has src/main.rs AND an API/server crate? -> rust-service
   c. Otherwise                                -> rust-crate

2. pyproject.toml or setup.py exists?
   a. Has web/, frontend/, or app/ dir with package.json? -> fullstack
   b. Has an ASGI/WSGI entrypoint (uvicorn, gunicorn,
      fastapi, flask in deps)?                            -> python-service
   c. Otherwise                                           -> python-package

3. package.json exists (no Python)?             -> typescript
```

For fullstack detection, also check for `docker-compose.yml` or `docker-compose.yaml` - if present, include Docker operational tasks.

**Tell the user** what type was detected and ask for confirmation before proceeding. If an existing `.otto.yml` exists, mention that too and say you will update it.

## Step 2: Gather Project-Specific Details

Based on the detected type, discover:

- **Rust**: crate name from `Cargo.toml`, workspace members, binary vs library
- **Python**: package name from `pyproject.toml` (`[project].name` or `[tool.poetry].name`), package manager (always `uv` - poetry is legacy), type checker (`mypy`)
- **Fullstack**: backend language, frontend dir name, frontend package manager (`npm`, `yarn`, `bun`, or `pnpm` based on lock files), whether Docker Compose exists
- **TypeScript/JavaScript**: package manager (`npm`, `yarn`, `bun`, or `pnpm` based on lock files), test runner from scripts

## Step 3: Generate or Update the .otto.yml

Read the appropriate reference file for the detected type, then generate the `.otto.yml`.

The `bash/` directory contains reusable snippets (bash and YAML). Templates reference them with `{{inline:bash/filename}}` markers. When generating the `.otto.yml`, read the referenced file and paste its contents in place of the marker. These are templates for inlining only - never copy them as standalone files into the user's repo.

Reference files:

| Type | Reference |
|------|-----------|
| `rust-crate`, `rust-workspace`, `rust-service` | `references/rust.md` |
| `python-package`, `python-service` | `references/python.md` |
| `fullstack` | `references/fullstack.md` |
| `typescript` | `references/typescript.md` |

If an existing `.otto.yml` exists, update it to match the template structure while preserving any custom tasks that don't conflict.

## Universal Rules (apply to ALL templates)

1. **Header**: Always `otto.api: 1`, `tasks: [ci]`, `VERSION` env var
2. **`lint` always includes `whitespace -r`** as the first command
3. **`ci` is a virtual task**: `before: [lint, check, test]` with a simple success message body
4. **`cov` is NEVER in `ci`** - it's a separate manual invocation
5. **Use `bash:` not `action:`** (action is deprecated)
6. **Every file ends with a trailing newline**
7. **Task order in file**: lint, check, test, cov, cov-report (if applicable), ci, build, clean, install (if applicable), then any extras

## Step 4: Write the File

- If creating new: write the generated `.otto.yml` to the repo root
- If updating existing: show the user what will change (summarize additions, removals, modifications) before writing

## Step 5: Validate

After writing, run `otto --help` in the repo to verify the file parses correctly. If otto is not installed, skip this step and tell the user.

## Audit Mode (existing file)

When an existing `.otto.yml` is found, compare it against the appropriate template and report:

1. **Missing tasks**: Tasks in the template but not in the file
2. **Deprecated patterns**: `action:` instead of `bash:`, `all` instead of `ci`, gen1 cov without cov-report
3. **Naming inconsistencies**: `unit-test` should be `unit`, `integration-test` should be `integ`
4. **Missing whitespace in lint**: `whitespace -r` should be the first line of every `lint` task
5. **Coverage in CI**: Flag if `cov` is wired into `ci.before`
6. **Missing --workspace flags**: For Rust workspaces missing `--workspace` on cargo commands
7. **Custom tasks to preserve**: Any task not in the template should be kept as-is (warn but don't remove)

Present findings as a checklist, then offer to fix all issues automatically.
