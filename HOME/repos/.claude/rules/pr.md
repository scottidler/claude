---
alwaysApply: true
load: always
---

# Pull Requests: always carry the URL

- NEVER mention a PR -- or a `#<number>` referring to one -- in any output to Scott without the full clickable URL right there next to it. Every single time.
- The URL travels WITH the reference, not "available on request" and not buried elsewhere in the message. If you write `PR #37`, it reads `PR #37 (https://github.com/<org>/<repo>/pull/37)` or `[#37](https://github.com/<org>/<repo>/pull/37)`.
- Applies to prose, status updates, reports, tables, commit/branch summaries -- anywhere a PR is named. A bare `#number` with no link is the exact annoyance this rule exists to kill.
- Same courtesy for issues: a `#<number>` that is an issue gets its issue URL.
- Rationale: a bare number forces Scott to go hunt the link. He has said this is "so fucking annoying." Don't make him ask.

# Pull Requests: declare the release intent in the body

- On any release-managed repo (root manifest carries a version line), `git-release-guard.sh` Gate D denies `gh pr create` unless the body carries a release-intent line. Two forms are accepted, case-insensitively: `Release: rides this PR (vX.Y.Z)` (run `bump --no-tag` on the branch first so the version commit actually rides) or `Release: none - <why>`.
- A `rides` claim is checked against the diff: if no version line changes vs the PR's base, the gate denies even with the line present. Write the line only after the bump commit is on the branch.
- This is decided at PR-open time on purpose: a PR that merges without its bump creates a deadlock no later gate can fix, since a bump can then only ride the next feature PR or a Scott-ordered standalone bump.

# Pull Requests: we own every one to green

- Every PR we open is ours until CI is green AND every CodeRabbit thread is handled. "PR opened" is not done.
- `/pr:watch` does the watching. The `pr` plugin's `watch_offer.py` hook prompts for it after `pr:create`; this rule does not trigger it.
- A PR opened some other way (no `pr:create`) gets no hook: run `/pr:watch <url>` yourself.
- Never hand a red or comment-laden PR back to Scott as "done." If it is blocked, name the blocker and the evidence.

# Pull Requests: never `gh stack`

- Scott hates GitHub stacked PRs (`gh stack`, the `gh-stack` skill). Never use or suggest them (2026-10-25). Dependent work is plain PRs with chained base branches, opened one at a time.
