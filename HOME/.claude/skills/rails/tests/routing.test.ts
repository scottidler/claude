/**
 * rails rule routing, end to end through the engine's own chain
 * (`claude plugin test`, Phase 0 (j)). The test's `on` hooks sit beneath
 * rails and stand for the engine: the file system, `$.state`, `$.ui` and the
 * bottom of each event are answered here, from memory.
 *
 * The kit runs with no file system, so the rule index is a small synthetic
 * one with the real classification (4 routed, the rest always or native) and
 * the e9ef7f18 burst is its 15 real paths with stub bodies; the routing
 * decision reads paths only. `rules.spec.ts` covers the real rule files and
 * the full recorded text under bun.
 */
import { describe, expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

const HOME = '/home/saidler'
const LINK_DIR = HOME + '/repos/.claude/rules'
const REAL_DIR = HOME + '/repos/scottidler/claude/HOME/repos/.claude/rules'

const GIT = String.raw`---
load:
  prompt: ['\b(push|tag|merge|rebase|release|branch)\b']
  bash:
    - '^git\b'
    - { match: '^git (push|tag|branch -D)\b', gate: true }
---

# Git

Git rule body.
`
const VOICE = String.raw`---
load:
  prompt: ['\bslack\b']
  tools:
    - { match: '^mcp__slack__chat_post_message$', gate: true }
---
# Voice

Voice rule body.
`
const MARQUEE = String.raw`---
load:
  prompt: ['marquee']
  bash: ['^marquee\b']
---
# Marquee
`
const OTTO = String.raw`---
load:
  prompt: ['\botto\b']
  bash: ['^otto\b']
---
# Otto
`
const always = (name: string): string => '---\nalwaysApply: true\nload: always\n---\n# ' + name + '\n'
const native = (name: string): string => '---\npaths: ["**/*"]\nload: native\n---\n# ' + name + '\n'

const RULES: Record<string, string> = {
    'git.md': GIT,
    'voice.md': VOICE,
    'marquee.md': MARQUEE,
    'otto.md': OTTO,
    'interaction.md': always('interaction'),
    'taste.md': always('taste'),
    'pr.md': always('pr'),
    'general.md': always('general'),
    'recall.md': always('recall'),
    'search.md': always('search'),
    'secrets.md': always('secrets'),
    'safety.md': native('safety'),
}

/** A link the rules dir still holds after its rule moved to refs/ (live: cli.md, logging.md). */
const DANGLING = 'cli.md'

/** The 15 rows of the e9ef7f18 burst (transcript :191-205), in order, by the path each names. */
const BURST = [
    HOME + '/repos/CLAUDE.md',
    REAL_DIR + '/marquee.md',
    REAL_DIR + '/interaction.md',
    REAL_DIR + '/logging.md',
    REAL_DIR + '/pr.md',
    REAL_DIR + '/otto.md',
    REAL_DIR + '/search.md',
    REAL_DIR + '/cli.md',
    REAL_DIR + '/git.md',
    REAL_DIR + '/recall.md',
    REAL_DIR + '/taste.md',
    REAL_DIR + '/voice.md',
    REAL_DIR + '/general.md',
    REAL_DIR + '/secrets.md',
    REAL_DIR + '/safety.md',
]

/** A compaction leaves at least one message. */
const SUMMARY = [{ role: 'user', text: 'summary', toolUses: [] }]

const nested = (path: string): string => 'Contents of ' + path + ':\n\n# ' + path.slice(path.lastIndexOf('/') + 1) + ' body\n'

/** What the engine beneath rails saw and was asked, for the assertions. */
type World = {
    logs: string[]
    status: (string | undefined)[]
    invalidated: string[]
    state: Record<string, unknown>
    toolCalls: string[]
    listFails: boolean
}

/** Answer every noun rails calls, from memory, and the bottom of each event it hooks. */
function world(on: On): World {
    const w: World = { logs: [], status: [], invalidated: [], state: {}, toolCalls: [], listFails: false }
    mock.env(on, { HOME })
    on('fs.exists', ($, e) => ({ value: e.path === LINK_DIR }))
    on('fs.list', ($, e) => {
        if (w.listFails) { return { deny: 'forced: fs.list failed' } }
        expect(e.path).toBe(LINK_DIR)
        return { value: [...Object.keys(RULES), DANGLING].map((name) => ({ name, kind: 'other' as const, size: 0, mtimeMs: 0, isLink: true })) }
    })
    on('fs.read', ($, e) => {
        const name = e.path.slice(LINK_DIR.length + 1)
        const text = RULES[name]
        if (!e.path.startsWith(LINK_DIR + '/') || text === undefined) { throw new Error('ENOENT ' + e.path) }
        return { value: text }
    })
    on('fs.stat', ($, e) => {
        if (e.path === LINK_DIR + '/' + DANGLING) { return { value: { kind: 'other' as const, size: 0, mtimeMs: 0, isLink: true } } }
        const realPath = e.path.startsWith(LINK_DIR + '/') ? REAL_DIR + e.path.slice(LINK_DIR.length) : e.path
        return { value: { kind: 'file' as const, size: 1, mtimeMs: 0, isLink: realPath !== e.path, realPath } }
    })
    on('state.get', ($, e) => {
        const value = w.state[e.key]
        return { value: { value, version: value === undefined ? 0 : 1 } }
    })
    on('state.set', ($, e) => {
        w.state[e.key] = JSON.parse(JSON.stringify(e.value))
        return { value: { isSet: true as const, version: 1 } }
    })
    on('ui.log', ($, e) => { w.logs.push(e.text); return { value: undefined } })
    on('ui.status', ($, e) => { w.status.push(e.text); return { value: undefined } })
    on('ui.invalidate', ($, e) => { w.invalidated.push(e.event); return { value: undefined } })
    on('settings.read', () => ({ value: {} }))
    on('prompt.attachment', ($, e) => ({ text: e.text }))
    on('prompt.submit', ($, e) => (e.context === undefined ? { text: e.text } : { text: e.text, context: e.context }))
    on('tool.call', ($, e) => {
        w.toolCalls.push(e.tool === 'Bash' ? String(e.command) : String(e.tool))
        if (e.tool === 'Bash' && String(e.command).endsWith('--bad')) { return { isError: true as const, result: 'rejected', text: 'rejected' } }
        return { result: 'ok' }
    })
    on('session.compact', ($, e) => (e.trigger === 'manual' ? { skip: 'not now' } : { messages: e.messages }))
    on('turn.step', async function* ($, e) {
        return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: null, usage: null } as never
    })
    return w
}

