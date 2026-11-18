import { describe, expect, test } from 'bun:test'
import { chainVerdict, judgeToolCall, surfaceOf } from '../hooks/rules.ts'
import { EMDASH_CASES, payloadOf } from './emdash-cases.ts'
import type { Verdict } from './emdash-cases.ts'

/*
 * Phase 2 parity: the real emdash.sh and the mod's tool.call judgment (the
 * matcher filter, then the rule) give the same allow or deny on every case
 * of emdash-test.sh. The script is run, not restated: if it changes, this
 * fails until the mod follows.
 */

const HOOK = import.meta.dir + '/../../../hooks/emdash.sh'

function scriptVerdict(payload: string): Verdict {
    const run = Bun.spawnSync(['bash', HOOK], { stdin: new TextEncoder().encode(payload) })
    const out = run.stdout.toString().trim()
    if (out === '' || out === '{}') { return 'allow' }
    const decision = (JSON.parse(out) as { hookSpecificOutput?: { permissionDecision?: string } }).hookSpecificOutput?.permissionDecision
    return decision === 'deny' ? 'deny' : 'allow'
}

function modVerdict(tool: string, input: Record<string, unknown>): Verdict {
    if (surfaceOf(tool) === null) { return 'allow' }
    return judgeToolCall(tool, input) === null ? 'allow' : 'deny'
}

describe('emdash.sh and the mod agree, case for case', () => {
    test('the table holds all 31 cases of emdash-test.sh, numbered in order', () => {
        expect(EMDASH_CASES.map((c) => c.n)).toEqual(Array.from({ length: 31 }, (_, i) => i + 1))
    })

    for (const c of EMDASH_CASES) {
        test(`${c.n} ${c.expect}: ${c.label}`, () => {
            expect({ script: scriptVerdict(payloadOf(c)), mod: modVerdict(c.tool, c.input) })
                .toEqual({ script: c.expect, mod: c.expect })
        })
    }
})

describe('surfaceOf: the four emdash.sh matchers in settings.json', () => {
    test('built-in write tools, Bash, the outward MCP posts and create_pr each have a surface', () => {
        expect(['Write', 'Edit', 'MultiEdit', 'NotebookEdit'].map(surfaceOf)).toEqual(['write', 'write', 'write', 'write'])
        expect(surfaceOf('Bash')).toBe('bash')
        expect(surfaceOf('mcp__slack__chat_update')).toBe('mcp-post')
        expect(surfaceOf('mcp__atlassian__createConfluenceInlineComment')).toBe('mcp-post')
        expect(surfaceOf('mcp__marquee__marquee_update')).toBe('mcp-post')
        expect(surfaceOf('mcp__multi-account-github__create_pr')).toBe('create_pr')
    })

    test('a read-only MCP tool, a lookalike name and Read have none', () => {
        expect(surfaceOf('mcp__slack__search_messages')).toBeNull()
        expect(surfaceOf('mcp__slack__chat_post_message_v2')).toBeNull()
        expect(surfaceOf('mcp__marquee__marquee_delete')).toBeNull()
        expect(surfaceOf('Read')).toBeNull()
        expect(surfaceOf('')).toBeNull()
    })
})

describe('chainVerdict: what the chain beneath decided (Phase 0 Q6)', () => {
    test('a settings hook deny, as next(e) resolves it, is a deny', () => {
        const r = { ref: 1, result: 'Error: PreToolUse:Bash hook error: SPIKE settings hook deny reason', text: 'PreToolUse:Bash hook error: SPIKE settings hook deny reason', isError: true }
        expect(chainVerdict(r)).toBe('deny')
        expect(chainVerdict({ ...r, text: 'PreToolUse:mcp__slack__chat_post_message hook error: no' })).toBe('deny')
    })

    test('a plugin beneath answering { deny } is a deny', () => {
        expect(chainVerdict({ deny: 'nope' })).toBe('deny')
    })

    test('a tool that merely errored, a clean result and junk are allows', () => {
        expect(chainVerdict({ ref: 1, result: 'Error: exit 1', text: 'Error: exit 1', isError: true })).toBe('allow')
        expect(chainVerdict({ ref: 1, result: { stdout: 'ok' }, text: 'ok', isReadOnly: true })).toBe('allow')
        expect(chainVerdict({ text: 'PreToolUse:Bash hook error: x' })).toBe('allow')
        expect(chainVerdict(undefined)).toBe('allow')
        expect(chainVerdict('deny')).toBe('allow')
    })
})
