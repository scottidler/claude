/**
 * rails: rule routing, the pure half (docs/design/2026-10-08-rule-routing.md).
 *
 * Every file in `~/repos/.claude/rules/` declares `load:` in its frontmatter:
 * `always` (stays in the engine's bulk load), `native` (has `paths:`, the engine
 * already loads it at the right time), or a trigger object (dropped from the
 * bulk load, injected when a prompt, tool or Bash statement matches). This file
 * parses that data, splits the engine's attachment text into per-file parts,
 * and matches triggers. It touches no engine noun; `index.ts` wires it.
 */

export type ToolTrigger = { match: string; gate?: boolean; query?: string; path?: string }
export type BashTrigger = { match: string; gate?: boolean }
export type Triggers = { prompt?: string[]; tools?: ToolTrigger[]; bash?: (string | BashTrigger)[] }
export type Load = 'always' | 'native' | Triggers

type CompiledTool = { match: RegExp; gate: boolean; query?: RegExp; path?: RegExp }
type CompiledBash = { match: RegExp; gate: boolean }
type Compiled = { prompt: RegExp[]; tools: CompiledTool[]; bash: CompiledBash[] }

/** One rule file: its real path, its `load:`, and the triggers when routed. */
export type IndexedRule = {
    path: string
    load: Load
    /** Why `load:` was rejected; the rule is then treated as `always`. */
    error?: string
    triggers?: Compiled
}

export type RuleIndex = { rules: IndexedRule[] }

/** One section of an `instructions` blob; `header` + `body` is its exact text. */
export type InstructionPart = { header: string; path?: string; body: string }

export type ToolMatch = { gate: string[]; after: string[] }

const TRIGGER_KEYS = new Set(['prompt', 'tools', 'bash'])
const TOOL_KEYS = new Set(['match', 'gate', 'query', 'path'])
const BASH_KEYS = new Set(['match', 'gate'])

// ---------------------------------------------------------------------------
// Frontmatter and the `load:` value
// ---------------------------------------------------------------------------

/** The text between a file's opening `---` line and its closing one. */
export function frontmatter(text: string): string | undefined {
    if (!text.startsWith('---\n')) { return undefined }
    const end = text.indexOf('\n---', 3)
    if (end < 0) { return undefined }
    const after = text.charAt(end + 4)
    if (after !== '\n' && after !== '') { return undefined }
    return text.slice(4, end + 1)
}

/** A line minus a trailing ` # comment`, quote-aware. */
function stripComment(line: string): string {
    let quote = ''
    for (let i = 0; i < line.length; i += 1) {
        const c = line.charAt(i)
        if (quote !== '') {
            if (c === quote) { quote = '' }
            continue
        }
        if (c === "'" || c === '"') { quote = c; continue }
        if (c === '#' && (i === 0 || /\s/.test(line.charAt(i - 1)))) { return line.slice(0, i).trimEnd() }
    }
    return line.trimEnd()
}

function indentOf(line: string): number {
    return line.length - line.trimStart().length
}

/**
 * A YAML flow value: `[...]`, `{...}`, a quoted scalar, or a plain scalar.
 *
 * Only the subset `load:` uses. Anything else throws, so a rule written in a
 * shape this parser does not understand fails CI instead of routing wrongly.
 */
class Flow {
    private at = 0
    constructor(private readonly src: string) {}

    static parse(src: string): unknown {
        const f = new Flow(src)
        const v = f.value(false)
        f.space()
        if (f.at !== src.length) { throw new Error('unexpected text after value: ' + src.slice(f.at)) }
        return v
    }

    private space(): void {
        while (this.at < this.src.length && /\s/.test(this.src.charAt(this.at))) { this.at += 1 }
    }

