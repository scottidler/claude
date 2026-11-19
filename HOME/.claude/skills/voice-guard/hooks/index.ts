import type { EngineInterface, HookFailure, Register, ToolCallResult } from 'claude-code'
import {
    chainSourceOf, chainVerdict, denyIdsFrom, emdashReason, judgeOutward, judgeProse, judgeToolCall,
    ruleReason, staleHeartbeats, surfaceOf, verdictOf, warnText, HEARTBEAT_PREFIX,
} from './rules'
import type { ChainSource, ChainVerdict, Surface } from './rules'

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
 *
 * Phase 5 adds the phrase table (`rules.ts:RULES`). At an outward `tool.call`
 * every table hit is a `warn` row, unless its id is in the `deny_outward`
 * option and the rule is `deny-outward`: then it denies (enforce) or logs a
 * `deny` and passes through (shadow). At `turn.complete`, with
 * `warn_structural` on, the `warn` rules run over the final reply and their
 * text is shown beneath the answer; a terminal reply never blocks.
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
    event: 'tool.call' | 'turn.complete'
    /** Null on a catch row for a call no matcher covers; `reply` at `turn.complete`. */
    surface: Surface | 'reply' | null
    tool: string
    rule: string | null
    label: string | null
    modVerdict: 'allow' | 'deny' | 'warn' | null
    chainResult: ChainVerdict | null
    /** Which layer denied: `settings` (prefix), `plugin` (`{ deny }`), null on allow or when the mod itself denied. */
    chainSource: ChainSource | null
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
    log.rows.push(JSON.stringify({ ts: new Date().toISOString(), session, ...row }))
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

/**
 * The load check's heartbeat (docs/design/2026-11-18-voice-mod.md, Data
 * Model): `heartbeat.<sessionId>` in the log directory, written at
 * `session.start`. `hooks-preflight.sh` reads `last-session-id` and warns when
 * that session has no heartbeat. Keeps the newest `HEARTBEAT_KEEP`; the rest
 * go through `rkvr rmrf` (rules/safety.md), skipped without it. Never throws:
 * a heartbeat that cannot be written must not fail the session start, and the
 * missing file is exactly what preflight reports.
 */
async function writeHeartbeat($: EngineInterface): Promise<void> {
    try {
        const home = await $.env.get('HOME')
        if (home === undefined || home === '') { throw new Error('HOME is unset') }
        const dir = home + LOG_DIR
        const id = await $.session.id()
        await $.fs.write(dir + '/' + HEARTBEAT_PREFIX + id, new Date().toISOString() + '\n')
        const stale = staleHeartbeats(await $.fs.list(dir))
        if (stale.length === 0) { return }
        const rkvr = await findRkvr($, home)
        if (rkvr === null) { return }
        await $.process.run([rkvr, 'rmrf', '--', ...stale.map((n) => dir + '/' + n)])
    } catch (err) {
        try { $.ui.log('voice-guard: heartbeat failed: ' + (err instanceof Error ? err.message : String(err)), { to: 'debug' }) } catch { /* nowhere left to say it */ }
    }
}

/** The `rkvr` on the engine's PATH, else `~/.cargo/bin/rkvr`; null when neither exists (as rails finds it). */
async function findRkvr($: EngineInterface, home: string): Promise<string | null> {
    const path = (await $.env.get('PATH')) ?? ''
    const dirs = [...path.split(':').filter((d) => d.startsWith('/')), home + '/.cargo/bin']
    for (const dir of dirs) {
        const candidate = dir.replace(/\/+$/, '') + '/rkvr'
        if (await $.fs.exists(candidate)) { return candidate }
    }
    return null
}

export const register: Register = (on, options) => {
    const mode: Mode = options['enforce'] === true ? 'enforce' : 'shadow'
    const log = newModLog()
    const { ids: denyIds, unknown: unknownDenyIds } = denyIdsFrom(options['deny_outward'])
    const warnStructural = options['warn_structural'] === true
    let notedUnknown = false

    on('session.start', async ($, e, next) => {
        await writeHeartbeat($)
        return next(e)
    }).catch(async ($, e, next) => next(e))

    on('tool.call', async ($, e, next) => {
        const tool = String(e.tool)
        const surface = surfaceOf(tool)
        if (surface === null) { return next(e) }
        if (unknownDenyIds.length > 0 && !notedUnknown) {
            notedUnknown = true
            $.ui.log('voice-guard: deny_outward ignores ' + unknownDenyIds.join(', ') + ' (not a deny-outward rule id)', { to: 'debug' })
        }
        const input = inputOf(e as unknown as Record<string, unknown>)
        const v = judgeToolCall(tool, input)
        // The em-dash rule keeps its own path. Otherwise one row per table hit, or a single allow row.
        const hits = v === null ? judgeOutward(tool, input, warnStructural) : []
        const judged: { rule: string | null; label: string | null; modVerdict: 'allow' | 'deny' | 'warn' }[] =
            v !== null ? [{ rule: v.rule, label: v.label, modVerdict: 'deny' }]
                : hits.length > 0 ? hits.map((h) => ({ rule: h.rule, label: h.label, modVerdict: verdictOf(h, denyIds) }))
                    : [{ rule: null, label: null, modVerdict: 'allow' }]
        const denying = hits.find((h) => verdictOf(h, denyIds) === 'deny')
        const reason = v !== null ? emdashReason(v) : denying !== undefined ? ruleReason(denying) : null
        const base = { event: 'tool.call' as const, surface, tool, mode, agentId: e.agentId ?? null }
        if (reason !== null && mode === 'enforce') {
            for (const j of judged) { void record($, log, { ...base, ...j, chainResult: null, chainSource: null }) }
            return { deny: reason }
        }
        const r: ToolCallResult = await next(e)
        for (const j of judged) { void record($, log, { ...base, ...j, chainResult: chainVerdict(r), chainSource: chainSourceOf(r) }) }
        return r
    }).catch(async ($, e, next) => {
        // Fail open: `next` is replay-safe here, so a hook that had already
        // called it gets the chain's settled result back, nothing run twice.
        const r = await next(e)
        const tool = String(e.tool)
        void record($, log, {
            event: 'tool.call', surface: surfaceOf(tool), tool, rule: 'catch', label: null, modVerdict: null,
            chainResult: chainVerdict(r), chainSource: chainSourceOf(r), mode, agentId: e.agentId ?? null, error: errorText(next.error),
        })
        return r
    })

    on('turn.complete', async ($, e, next) => {
        const r = await next(e)
        // A subagent's answer is a report to its spawner, not a terminal reply to Scott.
        if (!warnStructural || e.agentId !== undefined || typeof e.answer !== 'string') { return r }
        const hits = judgeProse(e.answer, 'reply', true, 'the final reply')
        if (hits.length === 0) { return r }
        for (const h of hits) {
            void record($, log, {
                event: 'turn.complete', surface: 'reply', tool: '', rule: h.rule, label: h.label,
                modVerdict: 'warn', chainResult: null, chainSource: null, mode, agentId: null,
            })
        }
        return { ...r, text: warnText(hits) }
    }).catch(async ($, e, next) => next(e))
}
