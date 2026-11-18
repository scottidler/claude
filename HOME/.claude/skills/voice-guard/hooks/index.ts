import type { Register } from 'claude-code'

/**
 * voice-guard, Phase 1: a pass-through. Every call goes to the chain beneath
 * unchanged, so loading the mod changes nothing. Phase 2 wires `rules.ts` in
 * shadow mode: judge, `await next(e)`, log both, return the chain's result.
 */
export const register: Register = (on) => {
    on('tool.call', async (_$, e, next) => next(e))
}
