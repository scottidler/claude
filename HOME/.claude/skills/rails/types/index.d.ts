// rails' contract: the values it keeps in `$.state` for rule routing
// (docs/design/2026-10-08-rule-routing.md). Plain JSON, since a Map or a Set
// reads back as `{}`.

/** Per rule per loop: denied with its text (`pending`), or in a request the model read. */
export type RailsDelivery = 'pending' | 'delivered'

/**
 * One loop's ledger. `rules` maps a routed rule's real path (or `pointer`, the
 * text a flush sends when the rules cannot be read) to how far it got.
 */
export type RailsLoopLedger = { rules: Record<string, RailsDelivery> }

/** Keyed by loop: a subagent's `agentId`, or `main`. */
export type RailsRuleLedger = Record<string, RailsLoopLedger>

declare module 'claude-code' {
    interface PluginState {
        rails: {
            ruleLedger: RailsRuleLedger
            /** Why routing is off for this session; never written while it is on. */
            routingOff: string
        }
    }
}
