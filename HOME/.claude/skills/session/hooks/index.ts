import type { Register, SessionContextBreakdown } from 'claude-code'

/**
 * session: one tool, `mcp__session__info`, that answers with the session's facts.
 *
 * The answer is a JSON string: core rejects an object `tool.call` result
 * (Phase 0 (b), docs/design/2026-10-16-self-session-tool.md). Core does not
 * enforce the input schema either (Phase 0 (g)), so `breakdown` is re-checked
 * here and an unknown value is denied.
 *
 * `seat` says whether the latest prompt was typed at this host's own keyboard.
 * Under herdr every pane inherits the server's environment, so SSH_CONNECTION
 * cannot tell. The kernel stamps a terminal's atime when it reads a keystroke
 * (what `w` shows as IDLE), so a local herdr client whose terminal was read at
 * submit time means the prompt was typed here. A remote attach arrives through
 * `herdr remote-client-bridge` in an sshd login session and reads no local
 * terminal.
 */

const TOOL = 'info'

const DESCRIPTION = "This session's id, cwd, project root, git repo, context-window fill, cost, prompt count and start time. "
    + 'Context figures are from the last API response, so they miss the current turn, and are absent right after a compaction. '
    + 'Pass breakdown (summary: local estimate, free | full: counted like /context, slower) for the per-category split; '
    + 'its percentage is against the compaction window. '
    + "From a subagent, context figures are the main conversation's. "
    + 'costUsd leaves out the response that made this call: it is priced only once that response ends. '
    + "seat.promptTypedOnHost: true when the latest prompt was typed at seat.host's own keyboard, "
    + 'false when it came over SSH (seat.remotePeers: who is attached that way now), null when unknown.'

const INPUT_SCHEMA = {
    type: 'object',
    properties: { breakdown: { type: 'string', enum: ['summary', 'full'] } },
    additionalProperties: false,
}

type Breakdown = 'summary' | 'full'

export type SessionFacts = {
    sessionId: string
    agentId?: string
    cwd: string
    root: string
    repo: { root: string; remote: string | null } | null
    context: {
        tokens?: number
        window: number
        percent?: number
        breakdown?: Omit<SessionContextBreakdown, 'gridRows'>
    }
    costUsd?: number
    turns: number
    startedAt: string
    seat: Seat
}

export type Seat = {
    host: string
    promptTypedOnHost: boolean | null
    promptAt: string | null
    remotePeers: { ip: string; host: string | null }[]
}

// Prints `H <hostname>`, then per client `L <tty> <atime s>` when it sits on a
// local terminal or `R <ip> [<name>]` when its logind session is remote. The
// clients are herdr's when this session runs in a herdr pane (skipping herdr
// processes inside panes), else this session's own process.
const SEAT_PROBE = String.raw`echo "H $(hostname)"
under() { q=$1; while [ "$q" -gt 1 ] 2>/dev/null; do [ "$q" = "$2" ] && return 0; q=$(ps -o ppid= -p "$q" | tr -d ' '); done; return 1; }
seat() {
    s=$(sed -n 's/.*session-\([^./]*\)\.scope.*/\1/p' /proc/$1/cgroup)
    if [ -n "$s" ] && [ "$(loginctl show-session "$s" -p Remote --value)" = yes ]; then
        ip=$(loginctl show-session "$s" -p RemoteHost --value)
        echo "R $ip $(getent hosts "$ip" | awk '{print $2}')"
        return
    fi
    t=$(ps -o tty= -p $1 | tr -d ' ')
    [ -n "$t" ] && [ "$t" != "?" ] && echo "L $t $(stat -c %X /dev/$t)"
}
server=$(pgrep -fx '.*herdr server' | head -1)
if [ -z "$server" ] || ! under $PPID "$server"; then seat $PPID; exit 0; fi
for p in $(pgrep -x herdr); do
    [ "$p" = "$server" ] || under "$p" "$server" || seat "$p"
done
`

// The kernel moves a terminal's atime once per 8-second window
// (tty_update_time), so a keystroke at submit can read up to 8 s stale.
const ATIME_SLACK_S = 9

/** Reads the probe's lines against the prompt's submit time. */
export function readSeat(stdout: string, promptAtMs: number | null): Seat {
    const seat: Seat = { host: '', promptTypedOnHost: null, promptAt: null, remotePeers: [] }
    const atimes: number[] = []
    for (const line of stdout.split('\n')) {
        const [kind, a, b] = line.trim().split(/\s+/)
        if (kind === 'H' && a !== undefined) { seat.host = a }
        if (kind === 'L' && b !== undefined && /^\d+$/.test(b)) { atimes.push(Number(b)) }
        if (kind === 'R' && a !== undefined) { seat.remotePeers.push({ ip: a, host: b ?? null }) }
    }
    if (promptAtMs === null) { return seat }
    seat.promptAt = new Date(promptAtMs).toISOString()
    const submitS = Math.floor(promptAtMs / 1000)
    if (atimes.some(t => t >= submitS - ATIME_SLACK_S && t <= submitS + 1)) {
        seat.promptTypedOnHost = true
    } else if (seat.remotePeers.length > 0) {
        seat.promptTypedOnHost = false
    }
    return seat
}

