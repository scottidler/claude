---
name: gha-versions
description: Audit GitHub Actions versions in workflow files and report available upgrades. Use when checking for outdated actions, Node.js deprecation warnings, or auditing CI/CD dependencies.
---

# GitHub Actions Version Auditor

Scan `.github/workflows/` for all `uses:` directives, resolve the latest major version for each action, and report which ones have upgrades available.

## Procedure

### 1. Find all workflow files

```bash
find .github/workflows -name '*.yml' -o -name '*.yaml' 2>/dev/null
```

If no `.github/workflows/` directory exists, tell the user and stop.

### 2. Extract all `uses:` directives

For each workflow file, extract every `uses:` line. Parse out:
- **owner/repo** (e.g. `actions/upload-artifact`)
- **current version** (e.g. `v4`)

Skip:
- Docker actions (`uses: docker://...`)
- Local actions (`uses: ./...`)
- Actions pinned to a full SHA (40-char hex) - note these separately as "SHA-pinned"

### 3. Resolve latest versions

For each unique `owner/repo`, get the latest release tag:

```bash
gh release list --repo <owner/repo> --limit 1 --json tagName --jq '.[0].tagName'
```

If `gh release list` returns nothing (some actions use tags only, not releases), fall back to:

```bash
gh api repos/<owner/repo>/tags --jq '.[].name' | grep -E '^v[0-9]+' | sort -V | tail -1
```

Extract the major version from the latest tag (e.g. `v7.0.0` -> `v7`).

### 4. Classify each action

For each action found, classify as:
- **outdated** - current major < latest major
- **current** - current major == latest major
- **sha-pinned** - pinned to a commit SHA (report but don't flag)
- **unknown** - could not resolve latest version (report the error)

Internal/org actions (e.g. `tatari-tv/github-actions/checkout@v5`) should also be checked if possible, but note they may not have public releases.

### 5. Output format

Present results as a table, grouped by status:

```
## Outdated (action required)

| File | Action | Current | Latest | Notes |
|------|--------|---------|--------|-------|
| release.yaml | actions/upload-artifact | v4 | v7 | Node.js 20 deprecated June 2026 |

## Current (no action needed)

| Action | Version |
|--------|---------|
| actions/checkout | v6 |

## SHA-pinned (review manually)

| File | Action | SHA |
|------|--------|----|
| ci.yaml | some/action | abc123... |

## Unknown (could not resolve)

| Action | Error |
|--------|-------|
| internal/action | no releases found |
```

### 6. Offer to fix

After presenting the report, ask the user if they want to upgrade the outdated actions. If yes:
- Edit each workflow file to bump the version tags
- Show the diff
- Do NOT commit automatically - let the user decide

## Notes

- Major version bumps (e.g. v4 -> v7) may have breaking changes. Always mention this when recommending upgrades.
- For `actions/upload-artifact` and `actions/download-artifact`, these should always be upgraded together to matching generations.
- Some actions like `Swatinem/rust-cache@v2` may still trigger Node.js warnings even on latest major - note when the issue is upstream.
- When checking tatari-tv org actions, use `account: "work"` with the multi-account-github MCP.
