# Local Environment

## Hostnames

- `lappy` or `laptop` => `ltl-7007.lan`
- `desk` or `desktop` => `desk.lan`

## Obsidian Vault

- Location: `~/repos/scottidler/obsidian/`

## Screenshots

- GNOME screenshot tool saves to `~/Pictures/Screenshots/` (capital S on both, plural)
- Filenames: `Screenshot From YYYY-MM-DD HH-MM-SS.png` (note the literal "From" and space-hyphen time format)
- Do not guess `~/Pictures/screenshots` (lowercase) or assume `find -newermt` will surface them — verify with `ls -la` on the exact path directly, since piped `find`/`ls -lt` output has silently come back empty here before

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
- Rules load from `~/repos/.claude/rules/` ONLY via symlink: after adding a rule file to the
  repo, run `manifest -l '*' | bash` from the repo root or the rule silently never loads
- `manifest -l`/`-s` patterns are fuzzy-matched against full lines, not path globs; `'*'` is
  the reliable form
- Any change to always-on rules / CLAUDE.md / $HOME symlinks is startup config: throwaway-launch
  test before calling it done (headless `claude -p "reply OK"` from a scratch dir)

## ~/Claude (Cowork space)

- `~/Claude` is the Claude Cowork workspace (desktop app, `coworkUserFilesPath` in
  `~/.config/Claude/claude_desktop_config.json`) AND a Syncthing folder (desk / mini / lappy;
  config at `~/.local/state/syncthing/config.xml`)
- REAL FILES ONLY: Syncthing syncs symlinks as symlinks (dangling on other machines, different
  $HOME paths) and Cowork boundary-checks resolved paths, so shared content there must be real
  files. A symlink is acceptable only for deliberately desk-local content that must NOT travel
  (e.g. the voice corpus)
- Managed content is deployed there by the private keep repo's manifest (`copy/` tree =
  copy-deployed real files, `HOME/` tree = symlinks); edit at the source repo and redeploy,
  never edit deployed copies in place
- `~/Claude/README.md` and `~/Claude/writing/README.md` document this in-place
