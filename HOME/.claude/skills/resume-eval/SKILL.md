---
name: resume-eval
description: Evaluate candidate resumes against a role rubric and produce a ranked shortlist with per-candidate probes and risks. Use when the user says "evaluate resumes", "rank these candos", "score this candidate", "resume review", or points at resumes in ~/hos/ (the hiring-search folder). Currently ships one rubric, Head of Security.
---

# resume-eval

Rank candidate resumes against a role rubric. Output goes to the hiring manager, so it is evidence-first and short.

## Inputs

- Candidate folders at `~/hos/<first-last>/`, each holding the resume PDF (Greenhouse export or original).
- A rubric at `rubrics/<role>.md` next to this file. Default: `rubrics/head-of-security.md`.
- If a candidate folder has no resume, say so and skip it. Greenhouse needs a login; this skill never fetches from it.

## Method

1. Read each resume in full (`pdftotext -layout`). The Greenhouse export wraps the resume in a cover sheet: the resume starts after the scorecard page.
2. Build a dated timeline per candidate: employer, title, start, end. Flag every overlap, gap, and stint under 2 years.
3. Score each rubric item 0-2 (0 absent, 1 implied or thin, 2 shown with evidence). Quote the resume line that grounds each score.
4. Read the order of the candidate's self-listed top accomplishments. Compare it to the rubric order. Name what is absent.
5. Check career shape: did they climb from hands-on work, or enter at exec level? Is the current level above the role?
6. Write probes: one question per risk, aimed at the screening call.
7. Rank. Break ties on trajectory and substance, not keyword match.

## Rules

- Many resumes echo the circulated JD and look AI-polished. Keyword match is low signal. Weight trajectory, tenure, and concrete outcomes over matched bullets.
- A timeline that does not reconcile (overlapping full-time titles, an employer missing from LinkedIn) is a hard flag. State it plainly and name the check: compare resume to LinkedIn.
- Missing rubric domains (for security: application security) count against the candidate even when the rest is strong.
- Over-leveled (CISO or VP empire, advisory portfolio) and under-leveled (needs a bigger org than ~324 people) both count as fit risk.
- Never invent facts. Unknown means "not on resume", not a guess.
- No effort or time estimates. No salary guesses.

## Output

Write `~/hos/<name>/evaluation.md` per candidate, then one `~/hos/RANKING.md` with all candidates.

Per candidate:

- **Verdict:** Strong Yes | Yes | No | Definitely Not, one line why.
- **Rubric table:** item, score, quoted evidence.
- **Timeline flags:** overlaps, gaps, short stints.
- **Probe:** the one or two questions that decide it.

`RANKING.md`: ranked list, each entry two to four lines (fit, probe), the way the hiring-manager thread does it.

## Voice

The ranking is outward prose under Scott's name when posted. Read `~/Claude/writing/VOICE.md` before drafting anything for Slack. The files in `~/hos/` are working notes.
