import type { Rule, Scope, Tier, Violation } from '../types/index.d.ts'

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
export function stringsOf(value: unknown, path: string[] = []): { path: string; text: string }[] {
    if (typeof value === 'string') { return [{ path: path.join('.'), text: value }] }
    if (value === null || typeof value !== 'object') { return [] }
    const entries = Array.isArray(value)
        ? value.map((v, i) => [String(i), v] as const)
        : Object.entries(value as Record<string, unknown>)
    return entries.flatMap(([k, v]) => stringsOf(v, [...path, k]))
}

/** `edits[].new_string`, joined: `old_string` is what is being removed. Non-string entries are skipped. */
function multiEditText(edits: unknown): unknown {
    if (!Array.isArray(edits)) { return undefined }
    return edits
        .map((ed) => (ed !== null && typeof ed === 'object' ? (ed as Record<string, unknown>)['new_string'] : undefined))
        .filter((s): s is string => typeof s === 'string')
        .join('\n')
}

/** The one string a built-in write tool owns, with its label; null for any other tool. */
function writtenField(tool: string, input: Record<string, unknown>): { label: string; text: unknown } | null {
    switch (tool) {
        case 'Write': return { label: 'Write content', text: input['content'] }
        case 'Edit': return { label: 'Edit new_string', text: input['new_string'] }
        case 'MultiEdit': return { label: 'MultiEdit edits[].new_string', text: multiEditText(input['edits']) }
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
 * is being removed), MultiEdit `edits[].new_string`, NotebookEdit `new_source`,
 * the whole Bash command when an outward stage is present, and every string at
 * any depth of an `mcp__*` input. Any other tool passes. Claude Code 2.1.327
 * offers no `MultiEdit`; its selector stays, inert, because the settings
 * matcher beneath still names it and shadow parity compares against that.
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

/** Which settings matcher of `emdash.sh` covers a tool: the same four entries `settings.json` wires. */
export type Surface = 'write' | 'bash' | 'mcp-post' | 'create_pr'

const OUTWARD_MCP = new RegExp(
    '^(mcp__slack__chat_post_message|mcp__slack__chat_update|mcp__slack__conversations_add_message'
    + '|mcp__atlassian__(addCommentToJiraIssue|createJiraIssue|editJiraIssue|createConfluencePage'
    + '|updateConfluencePage|createConfluenceFooterComment|createConfluenceInlineComment)'
    + '|mcp__marquee__marquee_(publish|update))$',
)

/**
 * The surface a tool call belongs to, or null when no `emdash.sh` matcher
 * covers it. The mod sees every call; judging one the hook never sees would
 * log a mismatch the hook could not have agreed with.
 */
export function surfaceOf(tool: string): Surface | null {
    if (tool === 'Write' || tool === 'Edit' || tool === 'MultiEdit' || tool === 'NotebookEdit') { return 'write' }
    if (tool === 'Bash') { return 'bash' }
    if (tool === 'mcp__multi-account-github__create_pr') { return 'create_pr' }
    if (OUTWARD_MCP.test(tool)) { return 'mcp-post' }
    return null
}

export type ChainVerdict = 'allow' | 'deny'

/** A settings-tier PreToolUse deny, as `next(e)` hands it back: Phase 0 Q6. */
const SETTINGS_DENY = /^PreToolUse:\S+ hook error: /

/**
 * What the chain beneath decided, read off the result `next(e)` resolved to.
 * A plugin beneath answers `{ deny }`; a settings hook's deny comes back as an
 * errored result whose text opens `PreToolUse:<tool> hook error: ` (Phase 0
 * Q6). A tool that merely failed is also `isError`, so the prefix is the key,
 * never `isError` alone.
 */
export function chainVerdict(result: unknown): ChainVerdict {
    if (result === null || typeof result !== 'object') { return 'allow' }
    const r = result as Record<string, unknown>
    if (typeof r['deny'] === 'string') { return 'deny' }
    if (r['isError'] === true && typeof r['text'] === 'string' && SETTINGS_DENY.test(r['text'])) { return 'deny' }
    return 'allow'
}

/**
 * Which layer a chain deny came from, for the Phase 7 parity matrix (which
 * counts only `settings` rows): `settings` when it came back as an errored
 * result opening `PreToolUse:<tool> hook error: ` (a settings hook), `plugin`
 * when it came back as `{ deny }` (a plugin beneath, such as rails), `null`
 * when the chain allowed. Keyed exactly as `chainVerdict` is, so
 * `chainSourceOf(r) !== null` iff `chainVerdict(r) === 'deny'`.
 */
export type ChainSource = 'settings' | 'plugin'

export function chainSourceOf(result: unknown): ChainSource | null {
    if (result === null || typeof result !== 'object') { return null }
    const r = result as Record<string, unknown>
    if (typeof r['deny'] === 'string') { return 'plugin' }
    if (r['isError'] === true && typeof r['text'] === 'string' && SETTINGS_DENY.test(r['text'])) { return 'settings' }
    return null
}

/** Heartbeat files kept, newest first. */
export const HEARTBEAT_KEEP = 20
export const HEARTBEAT_PREFIX = 'heartbeat.'

/**
 * The heartbeat files past the newest `keep`, by modification time. Only
 * regular files named `heartbeat.<id>` count; the logs and `last-session-id`
 * beside them are never named.
 */
export function staleHeartbeats(
    entries: readonly { name: string; kind: string; mtimeMs: number }[],
    keep: number = HEARTBEAT_KEEP,
): string[] {
    return entries
        .filter((e) => e.kind === 'file' && e.name.startsWith(HEARTBEAT_PREFIX))
        .sort((a, b) => b.mtimeMs - a.mtimeMs || (a.name < b.name ? 1 : -1))
        .slice(keep)
        .map((e) => e.name)
}

/*
 * The phrase table (Phase 5): the new bans from the 2026-11-18 scour. Every
 * rule defaults to a warning; a `deny-outward` rule denies on an outward
 * `tool.call` only when its id is in the `deny_outward` option. Structural
 * `warn` rules never deny. The source line names the VOICE.md anti-pattern
 * (paraphrased) or the public source, so the table cannot drift unseen.
 * Typographic characters are built from char codes, never typed.
 */

const LDQUOTE = String.fromCharCode(0x201c)
const RDQUOTE = String.fromCharCode(0x201d)
const LSQUOTE = String.fromCharCode(0x2018)
const RSQUOTE = String.fromCharCode(0x2019)

/** A sentence start: the text's head, a line start, or the end of a sentence before it. */
const SENTENCE_START = '(?:^|[.!?]\\s+|\\n\\s*)'

/** What follows a fiscal quarter: `Q1 2026`, `Q3 planning`, `Q2 revenue`, `Q4'26`. */
const FISCAL_AFTER = '(?!\\s+(?:20\\d\\d|FY|fiscal|earnings|revenue|budget|planning|roadmap|goals?|OKRs?|results|targets?|'
    + 'forecast|close|launch|spend|sales|quarter|bookings|numbers|review|kickoff|business|offsite)\\b|['
    + RSQUOTE + "']\\d\\d)"

/** What precedes a fiscal quarter: `in Q1`, `last Q3`, `by Q2`, `FY26 Q4`, `2026 Q2`. */
const FISCAL_BEFORE = '(?<!\\b(?:in|during|by|for|of|last|next|this|each|every|early|late|mid|since|until|through|from|FY\\d{0,4}|20\\d\\d)\\s)'

export const RULES: readonly Rule[] = [
    {
        id: 'belt-and-suspenders', tier: 'deny-outward', scope: 'outward',
        pattern: /\bbelt[\s-]+and[\s-]+(?:suspenders|braces)\b/i,
        fix: 'Name the actual second check, or cut the idiom.',
        source: 'VOICE.md anti-patterns and lint checklist: the stock idiom for redundancy',
    },
    {
        id: 'q-number-ref', tier: 'deny-outward', scope: 'outward',
        // A lettered ref (Q4a) is never a quarter. A bare Q1..Q99 is, unless fiscal context sits on either side.
        pattern: new RegExp('\\bQ\\d{1,2}[a-z]\\b|' + FISCAL_BEFORE + '\\bQ\\d{1,2}\\b' + FISCAL_AFTER),
        fix: 'Say the question itself, or link where it was asked. The reader never saw your Q-numbering.',
        source: 'Scott directive, 2026-11 scour: private working labels leaking outward (not in VOICE.md)',
    },
    {
        id: 'ac-number-ref', tier: 'deny-outward', scope: 'outward',
        pattern: /\bAC[- ]?\d{1,2}\b/,
        fix: 'State the acceptance criterion in words, or link the ticket that holds it.',
        source: 'Scott directive, 2026-11 scour: private working labels leaking outward (not in VOICE.md)',
    },
    {
        id: 'chat-residue', tier: 'deny-outward', scope: 'outward',
        pattern: new RegExp("\\bgreat question\\b|\\byou(?:'|" + RSQUOTE + ")re absolutely right\\b|" + SENTENCE_START + 'certainly[!,.]', 'i'),
        fix: 'Cut the chat opener. Lead with the point.',
        source: 'Wikipedia "Signs of AI writing": collaborative-chat residue; VOICE.md throat-clearing openers',
    },
    {
        id: 'staged-runup', tier: 'deny-outward', scope: 'outward',
        pattern: /\blet\W?s dive (?:in|into)\b|\bwithout further ado\b|\bhonestly\?|\breal talk\b/i,
        fix: 'Cut the staged run-up. State the point in the first sentence.',
        source: 'VOICE.md anti-patterns: throat-clearing openers; Wikipedia "Signs of AI writing"',
    },
    {
        id: 'let-that-sink-in', tier: 'deny-outward', scope: 'outward',
        pattern: /\blet that sink in\b/i,
        fix: 'Cut it. If the fact is strong, the number carries it.',
        source: 'Wikipedia "Signs of AI writing"; blader/humanizer: manufactured drama',
    },
    {
        id: 'full-stop', tier: 'deny-outward', scope: 'outward',
        pattern: new RegExp(SENTENCE_START + 'full stop\\.', 'i'),
        fix: 'Cut the dramatic fragment. Flat verdicts need no punctuation theatre.',
        source: 'VOICE.md anti-patterns: manufactured drama; hardikpandya/stop-slop',
    },
    {
        id: 'not-only-but', tier: 'warn', scope: 'outward-and-reply',
        pattern: /\bnot (?:only|just) [^.!?\n]{1,120}?\bbut(?: also)?\b/i,
        fix: 'State the claim directly instead of the not-only-but frame.',
        source: 'VOICE.md anti-patterns: binary-contrast reframe; Wikipedia "Signs of AI writing"',
    },
    {
        id: 'ing-tail', tier: 'warn', scope: 'outward-and-reply',
        pattern: /,\s+(?:highlighting|underscoring|showcasing|reflecting|emphasi[sz]ing|cementing|solidifying|demonstrating|contributing to|paving the way)\b[^.\n]*[.\n]/i,
        fix: 'Cut the trailing significance clause, or name the specific consequence.',
        source: 'VOICE.md anti-patterns: vague declaratives; Wikipedia "Signs of AI writing": -ing significance tails',
    },
    {
        id: 'triad', tier: 'warn', scope: 'outward-and-reply',
        // Three bare words closing a sentence: "fast, reliable, and secure."
        pattern: /\b[A-Za-z]{3,}, [A-Za-z]{3,},? and [A-Za-z]{3,}[.!]/,
        fix: 'Keep the items that carry weight; two honest items beat three padded ones.',
        source: 'Wikipedia "Signs of AI writing": rule of three; blader/humanizer',
    },
    {
        id: 'copula-avoidance', tier: 'warn', scope: 'outward-and-reply',
        pattern: /\b(?:serves?|stands?|acts?) as (?:a|an|the)\b/i,
        fix: 'Use "is".',
        source: 'Wikipedia "Signs of AI writing": copula avoidance; Kobak et al. (arXiv 2406.07016)',
    },
    {
        id: 'bold-label-bullet', tier: 'warn', scope: 'outward-and-reply',
        pattern: /^[ \t]*(?:[-*]|\d+\.)[ \t]+\*\*[^*\n]{1,60}\*\*[ \t]*:/m,
        fix: 'Drop the bold label, or make the bullet a plain sentence.',
        source: 'Wikipedia "Signs of AI writing": bold-label lists; hardikpandya/stop-slop',
    },
    {
        id: 'heres-leadin', tier: 'warn', scope: 'outward-and-reply',
        pattern: /^[ \t]*here\W?s (?:the |a |an |what |how |why )?[^\n]{0,80}:[ \t]*$/im,
        fix: 'State the content; skip the announcement that it is coming.',
        source: 'VOICE.md anti-patterns: throat-clearing openers',
    },
    {
        id: 'arguing-with-no-one', tier: 'warn', scope: 'outward-and-reply',
        pattern: /\bto be clear\b|\bi\W?m not saying\b|\bi am not saying\b|\blet me be clear\b/i,
        fix: 'Drop the rebuttal of a claim nobody made.',
        source: 'VOICE.md anti-patterns: throat-clearing openers and binary-contrast reframes',
    },
    {
        id: 'about-the-document', tier: 'warn', scope: 'outward-and-reply',
        pattern: /\bthis (?:document|doc|section|message|post) (?:will|aims to|covers|explains|describes|outlines)\b|\bin this (?:document|section|post),/i,
        fix: 'Write the content, not a description of the document.',
        source: 'Wikipedia "Signs of AI writing": writing about the text itself',
    },
    {
        id: 'ensure-word', tier: 'warn', scope: 'outward-and-reply',
        pattern: /\bensur(?:e|es|ed|ing)\b/i,
        fix: 'Name the check or the owner; "ensure" hides both.',
        source: 'Kobak et al. (arXiv 2406.07016): excess vocabulary; VOICE.md anti-patterns: buzzword abstraction',
    },
    {
        id: 'promote-word', tier: 'warn', scope: 'outward-and-reply',
        pattern: /\b(?:promot(?:e|es|ed|ing)|foster(?:s|ed|ing)?|streamlin(?:e|es|ed|ing)|facilitat(?:e|es|ed|ing))\b/i,
        fix: 'Use the plain verb for what actually happens.',
        source: 'Kobak et al. (arXiv 2406.07016): excess vocabulary; VOICE.md anti-patterns: buzzword abstraction',
    },
    {
        id: 'emphasis-word', tier: 'warn', scope: 'outward-and-reply',
        pattern: /\b(?:crucial|essential)\b|\bit\W?s important (?:to|that)\b|\bit is important (?:to|that)\b/i,
        fix: 'Say what breaks without it, or cut the emphasis.',
        source: 'VOICE.md anti-patterns: vague declaratives; Wikipedia "Signs of AI writing"',
    },
]

/** The rule ids a `deny_outward` option may promote: the table's `deny-outward` tier. */
export const DENYABLE_IDS: readonly string[] = RULES.filter((r) => r.tier === 'deny-outward').map((r) => r.id)

/**
 * `options.deny_outward` read defensively. The manifest schema has no array
 * type, so the option is one string of space-separated ids; an array (a hand
 * edit of settings) is read the same way. `ids` are the promotable ids it
 * names; `unknown` is everything else (a typo, a `warn` rule, a non-string),
 * ignored and reported, since a `warn` rule is never blocked.
 */
export function denyIdsFrom(option: unknown): { ids: ReadonlySet<string>; unknown: string[] } {
    const ids = new Set<string>()
    const unknown: string[] = []
    const items: unknown[] = typeof option === 'string' ? option.split(/\s+/).filter((t) => t !== '')
        : Array.isArray(option) ? option : []
    for (const v of items) {
        if (typeof v === 'string' && DENYABLE_IDS.includes(v)) { ids.add(v) } else { unknown.push(String(v)) }
    }
    return { ids, unknown }
}

const CODE_FENCE = /^[ \t]*(```|~~~)[^\n]*\n[\s\S]*?(?:^[ \t]*\1[ \t]*$|(?![\s\S]))/gm
const INLINE_CODE = /`[^`\n]*`/g
const BLOCKQUOTE_LINE = /^[ \t]*>.*$/gm
/** A quote escaped inside a shell string: `-m "ban \"phrase\" here"`. */
const ESCAPED_QUOTED_SPAN = /\\"[^\n]{0,300}?\\"/g
const QUOTED_SPAN = new RegExp('"[^"\\n]{0,300}"|' + LDQUOTE + '[^' + RDQUOTE + '\\n]{0,300}' + RDQUOTE + '|' + LSQUOTE + '[^' + RSQUOTE + '\\n]{0,300}' + RSQUOTE, 'g')

/**
 * The prose a rule may judge: fenced code, inline code, blockquote lines and
 * quoted spans removed. A banned phrase that is quoted or shown as code is
 * mentioned, not used. A fence left open runs to the end of the text.
 *
 * `shell` is set for a Bash command, where the message itself sits inside
 * shell quotes (`git commit -m "..."`): quoted spans are then left alone on
 * the line that holds an outward stage, or the whole message would vanish.
 * Quotes on every other line (a heredoc body, a continued message) still go.
 */
export function proseOf(text: string, shell = false): string {
    const unquoted = text
        .replace(CODE_FENCE, '')
        .replace(INLINE_CODE, '')
        .replace(BLOCKQUOTE_LINE, '')
        .replace(ESCAPED_QUOTED_SPAN, '')
    return unquoted
        .split('\n')
        .map((line) => (shell && OUTWARD.test(line) ? line : line.replace(QUOTED_SPAN, '')))
        .join('\n')
}

/** A hit of a table rule: the `Violation` plus its tier, so the caller decides warn or deny. */
export type RuleHit = Violation & { tier: Tier; fix: string }

function hitLine(prose: string, index: number): string {
    const start = prose.lastIndexOf('\n', index) + 1
    const end = prose.indexOf('\n', index)
    return Array.from(prose.slice(start, end === -1 ? undefined : end)).slice(0, MAX_LINE_CHARS).join('')
}

/**
 * Judge prose against the table. `where` picks the rules that apply: `outward`
 * runs every rule, `reply` only the `outward-and-reply` ones (a terminal reply
 * to Scott gets `warn` only). `warn` rules are skipped unless `includeWarn`.
 * One hit per rule, in table order.
 */
export function judgeProse(text: string, where: 'outward' | 'reply', includeWarn: boolean, label = '', shell = false): RuleHit[] {
    const prose = proseOf(text, shell)
    const hits: RuleHit[] = []
    for (const rule of RULES) {
        if (rule.tier === 'warn' && !includeWarn) { continue }
        if (where === 'reply' && (rule.scope as Scope) !== 'outward-and-reply') { continue }
        const m = rule.pattern.exec(prose)
        if (m !== null) { hits.push({ rule: rule.id, label, line: hitLine(prose, m.index), tier: rule.tier, fix: rule.fix }) }
    }
    return hits
}

/**
 * The command with the body of every heredoc that does not feed an outward
 * stage removed. A heredoc feeds an outward stage when its opener line holds
 * one (`git commit -F - <<'MSG'`, `git commit -m "$(cat <<'EOF'`, `gh pr
 * create --body-file - <<EOF`). `cat > notes.md <<EOF` is a file write, and a
 * file write is not outward (the Write tool is not). Terminators are dropped.
 */
export function outwardHeredocText(command: string): string {
    const kept: string[] = []
    const pending: { delim: string; dash: boolean; outward: boolean }[] = []
    for (const line of command.split('\n')) {
        if (pending.length > 0) {
            const head = pending[0] as { delim: string; dash: boolean; outward: boolean }
            let t = line
            if (head.dash) { t = t.replace(/^[ \t]+/, '') }
            t = t.replace(/[ \t]+$/, '')
            if (t === head.delim) { pending.shift() } else if (head.outward) { kept.push(line) }
            continue
        }
        const rest = line.replaceAll('<<<', HERESTRING)
        const outward = hasOutwardStage(line)
        for (const m of rest.matchAll(HEREDOC_OPENER)) {
            const delim = (m[1] as string).replaceAll('"', '').replaceAll("'", '')
            pending.push({ delim, dash: m[0].charAt(2) === '-', outward })
        }
        kept.push(line)
    }
    return kept.join('\n')
}

/**
 * The outward text of a call: what leaves the machine under Scott's name.
 * The Bash command from its first outward stage on, when one is present (the
 * bodies of heredocs that feed it kept, other heredoc bodies dropped), every string of an
 * outward MCP post or `create_pr`. Write, Edit and NotebookEdit are not
 * outward: the table's scope is Slack, Jira, Confluence, Marquee,
 * `create_pr`, commit and `gh`.
 */
export function outwardTexts(tool: string, input: Record<string, unknown>): { label: string; text: string; shell: boolean }[] {
    const surface = surfaceOf(tool)
    if (surface === 'bash') {
        const command = input['command']
        if (typeof command !== 'string' || command === '' || !hasOutwardStage(command)) { return [] }
        const body = outwardHeredocText(command)
        // Text before the first outward stage (an `echo`, a file write) is not what leaves the machine.
        const first = OUTWARD.exec(body)
        return [{ label: BASH_LABEL, text: first === null ? body : body.slice(first.index), shell: true }]
    }
    if (surface === 'mcp-post' || surface === 'create_pr') {
        return stringsOf(input).map((s) => ({ label: tool + ' ' + s.path, text: s.text, shell: false }))
    }
    return []
}

/**
 * Every table hit in one outward call. The caller passes `denyIds`, the
 * promoted ids; a hit is `deny` only for a `deny-outward` rule named there,
 * otherwise `warn`.
 */
export function judgeOutward(
    tool: string, input: Record<string, unknown>, includeWarn: boolean,
): RuleHit[] {
    const out: RuleHit[] = []
    for (const part of outwardTexts(tool, input)) { out.push(...judgeProse(part.text, 'outward', includeWarn, part.label, part.shell)) }
    return out
}

/** `deny` when the hit's rule is a promoted `deny-outward` one, else `warn`. */
export function verdictOf(hit: RuleHit, denyIds: ReadonlySet<string>): 'deny' | 'warn' {
    return hit.tier === 'deny-outward' && denyIds.has(hit.rule) ? 'deny' : 'warn'
}

/** The text the model sees when a promoted rule denies an outward call. */
export function ruleReason(hit: RuleHit): string {
    return 'voice-guard ' + hit.rule + ' in ' + hit.label + ': ' + hit.fix + ' The offending text: "' + hit.line + '"'
}

/** The warn text shown beneath a terminal answer; empty when there is nothing to say. */
export function warnText(hits: readonly RuleHit[]): string {
    if (hits.length === 0) { return '' }
    return 'voice-guard warn: ' + hits.map((h) => h.rule + ' (' + h.fix + ')').join('; ')
}
