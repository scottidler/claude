import type { EngineInterface, Register, Settings, ToolCallResult } from 'claude-code'

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

/** Where one simple command starts, and the word that heads it. */
type Head = { at: number; word: string; loop: boolean; piped: boolean }

/**
 * Past one redirection: the operator, an `&` fd duplication, and the target.
 *
 * The target is never a command, and `2>&1` must not read as a `&` separator
 * followed by a stage headed `1`.
 */
function skipRedirect(command: string, at: number): number {
    let i = at + 1
    const next = command.charAt(i)
    if (next === '>' || next === '<') { i += 1 }
    if (command.charAt(i) === '&') { i += 1 }
    while (command.charAt(i) === ' ' || command.charAt(i) === '\t') { i += 1 }
    const quote = command.charAt(i)
    if (quote === '"' || quote === "'") {
        i += 1
        while (i < command.length && command.charAt(i) !== quote) {
            i += command.charAt(i) === '\\' && quote === '"' ? 2 : 1
        }
        return i + 1
    }
    const target = WORD.exec(command.slice(i))
    return target === null ? i : i + target[0].length
}

/**
 * One shell word starting at `i`, joining adjacent quoted and unquoted runs the
 * way the shell does, returned with its quotes removed.
 *
 * A head may be written `"python3"`, `'python3'` or `"pyth"on3`; bash runs the
 * same command for all three. The scanner used to set `start = false` on an
 * opening quote and emit no Head, so a quoted head was invisible to
 * `classifyStages`: REST came back empty and the excluded-compound deny could
 * never fire. Two quote characters defeated the whole rule, live-proven by the
 * implementation audit (2026-09-13):
 *   `cargo --version >/dev/null 2>&1; "python3" -c '<AF_UNIX probe>'` ran
 *   UNSANDBOXED, while the same line unquoted denied.
 */
function quotedWord(command: string, i: number): { text: string; end: number } {
    let text = ''
    let j = i
    while (j < command.length) {
        const c = command.charAt(j)
        if (c === '"' || c === "'") {
            const q = c
            j += 1
            while (j < command.length) {
                const d = command.charAt(j)
                if (d === '\\' && q === '"' && j + 1 < command.length) { text += command.charAt(j + 1); j += 2; continue }
                if (d === q) { j += 1; break }
                text += d
                j += 1
            }
            continue
        }
        if (c === '\\' && j + 1 < command.length) { text += command.charAt(j + 1); j += 2; continue }
        if (/[\s;|&()<>]/.test(c)) { break }
        text += c
        j += 1
    }
    return { text, end: j }
}

/**
 * Every simple-command head in `command`, quote-aware.
 *
 * Scanning stops at an unquoted `<<`: a heredoc body is data, so neither a `gh`
 * in a PR body nor an `rm` in a script fixture is a command. `loop` marks a head
 * that follows a `do` keyword; that is a loop body, which the rm rule refuses to
 * rewrite because the paths are a variable, not text. `piped` marks a head whose
 * only separator from the stage before it was a single `|`, which is what makes
 * a stdin-only consumer transparent to the excluded-compound rule.
 */
function heads(command: string): Head[] {
    const found: Head[] = []
    let i = 0
    let start = true
    let loop = false
    let quote = ''
    let sep = ''
    while (i < command.length) {
        const c = command.charAt(i)
        if (quote !== '') {
            if (c === '\\' && quote === '"') { i += 2; continue }
            if (c === quote) { quote = '' }
            i += 1
            continue
        }
        if (c === '\\') { i += 2; continue }
        if (c === '"' || c === "'") {
            if (start) {
                const w = quotedWord(command, i)
                if (w.text === '') { quote = c; start = false; i += 1; continue }
                if (ASSIGN.test(w.text) || TRANSPARENT.has(w.text)) {
                    if (w.text === 'do') { loop = true }
                    i = w.end
                    continue
                }
                found.push({ at: i, word: w.text, loop, piped: sep === '|' })
                start = false
                sep = ''
                i = w.end
                continue
            }
            quote = c; start = false; i += 1; continue
        }
        if (c === '<' && command.charAt(i + 1) === '<') { break }
        if (c === '>' || c === '<') { i = skipRedirect(command, i); continue }
        if (SEP.has(c)) { start = true; loop = false; sep += c; i += 1; continue }
        if (c === ' ' || c === '\t' || c === '\r') { i += 1; continue }
        const word = WORD.exec(command.slice(i))
        if (word === null) { i += 1; continue }
        const text = word[0]
        if (start) {
            if (ASSIGN.test(text) || TRANSPARENT.has(text)) {
                if (text === 'do') { loop = true }
                i += text.length
                continue
            }
            found.push({ at: i, word: text, loop, piped: sep === '|' })
            start = false
            sep = ''
            i += text.length
            continue
        }
        i += text.length
    }
    return found
}

