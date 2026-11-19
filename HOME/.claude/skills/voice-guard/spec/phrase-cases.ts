/*
 * One positive and one negative fixture per phrase-table rule. The negative
 * is a near miss in plain prose: the rule's own words used in a way it must
 * not flag. The shared traps (code fence, quote, blockquote) are applied to
 * every positive in phrases.spec.ts.
 */
export type PhraseCase = { id: string; positive: string; negative: string }

export const PHRASE_CASES: readonly PhraseCase[] = [
    { id: 'belt-and-suspenders', positive: 'CI plus the hook is belt and suspenders.', negative: 'The hook runs first, then CI reruns the lint.' },
    { id: 'q-number-ref', positive: 'Per Q3 the answer is no, and Q4a confirms it.', negative: 'Revenue in Q1 2026 grew; Q3 planning starts in June and we closed out Q2 revenue.' },
    { id: 'ac-number-ref', positive: 'This satisfies AC3 and AC-4.', negative: 'The AC unit in room 12 is broken; the AC-130 gunship is a plane.' },
    { id: 'chat-residue', positive: 'Great question. The cap is 8.', negative: 'This certainly works on the happy path; the question was great for the team.' },
    { id: 'staged-runup', positive: "Let's dive in. Honestly? The cap is 8.", negative: 'We dive into the logs when a deploy fails; honestly the logs are fine.' },
    { id: 'let-that-sink-in', positive: 'We shipped nothing in March. Let that sink in.', negative: 'The tank holds water; the sink in the kitchen drains slowly.' },
    { id: 'full-stop', positive: 'The hook is bypassed. Full stop.', negative: 'The train came to a full stop at the station.' },
    { id: 'not-only-but', positive: 'It is not only fast but also cheap.', negative: 'It is not fast. The build is cheap, but flaky.' },
    { id: 'ing-tail', positive: 'The cache was cleared, highlighting the importance of invalidation.', negative: 'The cache was cleared, and the build went green.' },
    { id: 'triad', positive: 'The tool is fast, reliable, and secure.', negative: 'The tool is fast and secure; it ran on Monday, Tuesday and again later with retries.' },
    { id: 'copula-avoidance', positive: 'The hook serves as a gate for outward text.', negative: 'The hook is a gate for outward text.' },
    { id: 'bold-label-bullet', positive: '- **Speed**: the guard runs in-process.', negative: '- The guard runs in-process.\n- **Bold** is fine when no label colon follows.' },
    { id: 'heres-leadin', positive: "Here's what changed:\n- one file", negative: 'Here is a link to the PR, which changed one file.' },
    { id: 'arguing-with-no-one', positive: "To be clear, I'm not saying the hook is wrong.", negative: 'The clear cause was the missing key; he said nothing.' },
    { id: 'about-the-document', positive: 'This document explains the rollout.', negative: 'The rollout is in three phases; the document is linked below.' },
    { id: 'ensure-word', positive: 'This ensures the hook runs.', negative: 'The insurer sent the policy; the hook runs on every call.' },
    { id: 'promote-word', positive: 'Phase 5 promotes the rule to deny.', negative: 'Phase 5 moves the rule to deny. The promoter list is empty.' },
    { id: 'emphasis-word', positive: 'It is crucial to keep the default empty.', negative: 'Keep the default empty: a false positive costs a retry.' },
]