    private value(inFlow: boolean): unknown {
        this.space()
        const c = this.src.charAt(this.at)
        if (c === '[') { return this.seq() }
        if (c === '{') { return this.map() }
        if (c === "'") { return this.single() }
        if (c === '"') { return this.double() }
        return this.plain(inFlow ? /[,\]}]/ : null)
    }

    private seq(): unknown[] {
        this.at += 1
        const out: unknown[] = []
        this.space()
        if (this.src.charAt(this.at) === ']') { this.at += 1; return out }
        for (;;) {
            out.push(this.value(true))
            this.space()
            const c = this.src.charAt(this.at)
            this.at += 1
            if (c === ']') { return out }
            if (c !== ',') { throw new Error('expected , or ] in flow sequence: ' + this.src) }
        }
    }

    private map(): Record<string, unknown> {
        this.at += 1
        const out: Record<string, unknown> = {}
        this.space()
        if (this.src.charAt(this.at) === '}') { this.at += 1; return out }
        for (;;) {
            this.space()
            const c = this.src.charAt(this.at)
            const key = c === "'" ? this.single() : c === '"' ? this.double() : this.plainKey()
            this.space()
            if (this.src.charAt(this.at) !== ':') { throw new Error('expected : after key ' + key + ': ' + this.src) }
            this.at += 1
            if (key in out) { throw new Error('duplicate key ' + key + ': ' + this.src) }
            out[key] = this.value(true)
            this.space()
            const d = this.src.charAt(this.at)
            this.at += 1
            if (d === '}') { return out }
            if (d !== ',') { throw new Error('expected , or } in flow mapping: ' + this.src) }
        }
    }

    private single(): string {
        let out = ''
        this.at += 1
        while (this.at < this.src.length) {
            const c = this.src.charAt(this.at)
            if (c === "'") {
                if (this.src.charAt(this.at + 1) === "'") { out += "'"; this.at += 2; continue }
                this.at += 1
                return out
            }
            out += c
            this.at += 1
        }
        throw new Error('unterminated single-quoted scalar: ' + this.src)
    }

    private double(): string {
        let out = ''
        this.at += 1
        const escapes: Record<string, string> = { '\\': '\\', '"': '"', n: '\n', t: '\t', '/': '/' }
        while (this.at < this.src.length) {
            const c = this.src.charAt(this.at)
            if (c === '"') { this.at += 1; return out }
            if (c === '\\') {
                const e = escapes[this.src.charAt(this.at + 1)]
                if (e === undefined) { throw new Error('unsupported escape in double-quoted scalar: ' + this.src) }
                out += e
                this.at += 2
                continue
            }
            out += c
            this.at += 1
        }
        throw new Error('unterminated double-quoted scalar: ' + this.src)
    }

    private plainKey(): string {
        const start = this.at
        while (this.at < this.src.length && !/[:,{}[\]]/.test(this.src.charAt(this.at))) { this.at += 1 }
        const key = this.src.slice(start, this.at).trim()
        if (key === '') { throw new Error('empty key: ' + this.src) }
        return key
    }

    private plain(stop: RegExp | null): unknown {
        const start = this.at
        while (this.at < this.src.length && (stop === null || !stop.test(this.src.charAt(this.at)))) { this.at += 1 }
        const text = this.src.slice(start, this.at).trim()
        if (text === '') { throw new Error('empty value: ' + this.src) }
        if (/^[[\]{}]/.test(text)) { throw new Error('unexpected ' + text.charAt(0) + ': ' + this.src) }
        if (text === 'true') { return true }
        if (text === 'false') { return false }
        return text
    }
}

/** The indented block under `load:`: a map whose values are flow values or `- item` lists. */
function blockMap(lines: readonly string[]): Record<string, unknown> {
    const out: Record<string, unknown> = {}
    const base = indentOf(lines[0] ?? '')
    let i = 0
    while (i < lines.length) {
        const line = lines[i] as string
        if (indentOf(line) !== base) { throw new Error('unexpected indentation: ' + line.trim()) }
        const m = /^([A-Za-z_][A-Za-z0-9_]*):(.*)$/.exec(line.trim())
        if (m === null) { throw new Error('expected `key:` line: ' + line.trim()) }
        const key = m[1] as string
        if (key in out) { throw new Error('duplicate key ' + key) }
        const rest = (m[2] as string).trim()
        i += 1
        if (rest !== '') { out[key] = Flow.parse(rest); continue }
        const items: unknown[] = []
        while (i < lines.length && indentOf(lines[i] as string) > base) {
            const item = (lines[i] as string).trim()
            if (!item.startsWith('- ')) { throw new Error('expected `- item` under ' + key + ': ' + item) }
            items.push(Flow.parse(item.slice(2)))
            i += 1
        }
        if (items.length === 0) { throw new Error(key + ': has no value') }
        out[key] = items
    }
    return out
}

function compile(source: unknown, where: string): RegExp {
    if (typeof source !== 'string' || source === '') { throw new Error(where + ': expected a non-empty regex string') }
    try {
        return new RegExp(source, 'i')
    } catch (err) {
        throw new Error(where + ': regex does not compile: ' + source + ' (' + (err as Error).message + ')')
    }
}