/** Byte offsets of every simple command headed by `word`. */
function headSpots(command: string, word: string): number[] {
    return heads(command).filter((h) => h.word === word).map((h) => h.at)
}

/** Byte offsets of every `gh` that starts a simple command. */
function ghSpots(command: string): number[] {
    return headSpots(command, 'gh')
}

/** The one invocation starting at `at`, cut at the next unquoted separator. */
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

/**
 * rails: rm to rkvr rmrf
 *
 * The question the rule answers is intent (rules/safety.md, File Deletion):
 * regenerable build output costs only time and compilation to rebuild, so it is
 * removed with plain `rm`; everything else goes through `rkvr rmrf`, the
 * three-week bin. Four outcomes per stage: pass because the path is in the
 * regenerable set, pass because the model asserted `# regenerable`, rewrite to
 * `rkvr rmrf`, or deny a wrapper form that deletes through another head.
 */

/**
 * The regenerable set, kept in step with its one home in rules/safety.md.
 *
 * The match is POSITIONAL: the basename below AND one of its toolchain anchors
 * in the PARENT directory. Never a bare basename, because
 * `crates/loopr/src/target/tests.rs` is a tracked Rust source module named
 * `target`, and seven repos carry tracked `build/`, `dist/`, `out/` and
 * `coverage/` directories. An anchor beginning with `*` is a suffix glob over
 * the parent listing. Empty anchors mean the name is regenerable anywhere.
 *
 * `pom.xml` is deliberately not an anchor for `target` (a tracked Maven
 * `target/` in one work repo holds data files), and `bin/` and `vendor/` are
 * deliberately absent (tracked in 18 and 6 repos; general.md mandates `bin/`).
 */
const PY_ANCHORS = ['pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt'] as const
const JS_ANCHORS = ['package.json'] as const
const REGENERABLE: ReadonlyArray<{ name: string; anchors: readonly string[] }> = [
    { name: 'target', anchors: ['Cargo.toml'] },
    { name: 'node_modules', anchors: JS_ANCHORS },
    { name: 'dist', anchors: [...JS_ANCHORS, ...PY_ANCHORS] },
    { name: 'build', anchors: [...JS_ANCHORS, ...PY_ANCHORS] },
    { name: 'out', anchors: JS_ANCHORS },
    { name: 'coverage', anchors: JS_ANCHORS },
    { name: '.next', anchors: JS_ANCHORS },
    { name: '.turbo', anchors: JS_ANCHORS },
    { name: '.parcel-cache', anchors: JS_ANCHORS },
    { name: '.venv', anchors: PY_ANCHORS },
    { name: 'venv', anchors: PY_ANCHORS },
    { name: '.tox', anchors: [...PY_ANCHORS, 'tox.ini'] },
    { name: '.pytest_cache', anchors: [...PY_ANCHORS, 'pytest.ini'] },
    { name: '.mypy_cache', anchors: PY_ANCHORS },
    { name: '.ruff_cache', anchors: PY_ANCHORS },
    { name: '*.egg-info', anchors: PY_ANCHORS },
    { name: '.gradle', anchors: ['build.gradle', 'build.gradle.kts', 'settings.gradle'] },
    { name: '.terraform', anchors: ['*.tf'] },
    { name: '__pycache__', anchors: [] },
]

