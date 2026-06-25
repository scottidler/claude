---
name: create-repo
description: Create a new empty GitHub repo with a first commit (README + language .gitignore, optional LICENSE) via gh, then clone it locally with the clone tool. This replaces the manual GitHub-UI "create repository" click. Use whenever the user wants to make/create/start a new GitHub repo, spin up a new project, or says "create a repo", "new repo", "make me a repo on github" for either their personal account (scottidler) or work org (tatari-tv). Trigger even if they don't name gh or clone — this is the path for going from nothing to a cloned, ready-to-work repo.
user-invocable: true
allowed-tools: Bash(gh:*), Bash(clone:*), Bash(cd:*), Bash(ls:*), Bash(git:*)
---

# Create Repo

Go from nothing to a cloned, ready-to-work GitHub repo in one shot. This automates the part you'd normally do by clicking around the GitHub web UI — creating the repo *with* an initial commit — so that the `clone` tool (which needs a non-empty remote) works immediately afterward.

The first commit is what makes the repo clonable: GitHub's `gh repo create --add-readme` seeds `main` with a README, and `--gitignore <Lang>` / `--license <name>` fold the `.gitignore` and `LICENSE` into that same initial commit. Without that seed commit the remote has no branch to check out.

## Arguments

```
/create-repo <user|org> <name> [--public | --private] [--lang <Template>] [--license <name>] [--description "..."]
```

- **`<user|org>`** — *the literal word* `user` or `org`, selecting the destination:
  - `user` → owner `scottidler` (personal), GitHub account `home`, token `$GITHUB_PAT_HOME`, **defaults to public**
  - `org`  → owner `tatari-tv` (work), GitHub account `work`, token `$GITHUB_PAT_WORK`, **defaults to private**
- **`<name>`** — the repo name (just the name, not `owner/name`)
- **`--public` / `--private`** — override the per-domain default visibility above. Personal work is open by default; work-org repos are closed by default.
- **`--lang <Template>`** — `.gitignore` template, **defaults to `Rust`**. This is a GitHub gitignore template name and is **case-sensitive** (e.g. `Rust`, `Python`, `Go`, `Node`, `C++`). Pass `--lang none` to skip the `.gitignore`. If unsure a name is valid, list them with `gh api /gitignore/templates`.
- **`--license <name>`** — override the license default below (e.g. `mit`, `apache-2.0`). Pass `--license none` to force no license.
- **`--description "..."`** — optional repo description.

## Steps

### 1. Resolve destination and token

| arg   | owner       | account | token               | default visibility | default license |
|-------|-------------|---------|---------------------|--------------------|-----------------|
| `user`| `scottidler`| home    | `$GITHUB_PAT_HOME`  | **public**         | `mit`           |
| `org` | `tatari-tv` | work    | `$GITHUB_PAT_WORK`  | **private**        | *none*          |

The defaults differ because personal projects are open by default — public and MIT-licensed (matching `scaffold-rust-repo`) — while work-org repos default to private with the org's own licensing conventions. `--public`/`--private` and `--license` override either default.

### 2. Resolve visibility

Apply the per-domain default from the table above unless the user passed `--public` or `--private`, which always wins. Map the result to the `--public` or `--private` flag on `gh repo create`. (A flag is required — `gh` has no "inherit" option — so the skill always passes exactly one.)

### 3. Create the repo with its first commit

```bash
GH_TOKEN="$TOKEN" gh repo create <owner>/<name> \
  --public|--private \
  --add-readme \
  --gitignore <Template> \    # omit this flag entirely if --lang none
  --license <name> \          # omit this flag entirely if no license
  --description "..."         # omit if no description
```

`--add-readme` is what creates the seed commit on `main`; the `--gitignore` and `--license` files ride along in that same commit. Confirm `gh` prints the repo URL before moving on — if it errors (name already taken, bad token, invalid template name), stop and surface the actual error rather than proceeding to clone an empty/nonexistent remote.

### 4. Clone it with the `clone` tool

**NOTE:** `clone` is a custom tool (`~/.cargo/bin/clone`, also exposed as a shell function), **not** `git clone`. It picks the org-specific SSH key from `~/.config/clone/clone.cfg` (home key for `scottidler`, work key for `tatari-tv`). Git commit identity + signing key resolve automatically from `~/.gitconfig` and the `includeIf` work override — nothing to set per-repo. Always run it from `~/repos`.

```bash
cd ~/repos && clone <owner>/<name>
```

**Layout:** `clone` defaults to **bare layout** — it creates a bare container at `~/repos/<owner>/<name>/` (holding `.bare/`) and checks out each branch as a nested worktree. So the working copy you edit is at **`~/repos/<owner>/<name>/main`**, not the container directory itself. `cd` there to start working:

```bash
cd ~/repos/<owner>/<name>/main
```

The worktree now holds the README, `.gitignore`, and (if added) `LICENSE` on `main` from the `Initial commit` — ready to go.

## Examples

**Personal Rust repo — public + MIT by default:**
```
/create-repo user mytool --description "A tool that does things"
```
→ creates **public** `github.com/scottidler/mytool` (README, Rust `.gitignore`, MIT LICENSE in first commit) → worktree at `~/repos/scottidler/mytool/main`

**Work Python repo — private + no license by default:**
```
/create-repo org data-pipeline --lang Python
```
→ creates **private** `github.com/tatari-tv/data-pipeline` (README, Python `.gitignore`, no LICENSE) → worktree at `~/repos/tatari-tv/data-pipeline/main`

**Personal repo, kept private (override the public default), README only:**
```
/create-repo user notes --private --lang none
```
→ creates **private** `github.com/scottidler/notes` (README + MIT only) → worktree at `~/repos/scottidler/notes/main`

**Work repo published publicly (override the private default):**
```
/create-repo org public-sdk --public --lang Go
```
→ creates **public** `github.com/tatari-tv/public-sdk` (README, Go `.gitignore`, no LICENSE) → worktree at `~/repos/tatari-tv/public-sdk/main`

## Relationship to other skills

- **`clone`** — the binary/skill this uses in step 4; use it standalone to clone an *existing* repo.
- **`scaffold-rust-repo`** — when the goal is specifically a *scaffolded Rust CLI* (clap/eyre/etc.), reach for that instead; it does create-repo's job plus `scaffold`. `create-repo` is the language-agnostic, no-scaffold version.
