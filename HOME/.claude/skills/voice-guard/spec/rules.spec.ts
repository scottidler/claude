import { describe, expect, test } from 'bun:test'
import { EMDASH, emdashReason, hasOutwardStage, isAllowlistedPath, judgeToolCall, stripHeredocs } from '../hooks/rules.ts'

/*
 * Ported from emdash-test.sh, case for case, in the same order. The 31 cases
 * there are the 31 `describe`/`test` rows under "emdash-test.sh parity".
 * Each takes a tool call's fields and expects a violation (deny) or none.
 */

const ESCAPE_TEXT = String.raw`\u{2014}`
const deny = (tool: string, input: Record<string, unknown>) => expect(judgeToolCall(tool, input)).not.toBeNull()
const allow = (tool: string, input: Record<string, unknown>) => expect(judgeToolCall(tool, input)).toBeNull()

const write = (file_path: string, content: string) => ['Write', { file_path, content }] as const
const edit = (file_path: string, old_string: string, new_string: string) => ['Edit', { file_path, old_string, new_string }] as const
const bash = (command: string) => ['Bash', { command }] as const
const mcp = (tool: string, input: Record<string, unknown>) => [tool, input] as const

describe('emdash-test.sh parity: Write', () => {
    test('1 deny: literal U+2014 in content', () => deny(...write('docs/note.md', `The fix landed${EMDASH}CI is green.`)))
    test('2 allow: the escape text with no literal', () => allow(...write('docs/note.md', `Assert absence with the ${ESCAPE_TEXT} form.`)))
    test('3 allow: literal under tests/fixtures/ (relative)', () => allow(...write('tests/fixtures/sample.md', `A quoted log line${EMDASH}verbatim.`)))
    test('4 allow: literal under tests/fixtures/ (absolute)', () =>
        allow(...write('/home/saidler/repos/scottidler/x/tests/fixtures/sample.md', `verbatim${EMDASH}line`)))
    test('5 deny: literal PLUS the escape text (the escape exempts nothing)', () =>
        deny(...write('docs/note.md', `Write it as ${ESCAPE_TEXT}, not as ${EMDASH} itself.`)))
    test('6 allow: literal in a .golden file', () => allow(...write('crates/x/golden/out.golden', `rendered${EMDASH}output`)))
    test('7 deny: literal in a plain .json file (no longer exempt)', () => deny(...write('data/fixture.json', `{"s":"a${EMDASH}b"}`)))
    test('8 allow: literal in a .json UNDER tests/fixtures/', () => allow(...write('tests/fixtures/payload.json', `{"s":"a${EMDASH}b"}`)))
    test('9 allow: clean content', () => allow(...write('docs/note.md', 'The fix landed: CI is green.')))
})

describe('emdash-test.sh parity: Edit / MultiEdit / NotebookEdit', () => {
    test('10 deny: Edit new_string carries it', () => deny(...edit('docs/note.md', 'old text', `new${EMDASH}text`)))
    test('11 allow: Edit REMOVING it, only old_string carries it', () => allow(...edit('docs/note.md', `old${EMDASH}text`, 'old: text')))
    // 2.1.327 has no MultiEdit tool (Phase 0), but the settings matcher beneath still names it,
    // so its selector stays, inert, and shadow parity holds case for case (Phase 2).
    test('12 deny (restored in Phase 2, inert selector): MultiEdit second edit carries it', () =>
        deny('MultiEdit', { file_path: 'docs/note.md', edits: [{ old_string: 'x', new_string: 'clean one' }, { old_string: 'y', new_string: `second${EMDASH}edit` }] }))
    test('12b allow: MultiEdit removing it, only old_string carries it', () =>
        allow('MultiEdit', { file_path: 'docs/note.md', edits: [{ old_string: 'x', new_string: 'clean one' }, { old_string: `second${EMDASH}edit`, new_string: 'second: edit' }] }))
    test('13 allow: MultiEdit, neither edit carries it', () =>
        allow('MultiEdit', { file_path: 'docs/note.md', edits: [{ old_string: 'x', new_string: 'clean one' }, { old_string: 'y', new_string: 'clean two' }] }))
    test('14 deny: NotebookEdit new_source carries it', () =>
        deny('NotebookEdit', { notebook_path: 'nb.ipynb', cell_id: 'c1', new_source: `# heading${EMDASH}subtitle` }))
})

describe('emdash-test.sh parity: Bash outward stages only', () => {
    test('15 deny: git commit -m carrying it', () => deny(...bash(`git commit -m "fix the thing${EMDASH}it was broken"`)))
    test('16 allow: rg for the character, no outward stage', () => allow(...bash(`rg -n '${EMDASH}' docs/`)))
    test('17 allow: git commit with a clean message', () => allow(...bash("git add -A && git commit -m 'fix the thing: it was broken'")))
    test('18 deny: git -C <dir> commit carrying it', () =>
        deny(...bash(`git -C /home/saidler/repos/scottidler/claude commit -m "a${EMDASH}b"`)))
    test('19 deny: commit message arriving by heredoc', () =>
        deny(...bash(`git commit -F - <<'MSG'\nfeat(x): thing\n\nbody line${EMDASH}still the body\nMSG\n`)))
    test('20 allow: heredoc body mentions git commit, the command is a cat', () =>
        allow(...bash(`cat > notes.md <<'EOF'\nrun git commit after the${EMDASH}fix\nEOF\n`)))
    test('21 deny: gh pr create --title carrying it', () =>
        deny(...bash(`gh pr create --title "feat(hooks): em-dash guard${EMDASH}phase 3" --body-file body.md`)))
    test('22 deny: gh issue comment carrying it', () => deny(...bash(`gh issue comment 12 --body 'landed${EMDASH}see the PR'`)))
    test('23 allow: git log grepping for it (not an outward stage)', () => allow(...bash(`git log --oneline | grep -F '${EMDASH}'`)))
    test('24 allow: empty command', () => allow(...bash('')))
})

