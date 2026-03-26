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

## Rust CLI Overrides

- A Rust variant of `tail` is installed at `~/.cargo/bin/tail` and shadows `/usr/bin/tail`. It has incompatible flags. In Bash commands, always use `/usr/bin/tail` instead of bare `tail`.

## File Deletion Safety

- NEVER use `rm` or `rm -rf`. Always use `rkvr rmrf` instead. This archives files before deleting, enabling recovery if needed.
- No exceptions. Even for temp files or known-safe deletions, use `rkvr rmrf`.

## Git Safety

- NEVER delete a git tag, locally or on remote. No exceptions. Even if a design doc says to delete a tag, DO NOT do it.
- NEVER run `git tag -d`, `git push --delete` for tags, or use any MCP tool to delete tags (e.g., `delete_tag`).
- If a tag needs to be moved or recreated, ask the user explicitly and let them do it.
- ALWAYS use annotated tags (`git tag -a -m "message"`), NEVER lightweight tags (`git tag`). No exceptions.
- NEVER push directly to main/master on `tatari-tv/*` repos. No exceptions. If `branch.main.pushremote=no_push` is set, that means PRs are required. Create a feature branch, push it, and open a PR. Do NOT bypass the guard with `git push origin main`. Do NOT offer direct push as an option. If the user needs to push directly to main, they will do it themselves by hand.

## Hostnames

- `lappy` or `laptop` => `ltl-7007.lan`
- `desk` or `desktop` => `desk.lan`

## Obsidian Vault (my Second Brain)

- Location: `~/repos/scottidler/obsidian/`

## Repo Convention

- All cloned repos live under `~/repos/` using the full slug: `~/repos/<org|user>/<reponame>`
  - Example: `~/repos/scottidler/obsidian-borg`, `~/repos/tatari-tv/philo`
- If a repo or tool is mentioned by name, check `~/repos/` for it before asking where it is

## Dotfiles

- Repo: `scottidler/...` checked out at `~/...` (yes, literally three dots)
- Driven by `HOME/.config/manifest/manifest.yml` in the repo, symlinked to `~/.config/manifest/manifest.yml`
- Consumed by `manifest` (a Rust binary from `scottidler/manifest`, installed via cargo at `~/.cargo/bin/manifest`)
- `manifest` discovers the repo root automatically by resolving the config symlink
- The `HOME/` directory mirrors `$HOME` - files inside are symlinked into `~` via `manifest`
- `manifest.yml` declares: symlinks (`link:`), packages (`pkg:`, `apt:`, `dnf:`, `cargo:`, `pip3:`, `pipx:`, `npm:`, `flatpak:`), PPAs, GitHub repos to clone/build/link (`github:`), and install scripts (`script:`)
- Contains shell config, git config, tmux, vim/neovim, SSH, Rust formatting, and more
- Note: `scottidler/dotfiles` is archived on GitHub (redundant snapshot of `scottidler/...`)