/** Heads that delete through another command; rails cannot rewrite these. */
const WRAPPERS = new Set(['sudo', 'xargs', 'find', 'sh', 'bash', 'ssh', 'docker', 'kubectl'])
/** The only prefixes a wrapper delete may target without a deny. */
const SCRATCH = ['$TMPDIR', '/tmp/claude', '/tmp/review-panel']
/** Words a wrapper carries that are verbs, not paths. */
const WRAPPER_VERBS = new Set(['rm', 'exec'])
/** An `rm` word, including one inside a quoted `sh -c` payload. */
const RM_WORD = /(?:^|[\s;&|(])rm(?=\s|$)/
/** The only flags a rewritable `rm` may carry. */
const DELETE_FLAGS = /^-[rRf]+$/
/** The model's intent marker, matched exactly against the whole stage comment. */
const MARKER = '# regenerable'

const RM_REWRITE_NOTE = 'rails: rm -> rkvr rmrf (rules/safety.md); archive at /var/tmp/rmrf; if this was regenerable build output, re-issue with a trailing `# regenerable`'
const RM_SET_NOTE = 'rails: rm kept, regenerable build output (rules/safety.md)'
const RM_MARKER_NOTE = 'rails: rm kept, model asserted regenerable'
const RM_DENY = 'rails: this form deletes through another command, which rails cannot rewrite. Run `rkvr rmrf <paths>` yourself (rules/safety.md), or confine the command to $TMPDIR, /tmp/claude or /tmp/review-panel.'

function rmMiss(why: string): string {
    return 'rails: rm form not rewritten (' + why + ')'
}

/** One shell word: its source text, its unquoted value, and whether it was quoted. */
type Word = { raw: string; value: string; quoted: boolean }

/** Split one stage into shell words, honoring quotes and backslash escapes. */
function splitWords(seg: string): Word[] {
    const out: Word[] = []
    let i = 0
    while (i < seg.length) {
        const c = seg.charAt(i)
        if (c === ' ' || c === '\t' || c === '\r') { i += 1; continue }
        const from = i
        let value = ''
        let quote = ''
        let quoted = false
        while (i < seg.length) {
            const d = seg.charAt(i)
            if (quote !== '') {
                if (d === '\\' && quote === '"') { value += seg.charAt(i + 1); i += 2; continue }
                if (d === quote) { quote = ''; i += 1; continue }
                value += d
                i += 1
                continue
            }
            if (d === '\\') { value += seg.charAt(i + 1); i += 2; continue }
            if (d === '"' || d === "'") { quote = d; quoted = true; i += 1; continue }
            if (d === ' ' || d === '\t' || d === '\r') { break }
            value += d
            i += 1
        }
        out.push({ raw: seg.slice(from, i), value, quoted })
    }
    return out
}

/**
 * The trailing shell comment of one stage, with bash's own rule: an unquoted `#`
 * that STARTS a word. `a# regenerable` opens nothing, it is two filenames.
 */
function stageComment(seg: string): { at: number; text: string } | null {
    let i = 0
    let quote = ''
    let wordStart = true
    while (i < seg.length) {
        const c = seg.charAt(i)
        if (quote !== '') {
            if (c === '\\' && quote === '"') { i += 2; continue }
            if (c === quote) { quote = '' }
            i += 1
            continue
        }
        if (c === '\\') { i += 2; wordStart = false; continue }
        if (c === '"' || c === "'") { quote = c; wordStart = false; i += 1; continue }
        if (c === ' ' || c === '\t' || c === '\r') { wordStart = true; i += 1; continue }
        if (c === '#' && wordStart) { return { at: i, text: seg.slice(i).trimEnd() } }
        wordStart = false
        i += 1
    }
    return null
}

/**
 * A path argument as an absolute path, or null when it cannot be resolved by
 * string work alone. Unresolvable means a variable, a glob or a `~`, and it
 * falls through to the rkvr rewrite: the safe default costs one tarball.
 */
function resolvePath(cwd: string, p: string): string | null {
    if (p === '') { return null }
    if (/[$*?~\[]/.test(p)) { return null }
    let raw = p
    while (raw.length > 1 && raw.endsWith('/')) { raw = raw.slice(0, -1) }
    if (!raw.startsWith('/') && !cwd.startsWith('/')) { return null }
    const parts: string[] = []
    for (const s of (raw.startsWith('/') ? raw : cwd + '/' + raw).split('/')) {
        if (s === '' || s === '.') { continue }
        if (s === '..') { parts.pop(); continue }
        parts.push(s)
    }
    return '/' + parts.join('/')
}

/** What the rule needs from the world: the session cwd and the plugin filesystem. */
type Env = {
    cwd(): Promise<string>
    exists(path: string): Promise<boolean>
    list(dir: string): Promise<string[]>
}

/** Is this one path build output the toolchain can regenerate? Positional match. */
async function regenerable(value: string, env: Env): Promise<boolean> {
    const abs = resolvePath(await env.cwd(), value)
    if (abs === null) { return false }
    const parts = abs.split('/')
    const base = parts[parts.length - 1] ?? ''
    if (base === '') { return false }
    const entry = REGENERABLE.find((e) => e.name === base)
        ?? REGENERABLE.find((e) => e.name.startsWith('*') && base.endsWith(e.name.slice(1)))
    if (entry === undefined) { return false }
    if (entry.anchors.length === 0) { return true }
    const parent = parts.slice(0, -1).join('/') || '/'
    for (const anchor of entry.anchors) {
        if (anchor.startsWith('*')) {
            const names = await env.list(parent)
            if (names.some((n) => n.endsWith(anchor.slice(1)))) { return true }
            continue
        }
        if (await env.exists(parent + '/' + anchor)) { return true }
    }
    return false
}

/** Does a wrapper stage delete anything at all? */
function deletes(words: readonly Word[]): boolean {
    return words.some((w) => w.value === '-delete' || RM_WORD.test(w.value))
}

/**
 * A wrapper stage is denied unless every literal path argument it carries sits
 * under a scratch prefix. No literal path at all (bare `xargs rm`) is a deny:
 * the paths arrive on stdin and rails cannot see them.
 */
function wrapperDenied(words: readonly Word[]): boolean {
    const paths = words.slice(1).filter((w) => !w.value.startsWith('-') && !WRAPPER_VERBS.has(w.value))
    if (paths.length === 0) { return true }
    return !paths.every((p) => SCRATCH.some((s) => p.value.startsWith(s)))
}

/** One rewrite to splice back into the command. */
type Edit = { at: number; end: number; text: string }

/** What the rm rule decided: a (possibly unchanged) command, or a deny reason. */
type RmResult = { command?: string; note?: string; deny?: string }

/**
 * Classify and rewrite every `rm` stage in `command`.
 *
 * Pure apart from `env`, which is the only thing that cannot be decided from the
 * string: the session cwd and whether a toolchain anchor sits beside a path.
 */
async function rmRewrite(command: string, env: Env): Promise<RmResult> {
    const edits: Edit[] = []
    const notes: string[] = []
    for (const head of heads(command)) {
        const seg = segment(command, head.at)
        if (WRAPPERS.has(head.word)) {
            const words = splitWords(seg)
            if (!deletes(words)) { continue }
            if (wrapperDenied(words)) { return { deny: RM_DENY } }
            notes.push(rmMiss('wrapper delete confined to scratch'))
            continue
        }
        if (head.word !== 'rm') { continue }
        if (head.loop) { notes.push(rmMiss('loop body, the paths are a variable')); continue }

        const comment = stageComment(seg)
        const words = splitWords(comment === null ? seg : seg.slice(0, comment.at))
        const rest = words.slice(1)
        const flags = rest.filter((w) => !w.quoted && w.value.startsWith('-') && w.value.length > 1)
        const paths = rest.filter((w) => !flags.includes(w))

        const bad = flags.filter((f) => !DELETE_FLAGS.test(f.value))
        if (bad.length > 0) {
            notes.push(rmMiss('flags beyond -r -R -f: ' + bad.map((f) => f.value).join(' ')))
            continue
        }
        if (paths.length === 0) { notes.push(rmMiss('no path argument')); continue }
        if (comment !== null && comment.text === MARKER) { notes.push(RM_MARKER_NOTE); continue }

        let allRegenerable = flags.length > 0
        for (const p of paths) {
            if (!allRegenerable) { break }
            allRegenerable = await regenerable(p.value, env)
        }
        if (allRegenerable) { notes.push(RM_SET_NOTE); continue }

        const rebuilt = ['rkvr', 'rmrf', ...paths.map((p) => p.raw)]
        if (comment !== null) { rebuilt.push(comment.text) }
        edits.push({ at: head.at, end: head.at + seg.trimEnd().length, text: rebuilt.join(' ') })
        notes.push(RM_REWRITE_NOTE)
    }
    let out = command
    for (const edit of [...edits].sort((a, b) => b.at - a.at)) {
        out = out.slice(0, edit.at) + edit.text + out.slice(edit.end)
    }
    return { command: out, note: notes.join(' | ') }
}

/**
 * Cheap gate so a Bash call with no delete in it never costs an engine round trip.
 *
 * `git` is deliberately absent: `git rm` stages a deletion whose content stays
 * recoverable from git history, so it is not the class rkvr protects, and
 * noting it cost a context line on every one.
 */
const RM_INTEREST = /(?:^|[\s;&|(])(?:rm|sudo|xargs|find|sh|bash|ssh|docker|kubectl)(?=\s|$)/

/**
 * rails: excluded-compound deny
 *
 * `sandbox.excludedCommands` does NOT match a command-string prefix. It matches
 * any stage ANYWHERE in a compound and exempts the ENTIRE compound. Measured
 * 2026-09-13 with an AF_UNIX socket-creation marker (the sandbox denies
 * `socket(AF_UNIX)` outright, so creating one succeeds only outside it):
 * `marker.sh` alone is sandboxed, `ssh -V; marker.sh` is not, and neither is
 * `marker.sh; ssh -V`, which rules prefix matching out.
 *
 * So every entry is a general escape hatch: appending `; ssh -V` to anything
 * opts it out of the sandbox with no approval prompt. The only party who can
 * compose such a command is the model itself, so removing the composition
 * closes the hole. Scott's ruling 2026-09-13 (option D): keep all ten entries,
 * fix it here rather than in settings.json.
 */

/** Heads that carry an inner command; the inner head is what actually runs. */
const EX_WRAPPERS = new Set(['sh', 'bash', 'zsh', 'sudo', 'xargs', 'env', 'nohup'])
/** Of those, the ones whose inner command arrives as a `-c` payload. */
const EX_SHELLS = new Set(['sh', 'bash', 'zsh'])
/** `-c`, `-lc`, `-ec`: any short-flag cluster ending in c. */
const SHELL_C = /^-[A-Za-z]*c$/
/** Stages that carry no behavior of their own, so they never make a compound. */
const EX_TRANSPARENT = new Set(['cd', 'export', 'true', 'echo', 'wait'])
/** Pipe targets that can read only their stdin, when they name no file. */
const CONSUMERS = new Set([
    'tail', 'head', 'cat', 'nl', 'sort', 'uniq', 'wc', 'less', 'rg', 'grep', 'jq', 'awk', 'sed',
])
/** Of those, the ones whose first non-flag word is a pattern or a program, not a path. */
const PATTERN_CONSUMERS = new Set(['rg', 'grep', 'jq', 'awk', 'sed'])
/** A bare number is a flag's value (`tail -n 50`), never a path. */
const FLAG_VALUE = /^[0-9]+$/
/** A `sh -c` payload may itself be a compound; three levels is past any real use. */
const EX_MAX_DEPTH = 3
/** Every entry is written `<head> *`; the glob is not part of the head. */
const EX_GLOB_SUFFIX = ' *'

type Stages = { excluded: string[]; rest: string[] }

/**
 * The excluded heads from the engine's own merged settings, the one source of
 * truth. An absent or wrongly typed list yields none, which makes the rule inert.
 */
function excludedHeads(settings: Settings): string[] {
    const sandbox = (settings as { sandbox?: { excludedCommands?: unknown } }).sandbox
    const raw = sandbox?.excludedCommands
    if (!Array.isArray(raw)) { return [] }
    return raw
        .filter((e): e is string => typeof e === 'string')
        .map((e) => (e.endsWith(EX_GLOB_SUFFIX) ? e.slice(0, -EX_GLOB_SUFFIX.length) : e).trim())
        .filter((e) => e !== '')
}

/** Which excluded head this stage is, or null. Multi-word entries match the stage text. */
function excludedAs(seg: string, head: string, entries: readonly string[]): string | null {
    const text = seg.trim()
    for (const entry of entries) {
        if (head === entry) { return entry }
        if (text === entry || text.startsWith(entry + ' ')) { return entry }
    }
    return null
}

/** The command a wrapper stage runs, as text, or null when it carries none. */
function innerCommand(words: readonly Word[]): string | null {
    const head = words[0]?.value ?? ''
    if (EX_SHELLS.has(head)) {
        const at = words.findIndex((w, i) => i > 0 && SHELL_C.test(w.value))
        if (at === -1) { return null }
        return words[at + 1]?.value ?? null
    }
    for (let i = 1; i < words.length; i += 1) {
        const w = words[i]
        if (w === undefined) { continue }
        if (w.value.startsWith('-') || ASSIGN.test(w.value)) { continue }
        return words.slice(i).map((x) => x.raw).join(' ')
    }
    return null
}

/**
 * Does this stage read its stdin and nothing else?
 *
 * Both halves are load-bearing. The NAME is not enough: every consumer here also
 * takes file operands, so a name-only test would let
 * `cargo --version; tail ~/.ssh/identities/home/id_ed25519` read a deny-listed
 * key unsandboxed, which is worse than the hatch this rule closes. `tee` is
 * absent for the same reason: a file operand is its whole purpose.
 */
function readsOnlyStdin(head: string, seg: string): boolean {
    if (!CONSUMERS.has(head)) { return false }
    const operands = splitWords(seg)
        .slice(1)
        .filter((w) => !(w.value.startsWith('-') && w.value.length > 1) && !FLAG_VALUE.test(w.value))
    return operands.length <= (PATTERN_CONSUMERS.has(head) ? 1 : 0)
}

/** Split a command into its excluded stages and every other stage that acts. */
function classifyStages(command: string, entries: readonly string[], depth: number): Stages {
    const out: Stages = { excluded: [], rest: [] }
    for (const head of heads(command)) {
        const seg = segment(command, head.at)
        if (excludedAs(seg, head.word, entries) !== null) { out.excluded.push(head.word); continue }
        if (EX_TRANSPARENT.has(head.word)) { continue }
        if (head.piped && readsOnlyStdin(head.word, seg)) { continue }
        if (depth < EX_MAX_DEPTH && EX_WRAPPERS.has(head.word)) {
            const inner = innerCommand(splitWords(seg))
            if (inner !== null) {
                const nested = classifyStages(inner, entries, depth + 1)
                out.excluded.push(...nested.excluded)
                out.rest.push(...nested.rest)
                continue
            }
        }
        out.rest.push(head.word)
    }
    return out
}

/** The deny reason for a compound that smuggles a stage out of the sandbox, or null. */
function excludedDeny(command: string, entries: readonly string[]): string | null {
    if (entries.length === 0) { return null }
    const { excluded, rest } = classifyStages(command, entries, 0)
    if (excluded.length === 0 || rest.length === 0) { return null }
    return 'rails: "' + rest[0] + '" would run unsandboxed because "' + excluded[0]
        + '" is in sandbox.excludedCommands; run them as separate Bash calls'
}

/**
 * The live list, read once per session and cached.
 *
 * `$.settings.read()` is the engine's own merged view (user, project, local,
 * `--settings`, policy), which beats reading `~/.claude/settings.json` by path:
 * a hooks module may import nothing but its own files and `claude-code`, so
 * `node:fs` is not available to it (`claude plugin validate --strict` refuses
 * it outright). A read that rejects leaves the rule inert.
 */
function readExcluded($: EngineInterface): Promise<string[]> {
    return $.settings.read().then(excludedHeads).catch(() => [])
}

function envFor($: EngineInterface): Env {
    let cwd: Promise<string> | null = null
    return {
        cwd: () => {
            if (cwd === null) { cwd = $.session.cwd() }
            return cwd
        },
        // A probe that throws leaves the path unanchored, so the stage falls
        // through to the rkvr rewrite. Never the other way around.
        exists: (path) => $.fs.exists(path).catch(() => false),
        list: (dir) => $.fs.list(dir).then((es) => es.map((e) => e.name)).catch(() => []),
    }
}

function withContext<R extends ToolCallResult>(r: R, line: string): R {
    if (r.deny !== undefined || r.isError === true) { return r }
    return { ...r, context: [...(r.context ?? []), line] }
}

function debug($: EngineInterface, enabled: boolean, rule: string, line: string): void {
    if (enabled) { $.ui.log('rails/' + rule + ': ' + line) }
}

export const register: Register = (on, options) => {
    const persona = options['gh_persona'] !== false
    const rkvr = options['rm_rkvr'] !== false
    const compound = options['excluded_compound'] !== false
    const verbose = options['debug'] === true
    let excluded: Promise<string[]> | null = null

    on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
        const command = e.command
        if (!persona || typeof command !== 'string') { return next(e) }
        if (EXPLICIT.test(command)) {
            debug($, verbose, 'gh-persona', 'skip: command sets a persona or token itself')
            return next(e)
        }
        const spots = ghSpots(command)
        if (spots.length === 0) { return next(e) }

        const cwd = await $.session.cwd()
        debug($, verbose, 'gh-persona', 'gh spots=' + spots.length + ' cwd=' + cwd)

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
            debug($, verbose, 'gh-persona', 'no rewrite: ' + why)
            return withContext(await next(e), 'rails: GH_PERSONA not set (' + why + ')')
        }
        const rewritten = inject(command, picked)
        debug($, verbose, 'gh-persona', 'rewrote: ' + rewritten)
        const r = await next({ ...e, command: rewritten })
        return withContext(r, 'rails: GH_PERSONA injected (' + why + ')')
    })

    on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
        const command = e.command
        if (!rkvr || typeof command !== 'string') { return next(e) }
        if (!RM_INTEREST.test(command)) { return next(e) }

        const r = await rmRewrite(command, envFor($))
        if (r.deny !== undefined) {
            debug($, verbose, 'rm-rkvr', 'deny: ' + command)
            return { deny: r.deny }
        }
        const rewritten = r.command ?? command
        const note = r.note ?? ''
        if (note === '') { return next(e) }
        debug($, verbose, 'rm-rkvr', note + ' | ' + rewritten)
        if (rewritten === command) { return withContext(await next(e), note) }
        return withContext(await next({ ...e, command: rewritten }), note)
    })

    on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
        const command = e.command
        if (!compound || typeof command !== 'string') { return next(e) }
        if (excluded === null) { excluded = readExcluded($) }
        const deny = excludedDeny(command, await excluded)
        if (deny === null) { return next(e) }
        debug($, verbose, 'excluded-compound', 'deny: ' + command)
        return { deny }
    })
}

export const internals = {
    ghSpots,
    headSpots,
    heads,
    segment,
    personaFor,
    inject,
    inWorkTree,
    splitWords,
    stageComment,
    resolvePath,
    rmRewrite,
    REGENERABLE,
    excludedHeads,
    excludedDeny,
    classifyStages,
    readsOnlyStdin,
    skipRedirect,
}
