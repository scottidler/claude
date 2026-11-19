import { describe, expect, test } from 'bun:test'
import {
    DENYABLE_IDS, RULES, denyIdsFrom, judgeOutward, judgeProse, outwardHeredocText, outwardTexts, proseOf, ruleReason, verdictOf, warnText,
} from '../hooks/rules.ts'
import { PHRASE_CASES } from './phrase-cases.ts'

const ids = (text: string, where: 'outward' | 'reply' = 'outward') => judgeProse(text, where, true).map((h) => h.rule)

describe('phrase table shape', () => {
    test('every rule has a fixture, and every fixture a rule', () => {
        expect(PHRASE_CASES.map((c) => c.id).sort()).toEqual(RULES.map((r) => r.id).sort())
    })
    test('rule ids are unique and every rule names a source and a fix', () => {
        expect(new Set(RULES.map((r) => r.id)).size).toBe(RULES.length)
        for (const r of RULES) {
            expect(r.fix.length).toBeGreaterThan(0)
            expect(r.source.length).toBeGreaterThan(0)
            expect(r.pattern.global).toBe(false)
        }
    })
    test('no rule text carries a literal em-dash', () => {
        for (const r of RULES) { expect(r.fix + r.source + r.pattern.source).not.toContain(String.fromCharCode(0x2014)) }
    })
})

describe('one positive and one negative per rule', () => {
    for (const c of PHRASE_CASES) {
        test(c.id + ': positive fixture hits this rule', () => expect(ids(c.positive)).toContain(c.id))
        test(c.id + ': negative fixture does not hit this rule', () => expect(ids(c.negative)).not.toContain(c.id))
    }
})

