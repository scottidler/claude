---
description: Execute a phased design doc, one phase per commit, otto ci green
argument-hint: "<path to design doc>"
---
Read `~/.claude/skills/how-to-execute-a-plan/SKILL.md` and follow it.

Plan: ${@:-the design doc we just finished}

One phase at a time, fresh context per phase, tests that bite (break the code to prove the
test fails), `otto ci` green before the commit, exactly one conventional commit per phase.
Do not fold a later phase in early and do not defer anything without asking me first. Once
the plan is approved, run every phase without stopping for per-phase check-ins; stop only
for a destructive action or a genuine blocking ambiguity.