function probeSeat($: { process: { run: (argv: readonly string[], init?: { timeoutMs?: number }) => Promise<{ stdout: string }> } }): Promise<string> {
    return $.process.run(['sh', '-c', SEAT_PROBE], { timeoutMs: 5000 }).then(r => r.stdout)
}

/** `https://tok@host/x` -> `https://host/x`: a remote URL can carry a token in its userinfo. */
export function stripUserinfo(remote: string): string {
    return remote.replace(/^([a-z][a-z0-9+.-]*:\/\/)[^/]*@/i, '$1')
}

/** A rejection names the `$.session` method it came from, so the model can say what failed. */
async function named<T>(method: string, call: Promise<T>): Promise<T> {
    try {
        return await call
    } catch (error) {
        throw new Error(method + ': ' + (error instanceof Error ? error.message : String(error)))
    }
}

// Keys the engine itself puts on a tool.call event (ToolCallReserved, AgentLoop,
// ToolRequestMeta in the 2.1.302 types). Any other key is model input. A key a
// later engine adds denies every call until it is listed here, by Scott's ruling.
const ENGINE_KEYS = new Set(['tool', 'tool_use_id', 'consent', 'agentId', 'requestMeta'])
const INPUT_KEYS = new Set(['breakdown'])

export const register: Register = (on) => {
    // The probe runs at submit, while the keystroke's atime is fresh. A reload
    // starts this over, so the seat reads null until the next prompt.
    let prompt: { atMs: number; probe: string } | null = null

    on('prompt.submit', async ($, e, next) => {
        if (e.isMeta !== true) {
            try {
                prompt = { atMs: await $.clock.now(), probe: await probeSeat($) }
            } catch {
                prompt = null
            }
        }
        return next(e)
    })

    on('session.start', ($, e, next) =>
        $.tool.register({ name: TOOL, description: DESCRIPTION, inputSchema: INPUT_SCHEMA, isDeferred: false }).then(() => next(e)),
    )

    on('tool.call', { tool: 'mcp__session__info' }, async ($, e) => {
        const unknown = Object.keys(e).filter(k => !ENGINE_KEYS.has(k) && !INPUT_KEYS.has(k))
        if (unknown.length > 0) {
            return { deny: 'input: unknown key ' + unknown.map(k => JSON.stringify(k)).join(', ') + '; the only input is "breakdown"' }
        }
        const asked = (e as { breakdown?: unknown }).breakdown
        if (asked !== undefined && asked !== 'summary' && asked !== 'full') {
            return { deny: 'breakdown: expected "summary" or "full", got ' + JSON.stringify(asked) }
        }
        const breakdown = asked as Breakdown | undefined

        const now = probeSeat($).catch(() => '')
        let read
        try {
            read = await Promise.all([
                named('id', $.session.id()),
                named('cwd', $.session.cwd()),
                named('root', $.session.root()),
                named('repo', $.session.repo()),
                named('turns', $.session.turns()),
                named('usage', $.session.usage(breakdown === undefined ? undefined : { breakdown })),
            ])
        } catch (error) {
            return { deny: error instanceof Error ? error.message : String(error) }
        }
        const [sessionId, cwd, root, repo, turns, usage] = read

        const context: SessionFacts['context'] = { window: usage.context.window }
        if (usage.context.tokens !== undefined) { context.tokens = usage.context.tokens }
        if (usage.context.percent !== undefined) { context.percent = usage.context.percent }
        if (breakdown !== undefined) {
            const full = usage.context.breakdown
            if (full === undefined) { return { deny: 'breakdown: not returned' } }
            const { gridRows: _drawingGrid, ...split } = full
            context.breakdown = split
        }

        const facts: SessionFacts = {
            sessionId,
            cwd,
            root,
            repo: repo === null ? null : { root: repo.root, remote: repo.remote === null ? null : stripUserinfo(repo.remote) },
            context,
            turns,
            startedAt: new Date(usage.startedAt).toISOString(),
            seat: readSeat(prompt?.probe ?? await now, prompt?.atMs ?? null),
        }
        // Who is attached is read now, not at submit: it can change mid-turn.
        facts.seat.remotePeers = readSeat(await now, null).remotePeers
        const agentId = (e as { agentId?: string }).agentId
        if (agentId !== undefined) { facts.agentId = agentId }
        if (usage.cost?.usd !== undefined) { facts.costUsd = usage.cost.usd }

        return { result: JSON.stringify(facts) }
    }).catch(($, e, next) => ({ deny: 'session: ' + next.error.message }))
}
