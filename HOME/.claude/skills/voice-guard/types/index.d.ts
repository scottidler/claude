// voice-guard's contract: the shapes `rules.ts` returns and the rule table
// holds (docs/design/2026-11-18-voice-mod.md, Data Model).

/** `block` and `deny-outward` stop the call or reply; `warn` only tells the model. */
export type Tier = 'block' | 'deny-outward' | 'warn'

/** One rule hit: which rule, where in the tool input, and the first offending line. */
export type Violation = { rule: string; label: string; line: string }
