import type { EngineInterface, HookFailure, Register, ToolCallResult } from 'claude-code'
import { chainVerdict, emdashReason, judgeToolCall, surfaceOf } from './rules'
import type { ChainVerdict, Surface } from './rules'

/**
 * voice-guard at `tool.call`, Phase 2: shadow mode for the em-dash rule
 * (docs/design/2026-11-18-voice-mod.md, "The chain invariant").
 *
 * Shadow (`enforce` off, the default): judge the call, `await next(e)`, log the
 * mod's verdict beside the chain's, and return the chain's result untouched.
 * The settings hooks beneath (`emdash.sh`, `git-release-guard.sh`, the rest)
 * decide. Enforce: a violation returns `{ deny }`, which ends the chain; a pass
 * still returns `next(e)`. Every failure fails open through `next(e)`, as
 * `emdash.sh:48-49` does, and leaves a `catch` row.
 */

/**
 * The mod's log: `~/.local/state/voice-guard/<sessionId>.<copyTag>.jsonl`,
 * the scheme of rails' router log (`rails/hooks/index.ts:1156-1172`).
 *
 * `$.fs.write` writes whole files only, so this copy keeps the session's rows
 * in memory and rewrites its own file on each one, serialized. One file per
 * module copy: a hot reload loads a second copy beside the first, and two
 * whole-file writers on one file lose each other's rows. Past `ROW_CAP` the
 * oldest rows go and the file opens with a `dropped` row counting them.
 */
const LOG_DIR = '/.local/state/voice-guard'
const ROW_CAP = 2000

type Mode = 'shadow' | 'enforce'

/** One judged call: the Data Model's row fields that apply at `tool.call`. */
type Row = {
    /** Null on a catch row for a call no matcher covers. */
    surface: Surface | null
    tool: string
    rule: string | null
    label: string | null
    modVerdict: 'allow' | 'deny' | null
    chainResult: ChainVerdict | null
    mode: Mode
    agentId: string | null
    error?: string
}

type ModLog = {
    tag: string
    sessionId: string | null
    path: string | null
    rows: string[]
    dropped: number
    chain: Promise<void>
    /** A write failure is noted in the debug log once, then only swallowed. */
    noted: boolean
}

/** This copy's part of the file name: its load time, then a random suffix for two loads in one millisecond. */
function copyTag(): string {
    return Date.now().toString() + '-' + Math.random().toString(36).slice(2, 8)
}

function newModLog(): ModLog {
    return { tag: copyTag(), sessionId: null, path: null, rows: [], dropped: 0, chain: Promise.resolve(), noted: false }
}

function logContent(log: ModLog): string {
    const head = log.dropped > 0 ? JSON.stringify({ event: 'dropped', count: log.dropped }) + '\n' : ''
    return head + log.rows.map((r) => r + '\n').join('')
}

/** Point the log at the session's file; a new session id (a `/clear`) starts a file of its own. */
async function openFor($: EngineInterface, log: ModLog): Promise<string> {
    const id = await $.session.id()
    if (id !== log.sessionId || log.path === null) {
        const home = await $.env.get('HOME')
        if (home === undefined || home === '') { throw new Error('HOME is unset') }
        log.sessionId = id
        log.path = home + LOG_DIR + '/' + id + '.' + log.tag + '.jsonl'
        log.rows = []
        log.dropped = 0
    }
    return id
}

async function writeRow($: EngineInterface, log: ModLog, row: Row): Promise<void> {
    const session = await openFor($, log)
    log.rows.push(JSON.stringify({ ts: new Date().toISOString(), session, event: 'tool.call', ...row }))
    while (log.rows.length > ROW_CAP) {
        log.rows.shift()
        log.dropped += 1
    }
    await $.fs.write(log.path as string, logContent(log))
}

function noteLogFailure($: EngineInterface, log: ModLog, err: unknown): void {
    if (log.noted) { return }
    log.noted = true
    const message = err instanceof Error ? err.message : String(err)
    try { $.ui.log('voice-guard: log write failed (' + (log.path ?? 'no path') + '): ' + message, { to: 'debug' }) } catch { /* nowhere left to say it */ }
}

/**
 * Queue one row. Never awaited by a hook and never rejects: a log that cannot
 * be written must not hold up or fail the tool call.
 */
function record($: EngineInterface, log: ModLog, row: Row): Promise<void> {
    log.chain = log.chain
        .then(() => writeRow($, log, row))
        .catch((err: unknown) => { noteLogFailure($, log, err) })
    return log.chain
}

/** The call's own fields: `e` less what the engine stamps on every call. */
function inputOf(e: Record<string, unknown>): Record<string, unknown> {
    const { tool: _tool, tool_use_id: _id, agentId: _agent, consent: _consent, ...input } = e
    return input
}

/** Why the hook failed, as the engine reports it: `throw` or `timeout`, then the message. */
function errorText(f: HookFailure): string {
    return f.kind + (f.message === undefined ? '' : ': ' + f.message)
}

export const register: Register = (on, options) => {
    const mode: Mode = options['enforce'] === true ? 'enforce' : 'shadow'
    const log = newModLog()

    on('tool.call', async ($, e, next) => {
        const tool = String(e.tool)
        const surface = surfaceOf(tool)
        if (surface === null) { return next(e) }
        const v = judgeToolCall(tool, inputOf(e as unknown as Record<string, unknown>))
        const base = {
            surface, tool, rule: v?.rule ?? null, label: v?.label ?? null,
            modVerdict: v === null ? 'allow' as const : 'deny' as const, mode, agentId: e.agentId ?? null,
        }
        if (v !== null && mode === 'enforce') {
            void record($, log, { ...base, chainResult: null })
            return { deny: emdashReason(v) }
        }
        const r: ToolCallResult = await next(e)
        void record($, log, { ...base, chainResult: chainVerdict(r) })
        return r
    }).catch(async ($, e, next) => {
        // Fail open: `next` is replay-safe here, so a hook that had already
        // called it gets the chain's settled result back, nothing run twice.
        const r = await next(e)
        const tool = String(e.tool)
        void record($, log, {
            surface: surfaceOf(tool), tool, rule: 'catch', label: null, modVerdict: null,
            chainResult: chainVerdict(r), mode, agentId: e.agentId ?? null, error: errorText(next.error),
        })
        return r
    })
}
