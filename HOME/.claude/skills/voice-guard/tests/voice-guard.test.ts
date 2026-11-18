/**
 * voice-guard, end to end through the engine's own chain (`claude plugin test`).
 * Phase 1 is a pass-through: the call reaches the settings tier beneath
 * unchanged, em-dash or not. The test's `on` hook stands for the engine below.
 */
import { describe, expect, test } from 'claude-code/testing'

describe('voice-guard pass-through', () => {
    test('a clean Bash call reaches the hook beneath', async ($, on) => {
        const seen: string[] = []
        on('tool.call', (_$, e) => {
            if (e.tool === 'Bash') { seen.push(e.command) }
            return { result: 'ok' }
        })
        await $.tool.call({ tool: 'Bash', command: 'git status' })
        expect(seen).toEqual(['git status'])
    })

    test('a call carrying U+2014 still reaches the hook beneath: shadow phase 1 decides nothing', async ($, on) => {
        const seen: string[] = []
        on('tool.call', (_$, e) => {
            if (e.tool === 'Write') { seen.push(e.content) }
            return { result: 'ok' }
        })
        await $.tool.call({ tool: 'Write', file_path: 'a.md', content: 'a\u2014b' })
        expect(seen).toEqual(['a\u2014b'])
    })
})