/** A deny surfaces to the test's `$` as an errored result whose text is the reason. */
function denied(r: { deny?: string; isError?: true; text?: string }): string | undefined {
    if (r.deny !== undefined) { return r.deny }
    return r.isError === true ? r.text : undefined
}

/** One model request of the main loop, read to its end. */
async function step($: Engine, index: number): Promise<void> {
    const s = $.turn.step({ turnId: 't1', index, model: 'm', messageCount: 1 })
    for await (const chunk of s) { void chunk }
    await s.result
}

describe('rule routing: the drop path', () => {
    test('the e9ef7f18 burst keeps 11 files and drops 4', async ($, on) => {
        const w = world(on)
        const kept: string[] = []
        const dropped: string[] = []
        for (const path of BURST) {
            const text = nested(path)
            const r = await $.prompt.attachment({ type: 'nested_memory', text, origin: { kind: 'engine' } })
            if (r.text === null) { dropped.push(path) } else { expect(r.text).toBe(text); kept.push(path) }
        }
        expect(kept.length).toBe(11)
        expect(dropped.map((p) => p.slice(p.lastIndexOf('/') + 1))).toEqual(['marquee.md', 'otto.md', 'git.md', 'voice.md'])
        expect(w.logs.filter((l) => l.startsWith('rules: drop ')).length).toBe(4)
        expect(w.logs.filter((l) => l.startsWith('rules: keep ')).length).toBe(11)
        expect(w.logs).toContain('rules: drop git.md (routed) ' + REAL_DIR + '/git.md')
        expect(w.logs).toContain('rules: keep CLAUDE.md (bulk) ' + HOME + '/repos/CLAUDE.md')
        expect(w.logs).toContain('rules: keep cli.md (bulk) ' + REAL_DIR + '/cli.md')
        expect(w.logs).toContain('rules: skip cli.md (leads to no file) ' + LINK_DIR + '/cli.md')
        expect(w.invalidated).toEqual([])
    })

    test('a second nested_memory for an already-kept real path is left out', async ($, on) => {
        world(on)
        const first = nested(REAL_DIR + '/taste.md')
        expect((await $.prompt.attachment({ type: 'nested_memory', text: first, origin: { kind: 'engine' } })).text).toBe(first)
        const again = nested(LINK_DIR + '/taste.md')
        expect((await $.prompt.attachment({ type: 'nested_memory', text: again, origin: { kind: 'engine' } })).text).toBe(null)
    })

    test('the same attachment asked again is not its own duplicate', async ($, on) => {
        world(on)
        const text = nested(REAL_DIR + '/taste.md')
        expect((await $.prompt.attachment({ type: 'nested_memory', text, origin: { kind: 'engine' } })).text).toBe(text)
        expect((await $.prompt.attachment({ type: 'nested_memory', text, origin: { kind: 'engine' } })).text).toBe(text)
    })

    test('instructions: routed sections drop, preamble and managed tier stay, the tail is the blob own', async ($, on) => {
        const w = world(on)
        const blob = 'Codebase and user instructions are shown below.\n\n'
            + 'Contents of <managed-settings> (organization-managed policy instructions):\n\n# Policy\n\n'
            + 'Contents of ' + HOME + '/repos/CLAUDE.md (project instructions, checked into the codebase):\n\n# Repos\n\n'
            + 'Contents of ' + LINK_DIR + '/git.md (project instructions, checked into the codebase):\n\n# Git\n\n'
            + 'Contents of ' + LINK_DIR + '/taste.md (project instructions, checked into the codebase):\n\n# Taste\n\n'
            + 'Contents of ' + LINK_DIR + '/voice.md (project instructions, checked into the codebase):\n\n# Voice\n'
        const r = await $.prompt.attachment({ type: 'instructions', text: blob, origin: { kind: 'engine' } })
        expect(r.text).toBe('Codebase and user instructions are shown below.\n\n'
            + 'Contents of <managed-settings> (organization-managed policy instructions):\n\n# Policy\n\n'
            + 'Contents of ' + HOME + '/repos/CLAUDE.md (project instructions, checked into the codebase):\n\n# Repos\n\n'
            + 'Contents of ' + LINK_DIR + '/taste.md (project instructions, checked into the codebase):\n\n# Taste\n')
        expect(w.logs).toContain('rules: drop voice.md (routed) ' + REAL_DIR + '/voice.md')
        const later = nested(HOME + '/repos/CLAUDE.md')
        expect((await $.prompt.attachment({ type: 'nested_memory', text: later, origin: { kind: 'engine' } })).text).toBe(null)
    })

    test('instructions with nothing to drop pass byte for byte', async ($, on) => {
        world(on)
        const blob = 'Preamble.\n\nContents of ' + HOME + '/.claude/CLAUDE.md (user):\n\n# Me\n'
        expect((await $.prompt.attachment({ type: 'instructions', text: blob, origin: { kind: 'engine' } })).text).toBe(blob)
    })

    test('hook_additional_context passes untouched, even when it carries a routed rule', async ($, on) => {
        world(on)
        const text = 'tool.call hook additional context: ' + nested(REAL_DIR + '/git.md')
        const r = await $.prompt.attachment({ type: 'hook_additional_context', text, origin: { kind: 'plugin', event: 'tool.call' } })
        expect(r.text).toBe(text)
    })
})

