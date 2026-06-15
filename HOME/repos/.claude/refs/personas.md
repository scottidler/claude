# Personas

- Two personas with distinct identities and tooling: `home` and `work`

## Home (`home`)
- **GitHub:** `scottidler` (default account in multi-account-github MCP)
- **SSH key:** `~/.ssh/identities/home/id_ed25519`
- **Email:** `scott.a.idler@gmail.com`
- **gws (Google Workspace CLI):** `gws-home` → this account (see the `gws` skill)
- **Repos:** everything in `~/repos/` that is NOT under `tatari-tv/`

## Work (`work`)
- **GitHub:** `escote-tatari` (org: `tatari-tv`)
- **SSH key:** `~/.ssh/identities/work/id_ed25519`
- **Email:** `scott.idler@tatari.tv`
- **gws (Google Workspace CLI):** `gws-work` / bare `gws` → this account (see the `gws` skill)
- **Slack:** Tatari workspace
- **Atlassian:** Tatari (cloud ID: `e5e3855e-244e-490a-b52d-7eec95e203a5`)
- **Repos:** everything under `~/repos/tatari-tv/`
- **Title:** Director of Engineering - Platform (SRE | Data Platform)

### Jira & Confluence Spaces

| Scope | Jira Project | Confluence Space |
|-------|-------------|-----------------|
| SRE | `SRE` | `SRE` - [Site Reliability Engineering](https://tatari.atlassian.net/wiki/spaces/SRE) |
| Data Platform | `DAT` | `DATA` - [Data Platform](https://tatari.atlassian.net/wiki/spaces/DATA) |
| AI Foundry | `AIC` | `AIF` - [AI Foundry](https://tatari.atlassian.net/wiki/spaces/AIF) |
| Incidents (Eng + DS) | `INC` | `INC` |
| Engineering (shared) | `ENGPROG` | `ENG` - [Engineering](https://tatari.atlassian.net/wiki/spaces/ENG) |

- When using the `multi-account-github` MCP, specify `account: "home"` or `account: "work"` based on the repo/org context; default is `home`
- For the `gws` Google Workspace CLI, the persona is selected by wrapper: `gws-work` (and bare `gws`) = work, `gws-home` = home. Bare `gws` defaults to work — see the `gws` skill for the config-dir mechanism.
