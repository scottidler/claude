---
name: create-repo
description: Create a new GitHub repo with a first commit (README + language .gitignore, optional LICENSE) via gh, then clone it locally with the clone tool. This replaces the manual GitHub-UI "create repository" click. Use whenever the user wants to make/create/start a new GitHub repo, spin up a new project, or says "create a repo", "new repo", "make me a repo on github" for either their personal account (scottidler) or work org (tatari-tv). Trigger even if they don't name gh or clone — this is the path for going from nothing to a cloned, ready-to-work repo.
user-invocable: true
allowed-tools: Bash(env:*), Bash(gh:*), Bash(clone:*), Bash(cd:*), Bash(ls:*), Bash(git:*)
---

# Create Repo

Go from nothing to a cloned, ready-to-work GitHub repo in one shot. This automates the part you'd normally do by clicking around the GitHub web UI — creating the repo *with* an initial commit — so that the `clone` tool (which needs a non-empty remote) works immediately afterward.

The first commit is what makes the repo clonable: GitHub's `gh repo create --add-readme` seeds `main` with a README, and `--gitignore <Lang>` / `--license <name>` fold the `.gitignore` and `LICENSE` into that same initial commit. Without that seed commit the remote has no branch to check out.

## Arguments

```
/create-repo <name | owner/name> [--public | --private] [--lang <Template>] [--license <name>] [--description "..."]
```

- **`<name | owner/name>`** — the repo to create. A bare `name` defaults to owner `scottidler`; pass `owner/name` to target a specific owner (e.g. `tatari-tv/some-service`).
- **Persona is auto-detected from the slug** — there is no `user`/`org` argument. If the slug contains `tatari-tv`, the **work** identity is used (account `work`, token `$GITHUB_PAT_WORK`, **defaults to private**); otherwise the **home** identity is used (owner `scottidler`, account `home`, token `$GITHUB_PAT_HOME`, **defaults to public**). This mirrors how `clone` picks its SSH key from the owner.
- **`--public` / `--private`** — override the per-persona default visibility above. Personal work is open by default; work-org repos are closed by default.
- **`--lang <Template>`** — `.gitignore` template, **defaults to `Rust`**. This is a GitHub gitignore template name and is **case-sensitive** (e.g. `Rust`, `Python`, `Go`, `Node`, `C++`). Pass `--lang none` to skip the `.gitignore`. If unsure a name is valid, list them with `gh api /gitignore/templates`.
- **`--license <name>`** — override the license default below (e.g. `mit`, `apache-2.0`). Pass `--license none` to force no license.
- **`--description "..."`** — optional repo description.

## Steps

### 1. Resolve persona, owner, and token from the slug

Split the argument on `/`: if it contains a `/`, the left side is the owner; a bare name implies owner `scottidler`. Then pick the persona by testing the slug for `tatari-tv`:

| slug                 | owner                            | account | token               | default visibility | default license |
|----------------------|----------------------------------|---------|---------------------|--------------------|-----------------|
| no `tatari-tv`       | from slug (bare → `scottidler`)  | home    | `$GITHUB_PAT_HOME`  | **public**         | `mit`           |
| contains `tatari-tv` | `tatari-tv`                      | work    | `$GITHUB_PAT_WORK`  | **private**        | *none*          |

Owner always comes from the slug (the left side of `owner/name`, or `scottidler` for a bare name); the `tatari-tv` test selects only the persona/token/visibility/license, not the owner. So a non-`scottidler`, non-`tatari-tv` slug like `someorg/myrepo` keeps owner `someorg` and the home persona.

The defaults differ because personal projects are open by default — public and MIT-licensed (matching `scaffold-rust-repo`) — while work-org repos default to private with the org's own licensing conventions. `--public`/`--private` and `--license` override either default.

This is the same owner→identity rule `clone` uses (`[org.tatari-tv]` vs `[org.default]` in `clone.cfg`), just selecting a `gh` token instead of an SSH key.

### 2. Resolve visibility

Apply the per-domain default from the table above unless the user passed `--public` or `--private`, which always wins. Map the result to the `--public` or `--private` flag on `gh repo create`. (A flag is required — `gh` has no "inherit" option — so the skill always passes exactly one.)

### 3. Create the repo with its first commit

```bash
env GH_TOKEN="$TOKEN" gh repo create <owner>/<name> \
  --public \                  # or --private — exactly one, per step 2
  --add-readme \
  --gitignore <Template> \    # omit this flag entirely if --lang none
  --license <name> \          # omit this flag entirely if no license
  --description "..."         # omit if no description
```

The `env GH_TOKEN="$TOKEN"` prefix is **load-bearing**: an ambient `GH_TOKEN` is already exported in the shell pointing at the *work* account (`escote-tatari`), so a bare `gh repo create` would create personal repos under the wrong identity. Setting it via `env …` (rather than an inline `GH_TOKEN=… gh …`) also keeps the first token of the command `env`, so it matches the `Bash(env:*)`/`Bash(gh:*)` allowlist and runs without a permission prompt.

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

**Personal Rust repo — public + MIT by default (bare name → `scottidler`):**
```
/create-repo mytool --description "A tool that does things"
```
→ creates **public** `github.com/scottidler/mytool` (README, Rust `.gitignore`, MIT LICENSE in first commit) → worktree at `~/repos/scottidler/mytool/main`

**Work Python repo — private + no license by default (`tatari-tv` slug → work):**
```
/create-repo tatari-tv/data-pipeline --lang Python
```
→ creates **private** `github.com/tatari-tv/data-pipeline` (README, Python `.gitignore`, no LICENSE) → worktree at `~/repos/tatari-tv/data-pipeline/main`

**Personal repo, kept private (override the public default), README only:**
```
/create-repo notes --private --lang none
```
→ creates **private** `github.com/scottidler/notes` (README + MIT only) → worktree at `~/repos/scottidler/notes/main`

**Work repo published publicly (override the private default):**
```
/create-repo tatari-tv/public-sdk --public --lang Go
```
→ creates **public** `github.com/tatari-tv/public-sdk` (README, Go `.gitignore`, no LICENSE) → worktree at `~/repos/tatari-tv/public-sdk/main`

## Relationship to other skills

- **`clone`** — the binary/skill this uses in step 4; use it standalone to clone an *existing* repo.
- **`scaffold-rust-repo`** — when the goal is specifically a *scaffolded Rust CLI* (clap/eyre/etc.), reach for that instead; it does create-repo's job plus `scaffold`. `create-repo` is the language-agnostic, no-scaffold version.