describe('rule routing: the inject path', () => {
    test('a prompt trigger injects on the way down, once per loop', async ($, on) => {
        const w = world(on)
        const r = await $.prompt.submit({ text: 'push the branch', wait: false, origin: { kind: 'user' } } as never)
        expect(r.context?.length).toBe(1)
        expect(r.context?.[0]).toBe('Contents of ' + REAL_DIR + '/git.md:\n\n# Git\n\nGit rule body.')
        const again = await $.prompt.submit({ text: 'push it again', wait: false, origin: { kind: 'user' } } as never)
        expect(again.context).toBeUndefined()
        expect(w.logs.filter((l) => l.startsWith('rules: inject git.md')).length).toBe(1)
    })

    test('two gated calls for one rule in one step both deny; a third after turn.step runs', async ($, on) => {
        const w = world(on)
        const first = denied(await $.tool.call({ tool: 'Bash', command: 'git push origin main' }))
        expect(first).toContain('git.md must be in context before this call runs')
        expect(first).toContain('Contents of ' + REAL_DIR + '/git.md:\n\n# Git\n\nGit rule body.')
        expect(first).toContain('show Scott the new draft before sending')
        const second = denied(await $.tool.call({ tool: 'Bash', command: 'env X=1 git -C repo push' }))
        expect(second).toContain('git.md: rule delivered above, retry after reading it.')
        expect(second).not.toContain('Git rule body.')
        expect(w.toolCalls).toEqual([])

        await step($, 1)
        const third = await $.tool.call({ tool: 'Bash', command: 'git push origin main' })
        expect(denied(third)).toBeUndefined()
        expect(third.result).toBe('ok')
        expect(third.context).toBeUndefined()
        expect(w.toolCalls).toEqual(['git push origin main'])
    })

    test('a gated MCP tool denies once with the rule', async ($, on) => {
        world(on)
        const first = denied(await $.tool.call({ tool: 'mcp__slack__chat_post_message', channel: 'C1', text: 'hi' } as never))
        expect(first).toContain('Voice rule body.')
        await step($, 1)
        expect(denied(await $.tool.call({ tool: 'mcp__slack__chat_post_message', channel: 'C1', text: 'hi' } as never))).toBeUndefined()
    })

    test('an after trigger rides the result once', async ($, on) => {
        const w = world(on)
        const failed = await $.tool.call({ tool: 'Bash', command: 'otto ci' })
        expect(failed.context).toEqual(['Contents of ' + REAL_DIR + '/otto.md:\n\n# Otto'])
        const again = await $.tool.call({ tool: 'Bash', command: 'otto ci' })
        expect(again.context).toBeUndefined()
        expect(w.logs.filter((l) => l.startsWith('rules: inject otto.md')).length).toBe(1)
    })

    test('an errored call still carries its after rule', async ($, on) => {
        world(on)
        const r = await $.tool.call({ tool: 'Bash', command: 'git log --bad' })
        expect(r.isError).toBe(true)
        expect(r.context).toEqual(['Contents of ' + REAL_DIR + '/git.md:\n\n# Git\n\nGit rule body.'])
    })

    test('a compaction that installs clears the loop; a precompute and a skip do not', async ($, on) => {
        world(on)
        expect((await $.tool.call({ tool: 'Bash', command: 'otto ci' })).context?.length).toBe(1)
        await $.session.compact({ trigger: 'precompute', messages: SUMMARY } as never)
        expect((await $.tool.call({ tool: 'Bash', command: 'otto ci' })).context).toBeUndefined()
        await $.session.compact({ trigger: 'manual', messages: SUMMARY } as never)
        expect((await $.tool.call({ tool: 'Bash', command: 'otto ci' })).context).toBeUndefined()
        await $.session.compact({ trigger: 'auto', messages: SUMMARY } as never)
        expect((await $.tool.call({ tool: 'Bash', command: 'otto ci' })).context?.length).toBe(1)
    })

    test('loops are separate: a subagent gets its own copy of a rule main already has', async ($, on) => {
        world(on)
        expect((await $.tool.call({ tool: 'Bash', command: 'otto ci' })).context?.length).toBe(1)
        expect((await $.tool.call({ tool: 'Bash', command: 'otto ci', agentId: 'a1' } as never)).context?.length).toBe(1)
    })
})

