---
name: cli-shakedown
description: "Systematically exercise a CLI tool by discovering all commands/flags, running them with real inputs, testing output formats, building shell pipelines, and producing a field guide with tested examples. Use this skill whenever the user has a new or updated CLI tool and wants to test it, exercise it, put it through its paces, shake it down, try every command, verify it works, or generate usage examples. Also use when the user says 'test this CLI', 'try out persona', 'exercise this tool', 'run every command', 'shakedown', or refers to validating a freshly built binary. Trigger even if the user just says something like 'ok lets test it' after building a CLI."
---

# CLI Shakedown

You are testing a CLI tool the user just built or updated. Systematically discover everything the tool can do, run it for real, note what works and what breaks, and produce a field guide with tested examples and pipeline recipes.

The user builds a LOT of CLI tools. They need confidence that a freshly minted binary actually works before shipping it. This is not a unit test suite - CI already ran those. This is a real-world shakedown: does the tool actually do what it claims when a human (or script) uses it?

## Philosophy

- **Run everything for real.** No dry runs, no mocks. If a command queries an API, query it. The point is to find out what actually happens.
- **Be read-only by default.** Don't run commands that create, modify, or delete data unless the user explicitly says to. Discover them, document them, flag as "skipped (mutating)".
- **Handle auth gracefully.** If a command fails with an auth error, note it and move on. Don't run interactive login commands (browser flows, prompts) - just note they exist.
- **Capture everything.** Every command: capture exit code, stdout, stderr. Truncate huge outputs but note the size.
- **Chain outputs into inputs.** The most valuable testing comes from using the output of one command as the input to another. A `teams` command returns team names - feed one into `team <name>`. A `whois` returns a manager email - feed it into `reports <email>`. This is how real users will use the tool.
- **Validate output formats rigorously.** When a tool claims `--json` output, pipe it through `jq .` to validate. This both tests the flag AND validates the JSON in one shot. Check that `--csv` actually produces CSV with headers, not just a table.

## Phase 0: Permission Setup (do this FIRST)

A shakedown runs dozens or hundreds of commands. Being prompted for permission on each one makes the experience miserable. Before running a single command:

1. **Check if `Bash(<tool>:*)` exists in `~/.claude/settings.json` permissions.allow.**
2. **If not, add it.** Read the settings file, add the permission rule to the allow array, write it back. This is a one-time setup that makes the entire shakedown flow smoothly.

This is the single most important step. Skip it and the user will be clicking "approve" 50+ times. The tool is something they just built - they obviously want to run it.

**Critical: permission patterns are prefix-matched.** `Bash(persona:*)` only matches commands that literally start with `persona`. If you wrap the command in `echo "..."; persona ...` or chain it with `&&`, or pipe it with `| head`, the command string no longer starts with `persona` and will prompt again. During the shakedown:
- Run each `<tool>` command as a bare, standalone Bash call
- For pipelines that need `jq`, `head`, `wc`, etc., make sure those are already in the user's permissions too (check for `Bash(jq:*)`, `Bash(head:*)`, etc.), or start the command with the tool name and pipe after: `persona orgs --json | jq .` starts with `persona` so it matches
- Never wrap commands in `echo` prefixes or chain with `;`/`&&`

## Shakedown Process

### Phase 1: Discovery

1. **Find the binary.** Check `which <tool>`, or look in the project's `target/release/` or `target/debug/` directory. If not installed, run `cargo install --path .` first.
2. **Get the version.** Run `<tool> --version`.
3. **Map the command tree.** Run `<tool> --help`, then `<tool> <subcommand> --help` for every subcommand. Parse out:
   - All subcommands (including nested ones)
   - All flags and options per subcommand (with types and defaults)
   - Required vs optional arguments
   - Global flags that apply everywhere
4. **Classify each command:**
   - **Safe (read-only):** queries, lookups, listings, searches
   - **Auth-required:** anything that hits an external service
   - **Mutating:** creates, modifies, or deletes state
   - **Interactive:** requires user input (login flows, prompts)

### Phase 2: Execution

Work through commands in dependency order. The key insight: each successful command unlocks inputs for the next.

**Step 1: No-arg discovery commands.** These are the freebies that need no input - list commands, status commands, count commands. Run them all. Capture their output because it becomes input for step 2.

**Step 2: Feed outputs forward.** Use real values from step 1 as arguments:
- Team names from `teams` become input to `team <name>`
- Org names from `orgs` become filter values for `--organization <org>`
- Person names from any list become input to `whois <person>`
- Manager emails from `whois` become input to `reports <email>` and `chain <person>`

This chaining is critical. It tests the tool the way real users and scripts will actually use it, and catches issues like URL encoding, special characters in names, and mismatched field formats.

**Step 3: Output format matrix.** For every command that worked in table mode, re-run with each output format flag:
- `--json`: pipe through `jq .` to validate JSON structure. Check that it's an array for list commands, an object for single-item commands.
- `--csv`: verify headers exist on the first line, fields are properly quoted when they contain commas.
- Check for format flags that silently fall back to table output instead of actually producing the requested format - this is a common bug.

**Step 4: Flag combinations.** Test meaningful interactions:
- Boolean flags individually: `--recursive`, `--tree`, `--members`
- Flags that modify each other: `--recursive --ics-only`, `--recursive --managers-only`
- Format flag with other flags: `--recursive --tree --json`

