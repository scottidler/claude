/**
 * voice-guard, end to end through the engine's own chain (`claude plugin test`).
 *
 * The test's hooks sit beneath the mod and stand for the engine: a
 * `classic.PreToolUse` hook stands for the settings hooks (`emdash.sh`,
 * `git-release-guard.sh`), a `tool.call` hook for the tool itself, and
 * `fs.write` catches the mod's log. The kit runs no process, so the scripts
 * are not run here; `spec/parity.spec.ts` runs the real `emdash.sh` on the
 * same 31 cases, and each stand-in answers with its script's own deny text.
 */
import { describe, expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import { EMDASH_CASES, EMDASH_CHAR } from '../spec/emdash-cases'

// The engine's type-check carries no DOM or Node lib, so the timer is declared here.
declare function setTimeout(handler: (...args: any[]) => void, ms: number): unknown

const HOME = '/home/saidler'
const SESSION = 'sess-1'
const LOG_FILE = new RegExp('^' + (HOME + '/.local/state/voice-guard/').replace(/[./]/g, '\\$&') + SESSION + '\\.\\d+-[0-9a-z]+\\.jsonl$')

/** `git-release-guard.sh`'s deny for `git push --tags`, verbatim from the script. */
const RELEASE_DENY = "git.md: never 'git push --tags'/'--follow-tags' (the tag lands even if the branch push is rejected, and this orphaned okta-auth-rs v0.2.0). Push the branch first, then the tag by explicit name: git push origin vX.Y.Z"

/**
 * A settings hook's deny as a live session hands it to `next(e)`: the text
 * opens `PreToolUse:<tool> hook error: ` (Phase 0 Q6, a live run). The kit
 * returns the stand-in's reason bare, so the stand-in states the prefix the
 * engine adds; the live check in the implementation notes shows the real one.
 */
function settingsDenyText(tool: string, reason: string): string {
    return 'PreToolUse:' + tool + ' hook error: ' + reason
}

type LogRow = Record<string, unknown>

type World = {
    /** Every write of the mod's log, newest last. */
    writes: { path: string; text: string }[]
    /** The calls that reached the tool at the bottom of the chain. */
    ran: string[]
    /** The rows of the newest log write. */
    rows: () => LogRow[]
}

/**
 * The world beneath the mod. `denies(tool, input)` is the settings tier: a
 * string is its deny reason, undefined lets the call on.
 */
function world(on: On, denies: (tool: string, input: Record<string, unknown>) => string | undefined): World {
    const w: World = {
        writes: [],
        ran: [],
        rows: () => {
            const last = w.writes[w.writes.length - 1]
            if (last === undefined) { return [] }
            return last.text.split('\n').filter((l) => l !== '').map((l) => JSON.parse(l) as LogRow)
        },
    }
    on('ui.log', () => ({ value: undefined }))
    mock.env(on, { HOME })
    on('session.id', () => ({ value: SESSION }))
    on('fs.write', ($, e) => {
        w.writes.push({ path: e.path, text: String(e.text) })
        return { value: undefined }
    })
    on('classic.PreToolUse', ($, e) => {
        // The kit hands this hook the call's own fields (`tool`, `command`, ...), where a
        // settings hook reads `tool_name` and `tool_input`: both are read.
        const raw = e as unknown as Record<string, unknown>
        const tool = String(raw['tool_name'] ?? raw['tool'])
        const input = (raw['tool_input'] ?? raw) as Record<string, unknown>
        const reason = denies(tool, input)
        return reason === undefined ? {} : { deny: settingsDenyText(tool, reason) }
    })
    on('tool.call', ($, e) => {
        w.ran.push(String(e.tool))
        return { result: 'ok' }
    })
    return w
}

/** Let the mod's queued log writes run: they are never awaited by the hook. */
async function rowsSettled(w: World, count: number): Promise<LogRow[]> {
    for (let i = 0; i < 200 && w.rows().length < count; i += 1) {
        await new Promise((resolve) => setTimeout(resolve, 0))
    }
    return w.rows()
}

/** A deny reaches the test's own `$.tool.call` as `{ deny }`, or as an errored result whose text is the reason. */
function denied(r: { deny?: string; isError?: true; text?: string }): string | undefined {
    if (r.deny !== undefined) { return r.deny }
    return r.isError === true ? r.text : undefined
}

const allowAll = (): undefined => undefined

/** The fields the kit's call takes: the case's input with its tool. */
function callOf(tool: string, input: Record<string, unknown>): any {
    return { tool, ...input }
}

describe('shadow mode: the mod judges, the chain beneath decides', () => {
    test('every emdash-test.sh case: the mod logs the expected verdict and the chain result matches it', async ($, on) => {
        // The stand-in for emdash.sh denies exactly what emdash-test.sh expects denied
        // (the real script is held to that table in spec/parity.spec.ts).
        const expected = new Map(EMDASH_CASES.map((c) => [c.n, c.expect]))
        let current = 0
        const w = world(on, () => (expected.get(current) === 'deny' ? 'em-dash (U+2014) in the call; recast it' : undefined))
        const judged: { n: number; mod: unknown; chain: unknown }[] = []
        for (const c of EMDASH_CASES) {
            current = c.n
            const before = w.rows().length
            await $.tool.call(callOf(c.tool, c.input))
            // An unmatched tool (Read, 29) is never judged and leaves no row.
            if (c.tool === 'Read') {
                expect(await rowsSettled(w, before + 1)).toHaveLength(before)
                judged.push({ n: c.n, mod: 'allow', chain: 'allow' })
                continue
            }
            const rows = await rowsSettled(w, before + 1)
            const row = rows[rows.length - 1] as LogRow
            judged.push({ n: c.n, mod: row['modVerdict'], chain: row['chainResult'] })
        }
        expect(judged).toEqual(EMDASH_CASES.map((c) => ({ n: c.n, mod: c.expect, chain: c.expect })))
    })

    test('a U+2014 Write: modVerdict deny, chainResult deny, and the hook\'s errored result comes back untouched', async ($, on) => {
        const w = world(on, (tool) => (tool === 'Write' ? 'em-dash (U+2014) in Write content' : undefined))
        const r = await $.tool.call({ tool: 'Write', file_path: 'a.md', content: 'a' + EMDASH_CHAR + 'b' })
        expect(denied(r)).toContain('em-dash (U+2014) in Write content')
        expect(w.ran).toEqual([])
        const rows = await rowsSettled(w, 1)
        expect(rows).toEqual([expect.objectContaining({
            event: 'tool.call', session: SESSION, surface: 'write', tool: 'Write', rule: 'emdash',
            label: 'Write content', modVerdict: 'deny', chainResult: 'deny', mode: 'shadow', agentId: null,
        })])
        expect(w.writes[0]?.path).toMatch(LOG_FILE)
    })

    test('a U+2014 Write the hook beneath lets through still runs: shadow decides nothing', async ($, on) => {
        const w = world(on, allowAll)
        const r = await $.tool.call({ tool: 'Write', file_path: 'a.md', content: 'a' + EMDASH_CHAR + 'b' })
        expect(r.result).toBe('ok')
        expect(w.ran).toEqual(['Write'])
        expect(await rowsSettled(w, 1)).toEqual([expect.objectContaining({ modVerdict: 'deny', chainResult: 'allow' })])
    })

    test('a settings hook beneath (git-release-guard.sh) still denies git push --tags through the mod', async ($, on) => {
        const w = world(on, (tool, input) =>
            (tool === 'Bash' && /(^|\s)git\s+push\b.*--tags\b/.test(String(input['command'])) ? RELEASE_DENY : undefined))
        const r = await $.tool.call({ tool: 'Bash', command: 'git push --tags' })
        expect(denied(r)).toContain(RELEASE_DENY)
        expect(w.ran).toEqual([])
        expect(await rowsSettled(w, 1)).toEqual([expect.objectContaining({
            surface: 'bash', tool: 'Bash', rule: null, modVerdict: 'allow', chainResult: 'deny', mode: 'shadow',
        })])
    })

    test('a clean Bash call reaches the tool beneath', async ($, on) => {
        const w = world(on, allowAll)
        const r = await $.tool.call({ tool: 'Bash', command: 'git status' })
        expect(r.result).toBe('ok')
        expect(w.ran).toEqual(['Bash'])
        expect(await rowsSettled(w, 1)).toEqual([expect.objectContaining({ modVerdict: 'allow', chainResult: 'allow' })])
    })

    test('an outward MCP post and create_pr are judged; a read-only MCP call is not', async ($, on) => {
        const w = world(on, allowAll)
        await $.tool.call({ tool: 'mcp__slack__chat_post_message', channel_id: 'C1', text: 'a' + EMDASH_CHAR + 'b' } as any)
        await $.tool.call({ tool: 'mcp__multi-account-github__create_pr', title: 't', body: 'x' + EMDASH_CHAR + 'y' } as any)
        await $.tool.call({ tool: 'mcp__slack__search_messages', query: 'a' + EMDASH_CHAR + 'b' } as any)
        expect(w.ran).toEqual(['mcp__slack__chat_post_message', 'mcp__multi-account-github__create_pr', 'mcp__slack__search_messages'])
        const rows = await rowsSettled(w, 3)
        expect(rows.map((r) => [r['surface'], r['modVerdict'], r['label']])).toEqual([
            ['mcp-post', 'deny', 'mcp__slack__chat_post_message text'],
            ['create_pr', 'deny', 'mcp__multi-account-github__create_pr body'],
        ])
    })

    test('a subagent call logs its agentId', async ($, on) => {
        const w = world(on, allowAll)
        await $.tool.call({ tool: 'Edit', file_path: 'a.md', old_string: 'x', new_string: 'y', agentId: 'a1' } as any)
        expect(await rowsSettled(w, 1)).toEqual([expect.objectContaining({ agentId: 'a1', modVerdict: 'allow' })])
    })

    test('a log that cannot be written does not fail or hold the call', async ($, on) => {
        mock.env(on, { HOME })
        on('session.id', () => ({ value: SESSION }))
        on('fs.write', () => { throw new Error('disk full') })
        const ran: string[] = []
        on('tool.call', ($, e) => { ran.push(String(e.tool)); return { result: 'ok' } })
        const r = await $.tool.call({ tool: 'Write', file_path: 'a.md', content: 'a' + EMDASH_CHAR + 'b' })
        expect(r.result).toBe('ok')
        expect(ran).toEqual(['Write'])
    })

    test('a judge that throws fails open: the call runs and a catch row is logged', async ($, on) => {
        const w = world(on, allowAll)
        // Nested past the call stack: the rule's walk of every MCP string throws a RangeError.
        let deep: Record<string, unknown> = { text: 'clean' }
        for (let i = 0; i < 27000; i += 1) { deep = { d: deep } }
        const r = await $.tool.call({ tool: 'mcp__slack__chat_post_message', channel_id: 'C1', blocks: deep } as any)
        expect(r.result).toBe('ok')
        expect(w.ran).toEqual(['mcp__slack__chat_post_message'])
        expect(await rowsSettled(w, 1)).toEqual([expect.objectContaining({
            surface: 'mcp-post', rule: 'catch', modVerdict: null, chainResult: 'allow', error: expect.stringMatching(/^throw: Maximum call stack/),
        })])
    })
})

describe('enforce mode (off by default)', () => {
    test('a U+2014 Write is denied by the mod alone; nothing beneath runs', { options: { enforce: true } }, async ($, on) => {
        let hookRan = false
        const w = world(on, () => { hookRan = true; return undefined })
        const r = await $.tool.call({ tool: 'Write', file_path: 'a.md', content: 'a' + EMDASH_CHAR + 'b' })
        expect(denied(r)).toContain('em-dash (U+2014) in Write content')
        expect(hookRan).toBe(false)
        expect(w.ran).toEqual([])
        expect(await rowsSettled(w, 1)).toEqual([expect.objectContaining({ modVerdict: 'deny', chainResult: null, mode: 'enforce' })])
    })

    test('a clean call still reaches the settings hook beneath and the tool', { options: { enforce: true } }, async ($, on) => {
        const w = world(on, (tool, input) => (String(input['command']) === 'git push --tags' ? RELEASE_DENY : undefined))
        const r = await $.tool.call({ tool: 'Bash', command: 'git push --tags' })
        expect(denied(r)).toContain(RELEASE_DENY)
        const ok = await $.tool.call({ tool: 'Bash', command: 'git status' })
        expect(ok.result).toBe('ok')
        expect(w.ran).toEqual(['Bash'])
    })
})
