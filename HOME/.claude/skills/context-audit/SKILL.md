---
name: context-audit
description: >
  Audit your Claude Code setup for token waste and context bloat. Use when
  the user says "audit my context", "check my settings", "why is Claude so
  slow", "token optimization", "context audit", or runs /context-audit.
  Audits MCP servers, CLAUDE.md rules, skills, settings, and file permissions
  by reading files directly. Returns a health score with specific fixes.
user-invocable: true
---

# Usage Audit

Bloated context costs more and produces worse output. This skill finds
the waste and tells you what to cut.

Start the audit immediately by reading files directly. Run checks in
parallel where possible.

## Audit What's Bloated

### MCP Servers

Each server loads full tool definitions into context every turn
(~15,000-20,000 tokens each).

- Count configured servers from settings.json
- Flag any with CLI alternatives (Playwright, Google Workspace, GitHub
  all have CLIs that cost zero tokens when idle)
- Note whether on-demand loading is active (deferred schemas = near-zero idle cost)

### CLAUDE.md

Read all CLAUDE.md files (project root, .claude/, ~/.claude/).
Count lines. Then read every rule and test against five filters:

| Filter | Flag when... |
|--------|-------------|
| Default | Claude already does this without being told ("write clean code", "handle errors") |
| Contradiction | Conflicts with another rule in same or different file |
| Redundancy | Repeats something already covered elsewhere |
| Bandaid | Added to fix one bad output, not improve outputs generally |
| Vague | Interpreted differently every time ("be natural", "use good tone") |

If total CLAUDE.md lines > 200, check for progressive disclosure
opportunities: rules that only apply to specific tasks (API conventions,
deployment steps, testing guidelines) should move to reference files
with one-line pointers. Only recommend splitting when the file is
actually bloated -- a lean CLAUDE.md with universal context is fine
as a single file.

### Skills

Scan .claude/skills/*/SKILL.md. For each skill:
- Count lines (flag > 200, critical > 500)
- Run the same five filters on instructions
- Check for restated goals, hedging ("you may want to"), synonymous
  instructions ("be concise" + "keep it short" + "don't be verbose")

### Settings

Check settings.json for:

| Setting | Flag if | Recommended |
|---------|---------|-------------|
| autocompact_percentage_override | Missing or > 80 | 75 |
| BASH_MAX_OUTPUT_LENGTH (env) | At default (30-50K) | 150000 |

### File Permissions

Check settings.json for `permissions.deny` rules. If missing, check
whether bloat directories exist in the project:

| If this exists... | Should deny... |
|-------------------|---------------|
| package.json | node_modules, dist, build, .next, coverage |
| Cargo.toml | target |
| go.mod | vendor |
| pyproject.toml / requirements.txt | __pycache__, .venv, *.egg-info |

### Daily Habits

These can't be read from files, but they compound into serious token
savings. Surface all four as INFO items unless the user has already
indicated they follow them.

| Habit | Why it matters | Signal to look for |
|-------|---------------|-------------------|
| `/clear` between unrelated tasks | Old task context rides along for free — costs tokens on every message | User mentions switching topics mid-session |
| Plan mode before non-trivial work | Wrong-path rewrites are the most expensive mistake: 200 lines written, all scrapped | No `plan` in settings.json or user hasn't mentioned it |
| Edit the original prompt, not corrections | A follow-up correction adds bad response + correction + new response to context permanently | Can't detect; always surface |
| Right model for the job | Haiku for sub-agents/lookups, Sonnet for coding, Opus for architecture only | Check settings.json `model` field; flag if Opus is set as default |

Check settings.json for a `model` field. If it's set to `claude-opus-*`
as the default, flag it — Opus should be reserved for architecture, not
everyday use.

## Score and Report

Score starts at 100. Deduct per issue:

| Issue | Points |
|-------|--------|
| CLAUDE.md > 200 lines | -10 |
| CLAUDE.md > 500 lines | -20 |
| Per 5 rules flagged by filters | -5 |
| Contradictions between files | -10 |
| Missing autocompact override | -10 |
| Missing bash output override | -5 |
| Skill > 200 lines | -5 each |
| Skill > 500 lines | -10 each |
| Per MCP server | -3 each |
| No deny rules + bloat dirs exist | -10 |
| Opus set as default model | -5 |
| Daily habits section (surface all 4 as INFO) | 0 (INFO only, not scored) |

Floor at 0. Output this format:

```
# Usage Audit

Score: {N}/100 [{CLEAN|NEEDS WORK|BLOATED|CRITICAL}]

## Issues Found

### [{CRITICAL|WARNING|INFO}] {Category}
{What's wrong}
Fix: {One-line actionable fix}

### Rules to Cut
{Each flagged rule: the text, which filter, one-line reason}

### Conflicts
{Contradictions between files, with paths}

### [INFO] Daily Habits
- /clear between unrelated tasks — highest single-habit token savings
- Plan mode before non-trivial work — prevents expensive wrong-path rewrites
- Edit the original prompt instead of sending corrections — keeps bad exchanges out of context
- Right model for the job: Haiku for lookups/sub-agents, Sonnet for coding, Opus for architecture only

## Top 3 Fixes
1. {Highest-impact fix}
2. {Second}
3. {Third}
```

Score labels: 90-100 CLEAN, 70-89 NEEDS WORK, 50-69 BLOATED, 0-49 CRITICAL.
Severity: CRITICAL > 10pts, WARNING 5-10pts, INFO < 5pts.

## Step 4: Offer to Fix

After the report:

"Want me to fix any of these? I can:
- Show you a cleaned-up CLAUDE.md with the flagged rules removed
- Add the missing settings.json configs
- Add permissions.deny rules for build artifacts
- Show which skills to compress
- Walk through the daily habits and which ones apply to your workflow"

Auto-apply settings.json and permissions.deny (safe, reversible).
Show diffs for CLAUDE.md and skills -- let the user confirm before
modifying instruction files.