describe('shared traps, applied to every rule', () => {
    for (const c of PHRASE_CASES) {
        test(c.id + ': inside a code fence', () => expect(ids('Intro line.\n```\n' + c.positive + '\n```\nOutro line.')).not.toContain(c.id))
        test(c.id + ': inside a tilde fence', () => expect(ids('~~~sh\n' + c.positive + '\n~~~\n')).not.toContain(c.id))
        test(c.id + ': inside an unterminated fence', () => expect(ids('Intro.\n```\n' + c.positive + '\n')).not.toContain(c.id))
        test(c.id + ': inside inline code', () => expect(ids('The pattern `' + c.positive.replace(/\n/g, ' ') + '` is banned.')).not.toContain(c.id))
        test(c.id + ': as a quoted phrase', () => expect(ids('The rule bans "' + c.positive.replace(/\n/g, ' ').replace(/"/g, '') + '" outright.')).not.toContain(c.id))
        test(c.id + ': in a blockquote line', () => expect(ids('> ' + c.positive.replace(/\n/g, ' ') + '\n')).not.toContain(c.id))
    }
})

describe('fiscal Q1 and friends', () => {
    test('a bare fiscal quarter is not a question reference', () => {
        for (const t of ['Q1 2026 was strong', 'in Q1 we shipped', 'Q3 planning', 'last Q2', 'FY26 Q4 close', "Q1'26 numbers", 'by Q4 we ship', 'Training 2026 Q2: a doc']) {
            expect(ids(t)).not.toContain('q-number-ref')
        }
    })
    test('a bare Q-number with no fiscal word is a reference', () => expect(ids('Q1 is NEGATIVE')).toContain('q-number-ref'))
    test('a lettered Q ref is a reference even beside fiscal words', () => expect(ids('Q4a in Q4 2026')).toContain('q-number-ref'))
    test('the curly-quote year form is not a reference either', () => {
        expect(ids('Q1' + String.fromCharCode(0x2019) + '26 numbers')).not.toContain('q-number-ref')
    })
})

describe('chat-residue and full-stop sentence anchors', () => {
    test('Certainly opens a sentence: hit', () => expect(ids('Done. Certainly, here it is.')).toContain('chat-residue'))
    test('certainly mid-sentence: no hit', () => expect(ids('This certainly works.')).not.toContain('chat-residue'))
    test('the curly apostrophe form of you\'re absolutely right: hit', () => {
        expect(ids('You' + String.fromCharCode(0x2019) + 're absolutely right about that.')).toContain('chat-residue')
    })
    test('Full stop. opening a sentence: hit', () => expect(ids('It is blocked. Full stop.')).toContain('full-stop'))
    test('a full stop inside a sentence: no hit', () => expect(ids('It came to a full stop. Then it moved.')).not.toContain('full-stop'))
})

describe('proseOf', () => {
    test('removes fences, inline code, blockquotes and quoted spans', () => {
        const out = proseOf('keep\n```\ngone1\n```\n`gone2` and "gone3"\n> gone4\nend')
        expect(out).toContain('keep')
        expect(out).toContain('end')
        for (const g of ['gone1', 'gone2', 'gone3', 'gone4']) { expect(out).not.toContain(g) }
    })
    test('curly-quoted spans are removed too', () => {
        const out = proseOf('a ' + String.fromCharCode(0x201c) + 'gone' + String.fromCharCode(0x201d) + ' b')
        expect(out).not.toContain('gone')
    })
    test('an apostrophe is not a quote: text after it survives', () => {
        expect(proseOf("it's here and Q4a is there")).toContain('Q4a')
    })
    test('empty text is empty', () => expect(proseOf('')).toBe(''))
})

describe('proseOf in a shell command', () => {
    test('the message inside git commit -m "..." is judged, not stripped as a quoted span', () => {
        expect(proseOf('git commit -m "Great question"', true)).toContain('Great question')
        expect(proseOf('git commit -m "Great question"', false)).not.toContain('Great question')
    })
    test('a quoted phrase on a heredoc body line still goes', () => {
        const t = proseOf("git commit -F - <<'M'\nthe table bans \"Great question\" outright\nM", true)
        expect(t).not.toContain('Great question')
    })
    test('a double-quoted phrase on a non-outward line goes', () => {
        expect(proseOf('echo "Great question"\ngit commit -m x', true)).not.toContain('Great question')
    })
})

describe('judgeProse scope and tiers', () => {
    test('a reply gets warn rules only: a deny-outward phrase is not judged', () => {
        expect(ids('Great question.', 'reply')).toEqual([])
        expect(ids('It serves as a gate.', 'reply')).toEqual(['copula-avoidance'])
    })
    test('outward runs both tiers; includeWarn false drops the warn rules', () => {
        expect(ids('Great question. It serves as a gate.')).toEqual(['chat-residue', 'copula-avoidance'])
        expect(judgeProse('Great question. It serves as a gate.', 'outward', false).map((h) => h.rule)).toEqual(['chat-residue'])
    })
    test('clean prose has no hits', () => expect(ids('The guard runs in-process: CI is green.')).toEqual([]))
    test('a hit carries the rule line and its fix', () => {
        const [h] = judgeProse('first line\nGreat question. next', 'outward', true, 'slack text')
        expect(h).toMatchObject({ rule: 'chat-residue', label: 'slack text', tier: 'deny-outward', line: 'Great question. next' })
        expect(h?.fix.length).toBeGreaterThan(0)
    })
})

describe('outward extraction', () => {
    test('a Slack post, a Jira comment and create_pr are outward; every string is read', () => {
        expect(outwardTexts('mcp__slack__chat_post_message', { channel_id: 'C1', text: 'hi' }).map((t) => t.text)).toEqual(['C1', 'hi'])
        expect(outwardTexts('mcp__atlassian__addCommentToJiraIssue', { body: 'x' })).toHaveLength(1)
        expect(outwardTexts('mcp__multi-account-github__create_pr', { title: 't', body: 'b' })).toHaveLength(2)
    })
    test('a commit or gh Bash command is outward; a plain Bash command is not', () => {
        expect(outwardTexts('Bash', { command: 'git commit -m "x"' })).toHaveLength(1)
        expect(outwardTexts('Bash', { command: 'gh pr create --title t' })).toHaveLength(1)
        expect(outwardTexts('Bash', { command: 'echo Great question' })).toEqual([])
        expect(outwardTexts('Bash', { command: 42 })).toEqual([])
    })
    test('Write, Edit and read-only MCP calls are not outward', () => {
        expect(outwardTexts('Write', { file_path: 'a.md', content: 'Great question.' })).toEqual([])
        expect(outwardTexts('Edit', { new_string: 'Great question.' })).toEqual([])
        expect(outwardTexts('mcp__slack__search_messages', { query: 'Great question.' })).toEqual([])
    })
    test('judgeOutward finds a phrase in a double-quoted commit -m message', () => {
        expect(judgeOutward('Bash', { command: 'git commit -m "feat: x. Belt and suspenders."' }, false).map((h) => h.rule)).toEqual(['belt-and-suspenders'])
    })
    test('judgeOutward finds a phrase in a commit heredoc body and ignores one in a quoted rule', () => {
        const hit = judgeOutward('Bash', { command: "git commit -F - <<'MSG'\nfeat(x): y\n\nBelt and suspenders.\nMSG\n" }, false)
        expect(hit.map((h) => h.rule)).toEqual(['belt-and-suspenders'])
        const quoted = judgeOutward('Bash', { command: 'git commit -m "ban \\"belt and suspenders\\" in the table"' }, false)
        expect(quoted).toEqual([])
    })
})

describe('outwardHeredocText: only the heredocs that feed an outward stage', () => {
    test('a commit -F heredoc body is kept, its terminator dropped', () => {
        const t = outwardHeredocText("git commit -F - <<'MSG'\nfeat(x): y\n\nbody line\nMSG\n")
        expect(t).toContain('body line')
        expect(t).not.toContain('MSG\nMSG')
    })
    test('a commit -m "$(cat <<EOF" body is kept', () => {
        expect(outwardHeredocText('git commit -m "$(cat <<\'EOF\'\nfeat: z\n\nbody\nEOF\n)"')).toContain('body')
    })
    test('a file-write heredoc before the commit is dropped', () => {
        const t = outwardHeredocText("cat > notes.md <<'EOF'\nAC5 is a private label\nEOF\ngit commit -m 'docs: notes'")
        expect(t).not.toContain('AC5')
        expect(t).toContain("git commit -m 'docs: notes'")
    })
    test('a python heredoc feeding a later commit is dropped; a herestring opens nothing', () => {
        expect(outwardHeredocText("python3 - <<'PY'\nQ4a = 1\nPY\ngit commit -m x")).not.toContain('Q4a')
        expect(outwardHeredocText("cat <<< 'one'\ngit commit -m x")).toContain('git commit -m x')
    })
    test('no heredoc: the command comes back as it was', () => {
        expect(outwardHeredocText('git commit -m "x"')).toBe('git commit -m "x"')
    })
    test('text before the first outward stage is not judged; text after it is', () => {
        expect(judgeOutward('Bash', { command: 'echo "AC3: ok"; git commit -m "docs: x"' }, true)).toEqual([])
        expect(outwardTexts('Bash', { command: 'echo hi && git commit -m "AC3 fails"' })[0]?.text.startsWith(' git commit')).toBe(true)
        expect(judgeOutward('Bash', { command: 'echo hi && git commit -m "AC3 fails"' }, true).map((h) => h.rule)).toEqual(['ac-number-ref'])
    })
    test('a file-write heredoc body in an outward command is not judged', () => {
        const cmd = "cat > a.md <<'EOF'\nGreat question. AC5.\nEOF\ngit commit -m 'docs: a'"
        expect(judgeOutward('Bash', { command: cmd }, true)).toEqual([])
    })
})

describe('deny_outward option', () => {
    test('names a deny-outward rule: promoted', () => {
        const { ids: promoted, unknown } = denyIdsFrom('belt-and-suspenders full-stop')
        expect([...promoted]).toEqual(['belt-and-suspenders', 'full-stop'])
        expect(unknown).toEqual([])
    })
    test('a warn rule, a typo and a non-string are ignored and reported', () => {
        const { ids: promoted, unknown } = denyIdsFrom(['copula-avoidance', 'nope', 7])
        expect(promoted.size).toBe(0)
        expect(unknown).toEqual(['copula-avoidance', 'nope', '7'])
    })
    test('the option is one space-separated string; an array is read the same way', () => {
        expect([...denyIdsFrom('belt-and-suspenders  full-stop\n').ids]).toEqual(['belt-and-suspenders', 'full-stop'])
        expect([...denyIdsFrom(['full-stop']).ids]).toEqual(['full-stop'])
        expect(denyIdsFrom('belt-and-suspenders,full-stop').unknown).toEqual(['belt-and-suspenders,full-stop'])
    })
    test('missing, empty or another type is the empty default', () => {
        expect(denyIdsFrom(undefined).ids.size).toBe(0)
        expect(denyIdsFrom('').ids.size).toBe(0)
        expect(denyIdsFrom('').unknown).toEqual([])
        expect(denyIdsFrom(7).ids.size).toBe(0)
        expect(DENYABLE_IDS).toHaveLength(7)
    })
    test('verdictOf: deny only for a promoted deny-outward rule', () => {
        const [hit] = judgeProse('Great question.', 'outward', true)
        expect(hit).toBeDefined()
        expect(verdictOf(hit!, new Set())).toBe('warn')
        expect(verdictOf(hit!, new Set(['chat-residue']))).toBe('deny')
        const [warn] = judgeProse('It serves as a gate.', 'outward', true)
        expect(verdictOf(warn!, new Set(['copula-avoidance']))).toBe('warn')
    })
})

describe('messages', () => {
    test('ruleReason names the rule, the surface, the fix and the text', () => {
        const [hit] = judgeProse('Great question.', 'outward', true, 'slack text')
        const r = ruleReason(hit!)
        expect(r).toContain('chat-residue')
        expect(r).toContain('slack text')
        expect(r).toContain('Great question.')
    })
    test('warnText is empty with no hits and lists each rule otherwise', () => {
        expect(warnText([])).toBe('')
        const t = warnText(judgeProse('It serves as a gate. This ensures it.', 'reply', true))
        expect(t).toContain('copula-avoidance')
        expect(t).toContain('ensure-word')
    })
})
