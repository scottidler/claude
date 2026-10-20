/**
 * rails rule routing, end to end through the engine's own chain
 * (`claude plugin test`, Phase 0 (j)). The test's `on` hooks sit beneath
 * rails and stand for the engine: the file system, `$.state`, `$.ui` and the
 * bottom of each event are answered here, from memory.
 *
 * The kit runs with no file system, so the routed dir is a small synthetic
 * one with the real classification (git, marquee, otto, voice) and stub
 * bodies, and the bulk-loaded rules dir is a few stubs the misplacement scan
 * reads. `rules.spec.ts` covers the real rule files under bun.
 */
import { describe, expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

const HOME = '/home/saidler'
const LINK_DIR = HOME + '/repos/.claude/routed'
const BULK_DIR = HOME + '/repos/.claude/rules'
const SESSION = 'sess-1'
const LOG_DIR = HOME + '/.local/share/rails/router'
/** One module copy's file for a session: `<id>.<load ms>-<random>.log`. */
const logFileOf = (session: string): RegExp => new RegExp('^' + LOG_DIR.replace(/[./]/g, '\\$&') + '/' + session + '\\.\\d+-[0-9a-z]+\\.log$')
const RKVR = HOME + '/.cargo/bin/rkvr'
const DAY = 24 * 60 * 60 * 1000
const REAL_DIR = HOME + '/repos/scottidler/claude/HOME/repos/.claude/routed'

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

const ROUTED: Record<string, string> = { 'git.md': GIT, 'marquee.md': MARQUEE, 'otto.md': OTTO, 'voice.md': VOICE }
const FRAMED: Record<string, string> = {
    'git.md': 'Contents of ' + REAL_DIR + '/git.md:\n\n# Git\n\nGit rule body.',
    'marquee.md': 'Contents of ' + REAL_DIR + '/marquee.md:\n\n# Marquee',
    'otto.md': 'Contents of ' + REAL_DIR + '/otto.md:\n\n# Otto',
    'voice.md': 'Contents of ' + REAL_DIR + '/voice.md:\n\n# Voice\n\nVoice rule body.',
}
const ALL_FOUR = ['git.md', 'marquee.md', 'otto.md', 'voice.md'].map((n) => FRAMED[n] as string)

/** A compaction leaves at least one message. */
const SUMMARY = [{ role: 'user', text: 'summary', toolUses: [] }]

/** What the engine beneath rails saw and was asked, for the assertions. */
type World = {
    logs: string[]
    status: (string | undefined)[]
    state: Record<string, unknown>
    toolCalls: string[]
    /** The routed dir as it lists, by name; a name with no text is a dangling link. */
    routed: Record<string, string | null>
    /** `~/repos/.claude/routed` exists. */
    routedExists: boolean
    /** The bulk rules dir the misplacement scan reads, by name. */
    bulk: Record<string, string>
    /** Listing the bulk rules dir fails. */
    scanFails: boolean
    /** The next n reads of a routed file fail. */
    routedReadFails: number
    /** Every routed read fails. */
    routedUnreadable: boolean
    /** Files `$.fs.write` wrote, by path, last write wins. */
    files: Record<string, string>
    writes: number
    writeFails: boolean
    /** What the router log directory lists. */
    logDir: { name: string; kind: 'file' | 'dir'; mtimeMs: number }[]
    runs: string[][]
    /** What `$.session.id()` answers; a `/clear` moves it on. */
    sessionId: string
    /** `$.state.get` rejects. */
    stateFails: boolean
    /** `$.state.set` rejects. */
    setFails: boolean
    /** `$.session.id()` never settles, so the router log never opens. */
    hangs: boolean
    /** Every path `$.fs.read` was asked for. */
    reads: string[]
    /** `~/.cargo/bin/rkvr` exists. */
    rkvr: boolean
    /** The engine refuses the prompt (a later hook drops it). */
    dropPrompts: boolean
}

/** Answer every noun rails calls, from memory, and the bottom of each event it hooks. */
function world(on: On): World {
    const w: World = {
        logs: [], status: [], state: {}, toolCalls: [], routed: { ...ROUTED }, routedExists: true,
        bulk: { 'taste.md': always('taste'), 'pr.md': always('pr') }, scanFails: false,
        routedReadFails: 0, routedUnreadable: false,
        files: {}, writes: 0, writeFails: false, logDir: [], runs: [],
        sessionId: SESSION, stateFails: false, setFails: false, hangs: false, reads: [], rkvr: true, dropPrompts: false,
    }
    mock.env(on, { HOME })
    on('session.id', () => (w.hangs ? new Promise<never>(() => undefined) : { value: w.sessionId }))
    on('session.end', ($, e) => ({ sessionId: e.sessionId }))
    on('session.version', () => ({ value: { version: '9.9.9-test' } }))
    on('fs.write', ($, e) => {
        if (w.writeFails) { return { deny: 'forced: fs.write failed' } }
        w.files[e.path] = e.text
        w.writes += 1
        return { value: undefined }
    })
    on('process.run', ($, e) => {
        w.runs.push([...e.argv])
        return { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    })
    on('fs.exists', ($, e) => ({ value: (e.path === LINK_DIR && w.routedExists) || (w.rkvr && e.path === RKVR) }))
    on('fs.list', ($, e) => {
        const entry = (name: string) => ({ name, kind: 'other' as const, size: 0, mtimeMs: 0, isLink: true })
        if (e.path === LOG_DIR) { return { value: w.logDir.map((f) => ({ ...f, size: 1, isLink: false })) } }
        if (e.path === BULK_DIR) {
            if (w.scanFails) { return { deny: 'forced: rules/ list failed' } }
            return { value: Object.keys(w.bulk).map(entry) }
        }
        expect(e.path).toBe(LINK_DIR)
        return { value: Object.keys(w.routed).map(entry) }
    })
    on('fs.read', ($, e) => {
        w.reads.push(e.path)
        const written = w.files[e.path]
        if (written !== undefined) { return { value: written } }
        if (e.path.startsWith(BULK_DIR + '/')) {
            const text = w.bulk[e.path.slice(BULK_DIR.length + 1)]
            if (text === undefined) { throw new Error('ENOENT ' + e.path) }
            return { value: text }
        }
        const text = w.routed[e.path.slice(LINK_DIR.length + 1)]
        if (!e.path.startsWith(LINK_DIR + '/') || text === undefined || text === null) { throw new Error('ENOENT ' + e.path) }
        if (w.routedUnreadable) { throw new Error('EACCES ' + e.path) }
        if (w.routedReadFails > 0) { w.routedReadFails -= 1; return { deny: 'forced: EIO' } }
        return { value: text }
    })
    on('fs.stat', ($, e) => {
        if (e.path.startsWith(LINK_DIR + '/') && w.routed[e.path.slice(LINK_DIR.length + 1)] === null) {
            return { value: { kind: 'other' as const, size: 0, mtimeMs: 0, isLink: true } }
        }
        const realPath = e.path.startsWith(LINK_DIR + '/') ? REAL_DIR + e.path.slice(LINK_DIR.length) : e.path
        return { value: { kind: 'file' as const, size: 1, mtimeMs: 0, isLink: realPath !== e.path, realPath } }
    })
    on('state.get', ($, e) => {
        if (w.stateFails) { return { deny: 'forced: state offline' } }
        const value = w.state[e.key]
        return { value: { value, version: value === undefined ? 0 : 1 } }
    })
    on('state.set', ($, e) => {
        if (w.setFails) { return { deny: 'forced: state.set failed' } }
        w.state[e.key] = JSON.parse(JSON.stringify(e.value))
        return { value: { isSet: true as const, version: 1 } }
    })
    on('ui.log', ($, e) => { w.logs.push(e.text); return { value: undefined } })
    on('ui.status', ($, e) => { w.status.push(e.text); return { value: undefined } })
    on('settings.read', () => ({ value: {} }))
    on('prompt.submit', ($, e) => {
        if (w.dropPrompts) { return { drop: 'forced' } as never }
        return e.context === undefined ? { text: e.text } : { text: e.text, context: e.context }
    })
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

/** Resolves once every write the router started has landed. */
async function settled(w: World): Promise<void> {
    let seen = -1
    while (seen !== w.writes) {
        seen = w.writes
        await new Promise((resolve) => setTimeout(resolve, 20))
    }
}

/** The paths of a session's router log files, once every write has landed. */
async function logPaths(w: World, session: string = SESSION): Promise<string[]> {
    await settled(w)
    return Object.keys(w.files).filter((p) => logFileOf(session).test(p))
}

/** The session's one router log file, once every write has landed. */
async function logFile(w: World, session: string = SESSION): Promise<string> {
    const paths = await logPaths(w, session)
    expect(paths.length).toBe(1)
    return w.files[paths[0] as string] ?? ''
}

/** A deny surfaces to the test's `$` as an errored result whose text is the reason. */
function denied(r: { deny?: string; isError?: true; text?: string }): string | undefined {
    if (r.deny !== undefined) { return r.deny }
    return r.isError === true ? r.text : undefined
}

/** One model request of the main loop, read to its end. */
async function step($: Engine, index: number, agentId?: string): Promise<void> {
    const s = $.turn.step({ turnId: 't1', index, model: 'm', messageCount: 1, ...(agentId === undefined ? {} : { agentId }) } as never)
    for await (const chunk of s) { void chunk }
    await s.result
}

const prompt = ($: Engine, text: string) => $.prompt.submit({ text, wait: false, origin: { kind: 'user' } } as never)

describe('rule routing: the inject path', () => {
    test('a prompt trigger injects on the way down, once per loop', async ($, on) => {
        const w = world(on)
        const r = await prompt($, 'push the branch')
        expect(r.context).toEqual([FRAMED['git.md']])
        const again = await prompt($, 'push it again')
        expect(again.context).toBeUndefined()
        expect(w.logs.filter((l) => l.startsWith('rules: inject git.md')).length).toBe(1)
        expect(w.logs).toContain('rules: index of 4 files, routed git.md marquee.md otto.md voice.md')
    })

    test('two gated calls for one rule in one step both deny; a third after turn.step runs', async ($, on) => {
        const w = world(on)
        const first = denied(await $.tool.call({ tool: 'Bash', command: 'git push origin main' }))
        expect(first).toContain('git.md must be in context before this call runs')
        expect(first).toContain(FRAMED['git.md'])
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

    test('an after inject and a gated call in one step: the gate still denies; after turn.step it runs', async ($, on) => {
        const w = world(on)
        const log = await $.tool.call({ tool: 'Bash', command: 'git log -1' })
        expect(log.context).toEqual([FRAMED['git.md']])
        const push = denied(await $.tool.call({ tool: 'Bash', command: 'git push origin main' }))
        expect(push).toContain('git.md: rule delivered above, retry after reading it.')
        expect(push).not.toContain('Git rule body.')
        expect(w.toolCalls).toEqual(['git log -1'])

        await step($, 1)
        expect(w.logs).toContain('rules: delivered git.md (turn.step) ' + REAL_DIR + '/git.md')
        const retry = await $.tool.call({ tool: 'Bash', command: 'git push origin main' })
        expect(denied(retry)).toBeUndefined()
        expect(retry.context).toBeUndefined()
        expect(w.toolCalls).toEqual(['git log -1', 'git push origin main'])
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
        const first = await $.tool.call({ tool: 'Bash', command: 'otto ci' })
        expect(first.context).toEqual([FRAMED['otto.md']])
        const again = await $.tool.call({ tool: 'Bash', command: 'otto ci' })
        expect(again.context).toBeUndefined()
        expect(w.logs.filter((l) => l.startsWith('rules: inject otto.md')).length).toBe(1)
    })

    test('an errored call still carries its after rule', async ($, on) => {
        world(on)
        const r = await $.tool.call({ tool: 'Bash', command: 'git log --bad' })
        expect(r.isError).toBe(true)
        expect(r.context).toEqual([FRAMED['git.md']])
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

    test('a state write that fails after a prompt claim leaves no rule marked delivered that never arrived', async ($, on) => {
        const w = world(on)
        w.setFails = true
        // The claim's write throws: the claim is released, the router latches,
        // and the same prompt carries the flush with git.md in it, once.
        const r = await prompt($, 'push the branch')
        expect(r.context).toEqual(ALL_FOUR)
        expect(w.logs.some((l) => l.startsWith('rules: prompt.submit failed: ') && l.includes('forced: state.set failed'))).toBe(true)
    })
})

describe('rule routing: placement', () => {
    test('a routed file with no usable trigger is eager: it rides each loop first carrier and the status names it', async ($, on) => {
        const w = world(on)
        w.routed['extra.md'] = always('extra')
        const r = await prompt($, 'what time is it')
        expect(r.context).toEqual(['Contents of ' + REAL_DIR + '/extra.md:\n\n# extra'])
        expect((await prompt($, 'and now')).context).toBeUndefined()
        expect(w.status).toContain('rules: no usable trigger in extra.md, injected at every first carrier')
        const sub = await $.tool.call({ tool: 'Read', file_path: '/x', agentId: 'a1' } as never)
        expect(sub.context).toEqual(['Contents of ' + REAL_DIR + '/extra.md:\n\n# extra'])
        expect(w.logs).toContain('rules: index of 5 files, routed git.md marquee.md otto.md voice.md')
    })

    test('an eager rule whose prompt was refused is released and rides the next one', async ($, on) => {
        const w = world(on)
        w.routed['extra.md'] = always('extra')
        w.dropPrompts = true
        await prompt($, 'first')
        w.dropPrompts = false
        expect((await prompt($, 'second')).context).toEqual(['Contents of ' + REAL_DIR + '/extra.md:\n\n# extra'])
        expect(w.logs.some((l) => l.startsWith('rules: release extra.md (carrier refused)'))).toBe(true)
    })

    test('a trigger map in rules/ is named as misplaced and never injected', async ($, on) => {
        const w = world(on)
        w.bulk['stray.md'] = "---\nload:\n  prompt: ['\\bpush\\b']\n---\n# Stray\n"
        const r = await prompt($, 'push the branch')
        await settled(w)
        expect(r.context).toEqual([FRAMED['git.md']])
        expect(w.logs).toContain('rules: stray.md has triggers but sits in rules/, bulk-loaded')
        expect(w.status).toContain('rules: stray.md has triggers but sits in rules/, bulk-loaded')
    })

    test('a rules/ scan that fails is logged and leaves routing on', async ($, on) => {
        const w = world(on)
        w.scanFails = true
        expect((await prompt($, 'push the branch')).context).toEqual([FRAMED['git.md']])
        await settled(w)
        expect(w.logs.some((l) => l.startsWith('rules: rules/ scan failed: '))).toBe(true)
        expect(w.state['routingOff']).toBeUndefined()
        expect(w.status).toEqual([])
    })
})

describe('rule routing: the flush latch', () => {
    test('a missing routed dir latches, and the same prompt carries a pointer to it', async ($, on) => {
        const w = world(on)
        w.routedExists = false
        const r = await prompt($, 'hello')
        expect(r.context?.length).toBe(1)
        expect(r.context?.[0]).toContain('rails: the rule router is off (prompt.submit failed: no routed rules: ' + LINK_DIR + ' does not exist)')
        expect(r.context?.[0]).toContain('not in context: every .md. Read the one this task needs from ' + LINK_DIR + '/ before acting.')
        const [path] = await logPaths(w)
        expect(w.status).toEqual([
            'rules: router failed (prompt.submit: no routed rules: ' + LINK_DIR + ' does not exist), routed rules owed to every loop; log ' + path,
            'rules: routed rules unreadable, pointer sent (main)',
        ])
        expect((await prompt($, 'again')).context).toBeUndefined()
    })

    test('an empty routed dir latches', async ($, on) => {
        const w = world(on)
        w.routed = {}
        await prompt($, 'hello')
        expect(String(w.state['routingOff'])).toContain('holds no .md file')
    })

    test('a dangling entry in the routed dir latches instead of being skipped', async ($, on) => {
        const w = world(on)
        w.routed['gone.md'] = null
        const r = await prompt($, 'hello')
        expect(String(w.state['routingOff'])).toContain('gone.md in ' + LINK_DIR + ' leads to no file')
        expect(r.context?.[0]).toContain('not in context: git.md, gone.md, marquee.md, otto.md, voice.md.')
    })

    test('a forced throw latches, and the same prompt carries all four routed rules', async ($, on) => {
        const w = world(on)
        w.routedReadFails = 1
        const r = await prompt($, 'hello')
        expect(r.context).toEqual(ALL_FOUR)
        expect(w.status[0]).toContain('rules: router failed (prompt.submit: rails: $.fs.read: forced: EIO)')
        expect(w.status[1]).toBe('rules: routed rules flushed (main)')
        expect((await prompt($, 'again')).context).toBeUndefined()
    })

    test('a rule a prompt already delivered is not flushed again', async ($, on) => {
        const w = world(on)
        expect((await prompt($, 'push it')).context).toEqual([FRAMED['git.md']])
        w.setFails = true
        // The otto claim's write throws: latch, and this call is denied with the three main still lacks.
        const r = denied(await $.tool.call({ tool: 'Bash', command: 'otto ci' }))
        for (const name of ['marquee.md', 'otto.md', 'voice.md']) { expect(r).toContain(FRAMED[name] as string) }
        expect(r).not.toContain('Git rule body.')
        expect(w.toolCalls).toEqual([])
    })

    test('after the latch a subagent first tool call is denied with all four; a sibling waits; after turn.step it runs', async ($, on) => {
        const w = world(on)
        w.routedReadFails = 1
        await prompt($, 'hello')
        const first = denied(await $.tool.call({ tool: 'Read', file_path: '/x', agentId: 'a1' } as never))
        for (const t of ALL_FOUR) { expect(first).toContain(t) }
        expect(first).toContain('must be in context before this call runs')
        const sibling = denied(await $.tool.call({ tool: 'Grep', pattern: 'x', agentId: 'a1' } as never))
        expect(sibling).toContain('rule delivered above, retry after reading it.')
        expect(sibling).not.toContain('Git rule body.')
        expect(w.toolCalls).toEqual([])
        await step($, 1, 'a1')
        const retry = await $.tool.call({ tool: 'Read', file_path: '/x', agentId: 'a1' } as never)
        expect(denied(retry)).toBeUndefined()
        expect(w.toolCalls).toEqual(['Read'])
        expect(w.status).toContain('rules: routed rules flushed (a1)')
    })

    test('the main loop runs tools once its prompt carried the flush', async ($, on) => {
        const w = world(on)
        w.routedReadFails = 1
        await prompt($, 'hello')
        expect(denied(await $.tool.call({ tool: 'Bash', command: 'git push origin main' }))).toBeUndefined()
        expect(w.toolCalls).toEqual(['git push origin main'])
    })

    test('after a flush and a compaction that installs, the next carrier flushes again', async ($, on) => {
        const w = world(on)
        w.routedReadFails = 1
        expect((await prompt($, 'hello')).context).toEqual(ALL_FOUR)
        expect((await prompt($, 'again')).context).toBeUndefined()
        await $.session.compact({ trigger: 'auto', messages: SUMMARY } as never)
        expect((await prompt($, 'after compaction')).context).toEqual(ALL_FOUR)
    })

    test('a flush that cannot read the rules sends the pointer once per context, and a subagent tool gets it as the deny', async ($, on) => {
        const w = world(on)
        w.routedUnreadable = true
        const r = await prompt($, 'hello')
        expect(r.context?.[0]).toContain('not in context: git.md, marquee.md, otto.md, voice.md. Read the one this task needs from ' + LINK_DIR + '/ before acting.')
        expect((await prompt($, 'again')).context).toBeUndefined()
        const sub = denied(await $.tool.call({ tool: 'Read', file_path: '/x', agentId: 'a1' } as never))
        expect(sub).toContain('rails: the rule router is off (')
        expect(sub).toContain('This call did not run; retry it after reading the rule it needs.')
        const sibling = denied(await $.tool.call({ tool: 'Read', file_path: '/y', agentId: 'a1' } as never))
        expect(sibling).toBe('rails: rule router pointer delivered above, retry after reading it.')
        expect(w.toolCalls).toEqual([])
    })

    test('rule_routing false flushes all four on the first prompt, with no status line', { options: { rule_routing: false } }, async ($, on) => {
        const w = world(on)
        expect((await prompt($, 'hello')).context).toEqual(ALL_FOUR)
        expect(w.status).toEqual([])
        expect(w.state['routingOff']).toBe('rule_routing is false')
        expect(w.logs).toContain('rules: routed rules flushed (main)')
    })
})

describe('rule routing: the router log', () => {
    test('a session leaves its start line, the index and every inject in its own file, stamped and tagged with the loop', async ($, on) => {
        const w = world(on)
        await prompt($, 'push the branch')
        await $.tool.call({ tool: 'Bash', command: 'otto ci', agentId: 'a1' } as never)
        const text = await logFile(w)
        const lines = text.split('\n').filter((l) => l !== '')
        expect(lines[0]).toMatch(/^\d{4}-\d\d-\d\dT[\d:.]+Z main rules: session sess-1 start, routing on, CC 9\.9\.9-test$/)
        expect(lines.some((l) => l.endsWith(' main rules: index of 4 files, routed git.md marquee.md otto.md voice.md'))).toBe(true)
        expect(lines.some((l) => l.endsWith(' main rules: inject git.md (prompt) ' + REAL_DIR + '/git.md'))).toBe(true)
        expect(lines.some((l) => l.endsWith(' a1 rules: inject otto.md (Bash) ' + REAL_DIR + '/otto.md'))).toBe(true)
        expect(text.endsWith('\n')).toBe(true)
    })

    test('a rejecting fs.write leaves routing on and is noted in the debug log once', async ($, on) => {
        const w = world(on)
        w.writeFails = true
        expect((await prompt($, 'push the branch')).context).toEqual([FRAMED['git.md']])
        await prompt($, 'otto please')
        await settled(w)
        expect(w.status).toEqual([])
        expect(w.state['routingOff']).toBeUndefined()
        expect(w.logs.filter((l) => l.startsWith('rules: router log write failed')).length).toBe(1)
        expect(denied(await $.tool.call({ tool: 'mcp__slack__chat_post_message', channel: 'C1', text: 'hi' } as never))).toContain('voice.md must be in context')
    })

    test('index build deletes only router logs older than 14 days', async ($, on) => {
        const w = world(on)
        const now = Date.now()
        w.logDir = [
            { name: 'old.log', kind: 'file', mtimeMs: now - 15 * DAY },
            { name: 'fresh.log', kind: 'file', mtimeMs: now - 13 * DAY },
            { name: 'old.txt', kind: 'file', mtimeMs: now - 30 * DAY },
            { name: 'old-dir.log', kind: 'dir', mtimeMs: now - 30 * DAY },
        ]
        await prompt($, 'hello')
        await settled(w)
        expect(w.runs).toEqual([[RKVR, 'rmrf', '--', LOG_DIR + '/old.log']])
        expect(w.logs).toContain('rules: pruned 1 router logs older than 14 days')
    })

    test('without rkvr nothing is deleted and the log says so', async ($, on) => {
        const w = world(on)
        w.rkvr = false
        w.logDir = [{ name: 'old.log', kind: 'file', mtimeMs: Date.now() - 15 * DAY }]
        await prompt($, 'hello')
        const text = await logFile(w)
        expect(w.runs).toEqual([])
        expect(text).toContain(' main rules: prune skipped, no rkvr on PATH or at ' + RKVR + ': 1 router logs older than 14 days kept\n')
    })

    test('a latch before the log opened still reaches the file, and the status names it (audit round 2, P1)', async ($, on) => {
        const w = world(on)
        w.stateFails = true
        expect((await prompt($, 'hello')).context).toEqual(ALL_FOUR)
        const [path] = await logPaths(w)
        expect(path).toMatch(logFileOf(SESSION))
        expect(w.status[0]).toBe('rules: router failed (prompt.submit: rails: $.state.get: forced: state offline), routed rules owed to every loop; log '
            + path)
        const lines = (w.files[path as string] ?? '').split('\n')
        expect(lines[0]).toMatch(/ main rules: session sess-1 start, routing on, CC 9\.9\.9-test$/)
        expect(lines.some((l) => l.endsWith(' main rules: routing off: prompt.submit failed: rails: $.state.get: forced: state offline'))).toBe(true)
    })

    test('the log never reads a file back (audit round 2, P3)', async ($, on) => {
        const w = world(on)
        await prompt($, 'push the branch')
        await $.tool.call({ tool: 'Bash', command: 'otto ci' })
        await settled(w)
        expect(w.reads.filter((p) => p.startsWith(LOG_DIR))).toEqual([])
    })

    test('a log that never opens does not hold up the rule_routing false flush (audit round 2, P2)', { options: { rule_routing: false } }, async ($, on) => {
        const w = world(on)
        w.hangs = true
        expect((await prompt($, 'hello')).context).toEqual(ALL_FOUR)
        expect(w.state['routingOff']).toBe('rule_routing is false')
    })

    test('after /clear the new session id gets its own file (audit round 2, P5)', async ($, on) => {
        const w = world(on)
        await prompt($, 'push the branch')
        await settled(w)
        await $.session.end({ reason: 'clear', sessionId: SESSION, resume: { id: SESSION } } as never)
        w.sessionId = 'sess-2'
        await prompt($, 'post to slack')
        await settled(w)
        // Any file for the new id at all, whatever its name: before the fix there was none.
        expect(Object.keys(w.files).filter((p) => p.startsWith(LOG_DIR + '/sess-2.'))).toHaveLength(1)
        const second = await logFile(w, 'sess-2')
        const first = await logFile(w, SESSION)
        expect(first).toContain(' main rules: session sess-1 end (clear), the next session logs to its own file\n')
        expect(first).not.toContain('inject voice.md')
        expect(second.split('\n')[0]).toMatch(/ main rules: session sess-2 start, routing on, CC 9\.9\.9-test$/)
        expect(second).toContain(' main rules: inject voice.md (prompt) ' + REAL_DIR + '/voice.md\n')
    })
})
