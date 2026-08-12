---
name: babysit
description: Babysit ONLY the pull requests already named in this session - watch CI to green, fix failures, work every CodeRabbit and human review thread, report what needs the user. Use when the user says "babysit", "babysit it", "babysit them prs", "watch that PR", "drive it green", "get it mergeable", "handle the coderabbit comments", "fix the CI on that PR", or asks about the state of a PR discussed earlier in the session. This skill NEVER enumerates the user's open PRs and NEVER touches a PR the session did not name - if the request is to sweep everything, that is not this skill and the answer is to ask which PR.
---

# Babysit the PRs in front of you

## The one hard rule: session-named PRs only

The scope is exactly the PRs already named in THIS session. A PR is "named" if:

- its URL appeared (`https://github.com/<owner>/<repo>/pull/<n>`), or
- it was written as `<owner>/<repo>#<n>`, or
- this session created it, or
- the user names it in the request that triggered this skill.

Forbidden, without exception:

- `gh pr list`, `gh search prs`, `--author @me`, or any other enumeration of open PRs.
- Acting on a PR the session did not name, including "while I'm here" fixes on a
  sibling, a parent in a stack, or a PR that a named PR's comments mention.
- Treating "them prs" / "my prs" / "the prs" as license to sweep. It means the
  ones already on screen in this conversation.

**Zero named PRs in the session? STOP and ask which PR.** One question, no list,
no guessing, no default to all. This rule exists because a sweep once spent 21
background sessions on PRs the user never asked about.

## What babysitting one PR means

Work the named PRs one at a time, in this session, in the foreground. No
background fleet, no per-PR agents, no cache, no sentinels, no scheduled ticks.

1. **Read state once.** `gh pr view <n> --repo <owner>/<repo> --json number,title,baseRefName,headRefName,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup`
2. **CI red:** pull the failing job's log, find the cause, fix it, push. Two
   failed attempts at the same failure and you STOP: state the hypothesis, what
   you ruled out, and what evidence would settle it. Never ship a third blind try.
3. **CodeRabbit threads:** work each unresolved one to done, in this order, and do
   not hand back a PR with dangling bot threads:
   - **Query the threads. ALWAYS. `statusCheckRollup` is not evidence about them.**
     The `CodeRabbit` entry in the rollup is a check context reporting its own run
     state, NOT whether comments exist. `PENDING` there routinely coexists with
     comments already posted and waiting, and `SUCCESS` does not mean the threads
     are resolved. Reading the rollup and concluding "no comments yet" is the exact
     failure this bullet exists to prevent: it happened on `tatari-tv/slack-cli` #38
     (https://github.com/tatari-tv/slack-cli/pull/38), where 5 unresolved findings
     sat there while the rollup said `PENDING` and the PR got handed back as clean.
     There is no state of the rollup that lets you skip the thread query.
   - Fetch them: `gh api repos/<owner>/<repo>/pulls/<n>/comments --paginate` plus
     the GraphQL `reviewThreads` for `isResolved`.
   - To read one comment's full body it is `pulls/comments/<id>`, NOT
     `pulls/<n>/comments/<id>` (the latter 404s). Or pull bodies straight out of the
     `reviewThreads` query and skip the second round trip.
   - Fix what is right, in the code. A finding you disagree with gets a reply
     saying why, not silence.
   - Reply on the thread itself (`gh api .../pulls/<n>/comments/<id>/replies`),
     never a top-level PR comment.
   - Resolve the thread (`resolveReviewThread` mutation) once handled.
   - If CodeRabbit has not reviewed the current head, `@coderabbitai review`.
4. **Human review comments:** fix the mechanical ones and reply on the thread.
   Anything that is a judgment call about scope or design goes to the user with
   the options, not answered on their behalf under their name.
5. **Re-check** until CI is green and threads are clear, or until something needs
   the user.

## The exit gate: what you are allowed to report

Before you write a report, assert all three. If any is unknown, you have not
finished reading state, so go read it:

- unresolved review threads == 0 (from the `reviewThreads` query, never the rollup)
- every check is terminal (no `IN_PROGRESS` / `QUEUED` / `PENDING`)
- for each terminal failure: fixed and pushed, or blocked with named evidence

"CI is still running" and "CodeRabbit has not commented yet" are NOT endings. They
are the reason to keep the loop alive, not to hand the PR back. The only legitimate
early stop is a decision that genuinely needs the user (an approving review, a
scope call, a 2-strike blocker), and the report says exactly which.

**Do not hand-poll the user's patience.** If work remains and it is only a matter
of waiting, put it on a timer yourself before the turn ends:
`/loop 10m /babysit <pr-url>`. Never end a turn with "I'll check back" and no timer
armed, and never make the user ask twice for a step already written above.

## Check the base before saying one word about mergeability

`baseRefName` != the repo's default branch means the PR is **stacked**: it merges
into another PR's branch, so it is NOT mergeable to main no matter how green and
approved it looks.

For a stacked PR, report the chain and name the lowest blocked link, e.g.
`main <- 283 <- 284 (CHANGES_REQUESTED) <- 285 <- ... <- 289`. The whole stack is
blocked behind that link.

Born from 2026-08-12: two stacked PRs were reported "ready to merge" because each
was approved and green against its own base, when nothing in the stack could reach
main.

## Never

- **Never merge.** Say a PR is mergeable and let the user click.
- **Never** `git push --force` (or `--force-with-lease`) without explicit
  approval, and never rebase a branch that is merely behind a green base.
- **Never** post a top-level PR comment: it notifies humans and bumps the thread.
  Review-thread replies only. Single exception: `@coderabbitai review` when
  CodeRabbit has not reviewed the current head.
- **Never** write a message to a human colleague under the user's name. Draft it
  and let them send it.
- **Never** add cadence. If the user wants this on a timer they wrap it
  themselves: `/loop 15m /babysit`.

## Report

Per named PR, three lines at most:

- **State:** CI result, review decision, mergeable-to-main yes/no (with the stack
  chain if stacked).
- **Did:** what you changed and pushed, with the commit or thread link.
- **Needs you:** the specific decision, or nothing.

Every PR reference carries its full URL. No summary of PRs you did not touch.
