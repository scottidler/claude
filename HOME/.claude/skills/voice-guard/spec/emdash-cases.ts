/*
 * The 31 cases of emdash-test.sh as data: one table drives the real-script
 * parity spec (bun runs emdash.sh on each payload) and the engine-level shadow
 * test (`claude plugin test` drives each call through the mod). No literal
 * U+2014 here: the character is built from its code point.
 */

export const EMDASH_CHAR = String.fromCharCode(0x2014)
const D = EMDASH_CHAR
const ESCAPE_TEXT = '\\u{2014}'

export type Verdict = 'allow' | 'deny'

/**
 * One case. `tool` and `input` are the call as the mod sees it. `payload`
 * overrides the JSON fed to emdash.sh, for the two cases (30, 31) that are
 * about a payload the hook cannot parse: the mod is handed fields, never a
 * payload, so its side of those cases is a call with no usable fields.
 */
export type EmdashCase = {
    n: number
    expect: Verdict
    label: string
    tool: string
    input: Record<string, unknown>
    payload?: string
}

const w = (n: number, expect: Verdict, label: string, file_path: string, content: string): EmdashCase =>
    ({ n, expect, label, tool: 'Write', input: { file_path, content } })
const b = (n: number, expect: Verdict, label: string, command: string): EmdashCase =>
    ({ n, expect, label, tool: 'Bash', input: { command } })

export const EMDASH_CASES: readonly EmdashCase[] = [
    w(1, 'deny', 'literal U+2014 in content', 'docs/note.md', `The fix landed${D}CI is green.`),
    w(2, 'allow', 'the escape text with no literal', 'docs/note.md', `Assert absence with the ${ESCAPE_TEXT} form.`),
    w(3, 'allow', 'literal under tests/fixtures/ (relative)', 'tests/fixtures/sample.md', `A quoted log line${D}verbatim.`),
    w(4, 'allow', 'literal under tests/fixtures/ (absolute)', '/home/saidler/repos/scottidler/x/tests/fixtures/sample.md', `verbatim${D}line`),
    w(5, 'deny', 'literal PLUS the escape text', 'docs/note.md', `Write it as ${ESCAPE_TEXT}, not as ${D} itself.`),
    w(6, 'allow', 'literal in a .golden file', 'crates/x/golden/out.golden', `rendered${D}output`),
    w(7, 'deny', 'literal in a plain .json file', 'data/fixture.json', `{"s":"a${D}b"}`),
    w(8, 'allow', 'literal in a .json under tests/fixtures/', 'tests/fixtures/payload.json', `{"s":"a${D}b"}`),
    w(9, 'allow', 'clean content', 'docs/note.md', 'The fix landed: CI is green.'),
    { n: 10, expect: 'deny', label: 'Edit new_string carries it', tool: 'Edit', input: { file_path: 'docs/note.md', old_string: 'old text', new_string: `new${D}text` } },
    { n: 11, expect: 'allow', label: 'Edit removing it', tool: 'Edit', input: { file_path: 'docs/note.md', old_string: `old${D}text`, new_string: 'old: text' } },
    {
        n: 12, expect: 'deny', label: 'MultiEdit second edit carries it', tool: 'MultiEdit',
        input: { file_path: 'docs/note.md', edits: [{ old_string: 'x', new_string: 'clean one' }, { old_string: 'y', new_string: `second${D}edit` }] },
    },
    {
        n: 13, expect: 'allow', label: 'MultiEdit, neither edit carries it', tool: 'MultiEdit',
        input: { file_path: 'docs/note.md', edits: [{ old_string: 'x', new_string: 'clean one' }, { old_string: 'y', new_string: 'clean two' }] },
    },
    { n: 14, expect: 'deny', label: 'NotebookEdit new_source carries it', tool: 'NotebookEdit', input: { notebook_path: 'nb.ipynb', cell_id: 'c1', new_source: `# heading${D}subtitle` } },
    b(15, 'deny', 'git commit -m carrying it', `git commit -m "fix the thing${D}it was broken"`),
    b(16, 'allow', 'rg for the character, no outward stage', `rg -n '${D}' docs/`),
    b(17, 'allow', 'git commit with a clean message', "git add -A && git commit -m 'fix the thing: it was broken'"),
    b(18, 'deny', 'git -C <dir> commit carrying it', `git -C /home/saidler/repos/scottidler/claude commit -m "a${D}b"`),
    b(19, 'deny', 'commit message arriving by heredoc', `git commit -F - <<'MSG'\nfeat(x): thing\n\nbody line${D}still the body\nMSG\n`),
    b(20, 'allow', 'heredoc body mentions git commit, the command is a cat', `cat > notes.md <<'EOF'\nrun git commit after the${D}fix\nEOF\n`),
    b(21, 'deny', 'gh pr create --title carrying it', `gh pr create --title "feat(hooks): em-dash guard${D}phase 3" --body-file body.md`),
    b(22, 'deny', 'gh issue comment carrying it', `gh issue comment 12 --body 'landed${D}see the PR'`),
    b(23, 'allow', 'git log grepping for it', `git log --oneline | grep -F '${D}'`),
    b(24, 'allow', 'empty command', ''),
    { n: 25, expect: 'deny', label: 'slack chat_post_message text', tool: 'mcp__slack__chat_post_message', input: { channel_id: 'C123', text: `shipped${D}green CI` } },
    { n: 26, expect: 'allow', label: 'slack chat_post_message, clean text', tool: 'mcp__slack__chat_post_message', input: { channel_id: 'C123', text: 'shipped: green CI' } },
    {
        n: 27, expect: 'deny', label: 'atlassian confluence page, nested string', tool: 'mcp__atlassian__createConfluencePage',
        input: { spaceKey: 'ENG', title: 't', body: { representation: 'storage', value: `a${D}b` } },
    },
    { n: 28, expect: 'deny', label: 'marquee publish body', tool: 'mcp__marquee__marquee_publish', input: { space: '~scott-idler', slug: 's', content: `a${D}b` } },
    { n: 29, expect: 'allow', label: 'an unmatched tool (Read) carrying it', tool: 'Read', input: { file_path: `docs/a${D}b.md` } },
    { n: 30, expect: 'allow', label: 'malformed payload', tool: 'Write', input: { file_path: 'docs/note.md' }, payload: 'not json at all' },
    { n: 31, expect: 'allow', label: 'empty payload', tool: 'Write', input: {}, payload: '' },
]

/** The JSON emdash.sh reads on stdin for a case. */
export function payloadOf(c: EmdashCase): string {
    return c.payload ?? JSON.stringify({ hook_event_name: 'PreToolUse', tool_name: c.tool, tool_input: c.input })
}
