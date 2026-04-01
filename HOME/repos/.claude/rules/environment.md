# Local Environment

## Hostnames

- `lappy` or `laptop` => `ltl-7007.lan`
- `desk` or `desktop` => `desk.lan`

## Obsidian Vault

- Location: `~/repos/scottidler/obsidian/`

## Repo Convention

- All cloned repos live under `~/repos/` using the full slug: `~/repos/<org|user>/<reponame>`
  - Example: `~/repos/scottidler/obsidian-borg`, `~/repos/tatari-tv/philo`
- If a repo or tool is mentioned by name, check `~/repos/` for it before asking where it is

## Dotfiles

- Repo: `scottidler/...` checked out at `~/.claude` (the primary working directory)
- Driven by `HOME/.config/manifest/manifest.yml` in the repo, symlinked to `~/.config/manifest/manifest.yml`
- Consumed by `manifest` (a Rust binary from `scottidler/manifest`, installed via cargo at `~/.cargo/bin/manifest`)
- `manifest` discovers the repo root automatically by resolving the config symlink
- The `HOME/` directory mirrors `$HOME` - files inside are symlinked into `~` via `manifest`
- `manifest.yml` declares: symlinks (`link:`), packages (`pkg:`, `apt:`, `dnf:`, `cargo:`, `pip3:`, `pipx:`, `npm:`, `flatpak:`), PPAs, GitHub repos to clone/build/link (`github:`), and install scripts (`script:`)
- Contains shell config, git config, tmux, vim/neovim, SSH, Rust formatting, and more
- Note: `scottidler/dotfiles` is archived on GitHub (redundant snapshot of the dotfiles repo)
