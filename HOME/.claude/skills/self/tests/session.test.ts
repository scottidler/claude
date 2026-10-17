/**
 * `self`, end to end through the engine's own chain (`claude plugin test`).
 * The test's `on` hooks sit beneath the plugin and stand for the engine: each
 * `$.session` read and `$.tool.register` is answered here, from memory.
 */
import { describe, expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const TOOL = 'mcp__self__session'
const SESSION = '6a932ade-8d54-4b60-8795-207c6b659279'
const STARTED_MS = Date.UTC(2026, 9, 16, 12, 30, 45, 123)

type Usage = {
    startedAt: number
    context: { tokens?: number; window: number; percent?: number; breakdown?: Record<string, unknown> }
    rateLimits: never[]
    cost?: { usd: number }
}

type World = {
    registered: Record<string, unknown>[]
    usageAsked: (string | undefined)[]
    repo: { root: string; remote: string | null; internal: boolean; name: string | null } | null
    failing: string | null
    withBreakdown: boolean
}

const BREAKDOWN = {
    categories: [{ name: 'System prompt', tokens: 3000, color: 'x', isDeferred: false, kind: 'used' }],
    totalTokens: 3000, maxTokens: 200000, rawMaxTokens: 200000, autocompactSource: 'model', percentage: 2,
    gridRows: [[{ color: 'x' }]],
    model: 'm', memoryFiles: [], mcpTools: [], agents: [], isAutoCompactEnabled: true, apiUsage: null,
}

function world(on: On): World {
    const w: World = {
        registered: [], usageAsked: [], failing: null, withBreakdown: true,
        repo: { root: '/r', remote: 'https://x@host/o/r.git', internal: false, name: null },
    }
        on('session.start', ($, e) => ({ cwd: e.cwd }))
    on('tool.register', ($, e) => { w.registered.push(e as unknown as Record<string, unknown>); return { value: { tool: TOOL } } })
    on('session.id', () => (w.failing === 'id' ? { deny: 'forced id' } : { value: SESSION }))
    on('session.cwd', () => ({ value: '/r/sub' }))
    on('session.root', () => ({ value: '/r' }))
    on('session.repo', () => ({ value: w.repo }))
    on('session.turns', () => ({ value: 4 }))
    on('session.usage', ($, e) => {
        if (w.failing === 'usage') { return { deny: 'forced usage' } }
        const asked = (e as { breakdown?: string }).breakdown
        w.usageAsked.push(asked)
        const usage: Usage = {
            startedAt: STARTED_MS,
            context: { tokens: 34051, window: 1000000, percent: 3 },
            rateLimits: [],
            cost: { usd: 0.42 },
        }
        if (asked !== undefined && w.withBreakdown) { usage.context.breakdown = BREAKDOWN }
        return { value: usage }
    })
    return w
}

/** A deny surfaces to the test's `$` as an errored result whose text is the reason. */
function denied(r: { deny?: string; isError?: true; text?: string }): string | undefined {
    if (r.deny !== undefined) { return r.deny }
    return r.isError === true ? r.text : undefined
}

/** A `tool.call` answer is a JSON string. */
function facts(r: { result?: unknown }): any {
    expect(typeof r.result).toBe('string')
    return JSON.parse(r.result as string)
}

describe('self: mcp__self__session', () => {
    test('registers mcp__self__session at session.start, not deferred', async ($, on) => {
        const w = world(on)
        expect(w.registered.length).toBe(0)
        await $.session.start({ cwd: '/r', surface: null, isInteractive: false })
        expect(w.registered.length).toBe(1)
        const spec = w.registered[0] as { name: string; isDeferred?: boolean; description: string }
        expect(spec.name).toBe('session')
        expect(spec.isDeferred).toBe(false)
        expect(spec.description).toContain("From a subagent, context figures are the main conversation's")
    })

    test('answers with sessionId equal to $.session.id()', async ($, on) => {
        world(on)
        const r = facts(await $.tool.call({ tool: TOOL }))
        expect(r.sessionId).toBe(SESSION)
        expect(r.cwd).toBe('/r/sub')
        expect(r.root).toBe('/r')
        expect(r.turns).toBe(4)
        expect(r.costUsd).toBe(0.42)
        expect(r.context).toEqual({ tokens: 34051, window: 1000000, percent: 3 })
    })

    test('omits breakdown unless asked', async ($, on) => {
        const w = world(on)
        const r = facts(await $.tool.call({ tool: TOOL }))
        expect(r.context.breakdown).toBeUndefined()
        expect(w.usageAsked).toEqual([undefined])
    })

    test('breakdown summary carries categories and no gridRows', async ($, on) => {
        const w = world(on)
        const r = facts(await $.tool.call({ tool: TOOL, breakdown: 'summary' }))
        expect(w.usageAsked).toEqual(['summary'])
        expect(r.context.breakdown.categories.length).toBe(1)
        expect(r.context.breakdown.percentage).toBe(2)
        expect('gridRows' in r.context.breakdown).toBe(false)
    })

    test('denies an unknown breakdown value', async ($, on) => {
        const w = world(on)
        const reason = denied(await $.tool.call({ tool: TOOL, breakdown: 'bogus' }))
        // The kit also checks the schema (the live core does not, Phase 0 (g)); the hook's own wording proves the hook did the denying.
        expect(reason).toBe('breakdown: expected "summary" or "full", got "bogus"')
        expect(w.usageAsked).toEqual([])
    })

    test('denies an unknown input key', async ($, on) => {
        const w = world(on)
        const reason = denied(await $.tool.call({ tool: TOOL, breakdwon: 'full' } as never))
        expect(reason).toBe('input: unknown key "breakdwon"; the only input is "breakdown"')
        expect(w.usageAsked).toEqual([])
    })

    test('strips userinfo from repo.remote', async ($, on) => {
        const w = world(on)
        expect(facts(await $.tool.call({ tool: TOOL })).repo).toEqual({ root: '/r', remote: 'https://host/o/r.git' })
        w.repo = { root: '/r', remote: 'https://user:p%40ss@host/o/r.git', internal: false, name: null }
        expect(facts(await $.tool.call({ tool: TOOL })).repo.remote).toBe('https://host/o/r.git')
        w.repo = { root: '/r', remote: null, internal: false, name: null }
        expect(facts(await $.tool.call({ tool: TOOL })).repo.remote).toBe(null)
    })

    test('denies, naming the method, when a $.session call rejects', async ($, on) => {
        const w = world(on)
        w.failing = 'usage'
        const usage = denied(await $.tool.call({ tool: TOOL }))
        expect(usage).toBe('usage: self: $.session.usage: forced usage')
        w.failing = 'id'
        expect(denied(await $.tool.call({ tool: TOOL }))).toBe('id: self: $.session.id: forced id')
    })

    test('denies when a requested breakdown does not come back', async ($, on) => {
        const w = world(on)
        w.withBreakdown = false
        expect(denied(await $.tool.call({ tool: TOOL, breakdown: 'full' }))).toContain('breakdown: not returned')
    })

    test('repo is null outside git', async ($, on) => {
        const w = world(on)
        w.repo = null
        expect(facts(await $.tool.call({ tool: TOOL })).repo).toBe(null)
    })

    test('startedAt is ISO 8601 of usage().startedAt', async ($, on) => {
        world(on)
        const r = facts(await $.tool.call({ tool: TOOL }))
        expect(r.startedAt).toBe('2026-10-16T12:30:45.123Z')
        expect(r.startedAt).toBe(new Date(STARTED_MS).toISOString())
    })
})
