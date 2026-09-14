---
alwaysApply: true
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

# Pull Requests: babysit every one we open to green

- Every time we create a PR, we OWN it to done -- do not open-and-walk-away. "Done" is CI green AND every CodeRabbit thread handled, not "PR opened."
- Babysit the PR after opening it: watch CI to completion, fix any failure, and work every CodeRabbit comment (fold in the fix, or push back with rationale on the thread). Handle simple human review comments the same way.
- CodeRabbit threads: fix -> reply on the thread -> mark it resolved. Don't leave dangling unresolved bot threads. Use `/general:coderabbit-autofix` (the extended fix+reply+resolve flow).
- Use the `general:babysit-prs` skill for the sweep; wrap it in `/loop 15m /babysit-prs` for a workday cadence when several PRs are in flight.
- Never hand a red or comment-laden PR back to Scott as "done." If something is genuinely blocked, name the concrete blocker and the evidence -- per the 2-strike / root-cause rules, not another blind retry.
- Applies to PRs on any repo, ours or work (`tatari-tv/*`).
