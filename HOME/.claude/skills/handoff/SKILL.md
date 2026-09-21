---
name: handoff
description: Resume from a handoff, or write one for the next session. Resume is the default whenever a handoff for this work already exists.
argument-hint: "What the next session should focus on"
---

# handoff

Two modes. Decide which one you are in BEFORE writing anything.

## Which mode am I in?

You are **RESUMING** if any of these is true:

- a handoff document, or a summary of one, was in your context when this session started
- the user pointed you at a handoff file, a baton or tracker doc, or said "pick up", "continue", "where we left off", "you are the next session"
- a handoff file already exists for this branch or work item

Otherwise you are **WRITING**.

When in doubt, you are RESUMING. Writing a second handoff is the expensive mistake; reading one twice costs nothing.

## Resume mode

You are the receiver. Your job is to **do the work**, not to describe its state.

1. Read the handoff, then read every artifact it references by path. The handoff is an index, not the content.
2. **Re-test every blocker it claims, with a command, before you believe it.** A handoff records what was true when it was written. A restart, a merge, a deploy, or a config reload may have cleared it. An inherited claim is not evidence, and repeating one as fact is the failure this mode exists to prevent.
3. If a claimed blocker is gone, say so in one line and start the work.
4. If a claimed blocker is still real, prove it with the command output, then work every item that does not depend on it.
5. Do the next unfinished item. Then the one after that.

### Hard rules for resume mode

- **Do NOT write a new handoff.** Not to `/tmp`, not into the repo, not as a doc, not as a status summary.
- **Do NOT relocate, re-file, or "make durable" the handoff you were given.** That is not the work. If its location is genuinely wrong, say so in one line and keep going.
- **Do NOT restate the handoff back to the user.** They wrote it or they already read it.
- If you find yourself opening an editor on a document instead of running the plan, stop. You are in the wrong mode.
- The only exception: the user, in this session, explicitly asks for a handoff **after** you have completed new work. Then update the existing handoff in place. Never create a second file.

## Write mode

Write a handoff so a fresh agent can continue. Save it to **`docs/handoff/<branch>.md`** in the repo being worked, where `<branch>` is `git rev-parse --abbrev-ref HEAD`. One file per branch, committed with the work.

The path is fixed and keyed on the branch because that is what the resume side can compute without being told: `handoff-guard.sh` stats exactly that path and points the next session at it. A per-session temporary location cannot be found by anything and dies with the session that wrote it. If HEAD is detached or the work is not in a repo, ask the user where it goes rather than inventing a throwaway location.

- Do not duplicate what other artifacts already hold (design docs, plans, ADRs, issues, commits, diffs). Reference them by path or URL.
- **Name the commits.** The branch, its HEAD sha, and what landed in each commit that matters. A receiver who cannot tell which commits are yours re-derives the diff.
- **Name the PR URL** if one is open, with its CI and review state at the time of writing.
- **List the read-first paths**, in order, as the first thing the receiver should open. The handoff is an index; this is its table of contents.
- **Every blocker gets the command that proves it**, so the receiver can re-run it in one step instead of taking it on faith. A blocker with no probe is a rumor.
- Mark anything time-sensitive or session-scoped as such: plugin and hook load state, cached credentials, background jobs, anything that a restart changes.
- Include a "suggested skills" section naming the skills the next agent should invoke.
- Lead with the single next action, not with history.
- Redact secrets, tokens, and personally identifiable information.
- If the user passed arguments, treat them as the next session's focus and tailor the doc to it.
- One handoff per work item. If one already exists, update it rather than adding another.
