# Scott Idler

## Personas

I have two personas with distinct identities and tooling:

### Home (`home`)
- **GitHub:** `scottidler` (default account in multi-account-github MCP)
- **SSH key:** `~/.ssh/identities/home/id_ed25519`
- **Email:** `scott.a.idler@gmail.com`
- **Repos:** everything in `~/repos/` that is NOT under `tatari-tv/`

### Work (`work`)
- **GitHub:** `escote-tatari` (org: `tatari-tv`)
- **SSH key:** `~/.ssh/identities/work/id_ed25519`
- **Email:** `scott.idler@tatari.tv`
- **Slack:** Tatari workspace
- **Atlassian:** Tatari (cloud ID: `e5e3855e-244e-490a-b52d-7eec95e203a5`)
- **Repos:** everything under `~/repos/tatari-tv/`
- **Title:** Director of Engineering — Platform (SRE | Data Platform)

#### Jira & Confluence Spaces

| Scope | Jira Project | Confluence Space |
|-------|-------------|-----------------|
| SRE | `SRE` | `SRE` — [Site Reliability Engineering](https://tatari.atlassian.net/wiki/spaces/SRE) |
| Data Platform | `DAT` | `DATA` — [Data Platform](https://tatari.atlassian.net/wiki/spaces/DATA) |
| AI Foundry | `AIC` | `AIF` — [AI Foundry](https://tatari.atlassian.net/wiki/spaces/AIF) |
| Incidents (Eng + DS) | `INC` | `INC` |
| Engineering (shared) | `ENGPROG` | `ENG` — [Engineering](https://tatari.atlassian.net/wiki/spaces/ENG) |

When using the `multi-account-github` MCP, specify `account: "home"` or `account: "work"` as appropriate based on the repo/org context. Default is `home`.

## Formatting Rules

- NEVER use em dashes (—) in any output destined for documentation, comments, Confluence, Jira, Slack, or any external system. Use regular dashes (-), commas, or semicolons instead.

## Python Package Management

- NEVER use `pip install`. EVER. Always use `pipx` for installing Python tools/packages. No exceptions.

## Git Safety

- NEVER delete a git tag, locally or on remote. No exceptions. Even if a design doc says to delete a tag, DO NOT do it.
- NEVER run `git tag -d`, `git push --delete` for tags, or use any MCP tool to delete tags (e.g., `delete_tag`).
- If a tag needs to be moved or recreated, ask the user explicitly and let them do it.

## Repo Convention

- All cloned repos live under `~/repos/` using the full slug: `~/repos/<org|user>/<reponame>`
  - Example: `~/repos/scottidler/obsidian-borg`, `~/repos/tatari-tv/philo`
- If a repo or tool is mentioned by name, check `~/repos/` for it before asking where it is
