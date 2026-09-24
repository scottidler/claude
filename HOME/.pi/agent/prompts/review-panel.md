---
description: Dispatch the Architect (Gemini) and Staff Engineer (Codex) reviewers
argument-hint: "<path to design doc>"
---
Read `~/.claude/skills/review-panel/SKILL.md` and follow it.

Doc: ${@:-the design doc we just finished}

Fan both reviewers out in parallel, not one after the other, and reconcile their findings
into a single list. Then run the consensus loop: fold in everything I agree with, send
pushbacks back to the reviewer WITH rationale, and escalate to me only what the agents
cannot close. Never silently drop or defer a finding. Cap it at three rounds unless I say
otherwise.