function isRecord(v: unknown): v is Record<string, unknown> {
    return typeof v === 'object' && v !== null && !Array.isArray(v)
}

function onlyKeys(v: Record<string, unknown>, allowed: ReadonlySet<string>, where: string): void {
    for (const k of Object.keys(v)) {
        if (!allowed.has(k)) { throw new Error(where + ': unknown key ' + k) }
    }
}

function gateOf(v: Record<string, unknown>, where: string): boolean {
    if (v['gate'] === undefined) { return false }
    if (typeof v['gate'] !== 'boolean') { throw new Error(where + ': gate must be true or false') }
    return v['gate']
}

/** The parsed `load:` value, checked for shape, with every regex compiled. */
function validate(value: unknown): { load: Load; compiled?: Compiled } {
    if (value === 'always' || value === 'native') { return { load: value } }
    if (!isRecord(value)) { throw new Error('load: must be always, native, or a trigger map; got ' + JSON.stringify(value)) }
    onlyKeys(value, TRIGGER_KEYS, 'load')
    const load: Triggers = {}
    const compiled: Compiled = { prompt: [], tools: [], bash: [] }

    if (value['prompt'] !== undefined) {
        if (!Array.isArray(value['prompt'])) { throw new Error('load.prompt: must be a list') }
        load.prompt = value['prompt'].map((p, i) => {
            compiled.prompt.push(compile(p, 'load.prompt[' + i + ']'))
            return p as string
        })
    }
    if (value['tools'] !== undefined) {
        if (!Array.isArray(value['tools'])) { throw new Error('load.tools: must be a list') }
        load.tools = value['tools'].map((t, i) => {
            const where = 'load.tools[' + i + ']'
            if (!isRecord(t)) { throw new Error(where + ': must be a { match, ... } map') }
            onlyKeys(t, TOOL_KEYS, where)
            const entry: ToolTrigger = { match: t['match'] as string }
            const c: CompiledTool = { match: compile(t['match'], where + '.match'), gate: gateOf(t, where) }
            if (t['gate'] !== undefined) { entry.gate = c.gate }
            if (t['query'] !== undefined) { c.query = compile(t['query'], where + '.query'); entry.query = t['query'] as string }
            if (t['path'] !== undefined) { c.path = compile(t['path'], where + '.path'); entry.path = t['path'] as string }
            compiled.tools.push(c)
            return entry
        })
    }
    if (value['bash'] !== undefined) {
        if (!Array.isArray(value['bash'])) { throw new Error('load.bash: must be a list') }
        load.bash = value['bash'].map((b, i) => {
            const where = 'load.bash[' + i + ']'
            if (typeof b === 'string') {
                compiled.bash.push({ match: compile(b, where), gate: false })
                return b
            }
            if (!isRecord(b)) { throw new Error(where + ': must be a regex string or a { match, gate } map') }
            onlyKeys(b, BASH_KEYS, where)
            const gate = gateOf(b, where)
            compiled.bash.push({ match: compile(b['match'], where + '.match'), gate })
            return b['gate'] === undefined ? { match: b['match'] as string } : { match: b['match'] as string, gate }
        })
    }
    if (compiled.prompt.length + compiled.tools.length + compiled.bash.length === 0) {
        throw new Error('load: a trigger map with no triggers never loads its rule')
    }
    return { load, compiled }
}

function parse(frontmatterText: string): { load: Load; compiled?: Compiled } {
    const lines = frontmatterText.split('\n').map(stripComment)
    const starts = lines.flatMap((l, i) => (/^load:/.test(l) ? [i] : []))
    if (starts.length === 0) { throw new Error('no load: key') }
    if (starts.length > 1) { throw new Error('load: appears ' + starts.length + ' times') }
    const at = starts[0] as number
    const inline = (lines[at] as string).slice('load:'.length).trim()
    if (inline !== '') { return validate(Flow.parse(inline)) }
    const block: string[] = []
    for (let i = at + 1; i < lines.length; i += 1) {
        const line = lines[i] as string
        if (line.trim() === '') { continue }
        if (indentOf(line) === 0) { break }
        block.push(line)
    }
    if (block.length === 0) { throw new Error('load: has no value') }
    return validate(blockMap(block))
}

/**
 * The `load:` value in a rule's frontmatter (the text between the `---` lines).
 *
 * Every regex is compiled here, case-insensitive, so a rule that parses also
 * matches; an Error names the key and the reason.
 */