describe('rule routing: the latch', () => {
    test('a forced throw in the drop hook latches, re-asks, and the same attachment then passes unchanged', async ($, on) => {
        const w = world(on)
        w.listFails = true
        const text = nested(REAL_DIR + '/git.md')
        const failed = await $.prompt.attachment({ type: 'nested_memory', text, origin: { kind: 'engine' } })
        expect(failed.text).toBe(text)
        expect(w.invalidated).toEqual(['prompt.attachment'])
        expect(w.status).toEqual(['rules: router failed, full load restored'])
        expect(w.state['routingOff']).toEqual(expect.stringContaining('prompt.attachment failed: '))
        expect(String(w.state['routingOff'])).toContain('forced: fs.list failed')
        expect(w.logs.some((l) => l.includes('forced: fs.list failed'))).toBe(true)

        w.listFails = false
        const again = await $.prompt.attachment({ type: 'nested_memory', text, origin: { kind: 'engine' } })
        expect(again.text).toBe(text)
        expect(w.invalidated).toEqual(['prompt.attachment'])
        const r = await $.tool.call({ tool: 'Bash', command: 'git push' })
        expect(denied(r)).toBeUndefined()
        expect(r.context).toBeUndefined()
    })

    test('rule_routing false latches quietly on the first hook and routes nothing', { options: { rule_routing: false } }, async ($, on) => {
        const w = world(on)
        const text = nested(REAL_DIR + '/git.md')
        expect((await $.prompt.attachment({ type: 'nested_memory', text, origin: { kind: 'engine' } })).text).toBe(text)
        expect(w.invalidated).toEqual(['prompt.attachment'])
        expect(w.status).toEqual([])
        expect(w.state['routingOff']).toBe('rule_routing is false')
        expect(denied(await $.tool.call({ tool: 'Bash', command: 'git push' }))).toBeUndefined()
    })
})
