# Design Exemplars

Worked examples of Scott's design/review judgment, mined from all ~1,629
sessions (2026-05 through 2026-07). Each is a real episode: what was proposed,
what he rejected or accepted, and the visible reasoning. Use these as few-shot
calibration when authoring or reviewing a design doc, auditing an
implementation, or deciding a judgment call the distilled rules
(`~/repos/.claude/rules/taste.md`) don't settle.

Provenance format: `session-id-prefix | project dir`. Full transcripts live
under `~/.claude/projects/<project>/<session>.jsonl`; search with
`clyde session search`.

## The process, in his own words

> "I never build with open questions, or disputes." ... design docs are
> "templated to provide a structured doc. that structure is important and is
> passed as a baton to /how-to-execute-a-plan" ... phases run "until all pass.
> once they do commit the progress on the working branch. this way we have a
> fallback point" ... at code-complete "I keep doing these passes until
> Claude, Gemini, Codex and Scott is satisfied" ... then /cli-shakedown
> "often catches another class of bugs and may be targetted fixes or another
> phase or even another design doc! ... RINSE AND REPEAT."

(c51a4c86 | -home-saidler, 2026-07-02)

## 1. Reviewers advise, the owner decides

Scott asked for option B. The agent plus both reviewers built something else
and marked his option "deferred."

> "you, the architect and the staff engineer overrode me and went with
> something else? ... I wanted it build/adopted unless some flaw was called
> out by either you, the architect or the staff engineer. so has it? or does
> it completely solve my problem once and for all. And if it does, why did
> you mark it deferred?"

Lesson: review exists to find concrete flaws, not to re-decide. Absent a named
flaw, build the owner's option. A solution that fully solves the problem is
never "deferred." (cc80ecde | claude-pricing, 2026-06-10)

## 2. "WE DONT SILENTLY DROP SHIT"

After a cross-model review, the agent folded in some fixes but left pushbacks
and open questions dangling.

> "can you fucking manage the closing of these issues. not just dropping them
> on the floor? what are you doing with the pushbacks. you must send back and
> forth with the agent supplying your rationale. WE DONT SILENTLY DROP SHIT.
> WHAT ABOUT YOUR OPEN QUESTIONS. Send those to the two agents too."

Accepted resting state: every finding has a dispositive answer communicated to
its raiser, and the doc's Open Questions section is EMPTY.
(59d90b84 | marquee, 2026-06-20)

## 3. Least-privilege must quantify the delta

Agent resisted sharing one Okta client across persona/marquee/verify with
generic least-privilege arguments.

> "speak about least priv SPECIFICALLY in these usecases ... I setup the okta
> apps for persona and marquee, they were literally identical apart from the
> name and the id. so be honest" ... "that is no different than having
> completely separate cache paths and client ids! defend yourself that it is
> not, OR NEVER MENTION IT AGAIN"

Resolution: one shared PKCE public client, its id committed with an inline
doc-comment citing Okta's docs on why that is safe, cache in `~/.cache/okta`.
Lesson: security arguments must name the actual permission delta; when
separation buys nothing, consolidate. When the human controls the constraint
(he owns the Okta org), "you can't" is invalid. And a refuted argument stays
dead. (10fa7bdb | verify, 2026-06-14)

## 4. Decompose along change frequency

Agent framed pricing updates as rebuilding ccu/cr against a shared Rust lib.

> "it was to make this repo ONLY into something that publishes the pricing
> .json via github pages AND make ccu and cr consume only the json. NOT have
> to be built against this as a rust lib ... Anthropic changes pricing data
> WAY MORE OFTEN THAN I WANT TO DEAL WITH ... The fucking logic in the shared
> rust lib IS NOT CHANGING THAT OFEN!!!"