export function parseLoad(frontmatterText: string): Load | Error {
    try {
        return parse(frontmatterText).load
    } catch (err) {
        return err instanceof Error ? err : new Error(String(err))
    }
}

/**
 * The rule index from each rule file's real path and full text.
 *
 * A file whose `load:` is missing or broken is indexed as `always` with the
 * reason in `error`: the rule stays in the bulk load, and the caller says so.
 */
export function buildIndex(files: readonly { path: string; text: string }[]): RuleIndex {
    const rules = files.map((f): IndexedRule => {
        const fm = frontmatter(f.text)
        if (fm === undefined) { return { path: f.path, load: 'always', error: 'no frontmatter' } }
        try {
            const { load, compiled } = parse(fm)
            return compiled === undefined ? { path: f.path, load } : { path: f.path, load, triggers: compiled }
        } catch (err) {
            return { path: f.path, load: 'always', error: (err as Error).message }
        }
    })
    return { rules }
}

/** The indexed rule at this real path, if it is in the rule index at all. */
export function ruleAt(index: RuleIndex, realPath: string): IndexedRule | undefined {
    return index.rules.find((r) => r.path === realPath)
}

/** True when the file at this real path is a rule whose `load:` is a trigger map. */
export function isRouted(index: RuleIndex, realPath: string): boolean {
    return ruleAt(index, realPath)?.triggers !== undefined
}

// ---------------------------------------------------------------------------
// Attachment text
// ---------------------------------------------------------------------------

/**
 * A file section header in an `instructions` blob, one line:
 * `Contents of <path> (<tier>):`, or `Contents of <managed-settings> (...)`
 * for the managed tier, which has no path (Phase 0 (b)).
 */
const SECTION = /^Contents of (<[^<>\n]+>|\/[^\n]*?) \(([^()\n]+)\):$/gm

/**
 * An `instructions` attachment's text, cut into its file sections.
 *
 * The text opens with a one-line preamble (`Codebase and user instructions are
 * shown below...`), returned as a part with an empty header and no path. Each
 * section's `body` runs from the end of its header line to the next header, so
 * it carries the blank-line separator; `joinInstructions` is plain
 * concatenation and inverts this byte for byte. A header must start the text
 * or follow a blank line, so a quoted `Contents of` inside a rule is body.
 * Text with no section header at all throws: the engine changed its framing.
 */
export function splitInstructions(blob: string): InstructionPart[] {
    const starts: { at: number; header: string; path?: string }[] = []
    for (const m of blob.matchAll(SECTION)) {
        const at = m.index as number
        if (at !== 0 && blob.slice(at - 2, at) !== '\n\n') { continue }
        const target = m[1] as string
        const header = m[0]
        starts.push(target.startsWith('/') ? { at, header, path: target } : { at, header })
    }
    if (starts.length === 0) { throw new Error('instructions: no `Contents of <path> (<tier>):` section header') }

    const parts: InstructionPart[] = []
    const first = starts[0] as { at: number }
    if (first.at > 0) { parts.push({ header: '', body: blob.slice(0, first.at) }) }
    starts.forEach((s, i) => {
        const end = i + 1 < starts.length ? (starts[i + 1] as { at: number }).at : blob.length
        const part: InstructionPart = { header: s.header, body: blob.slice(s.at + s.header.length, end) }
        if (s.path !== undefined) { part.path = s.path }
        parts.push(part)
    })
    return parts
}

/** The inverse of `splitInstructions`: every part's header then body, in order. */
export function joinInstructions(parts: readonly InstructionPart[]): string {
    return parts.map((p) => p.header + p.body).join('')
}

const NESTED = /^Contents of (\/[^\n]*?)(?: \([^()\n]*\))?:(?:\n|$)/

/** The file path a `nested_memory` attachment's text opens with (`Contents of <path>:`). */
export function nestedPath(text: string): string | undefined {
    return NESTED.exec(text)?.[1]
}

// ---------------------------------------------------------------------------
// Triggers
// ---------------------------------------------------------------------------

const ASSIGN = /^[A-Za-z_][A-Za-z0-9_]*=/
/** git global options that take the next word as their value. */
const GIT_VALUE_OPTS = new Set(['-C', '-c', '--git-dir', '--work-tree', '--namespace', '--config-env'])
/** env options that take the next word as their value. */
const ENV_VALUE_OPTS = new Set(['-u', '--unset', '-C', '--chdir', '-S', '--split-string'])

