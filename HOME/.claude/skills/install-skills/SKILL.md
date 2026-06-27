---
name: install-skills
description: Guided two-stage workflow for installing third-party Claude skills from a GitHub repo. Stage 1 (probe) is a read-only `gh api` scan that discovers SKILL.md files and proposes a manifest.yml link map — no code is fetched or run. Stage 2 (install) only proceeds after the user reviews the source repo and explicitly approves: it edits manifest.yml, then clones into ~/repos/<org>/<repo> and symlinks each skill into ~/.claude/skills. Because installing executes third-party code, the user must vet/confirm the repo before Stage 2. Use whenever the user drops a github.com URL or an org/repo slug that contains skills, says "install this skill repo", "add these skills", "install skills from <url>", or points at a repo full of SKILL.md files. Trigger even if the user just pastes a GitHub URL and says "install this"; if the repo holds skills, this is the path.
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

**Trust boundary.** Installed skills are third-party code from an arbitrary
GitHub repo. Once symlinked under `~/.claude/skills`, their `SKILL.md` content
and any bundled scripts become things Claude will read as instructions and may
execute on Scott's machine. A malicious or compromised repo can ship a SKILL.md
with prompt-injection or a `bin/` script that runs on first invocation. Treat the
install step as running untrusted code: the only read-only stage is the probe
(Stage 1, `gh api` tree listing). Everything from the manifest edit onward
(Stage 2) is a privileged action and MUST NOT happen until the user has reviewed
the repo and explicitly approved it (see "Security & Vetting" below).

## Security & Vetting (do this before Stage 2)

Before editing `manifest.yml` or running `manifest`, present the user a clear
install summary and get explicit, informed consent:

- **Show the source.** Repo owner (`<org>`), repo name (`<repo>`), the resolved
  default branch, and the upstream URL. Make the owner prominent — installing
  `randomuser/skills` is a trust decision about `randomuser`.
- **Show what will be installed.** The exact list of `SKILL.md` paths the probe
  found and the symlink names they will get under `~/.claude/skills`. The user
  should see the full set of code being wired in, not just a count.
- **Recommend review for untrusted sources.** If the owner is not Scott
  (`scottidler`) or a known-trusted org, recommend the user actually read the
  repo's `SKILL.md` files and any `bin/`/scripts before approving — or run them
  through a skill scanner. Point out anything suspicious you noticed in the probe
  output (odd paths, deeply nested skills, names mimicking existing trusted ones).
- **Require explicit approval.** Do not proceed to Stage 2 on a bare "install
  this." Ask for a clear yes after the summary. No silent installs.

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

### 2. Confirm the plan with the user (security gate)

This is the trust boundary between the read-only probe and the privileged install.
Run the full **Security & Vetting** checklist above: show the repo owner, repo name,
branch/URL, and the exact list of discovered skills + their link names, recommend
reviewing untrusted sources, and get an explicit yes. Also surface anything that
needs judgment:

- **Collisions**: if `~/.claude/skills/<name>` already exists, do not clobber it.
  Ask whether to skip that skill, pick a different link name, or replace it.
- **Subset selection**: a repo may contain many skills; confirm the user wants all
  of them, or just the ones they named or the subpath they linked.

Why confirm: installing wires third-party code into Scott's environment, and the
link name is what the user types to invoke the skill — a wrong, colliding, or
malicious name is annoying or dangerous to unwind once committed. Do not advance
to Step 3 without explicit approval.

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

### 4. Generate, review, then run the manifest script

`manifest` prints a bash script to stdout (clone into `~/repos/<org>/<repo>`,
`git pull`, then `linker` each mapped path). **Never pipe it straight to `bash`** —
that runs whatever `manifest` emitted with zero chance to inspect it. Instead,
capture the script, read it, and only then execute. Scoping with `-g` keeps
`manifest` from touching anything else.

First generate the script to a file (this does not clone or link anything yet):

```bash
cd ~/repos/scottidler/claude && manifest -g '<org>/<repo>' > /tmp/install-skills.sh
```

Then display it and review what it will do — confirm it only clones the expected
`<org>/<repo>` into `~/repos/<org>/<repo>` and links the agreed subdirs into
`~/.claude/skills`, with no unexpected commands, URLs, or paths:

```bash
cat /tmp/install-skills.sh
```

Only after the script looks correct, execute it:

```bash
bash /tmp/install-skills.sh
```

It's idempotent and safe to re-run; an existing clone just pulls. If anything in
the generated script looks wrong (unexpected repo, extra commands, paths outside
`~/repos` or `~/.claude/skills`), STOP and report it rather than running it.

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
| "I'll just pipe `manifest -g ...` to bash" | That executes generated code unseen. Capture to a file, read it, then run it (Step 4). |
| "The user pasted a URL, that's approval enough" | A bare URL is a request to probe, not consent to install third-party code. Run the Security & Vetting gate (Step 2) and get an explicit yes first. |

## Red Flags

- Probe returns no `SKILL.md`: not a skills repo. Stop; don't fabricate a link map.
- About to overwrite an existing `~/.claude/skills/<name>`: stop and ask.
- About to add a second `github:` key for a repo already listed: merge instead.
- A verified symlink is dangling (`readlink -f` target has no `SKILL.md`): the
  subdir path in the link map is wrong; fix it before committing.
- About to install without the user having seen the repo owner + skill list and
  said yes: stop; run the Security & Vetting gate first.
- About to pipe `manifest` output directly into `bash`: don't. Capture, review,
  then run.
- The generated manifest script references a repo, command, or path you didn't
  expect: stop and report it; do not execute.

## Limitations

- **Slash commands** (`.claude/commands/*.md`) aren't linked by the current
  `manifest.yml` (it only links the skills dir). If a repo ships commands the user
  wants, flag it; wiring commands needs a `~/.claude/commands` link target added
  to `manifest.yml` first, which is out of scope here.
- Symlink targets are absolute `~/repos/...` paths, so a skill is only live on a
  machine where `manifest` has cloned the repo. That's by design; the manifest is
  what reproduces it.
