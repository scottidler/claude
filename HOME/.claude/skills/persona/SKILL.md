---
name: persona
description: Query Tatari's internal Persona API for employee and org data - look up people, reporting chains, teams, and org proximity. Use when you need to find a person's role, manager, direct reports, teammates, or GitHub username.
allowed-tools: Bash(persona:*)
---

# Persona - Tatari Employee & Org Data

`persona` is a CLI tool that queries Tatari's internal Persona API (https://persona.ops.tatari.dev) for employee and org structure data.

## Authentication

Uses Okta SSO. If you get an auth error, run `persona login` to re-authenticate via browser.

## Quick Reference

```bash
persona whoami                          # Show currently authenticated user
persona whois "Name or email"           # Look up a person
persona whois --json "Scott Idler"      # JSON output for parsing
persona whois --first "partial name"    # Use first match if multiple results

persona manager "Scott Idler"           # Show direct manager
persona reports "Scott Idler"           # Show direct reports
persona chain "Scott Idler"             # Full management chain to top
persona teammates "Scott Idler"         # Peers (same manager)
persona github "Scott Idler"            # Get GitHub username

persona team "Site Reliability Engineering"   # All members of a named team
persona teams                           # List all team names
persona orgs                            # List all org names
persona departments                     # List all department names

persona search "partial name"           # Search by name
persona search --organization Engineering "name"   # Filter by org
persona search --title "Director" --json           # Filter by title

persona headcount                       # Total employee count
persona hired --start 2025-01-01        # Employees hired after date
```

## Org Context: Scott Idler

Scott's org position (Director of Engineering, Platform):

```
Mark Weiler (manager)
  Scott Idler (Director of Engineering - Platform)
    Patrick Shelby (Manager, Engineering - SRE)
      Calvin Morrow, Johnny Carr, Keegan Ferrando, Stephen Price
    Zach Fierstadt (Senior Manager, Engineering - Data Platform)
      Ben Horn, Jonathan Hohrath, Leslie Rod, Luke Chu, Russell Simco
```

Peers (all report to Mark Weiler): Bruce Rechichar, Dan Stynchula, Mike Sisario, Reno Brown, Toussaint Minett

## Common Patterns

### Look up someone before DMing or mentioning them
```bash
persona whois --json --first "Calvin"
# Returns work_email, business_title, team_org, github_username, etc.
```

### Find org proximity for a task
```bash
# Who owns a given team?
persona team "Data Platform" --json

# Who reports to a person?
persona reports "Patrick Shelby" --json

# Full chain from individual to top
persona chain "Keegan Ferrando" --json
```

### Cross-reference with Slack
Slack usernames at Tatari are typically the local part of the work email:
- `calvin@tatari.tv` -> `@calvin`
- `patrick.shelby@tatari.tv` -> `@patrick.shelby`

DM channel IDs for org members are in `.claude/slack-ids.yml`.

## Output Fields (JSON)

| Field | Description |
|-------|-------------|
| `work_email` | Primary email (use local part for Slack username) |
| `preferred_full_name` | Display name |
| `business_title` | Job title |
| `team_org` | Team name |
| `organization_org` | Org (e.g. Engineering) |
| `department_org` | Department |
| `supervisor_email` | Manager's email |
| `supervisor_name` | Manager's name |
| `github_username` | GitHub handle |
| `hire_date` | Start date |
| `termination_date` | Set if no longer active - always filter these out |

## Notes

- Always filter out records where `termination_date` is set - these are former employees
- Use `--first` flag when you want the top match without an ambiguity prompt
- Use `--json` whenever you need to parse or extract specific fields
