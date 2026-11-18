import type { Violation } from '../types/index.d.ts'

/*
 * The em-dash rule, ported from emdash.sh. Pure functions: no `$`, no I/O.
 * This file carries no literal U+2014: the character is built from its escape,
 * or the rule would flag its own source.
 */

export const EMDASH = '\u2014'

const RULE = 'emdash'
const MAX_LINE_CHARS = 200

/**
 * An outward stage: the forms whose text leaves this machine under Scott's
 * name. `git -c k=v` may sit between `git` and `commit`.
 */
const OUTWARD = new RegExp(
    '(^|[^A-Za-z0-9_/-])git(\\s+-[cC]\\s+\\S+)*\\s+commit(\\s|$)'
    + '|(^|[^A-Za-z0-9_/-])gh\\s+pr\\s+(create|edit|comment)(\\s|$)'
    + '|(^|[^A-Za-z0-9_/-])gh\\s+issue(\\s|$)'
    + '|(^|[^A-Za-z0-9_/-])gh\\s+api\\b.*comments',
)

const HEREDOC_OPENER = /<<-?[ \t]*("[^"]*"|'[^']*'|[A-Za-z_][A-Za-z0-9_-]*)/g
const HERESTRING = '\u0001'

/**
 * Verbatim material that must keep the character lives under a fixtures path
 * or a golden file. A bare `*.json` is not exempt: it would cover every config
 * file in the tree.
 */
export function isAllowlistedPath(path: string): boolean {
    return path.startsWith('tests/fixtures/') || path.includes('/tests/fixtures/') || path.endsWith('.golden')
}

/**
 * The command with every heredoc body and terminator removed. A body line that
 * reads "git commit" is prose, not a statement. `<<<` herestrings open nothing.
 */
export function stripHeredocs(command: string): string {
    const kept: string[] = []
    const pending: { delim: string; dash: boolean }[] = []
    for (const line of command.split('\n')) {
        if (pending.length > 0) {
            const head = pending[0] as { delim: string; dash: boolean }
            let t = line
            if (head.dash) { t = t.replace(/^[ \t]+/, '') }
            t = t.replace(/[ \t]+$/, '')
            if (t === head.delim) { pending.shift() }
            continue
        }
        const rest = line.replaceAll('<<<', HERESTRING)
        for (const m of rest.matchAll(HEREDOC_OPENER)) {
            const token = m[0]
            const delim = (m[1] as string).replaceAll('"', '').replaceAll("'", '')
            pending.push({ delim, dash: token.charAt(2) === '-' })
        }
        kept.push(line)
    }
    return kept.join('\n')
}

/** True when some stage of the command, heredoc bodies aside, is an outward one. */
export function hasOutwardStage(command: string): boolean {
    return stripHeredocs(command)
        .split(/&&|\|\||;|\||\n/)
        .some((stage) => OUTWARD.test(stage))
}

/** The first line of `text` that carries the character, cut to a readable length by codepoint. */
function firstLine(text: string): string {
    const line = text.split('\n').find((l) => l.includes(EMDASH)) ?? ''
    return Array.from(line).slice(0, MAX_LINE_CHARS).join('')
}

/** Every string value in `value`, at any depth, with its dotted path. */
function stringsOf(value: unknown, path: string[] = []): { path: string; text: string }[] {
    if (typeof value === 'string') { return [{ path: path.join('.'), text: value }] }
    if (value === null || typeof value !== 'object') { return [] }
    const entries = Array.isArray(value)
        ? value.map((v, i) => [String(i), v] as const)
        : Object.entries(value as Record<string, unknown>)
    return entries.flatMap(([k, v]) => stringsOf(v, [...path, k]))
}

/** The one string a built-in write tool owns, with its label; null for any other tool. */
function writtenField(tool: string, input: Record<string, unknown>): { label: string; text: unknown } | null {
    switch (tool) {
        case 'Write': return { label: 'Write content', text: input['content'] }
        case 'Edit': return { label: 'Edit new_string', text: input['new_string'] }
        case 'NotebookEdit': return { label: 'NotebookEdit new_source', text: input['new_source'] }
        default: return null
    }
}

const BASH_LABEL = 'the Bash command (it carries a git commit / gh stage, so this text leaves the machine)'

/**
 * Judge one tool call. `input` is the call's fields (`e` minus `tool`,
 * `tool_use_id` and `agentId`). Returns the first violation, or null.
 *
 * Scanned per tool: Write `content`, Edit `new_string` (not `old_string`, which
 * is being removed), NotebookEdit `new_source`, the whole Bash command when an
 * outward stage is present, and every string at any depth of an `mcp__*` input.
 * Any other tool passes. There is no `MultiEdit`: Claude Code 2.1.327 offers none.
 */
export function judgeToolCall(tool: string, input: Record<string, unknown>): Violation | null {
    const filePath = input['file_path'] ?? input['notebook_path'] ?? ''
    if (typeof filePath === 'string' && isAllowlistedPath(filePath)) { return null }

    if (tool === 'Bash') {
        const command = input['command']
        if (typeof command !== 'string' || command === '') { return null }
        if (!hasOutwardStage(command) || !command.includes(EMDASH)) { return null }
        return { rule: RULE, label: BASH_LABEL, line: firstLine(command) }
    }

    if (tool.startsWith('mcp__')) {
        const hit = stringsOf(input).find((s) => s.text.includes(EMDASH))
        return hit === undefined ? null : { rule: RULE, label: tool + ' ' + hit.path, line: firstLine(hit.text) }
    }

    const field = writtenField(tool, input)
    if (field === null || typeof field.text !== 'string' || !field.text.includes(EMDASH)) { return null }
    return { rule: RULE, label: field.label, line: firstLine(field.text) }
}

/** The text the model sees on a deny, the same words `emdash.sh` uses. */
export function emdashReason(v: Violation): string {
    return 'em-dash (U+2014) in ' + v.label
        + '; recast with a colon, parens, comma, or a split sentence (rules/safety.md). The offending text: "' + v.line + '"'
}
