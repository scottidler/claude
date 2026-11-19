// voice-guard's contract: the shapes `rules.ts` returns and the rule table
// holds (docs/design/2026-11-18-voice-mod.md, Data Model).

/** `block` and `deny-outward` stop the call or reply; `warn` only tells the model. */
export type Tier = 'block' | 'deny-outward' | 'warn'

/** One rule hit: which rule, where in the tool input, and the first offending line. */
export type Violation = { rule: string; label: string; line: string }

/**
 * Where a rule runs. `outward`: only text that leaves the machine through a
 * tool call (Slack, Jira, Confluence, Marquee, `create_pr`, commit and `gh`
 * bodies). `outward-and-reply`: outward text and the final terminal reply.
 */
export type Scope = 'outward' | 'outward-and-reply'

/**
 * One row of the phrase table. `fix` is the recast instruction the model sees.
 * `source` names the VOICE.md anti-pattern (paraphrased, the private profile is
 * never quoted here) or the public source the rule comes from.
 */
export type Rule = {
    id: string
    tier: Tier
    pattern: RegExp
    scope: Scope
    fix: string
    source: string
}