describe('emdash-test.sh parity: MCP posts', () => {
    test('25 deny: slack chat_post_message text', () =>
        deny(...mcp('mcp__slack__chat_post_message', { channel_id: 'C123', text: `shipped${EMDASH}green CI` })))
    test('26 allow: slack chat_post_message, clean text', () =>
        allow(...mcp('mcp__slack__chat_post_message', { channel_id: 'C123', text: 'shipped: green CI' })))
    test('27 deny: atlassian confluence page, nested string', () =>
        deny(...mcp('mcp__atlassian__createConfluencePage', { spaceKey: 'ENG', title: 't', body: { representation: 'storage', value: `a${EMDASH}b` } })))
    test('28 deny: marquee publish body', () =>
        deny(...mcp('mcp__marquee__marquee_publish', { space: '~scott-idler', slug: 's', content: `a${EMDASH}b` })))
})

describe('emdash-test.sh parity: pass-throughs', () => {
    test('29 allow: an unmatched tool (Read) carrying it', () => allow('Read', { file_path: `docs/a${EMDASH}b.md` }))
    // The hook parsed a payload; the mod is handed fields. A call with no readable fields is the same case.
    test('30 allow: malformed payload, no usable fields', () => {
        allow('Write', { content: 42 })
        allow('Bash', { command: ['not', 'a string'] })
    })
    test('31 allow: empty payload', () => {
        allow('', {})
        allow('Write', {})
    })
})

describe('judgeToolCall detail', () => {
    test('names the label and the first offending line', () => {
        const v = judgeToolCall('Write', { file_path: 'a.md', content: `clean\nbad${EMDASH}line\nlater${EMDASH}one` })
        expect(v).toEqual({ rule: 'emdash', label: 'Write content', line: `bad${EMDASH}line` })
    })

    test('an mcp label carries the dotted path of the string', () => {
        const v = judgeToolCall('mcp__x__y', { a: [{ b: `1${EMDASH}2` }] })
        expect(v?.label).toBe('mcp__x__y a.0.b')
    })

    test('the offending line is cut to 200 codepoints, not bytes', () => {
        const v = judgeToolCall('Write', { content: EMDASH + 'x'.repeat(500) })
        expect(Array.from(v?.line ?? '').length).toBe(200)
    })

    test('a notebook path under tests/fixtures/ is allowlisted', () => {
        allow('NotebookEdit', { notebook_path: 'tests/fixtures/nb.ipynb', new_source: `a${EMDASH}b` })
    })
})

describe('isAllowlistedPath', () => {
    test('fixtures dir and golden files pass', () => {
        expect(isAllowlistedPath('tests/fixtures/a.md')).toBe(true)
        expect(isAllowlistedPath('/r/tests/fixtures/a.md')).toBe(true)
        expect(isAllowlistedPath('x/out.golden')).toBe(true)
    })

    test('a plain json, a lookalike dir and the empty path do not', () => {
        expect(isAllowlistedPath('data/fixture.json')).toBe(false)
        expect(isAllowlistedPath('mytests/fixtures/a.md')).toBe(false)
        expect(isAllowlistedPath('')).toBe(false)
    })
})

describe('stripHeredocs', () => {
    test('drops the body and terminator, keeps the opener line', () => {
        expect(stripHeredocs("cat <<'EOF'\nbody\nEOF\nnext")).toBe("cat <<'EOF'\nnext")
    })

    test('two openers on one line queue in order', () => {
        expect(stripHeredocs('f <<A <<B\na body\nA\nb body\nB\nafter')).toBe('f <<A <<B\nafter')
    })

    test('<<- allows an indented terminator; plain << does not', () => {
        expect(stripHeredocs('c <<-E\n\tbody\n\tE\nafter')).toBe('c <<-E\nafter')
        expect(stripHeredocs('c <<E\n\tE\nstill body\nE\nafter')).toBe('c <<E\nafter')
    })

    test('a <<< herestring opens no body', () => {
        expect(stripHeredocs('grep x <<< "git commit"\nnext')).toBe('grep x <<< "git commit"\nnext')
    })

    test('an unterminated heredoc swallows to the end', () => {
        expect(stripHeredocs('cat <<EOF\nbody\nmore')).toBe('cat <<EOF')
    })
})

describe('hasOutwardStage', () => {
    test('finds each outward form', () => {
        for (const c of ['git commit -m x', 'git -c a=b commit', 'gh pr create', 'gh pr edit 1', 'gh pr comment 1', 'gh issue list', 'gh api repos/o/r/issues/1/comments']) {
            expect(hasOutwardStage(c)).toBe(true)
        }
    })

    test('ignores lookalikes and read-only forms', () => {
        for (const c of ['git status', 'gh pr view 1', 'echo digit commit', 'git log --grep commit', '']) {
            expect(hasOutwardStage(c)).toBe(false)
        }
    })

    test('finds a stage after && and ignores one that lives in a heredoc body', () => {
        expect(hasOutwardStage('git add -A && git commit -m x')).toBe(true)
        expect(hasOutwardStage("cat <<'E'\ngit commit\nE")).toBe(false)
    })
})

describe('emdashReason', () => {
    test('uses the hook text and quotes the line', () => {
        const text = emdashReason({ rule: 'emdash', label: 'Write content', line: 'bad line' })
        expect(text).toBe('em-dash (U+2014) in Write content; recast with a colon, parens, comma, or a split sentence (rules/safety.md). The offending text: "bad line"')
    })
})
