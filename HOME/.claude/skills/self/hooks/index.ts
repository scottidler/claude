import type { Register, SessionContextBreakdown } from 'claude-code'

/**
 * self: one tool, `mcp__self__session`, that answers with the session's facts.
 *
 * The answer is a JSON string: core rejects an object `tool.call` result
 * (Phase 0 (b), docs/design/2026-10-16-self-session-tool.md). Core does not
 * enforce the input schema either (Phase 0 (g)), so `breakdown` is re-checked
 * here and an unknown value is denied.
 */

const TOOL = 'session'

const DESCRIPTION = "This session's id, cwd, project root, git repo, context-window fill, cost, prompt count and start time. "
    + 'Context figures are from the last API response, so they miss the current turn, and are absent right after a compaction. '
    + 'Pass breakdown (summary: local estimate, free | full: counted like /context, slower) for the per-category split; '
    + 'its percentage is against the compaction window. '
    + "From a subagent, context figures are the main conversation's."

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

export const register: Register = (on) => {
    on('session.start', ($, e, next) =>
        $.tool.register({ name: TOOL, description: DESCRIPTION, inputSchema: INPUT_SCHEMA, isDeferred: false }).then(() => next(e)),
    )

    on('tool.call', { tool: 'mcp__self__session' }, async ($, e) => {
        const asked = (e as { breakdown?: unknown }).breakdown
        if (asked !== undefined && asked !== 'summary' && asked !== 'full') {
            return { deny: 'breakdown: expected "summary" or "full", got ' + JSON.stringify(asked) }
        }
        const breakdown = asked as Breakdown | undefined

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
        }
        const agentId = (e as { agentId?: string }).agentId
        if (agentId !== undefined) { facts.agentId = agentId }
        if (usage.cost?.usd !== undefined) { facts.costUsd = usage.cost.usd }

        return { result: JSON.stringify(facts) }
    }).catch(($, e, next) => ({ deny: 'self: ' + next.error.message }))
}
