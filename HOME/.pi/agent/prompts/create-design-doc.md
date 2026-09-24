---
description: Author a design doc with the Rule of Five passes
argument-hint: "<feature or problem>"
---
Read `~/.claude/skills/create-design-doc/SKILL.md` and follow it, all five passes.

Subject: ${@:-ask me what the doc is for before starting}

The doc lands at `docs/design/YYYY-MM-DD-feature-name.md`. Everything agreed goes IN the
doc: no follow-on lists, no side notes, no agent memory. Every requirement is traceable to
who asked for it, and unrequested scope is illegitimate regardless of quality. Phases are
small, countable, independently committable, each one `otto ci` green with exactly one
commit. Do not mark it ready to build while any Open Question or unresolved pushback
remains.
