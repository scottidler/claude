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

- Repo: `scottidler/dotfiles` checked out at `~/repos/scottidler/dotfiles/`
- `manifest.yml` lives at the repo root
- Consumed by `manifest` (a Rust binary from `scottidler/manifest`, installed via cargo at `~/.cargo/bin/manifest`)
- Run from the repo root: `cd ~/repos/scottidler/dotfiles && manifest | bash`
- The `HOME/` directory mirrors `$HOME` - files inside are symlinked into `~` via `manifest`
- `manifest.yml` declares: symlinks (`link:`), packages (`pkg:`, `apt:`, `dnf:`, `cargo:`, `pip3:`, `pipx:`, `npm:`, `flatpak:`), PPAs, GitHub repos to clone/build/link (`github:`), and install scripts (`script:`)
- Contains shell config, git config, tmux, vim/neovim, SSH, Rust formatting, and more
- `~/.config/manifest/identity.txt` is an age private key for decrypting secrets - backed up in 1Password

## Claude Config

- Repo: `scottidler/claude` checked out at `~/repos/scottidler/claude/`
- `manifest.yml` at the repo root links `HOME/` into `~` (same pattern as dotfiles)
- Contains Claude rules, skills, hooks, and settings