/** Whitespace-separated words, quote-aware, each kept as written. */
function rawWords(stmt: string): string[] {
    const words: string[] = []
    let cur = ''
    let quote = ''
    for (let i = 0; i < stmt.length; i += 1) {
        const c = stmt.charAt(i)
        if (quote !== '') {
            cur += c
            if (c === '\\' && quote === '"' && i + 1 < stmt.length) { cur += stmt.charAt(i + 1); i += 1; continue }
            if (c === quote) { quote = '' }
            continue
        }
        if (c === '\\' && i + 1 < stmt.length) { cur += c + stmt.charAt(i + 1); i += 1; continue }
        if (c === "'" || c === '"') { quote = c; cur += c; continue }
        if (/\s/.test(c)) {
            if (cur !== '') { words.push(cur); cur = '' }
            continue
        }
        cur += c
    }
    if (cur !== '') { words.push(cur) }
    return words
}

/**
 * One Bash statement as a `bash:` trigger sees it.
 *
 * Leading `VAR=val` assignments and an `env` prefix (with its own options and
 * assignments) are stripped, and git's global options (`-C <dir>`, `-c <k=v>`,
 * `--git-dir=...`, `--no-pager`, ...) are removed, so `env X=1 git -C repo push`
 * reads `git push`. Words are rejoined with single spaces.
 */
export function normalizeStatement(stmt: string): string {
    const w = rawWords(stmt)
    let i = 0
    for (;;) {
        while (i < w.length && ASSIGN.test(w[i] as string)) { i += 1 }
        if (w[i] !== 'env') { break }
        i += 1
        while (i < w.length) {
            const word = w[i] as string
            if (ASSIGN.test(word)) { i += 1; continue }
            if (ENV_VALUE_OPTS.has(word)) { i += 2; continue }
            if (word.startsWith('-')) { i += 1; continue }
            break
        }
    }
    const rest = w.slice(i)
    if (rest[0] !== 'git') { return rest.join(' ') }
    let j = 1
    while (j < rest.length && (rest[j] as string).startsWith('-') && rest[j] !== '--') {
        j += GIT_VALUE_OPTS.has(rest[j] as string) ? 2 : 1
    }
    return ['git', ...rest.slice(j)].join(' ')
}

function routed(index: RuleIndex): (IndexedRule & { triggers: Compiled })[] {
    return index.rules.filter((r): r is IndexedRule & { triggers: Compiled } => r.triggers !== undefined)
}

/** Real paths of routed rules with a `prompt` regex matching this text. */
export function matchPrompt(index: RuleIndex, text: string): string[] {
    return routed(index).filter((r) => r.triggers.prompt.some((re) => re.test(text))).map((r) => r.path)
}

function field(input: unknown, key: string): string | undefined {
    if (!isRecord(input)) { return undefined }
    const v = input[key]
    return typeof v === 'string' ? v : undefined
}

/**
 * Real paths of routed rules this tool call triggers, split by when they land.
 *
 * `gate` rules must be in context before the call runs; `after` rules ride on
 * its result. A rule that both gates and rides is reported as `gate` only.
 * `tools` entries match the tool name, then `path` against `input.file_path`
 * and `query` against `input.query` when given (a missing field never
 * matches). For the Bash tool, `split` cuts `input.command` into statements
 * (rails' quote-aware head scan) and each statement is normalized before the
 * `bash` entries test it.
 */
export function matchTool(index: RuleIndex, tool: string, input: unknown, split: (command: string) => string[]): ToolMatch {
    const gate = new Set<string>()
    const after = new Set<string>()
    const command = tool === 'Bash' ? field(input, 'command') : undefined
    const statements = command === undefined ? [] : split(command).map(normalizeStatement)
    const filePath = field(input, 'file_path')
    const query = field(input, 'query')

    for (const r of routed(index)) {
        for (const t of r.triggers.tools) {
            if (!t.match.test(tool)) { continue }
            if (t.path !== undefined && (filePath === undefined || !t.path.test(filePath))) { continue }
            if (t.query !== undefined && (query === undefined || !t.query.test(query))) { continue }
            ;(t.gate ? gate : after).add(r.path)
        }
        for (const b of r.triggers.bash) {
            if (statements.some((s) => b.match.test(s))) { (b.gate ? gate : after).add(r.path) }
        }
    }
    return { gate: [...gate], after: [...after].filter((p) => !gate.has(p)) }
}
