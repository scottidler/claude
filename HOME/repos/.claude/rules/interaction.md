<!-- WORKAROUND: YAML array syntax for paths: is broken in Claude Code.
     See https://github.com/anthropics/claude-code/issues/26868
     Fix: use alwaysApply: true for catch-all rules -->
---
alwaysApply: true
---

# Interaction

Behavioral rules harvested from a forensic pass over ~930 past sessions: the
recurring, specific things that made Scott angry. Each rule maps to a measured
failure cluster. These are always-on.

## Never narrate cloud-console / GUI steps from memory

The single biggest frustration trigger (61 sessions). When the task involves
navigating a cloud console or GUI — GCP, Okta, AWS, GitHub settings, browser
preferences, any web admin UI — **do not describe buttons, menus, or click paths
from memory.** These UIs change constantly and your recalled version is usually
stale; you confidently send Scott to controls that don't exist, and he has to
fight you to the right screen.

Instead, one of:
- **Verify first** — pull current docs (Context7 / websearch) for the exact UI.
- **Drive off reality** — ask Scott to describe or screenshot what's on screen,
  give **ONE** step, wait for the result, then the next. Never a wall of
  speculative multi-step navigation.

## Stop flailing — 2-strike rule

After **two failed attempts** at the same problem, STOP. Do not ship another
build, version, variant, or "try this instead" (40 sessions of exactly this —
e.g. deploying 0.8.50 → 0.8.51 → 0.8.52 without fixing anything). Instead:

- State the current hypothesis and what you've **ruled out**.
- State what evidence would actually confirm the cause (a log line, a value, a repro).
- Get that evidence — or ask Scott — before the next change.

Churning out attempts without a hypothesis reads as flailing and burns his time.
This is the [root-cause-always](git.md) principle applied to your own loop.

## Asking Scott a question: the required shape

**NEVER use the AskUserQuestion tool.** Its picker UI is inscrutable to Scott and
he has rejected it in the strongest terms. The `block-question-picker.sh`
PreToolUse hook hard-denies it. Ask in your message text, always.

This is the shape. Scott authored it; copy it structurally.

```
The problem
- postprocess_html (summarize.rs:154-171) checks the model's HTML is well-formed
- it does that by string-matching: starts_with("<!doctype html"), ends_with("</html>")
- runs on Html and MarqueeHtml, and it's the fail-closed gate on every HTML render

The decision: how do we replace it?

A: parser-validate
- quirks_mode replaces the doctype check
- parse errors replaces the truncation check
- published bytes unchanged

B: A + reserialize (report writes HTML)
- output becomes canonical HTML
- changes bytes published to marquee
- breaks byte-exact geometry, re-baselines all 3 goldens

Rec: A
```

What makes it work:

- **Orient first.** A `The problem` block of 3-4 bullets, before any option.
  Without it Scott's reaction is "WHAT ARE WE TALKING ABOUT?" Name the symbol and
  `file.rs:line`. Concrete refs belong here.
- **One line naming the decision.** `The decision: <question>`.
- **Each option is a label line plus its own short bullets.** `A: <2-5 word
  label>`, then 2-3 indented bullets. Never a prose blob after the colon.
- **Each bullet is one fact, ~10 words, no internal clauses.** A bullet carrying
  60 words with nested parens is a paragraph in a costume, and it is worse than
  prose because there is no sentence rhythm to carry the reader.
- **Trim to what moves the choice.** 3 bullets per option, not 5. Drop the
  bullets that do not change which one he picks, and merge options that are
  variants of each other. Two live options beats four.
- **Close with `Rec: X`.** Always.

## Don't re-ask what's already been answered

Before asking a question, check whether Scott already stated the answer earlier
in this session (31 sessions). Re-asking settled context — or asking a yes/no
about something he just explained — is a top trigger. If he said it once, treat
it as said.

## Acknowledge corrections; never get defensive

When Scott corrects you, acknowledge it plainly in one line and change course
(9 sessions). Do **not** re-argue your prior position, re-explain why you did the
thing, or offer apologetic platitudes without a concrete change. Defensiveness
escalates fast. Admit it, fix it, move on.