He then pushed model names out of the type system ("we dont build types like
Opus ... a type that holds the name as a string") and kept probing until zero
rebuild triggers remained for data-only changes. (cc80ecde | claude-pricing,
2026-06-10)

## 5. State the ideal, then price it; design across the replica boundary

View counts showed 0 after a real view; the agent explained flush lag as
"working as intended."

> "you think that fucking makes sense and is 'working as intended?'" ...
> "I will tell you want I want. I want perfect counts, instantly. We have s3,
> sqlite3, and a running webserver (axum). what does it take to achieve
> that?" ... "is this going to be architected in such a way that when replica
> is 1, all complexity falls away ... or does that architecture require this
> complexity even when replicas are 1 and still resolves to the correct
> count. tell me about how this arch plays across that 1 -> 2+ boundary"

He accepted the robust design, recorded the rejected cost optimization as a
doc addendum ("we are rejecting doing this work for now, but we want to write
it down"), and scolded re-flagging of the settled replica question.
(4f61fd82 | marquee, 2026-06-24)

## 6. Name kludge-mode and step back

Slack unfurl previews accumulated patch-on-patch options.

> "this whole area and issue feels wonky to me. not architecturally settled.
> it seems like we are in full-on kludge-mode. can we step back and think
> about what is really going on here and if this is the best way. perhaps
> search for and read some published literature on slack unfurl/preview
> semantics and how Slack and others recommend doing it, like a professional."

Resolution: pragmatic option A now, aspiration B recorded as an addendum, all
through a design doc. (cf6df9c6 | marquee, 2026-06-25)

## 7. Derived fields never diverge

Marquee stored a display title and a separately-editable slug that drifted.

> "I dont fucking read a page of bullshit. WHY ARE THESE NOT EXACTLY THE SAME?
> ALWAYS!" ... "why would they EVER be assumed to be two separate fields.
> scour my docs. did I EVER express that as a design requirement?" ... "fix it
> so slug always equals slugified title; do we need to drop a field that
> should have never been created?" ... "the only one that can differ is the
> s3 slug path and for cause"

Lesson: an invented second field is an unrequested design decision. Invariants
(X always equals f(Y)) beat synchronization logic; exceptions only with
explicit cause; constraints that can't be met get surfaced, not relaxed.
(010e3b2e | marquee-slug-alignment, 2026-07-01)

## 8. An impossibility claim must survive the obvious composition

Agent's root-cause analysis concluded "there is no correct way to use bump on
a gated repo."

> "I disagree. you just do the entire PR fucking dance and land that shit on
> main, then run bump. Whats so fucking hard?"

Then the durable fix: fold the gated flow into the `bump` tool itself via a
design doc, and tighten the config invariant in github-setup. Recurring
process failures get fixed in the tool and the rails, not per session.
(067afb22 | -home-saidler, 2026-06-12)

## 9. Never fabricate process

Agent reported "review pass 1/5" for a doc that had never gone through
/create-design-doc.

> "I dont know what review pass 1/5 means. That is not spelled out in the
> /create-design-doc skill. Is that something you made up?" ... "are you
> saying you have NOT run this through /create-design-doc ? yes or no?"

Lesson: process counters and methodology claims are audited word for word
against the actual skill definitions. When the user asks "do we have enough
for a design doc?", the correct move is to invoke the skill, not simulate it.
(d4f786b1 | -home-saidler, 2026-06-22)

## 10. "Discipline is on you" is an empty statement

After an agent violated a rule it knew about, it offered to be more careful.

> "you saying 'discipline is on you' is an empty statement. you should stop
> saying it. you have ZERO method of making a change to prevent your behavior
> in the future. Whatever let you fuck it up today will still be present
> tomorrow."

Accepted remediation: an env-redaction shim plus a secret-echo-guard hook,
committed with cross-links between them. Post-incident review must produce a
structural guard that would have prevented the specific failure.
(8881f301 | scottidler-claude, 2026-06-27)

## 11. Infra that can't weld to the auth edge is dead

A token-vending service got built down a Lambda path with no SSO-gated HTTP
edge.

> "we already have oauth2-proxy in EKS and now Envoy Gateway. do either of
> those help me weld auth to this pos lambda path you led me down?" ...
> "I think you have led me astray. the EKS version of this service would have
> been the better path"

He renamed the repo broken-toker, deregistered it, unwound the terraform, and
re-platformed to EKS. Decommission reason on record: "Lambda path had no
SSO-gated HTTP edge." Sunk cost never rescues a shape that can't reuse the
platform's auth boundary. (88188935 | platform-templates, 2026-07-01)

## 12. Curated surface + raw passthrough beats codegen bloat

A generated Drata client produced hundreds of types.

> "It makes me think I DONT WANT 437 types either. thoughts?" ... "nah dawg.
> I am with the reviewers. learn and harvest my style form pagerduty-cli.
> apply those learnings here"

Accepted architecture: Value-based client, curated command verticals, a
`raw METHOD path` escape hatch covering all 167 operations, and a coverage
test that fails if any operation becomes unreachable. Full reach without full
typing; curation where it earns value; consistency with his proven repo
pattern beats a novel design. (923f3a35, 7114f1fa | drata-cli, 2026-06-27)

## 13. Config that doesn't configure is pointless

Agent changed a YAML value, then baked the same value into the systemd timer.

> "you change the value in the yaml and then just back it into the timer
> hardcode? what the fuck is the point of that?" ... "that serde default is
> stupid. what say you/"

Same session: the real config moved out of the repo to dotfiles; the repo
kept ONE example "marked up with directions and comments."
(61c67432 | eratosthenes, 2026-06-10)

## 14. Regressions are fixed forward, and baseline claims get tested

Agent proposed reverting a broken auth flow to a pre-PR design.

> "NO ... this worked as recently as the tagged release v1.0.14! NOT BACK TO
> THAT OLD SHIT"

Scott then empirically tested his own claimed-good baseline, conceded it also
failed ("so no. didnt work on v1.0.14"), and still demanded the causal
question stay open: "THEN WHY DID IT BREAK". Everyone's claims get tested,
including his; the fix moves forward from the current design.
(450c27c6 | persona-cli, 2026-06-02)

## 15. Phase 0 proves the environmental assumption with zero code

The marquee publish-CLI design rested on the Envoy gateway passing Bearer API
calls through. The approved doc's Phase 0 was a pure spike: curl the deployed
endpoint with an existing persona token "to prove the gateway passes Bearer
API calls before anything is built." It survived multiple review rounds and
he executed it first. (08b07987 | marquee, 2026-06-12)

## 16. Kill the doc when ROI evaporates; ship the 5-line alternative

A manifest ETC feature went through motivation, edge investigation, a rejected
first design ("I kinda hate your solution ... I dont want to sling giant bash
files. have another think"), then:

> "ok I am going to abandon this effort. not enough ROI. rmrf the doc.
> meanwhile, update what I have exising for editing my sudoers file, to
> instead do it the drop a file into sudoers.d/ way"

Generalize a pattern only when the design survives scrutiny; when it doesn't,
kill it and ship the small change that removes the original pain.
(fe3328a1 | manifest, 2026-06-07)

## 17. Truth in naming is absolute; conformance beats local optimization

Reworking marquee CI to mirror platform-standard-ci, the agent quibbled about
a cache key and wanted to drop a platform step.

> "rename the cache key. we will never have a key say bookworm but be for
> trixie. that kind of cognitive dissonance is NEVER allowed. leave in
> check-ecr. we are trying to make the build be as much like the platorm.
> stop quibbling, just do it."

Two rulings in one message: a lying identifier is rejected even when
functionally harmless, and a redundant-looking step stays because the
governing goal is conformance to the org standard.
(fa585081 | marquee, 2026-06-18)

## 18. Defaults are opt-in; he rolls back his own features

After clone started defaulting every repo to bare+worktree checkouts:

> "They have been infected by a change to clone and addition of worktree ...
> we should 1. change clone to NOT default to barerepo+worktrees checkout
> 2. clean up any of the current repos, that do not need this treatment
> 3. figure out how to featherin this .worktree ignore file. anything else I
> missed? anything I got wrong?"

A new mechanism that silently changed fleet-wide behavior is an "infection"
even when he built it. Correct shape: opt-in per repo. Note he also invites
correction of his own remediation plan. (e5ce0e49 | gx, 2026-07-03)

## 19. Tests must bite, and work stays inspectable

Two PRs' worth of code and tests were prepared out of sight.

> "you usually show the creation of code changes. this time that has been
> totally hidden from me. I would like to test or talk about the tests that
> you wrote ... It is off putting" ... "break a test to prove it bites."

Tests aren't evidence until demonstrated to fail on broken code.
(c4cceaaa | marquee, 2026-06-15)

## 20. Acceptance criteria are assert statements

On Jira tickets, generalized to design docs during the pentest planning work:

> "there is a Custom field called Acceptance Criteria that MUST be filled
> out. this is 3-5 assert statements/phrases that evaluate to be true when
> the work is finished"

And the accepted fifth-pass behavior on a design doc: "Resolved both open
questions instead of punting ... Added Acceptance Criteria: concrete
done-conditions ... a zero dead-code-warnings check as proof the snap paths
are truly excised (not #[allow]-silenced)." Done-conditions are falsifiable,
mechanically checkable statements, not vibes. (14703cf9 | pentest,
2026-06-11; 8152b930 | second-brain, 2026-06-07)
