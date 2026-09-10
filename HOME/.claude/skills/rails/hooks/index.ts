import type { EngineInterface, Register, ToolCallResult } from 'claude-code'

/**
 * rails: gh persona
 *
 * Every `gh` invocation the Bash tool runs gets an explicit GH_PERSONA prefix.
 * `~/repos/tatari-tv/**` is work, everything else is home. An org named in the
 * gh arguments themselves beats the cwd, because the recurring failure is a
 * tatari-tv call made from OUTSIDE the work tree: the `gh()` shell function
 * guesses from $PWD, picks the home token, and a private work repo comes back
 * 404 (see rules/secrets.md).
 */

type Persona = 'work' | 'home'
type Spot = { at: number; persona: Persona }
type Verdict = { persona: Persona | null; why: string }

const WORK_MARKER = '/repos/tatari-tv'
const WORK_ORG = 'tatari-tv'
const HOME_ORG = 'scottidler'

/** An explicit choice already in the command wins; never second-guess it. */
const EXPLICIT = /\b(?:GH_PERSONA|GH_TOKEN|GITHUB_TOKEN)=/

/*
 * The engine normalizes a leading env assignment when it matches Bash
 * permission rules, so `Bash(gh cache delete:*)` in settings.json still denies
 * the rewritten `GH_PERSONA=work gh cache delete ...`. Verified live 2026-09-10
 * against both rule forms: this hook cannot move a command out from under a
 * deny rule, so it has no reason to leave destructive verbs alone.
 */

const SEP = new Set([';', '|', '&', '\n', '(', ')', '{', '}'])
const WORD = /^[^\s;|&()<>]+/
const ASSIGN = /^[A-Za-z_][A-Za-z0-9_]*=/
/** Keywords a simple command may follow, so `then gh ...` is still a gh spot. */
const TRANSPARENT = new Set(['then', 'do', 'else', 'elif', '!'])

/**
 * Byte offsets of every `gh` that starts a simple command, quote-aware.
 *
 * Scanning stops at an unquoted `<<`: a heredoc body is data, and a `gh` inside
 * one is text in a PR body, not a command.
 */
function ghSpots(command: string): number[] {
    const spots: number[] = []
    let i = 0
    let start = true
    let quote = ''
    while (i < command.length) {
        const c = command.charAt(i)
        if (quote !== '') {
            if (c === '\\' && quote === '"') { i += 2; continue }
            if (c === quote) { quote = '' }
            i += 1
            continue
        }
        if (c === '\\') { i += 2; continue }
        if (c === '"' || c === "'") { quote = c; start = false; i += 1; continue }
        if (c === '<' && command.charAt(i + 1) === '<') { break }
        if (SEP.has(c)) { start = true; i += 1; continue }
        if (c === ' ' || c === '\t' || c === '\r') { i += 1; continue }
        const word = WORD.exec(command.slice(i))
        if (word === null) { i += 1; continue }
        const text = word[0]
        if (start) {
            if (text === 'gh') { spots.push(i); start = false; i += text.length; continue }
            if (ASSIGN.test(text) || TRANSPARENT.has(text)) { i += text.length; continue }
            start = false
        }
        i += text.length
    }
    return spots
}

/** The one gh invocation starting at `at`, cut at the next unquoted separator. */
function segment(command: string, at: number): string {
    let i = at
    let quote = ''
    while (i < command.length) {
        const c = command.charAt(i)
        if (quote !== '') {
            if (c === '\\' && quote === '"') { i += 2; continue }
            if (c === quote) { quote = '' }
            i += 1
            continue
        }
        if (c === '\\') { i += 2; continue }
        if (c === '"' || c === "'") { quote = c; i += 1; continue }
        if (SEP.has(c)) { break }
        i += 1
    }
    return command.slice(at, i)
}

function inWorkTree(cwd: string): boolean {
    return cwd === WORK_MARKER || cwd.endsWith(WORK_MARKER) || cwd.includes(WORK_MARKER + '/')
}

/** Which persona one gh invocation needs, and the reason to put in the transcript. */
function personaFor(seg: string, cwd: string): Verdict {
    const work = seg.includes(WORK_ORG)
    const home = seg.includes(HOME_ORG)
    if (work && home) {
        return { persona: null, why: 'names both orgs: set GH_PERSONA yourself' }
    }
    if (work) { return { persona: 'work', why: WORK_ORG + ' in the args' } }
    if (home) { return { persona: 'home', why: HOME_ORG + ' in the args' } }
    return inWorkTree(cwd)
        ? { persona: 'work', why: 'cwd under ' + WORK_MARKER }
        : { persona: 'home', why: 'cwd outside ' + WORK_MARKER }
}

/** Splice the prefixes in right to left, so earlier offsets stay valid. */
function inject(command: string, spots: readonly Spot[]): string {
    let out = command
    const ordered = [...spots].sort((a, b) => b.at - a.at)
    for (const spot of ordered) {
        out = out.slice(0, spot.at) + 'GH_PERSONA=' + spot.persona + ' ' + out.slice(spot.at)
    }
    return out
}

function withContext<R extends ToolCallResult>(r: R, line: string): R {
    if (r.deny !== undefined || r.isError === true) { return r }
    return { ...r, context: [...(r.context ?? []), line] }
}

function debug($: EngineInterface, enabled: boolean, line: string): void {
    if (enabled) { $.ui.log('rails/gh-persona: ' + line) }
}

export const register: Register = (on, options) => {
    const active = options['gh_persona'] !== false
    const verbose = options['debug'] === true

    on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
        const command = e.command
        if (!active || typeof command !== 'string') { return next(e) }
        if (EXPLICIT.test(command)) {
            debug($, verbose, 'skip: command sets a persona or token itself')
            return next(e)
        }
        const spots = ghSpots(command)
        if (spots.length === 0) { return next(e) }

        const cwd = await $.session.cwd()
        debug($, verbose, 'gh spots=' + spots.length + ' cwd=' + cwd)

        const picked: Spot[] = []
        const whys: string[] = []
        for (const at of spots) {
            const verdict = personaFor(segment(command, at), cwd)
            if (verdict.persona === null) {
                whys.push('none, ' + verdict.why)
                continue
            }
            picked.push({ at, persona: verdict.persona })
            whys.push(verdict.persona + ', ' + verdict.why)
        }
        const why = whys.join(' | ')

        if (picked.length === 0) {
            debug($, verbose, 'no rewrite: ' + why)
            return withContext(await next(e), 'rails: GH_PERSONA not set (' + why + ')')
        }
        const rewritten = inject(command, picked)
        debug($, verbose, 'rewrote: ' + rewritten)
        const r = await next({ ...e, command: rewritten })
        return withContext(r, 'rails: GH_PERSONA injected (' + why + ')')
    })
}

export const internals = { ghSpots, segment, personaFor, inject, inWorkTree }