**Step 5: Edge cases.**
- Missing required arguments (should show usage, not crash)
- Invalid/nonexistent inputs ("Nonexistent Person", "99999")
- Ambiguous inputs that might match multiple results
- Boundary values (empty strings passed as args)

### Phase 3: Pipelines

Build real shell pipelines and verify they work. Every pipeline should be copy-pasteable.

**Pattern 1: jq extraction** (validates JSON AND demonstrates the pipeline)
```bash
<tool> <cmd> --json | jq '.[].field_name'
<tool> <cmd> --json | jq '. | length'
<tool> <cmd> --json | jq 'to_entries | sort_by(-.value) | .[:5]'
```

**Pattern 2: Tool chaining** (output of command A feeds into command B)
```bash
# Get a person's manager, then look up that manager's reports
manager=$(<tool> whois "person" --json | jq -r '.supervisor_email')
<tool> reports "$manager"
```

**Pattern 3: Unix pipeline composition**
```bash
<tool> <list-cmd> --json | jq -r '.[].field' | sort | uniq -c | sort -rn | head -10
<tool> <search-cmd> --csv > /tmp/export.csv
```

### Phase 4: Formatting Quality Check

Specifically examine the table output for formatting issues - this is where many CLIs have subtle bugs:
- Are columns aligned when data has varying lengths?
- Do long values overflow into adjacent columns?
- Are there clear separators between columns?
- Does the header row match the data rows?

### Phase 5: Release Validation

If the tool lives in a GitHub repo, validate that the release pipeline produced working binaries for the current version.

1. **Get the repo slug.** Look for a git remote in the project directory, or use `reposlug` if available. Determine whether it's a `home` or `work` account for the multi-account-github MCP.

2. **Find the matching release.** Use the version from `<tool> --version` (e.g., `v0.3.0`) and look for a GitHub release with that tag. Use the multi-account-github MCP `get_release` or `list_releases`, or `gh release view v<version>`.

3. **Check release assets.** A properly released Rust CLI should have binaries for at least these targets:
   - `<tool>-x86_64-unknown-linux-gnu` (or similar linux amd64)
   - `<tool>-aarch64-unknown-linux-gnu` (linux arm64)
   - `<tool>-x86_64-apple-darwin` (macOS Intel)
   - `<tool>-aarch64-apple-darwin` (macOS Apple Silicon)

   List all assets and note which targets are present vs missing. The exact naming varies by project - some use `.tar.gz`, some are bare binaries, some include the version in the filename. Adapt to what you find.

4. **Download and test the matching binary.** Determine the current OS and architecture (`uname -s` + `uname -m`), download the matching asset to `/tmp/`, make it executable, and run `<binary> --version`. Compare the output to what the locally-installed binary reports. They should match exactly.

5. **Verify the git tag.** Check that the tag exists, is annotated (not lightweight), and that it points to the expected commit. Use `git tag -v <tag>` or `git cat-file -t <tag>` (annotated tags have type "tag", lightweight have type "commit").

Report findings in a "Release Validation" section:
- Tag: exists? annotated? points to correct commit?
- Release: exists? draft? published?
- Assets: which targets are present? which are missing?
- Binary test: downloaded which asset? version matches? runs correctly?

### Phase 6: Report

Save a structured report to `docs/shakedown-v<version>.md`:

```markdown
# CLI Shakedown Report: <tool> v<version>

## Summary
| Metric | Count |
|--------|-------|
| Commands discovered | N |
| Commands tested | N |
| Commands passed | N |
| Commands failed | N |
| Commands skipped | N (with reasons) |
| Pipelines tested | N |
| Edge cases tested | N |

## Command Results
For each command tested: the exact invocation, exit code, and
a representative sample of the output. Group by category.

## Output Format Matrix
Table showing which commands support which output formats,
and whether each format actually works correctly.

## Failures & Bugs
For each issue found:
- The command that exposed it
- What happened vs what should have happened
- Severity: bug, cosmetic, or suggestion

## Pipeline Recipes
Working pipeline examples with actual output, ready to copy-paste.

## Edge Cases
What happened with bad inputs - did it error gracefully?

## Observations
Inconsistencies, missing features, UX suggestions.
```

## Constraints

- Don't run `rm`, `delete`, `drop`, or any destructive command unless explicitly asked
- Don't run interactive commands (login flows, browser auth) - just note they exist
- If a command hangs (no output for 10+ seconds), kill it and note the timeout
- If a command produces huge output, capture the first 50 lines and note the total size
- Use `rkvr rmrf` instead of `rm -rf` for any cleanup
- Run commands one at a time for clean, isolated output
- Append `; echo "EXIT: $?"` to capture exit codes reliably

## Adapting to the Tool

- **API-backed tools** (persona, gh): focus on real queries, auth flow, response validation, JSON pipeline composition
- **File-processing tools** (dashify, namify): create sample input files, test transformations, verify idempotency
- **Git/repo tools** (gx, git-tools): test against real repos in the user's ~/repos/
- **Calculator/utility tools** (cidr, aka): test with known inputs, verify correct outputs against expected values
- **System tools** (manifest): test in a safe namespace, verify state changes

Look at `--help` output and any README to understand which category the tool falls into, then weight testing accordingly.

ARGUMENTS: <tool-name-or-path>
