---
name: install-skills
description: Install Claude skills from a GitHub repository into Scott's environment using the manifest workflow, cloning into ~/repos/<org>/<repo> and symlinking each skill into ~/.claude/skills via manifest.yml. Use whenever the user drops a github.com URL or an org/repo slug that contains skills, says "install this skill repo", "add these skills", "install skills from <url>", or points at a repo full of SKILL.md files. Trigger even if the user just pastes a GitHub URL and says "install this"; if the repo holds skills, this is the path.
---

# install-skills

## Overview

Scott installs third-party Claude skills declaratively through `manifest`, not by
hand. The single source of truth is `~/repos/scottidler/claude/manifest.yml`: its
`github:` section lists each external repo and a `link:` map saying which
subdirectory becomes which symlink under `~/.claude/skills/`. Running `manifest`
clones the repos and creates the symlinks.

`~/.claude/skills` is itself a symlink into the `scottidler/claude` dotfiles repo,
so the `manifest.yml` edit is the durable, version-controlled record of what's
installed. Your job is to take a GitHub URL, figure out what skills it contains,
add a correct and idempotent entry to `manifest.yml`, run `manifest` scoped to
just that repo, and verify the result.

## When to Use

Triggering conditions live in the description. The one scope distinction worth
stating here: this skill is for **skills** (directories containing a `SKILL.md`).
Slash commands (`.claude/commands/*.md`) are not wired through `manifest` today;
see Limitations.

## Process

### 1. Probe the repo (read-only)

Run the bundled probe to discover what's installable. It reads the repo tree via
`gh api` (no clone yet), finds every `SKILL.md`, derives the skill name from its
containing directory, and prints a ready-to-paste `manifest.yml` snippet with
collision warnings:

```bash
~/.claude/skills/install-skills/bin/probe.sh <github-url-or-org/repo>
```

If the probe finds zero `SKILL.md` files, stop and tell the user; it isn't a
skills repo, and silently wiring nothing is worse than saying so.

### 2. Confirm the plan with the user

Show the discovered skills and the proposed link map. Surface anything that needs
judgment:

- **Collisions**: if `~/.claude/skills/<name>` already exists, do not clobber it.
  Ask whether to skip that skill, pick a different link name, or replace it.
- **Subset selection**: a repo may contain many skills; confirm the user wants all
  of them, or just the ones they named or the subpath they linked.

Why confirm: the link name is what the user types to invoke the skill, and a wrong
or colliding name is annoying to unwind once committed. Cheap to get right up front.

### 3. Edit manifest.yml idempotently

Edit `~/repos/scottidler/claude/manifest.yml`, matching the existing 2-space-indent
style exactly:

```yaml
github:
  <org>/<repo>:
    link:
      <subdir-with-SKILL.md>: ~/.claude/skills/<name>
```

- If `<org>/<repo>` is **already present** under `github:`, merge the new `link:`
  entries into its existing block. Do not add a duplicate repo key.
- If a specific link line already exists, leave it; don't duplicate it.
- Keep entries grouped under the one repo key. One repo, one block.

### 4. Run manifest scoped to the new repo

From the dotfiles repo, generate the script for just this repo and execute it.
Scoping with `-g` keeps `manifest` from touching anything else:

```bash
cd ~/repos/scottidler/claude && manifest -g '<org>/<repo>' | bash
```

`manifest` prints a bash script to stdout (clone into `~/repos/<org>/<repo>`,
`git pull`, then `linker` each mapped path); piping to `bash` runs it. It's
idempotent and safe to re-run; an existing clone just pulls.

### 5. Verify

Confirm each new symlink resolves to a real skill, not a dangling link:

```bash
for n in <name1> <name2>; do
  tgt=$(readlink -f ~/.claude/skills/$n) || true
  if [ -f "$tgt/SKILL.md" ]; then
    echo "OK   $n -> $tgt"
  else
    echo "FAIL $n (link target has no SKILL.md)"
  fi
done
```

Then sanity-check that each `SKILL.md` has valid frontmatter with `name` and
`description`; a skill missing either won't trigger. Read the first ~10 lines of
each and confirm.

### 6. Commit the manifest change

The `manifest.yml` edit is the durable record; commit it in the dotfiles repo so
the install survives and reproduces on other machines:

```bash
cd ~/repos/scottidler/claude && git add manifest.yml && \
  git commit -m "manifest: install <name(s)> from <org>/<repo>"
```

Report back: what was installed, the invocation name(s), and any skills skipped
(collisions, non-skill repos) so the user knows the final state.

## Common Rationalizations

| Thought | Reality |
|---------|---------|
| "I'll just `git clone` and `ln -s` it directly" | That bypasses `manifest.yml`, so the install isn't recorded and won't reproduce. Always go through the manifest. |
| "The repo name is the skill name" | No. The skill name is the basename of the directory containing `SKILL.md`. A repo can hold many, nested at varying depths. Trust the probe. |
| "I'll run plain `manifest`" | Unscoped, it processes every entry. Use `-g '<org>/<repo>'` to act on only the new repo. |
| "A collision is fine, it'll overwrite" | The existing name may be a different skill the user relies on. Never clobber a name silently; ask. |

## Red Flags

- Probe returns no `SKILL.md`: not a skills repo. Stop; don't fabricate a link map.
- About to overwrite an existing `~/.claude/skills/<name>`: stop and ask.
- About to add a second `github:` key for a repo already listed: merge instead.
- A verified symlink is dangling (`readlink -f` target has no `SKILL.md`): the
  subdir path in the link map is wrong; fix it before committing.

## Limitations

- **Slash commands** (`.claude/commands/*.md`) aren't linked by the current
  `manifest.yml` (it only links the skills dir). If a repo ships commands the user
  wants, flag it; wiring commands needs a `~/.claude/commands` link target added
  to `manifest.yml` first, which is out of scope here.
- Symlink targets are absolute `~/repos/...` paths, so a skill is only live on a
  machine where `manifest` has cloned the repo. That's by design; the manifest is
  what reproduces it.
