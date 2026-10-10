import type { EngineInterface, Register, Settings, ToolCallResult } from 'claude-code'
import {
    buildIndex, isRouted, joinInstructions, matchPrompt, matchTool, nestedPath, splitInstructions,
} from './rules.ts'
import type { InstructionPart, RuleIndex } from './rules.ts'
import type { RailsLoopLedger, RailsRuleLedger } from '../types/index.d.ts'

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

/** A heredoc whose body starts after the current line: its delimiter, and whether `<<-` strips tabs. */
type Heredoc = { delim: string; tabs: boolean }

/**
 * Where the scan resumes after the heredoc bodies that start at `at` (the
 * offset just past the newline ending the `<<` line), or -1 when a body has no
 * terminator line and so runs to the end of the command.
 */
function pastBodies(command: string, at: number, docs: readonly Heredoc[]): number {
    let i = at
    for (const doc of docs) {
        for (;;) {
            if (i >= command.length) { return -1 }
            const nl = command.indexOf('\n', i)
            const end = nl === -1 ? command.length : nl
            const line = command.slice(i, end)
            i = nl === -1 ? command.length : nl + 1
            if ((doc.tabs ? line.replace(/^\t+/, '') : line) === doc.delim) { break }
        }
    }
    return i
}

/**
 * Every simple-command head in `command`, quote-aware.
 *
 * A heredoc body is data, so neither a `gh` in a PR body nor an `rm` in a
 * script fixture is a command. The scan skips each body and resumes after its
 * terminator line, so `git commit -F - <<'EOF' ... EOF` followed by
 * `git push` still sees the push (implementation audit round 1, X6CMQgQe); a
 * body with no terminator runs to the end, and scanning stops there. A `<<<`
 * here-string has no body: its word is a redirect target. `loop` marks a head
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
    let docs: Heredoc[] = []
    while (i < command.length) {
        const c = command.charAt(i)
        if (quote !== '') {
            if (c === '\\' && quote === '"') { i += 2; continue }
            if (c === quote) { quote = '' }
            i += 1
            continue
        }
        if (c === '\\') { i += 2; continue }
        if (c === '\n' && docs.length > 0) {
            const resume = pastBodies(command, i + 1, docs)
            if (resume === -1) { break }
            docs = []
            start = true
            loop = false
            sep += c
            i = resume
            continue
        }
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
        if (c === '<' && command.charAt(i + 1) === '<') {
            if (command.charAt(i + 2) === '<') { i = skipRedirect(command, i + 1); continue }
            let j = i + 2
            const tabs = command.charAt(j) === '-'
            if (tabs) { j += 1 }
            while (command.charAt(j) === ' ' || command.charAt(j) === '\t') { j += 1 }
            const delim = quotedWord(command, j)
            if (delim.text === '') { break }
            docs.push({ delim: delim.text, tabs })
            i = delim.end
            continue
        }
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
const REVIEW_RUNS = '.cache/review-panel/runs'
const SCRATCH = ['$TMPDIR', '/tmp/claude', '~/' + REVIEW_RUNS]
/**
 * The absolute form of the runs/ prefix under any home directory. A hooks
 * module may import nothing but its own files and `claude-code`, so
 * `node:os`'s `homedir()` is unavailable: importing it made the engine refuse
 * the whole module and every rails rule went dark in fresh sessions
 * (36f02a4 -> fixed 2026-10-09, retro Phase 14).
 */
const SCRATCH_ABS = /^\/(?:home\/[^/]+|root|Users\/[^/]+)\/\.cache\/review-panel\/runs(?:\/|$)/
/** Words a wrapper carries that are verbs, not paths. */
const WRAPPER_VERBS = new Set(['rm', 'exec'])
/**
 * For docker/kubectl only: the subcommands that hand off to an arbitrary
 * INNER command rails cannot see into (`docker exec c rm -rf /x`, `docker run
 * --rm -v host:/host img rm -rf /host/x`). Absent one of these, an `rm` word
 * is the tool's OWN resource verb (`docker rm`, `docker rmi`, `docker volume
 * rm`, `docker compose rm`), which deletes containers/images/volumes, not
 * host files, so rkvr rmrf does not apply and it is not this rule's business.
 */
const DOCKER_DELEGATES = new Set(['exec', 'run'])
/** An `rm` word, including one inside a quoted `sh -c` payload. */
const RM_WORD = /(?:^|[\s;&|(])rm(?=\s|$)/
/** The only flags a rewritable `rm` may carry. */
const DELETE_FLAGS = /^-[rRf]+$/
/** The model's intent marker, matched exactly against the whole stage comment. */
const MARKER = '# regenerable'

const RM_REWRITE_NOTE = 'rails: rm -> rkvr rmrf (rules/safety.md); archive at /var/tmp/rmrf; if this was regenerable build output, re-issue with a trailing `# regenerable`'
const RM_SET_NOTE = 'rails: rm kept, regenerable build output (rules/safety.md)'
const RM_MARKER_NOTE = 'rails: rm kept, model asserted regenerable'
const RM_DENY = 'rails: this form deletes through another command, which rails cannot rewrite. Run `rkvr rmrf <paths>` yourself (rules/safety.md), or confine the command to $TMPDIR, /tmp/claude or ~/.cache/review-panel/runs.'

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
    return !paths.every((p) => SCRATCH.some((s) => p.value.startsWith(s)) || SCRATCH_ABS.test(p.value))
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
            const isDockerLike = head.word === 'docker' || head.word === 'kubectl'
            if (isDockerLike && !words.some((w) => DOCKER_DELEGATES.has(w.value))) { continue }
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
 * rails: pkill -f bracket
 *
 * `pkill -f <pat>` matches <pat> against every process's full command line, and
 * the shell the Bash tool spawns carries the command text in its own argv.
 * pkill spares itself, not its parent, so the shell is killed and the call
 * comes back exit 144 (18 sessions, retro 2026-10-08) or 143 (SIGTERM,
 * measured 2026-10-09 in a fresh `claude -p` with this rule off). Bracketing the first
 * character keeps the regex identical (`[q]uartz` still matches `quartz`)
 * while the shell's copy of the text (`[q]uartz`) no longer contains the
 * literal the regex needs.
 *
 * That rewrite is exact only in a subset: the first character is a literal,
 * there is no `|` (every alternative would need its own bracket), and it is
 * not already bracketed. Outside the subset the call is denied with the
 * bracketed form of each alternative named, never rewritten half-right. `-x`
 * anchors the match to the whole command line, which the shell's never equals,
 * and without `-f` pkill matches the process name, so both pass untouched.
 */
const PKILL_INTEREST = /(?:^|[\s;&|(])(?:\S*\/)?pkill(?=\s|$)/
/** Short options whose value is the next character run or the next word. */
const PKILL_VALUE_SHORT = new Set([...'qgGOPstuUFr'])
/** Long options that take a value, `--name value` or `--name=value`. */
const PKILL_VALUE_LONG = new Set([
    'queue', 'pgroup', 'group', 'older', 'parent', 'session', 'terminal', 'euid', 'uid',
    'pidfile', 'runstates', 'signal', 'cgroup', 'ns', 'nslist',
])
/** `-<sig>` by name: `-KILL`, `-SIGTERM`, `-kill`, `-RTMIN+1`. Numbers are matched separately. */
const PKILL_SIGNALS = new Set([
    'HUP', 'INT', 'QUIT', 'ILL', 'TRAP', 'ABRT', 'IOT', 'BUS', 'FPE', 'KILL', 'USR1', 'SEGV', 'USR2',
    'PIPE', 'ALRM', 'TERM', 'STKFLT', 'CHLD', 'CLD', 'CONT', 'STOP', 'TSTP', 'TTIN', 'TTOU', 'URG',
    'XCPU', 'XFSZ', 'VTALRM', 'PROF', 'WINCH', 'IO', 'POLL', 'PWR', 'SYS',
])
/** ERE metacharacters; a pattern whose first character is one of these has no literal to bracket. */
const REGEX_META = new Set([...'.[](){}*+?^$\\|'])
/** A redirect word (`2>/dev/null`, `>out`) is never the pattern. */
const REDIRECT_WORD = /^[0-9]*[<>]/
/** A `$` that starts an expansion, or a backtick: the shell, not the text, decides the pattern. */
const EXPANSION = /\$[A-Za-z_{(0-9@*#?!$-]|`/
const PKILL_WHY = 'would match the Bash tool\'s own shell (its command line carries the pattern) and kill it (exit 143 or 144)'

function isPkillSignal(flag: string): boolean {
    const name = flag.slice(1)
    if (/^[0-9]+$/.test(name)) { return true }
    const upper = name.toUpperCase()
    const bare = upper.startsWith('SIG') ? upper.slice(3) : upper
    return PKILL_SIGNALS.has(bare) || /^RT(?:MIN|MAX)(?:[+-][0-9]+)?$/.test(bare)
}

/** What one pkill stage asks for: `-f`, `-x`, and which word is the pattern (-1 for none). */
function pkillArgs(words: readonly Word[]): { full: boolean; exact: boolean; pattern: number } {
    let full = false
    let exact = false
    let i = 1
    while (i < words.length) {
        const w = words[i]
        if (w === undefined) { break }
        const v = w.value
        if (REDIRECT_WORD.test(w.raw)) { i += 1; continue }
        if (v === '--') { return { full, exact, pattern: i + 1 < words.length ? i + 1 : -1 } }
        if (v.startsWith('--')) {
            const name = v.slice(2).split('=')[0] ?? ''
            if (name === 'full') { full = true }
            if (name === 'exact') { exact = true }
            i += PKILL_VALUE_LONG.has(name) && !v.includes('=') ? 2 : 1
            continue
        }
        if (v.startsWith('-') && v.length > 1) {
            if (isPkillSignal(v)) { i += 1; continue }
            let step = 1
            for (let k = 1; k < v.length; k += 1) {
                const f = v.charAt(k)
                if (f === 'f') { full = true }
                if (f === 'x') { exact = true }
                if (PKILL_VALUE_SHORT.has(f)) {
                    if (k === v.length - 1) { step = 2 }
                    break
                }
            }
            i += step
            continue
        }
        return { full, exact, pattern: i }
    }
    return { full, exact, pattern: -1 }
}

/** Does the raw word expand anything outside single quotes? */
function pkillExpands(raw: string): boolean {
    let quote = ''
    let plain = ''
    for (let i = 0; i < raw.length; i += 1) {
        const c = raw.charAt(i)
        if (quote === "'") { if (c === "'") { quote = '' } continue }
        if (c === "'" && quote === '') { quote = "'"; plain += ' '; continue }
        plain += c
    }
    return EXPANSION.test(plain)
}

/** The first code point of `s`, so an astral character is bracketed whole. */
function firstChar(s: string): string {
    return Array.from(s)[0] ?? ''
}

/** One alternative with its first character bracketed, itself if already bracketed, or null. */
function bracketAlt(alt: string): string | null {
    if (alt.startsWith('[')) { return alt }
    const c = firstChar(alt)
    if (c === '' || REGEX_META.has(c)) { return null }
    return '[' + c + ']' + alt.slice(c.length)
}

/**
 * The raw word rewritten with its first character bracketed, keeping the
 * user's quoting, or null when the quoting is past what this splices safely.
 * A bare word is single-quoted whole so the new `[q]` cannot glob; a bare word
 * that also carries a redirect or other shell syntax gets only `'[q]'` quoted.
 */
function bracketRaw(raw: string, value: string): string | null {
    const want = firstChar(value)
    const open = raw.charAt(0)
    if (open === "'" || open === '"') {
        const c = firstChar(raw.slice(1))
        if (c !== want || c === open || (open === '"' && '\\$`'.includes(c))) { return null }
        return open + '[' + c + ']' + raw.slice(1 + c.length)
    }
    const c = firstChar(raw)
    if (c !== want || '\\$`'.includes(c)) { return null }
    if (/^[^\s'"\\$`<>;&|()]+$/.test(raw)) { return "'[" + c + ']' + raw.slice(c.length) + "'" }
    return "'[" + c + "]'" + raw.slice(c.length)
}

/** The deny for a pattern outside the subset, naming the bracketed form of each alternative. */
function pkillDeny(value: string, alts: readonly string[]): string {
    const head = 'rails: pkill -f \'' + value + '\' ' + PKILL_WHY + '. rails brackets only a pattern with a literal first '
        + 'character and no `|`. '
    const metas = alts.filter((a) => bracketAlt(a) === null)
    if (metas.length > 0) {
        return head + metas.map((a) => '"' + a + '"').join(', ') + ' starts with a regex metacharacter, so no bracket '
            + 'keeps it off the shell: lead each alternative with a literal and bracket it '
            + '(quartz.*4173 -> [q]uartz.*4173)'
    }
    return head + 'Re-issue with every alternative bracketed: pkill -f \'' + alts.map(bracketAlt).join('|') + '\''
}

/** What the pkill rule decided: a (possibly unchanged) command, or a deny reason. */
type PkillResult = { command: string; note: string } | { deny: string }

/** Classify and rewrite every `pkill -f` stage in `command`. Pure. */
function pkillRewrite(command: string): PkillResult {
    const edits: Edit[] = []
    const notes: string[] = []
    for (const head of heads(command)) {
        if (head.word.split('/').pop() !== 'pkill') { continue }
        const seg = segment(command, head.at)
        const comment = stageComment(seg)
        const body = comment === null ? seg : seg.slice(0, comment.at)
        const words = splitWords(body)
        const args = pkillArgs(words)
        if (!args.full || args.exact || args.pattern === -1) { continue }
        const word = words[args.pattern]
        if (word === undefined || word.value === '') { continue }
        if (pkillExpands(word.raw)) {
            notes.push('rails: pkill -f pattern not bracketed (it carries a shell expansion rails cannot see)')
            continue
        }
        const alts = word.value.split('|')
        if (alts.every((a) => a.startsWith('['))) { continue }
        if (alts.length > 1 || bracketAlt(word.value) === null) { return { deny: pkillDeny(word.value, alts) } }

        const bracketed = bracketAlt(word.value) ?? word.value
        const text = bracketRaw(word.raw, word.value)
        if (text === null) {
            return {
                deny: 'rails: pkill -f ' + word.raw + ' ' + PKILL_WHY + ', and its quoting is past what rails rewrites. '
                    + 'Re-issue as: pkill -f \'' + bracketed + '\'',
            }
        }
        let at = 0
        for (let k = 0; k < args.pattern; k += 1) {
            while (at < body.length && ' \t\r'.includes(body.charAt(at))) { at += 1 }
            at += words[k]?.raw.length ?? 0
        }
        while (at < body.length && ' \t\r'.includes(body.charAt(at))) { at += 1 }
        const start = head.at + at
        edits.push({ at: start, end: start + word.raw.length, text })
        notes.push('rails: pkill -f pattern bracketed (' + word.value + ' -> ' + bracketed
            + ') so it cannot match the Bash tool\'s own shell')
    }
    let out = command
    for (const edit of [...edits].sort((a, b) => b.at - a.at)) {
        out = out.slice(0, edit.at) + edit.text + out.slice(edit.end)
    }
    return { command: out, note: notes.join(' | ') }
}

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
 *
 * Re-measured 2026-10-08 on Claude Code 2.1.295 with the same marker, and the
 * harness now does the OPPOSITE: a compound (`;`, `&&`, `|`, a `VAR=x;` prefix,
 * `bash -c '...'`) runs fully SANDBOXED whatever heads it contains; only a bare
 * simple command matching the glob is exempt. `cargo run -q` ran unsandboxed,
 * `S=x; cargo run -q ...` sandboxed, `otto ci | tail` sandboxed, a bare
 * `ssh ripr.lan ls /tmp` unsandboxed. That matches `intent-guard.sh`'s GIT-NET
 * finding (2026-09-24). The deny stays for the heads that FAIL in the sandbox
 * (git network verbs, `bump`, `ssh`, `slack`, `systemctl`, `aws-vault`,
 * `crontab`): it turns a confusing in-sandbox auth/DNS failure into a plain
 * two-call rewrite, and it keeps the hatch shut if a later harness exempts
 * compounds again. The deny text says what actually happens (2.1.295), not
 * what the 2026-09-13 build did.
 */

/** Heads that carry an inner command; the inner head is what actually runs. */
const EX_WRAPPERS = new Set(['sh', 'bash', 'zsh', 'sudo', 'xargs', 'env', 'nohup', 'docker', 'kubectl'])
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
/**
 * Flags whose value is a FILE, which makes the consumer read something other
 * than its stdin. `sed -f prog.sed` and `rg -f patterns.txt` were passing as
 * transparent because the flag was filtered out and its path then landed in the
 * single pattern slot PATTERN_CONSUMERS allows (audit 2026-09-13, C1).
 */
const FILE_FLAGS = new Set([
    '-f', '--file', '--from-file', '--slurpfile', '--rawfile', '--argfile', '-T', '--files-from',
])
/**
 * A `sh -c` payload may itself be a compound. Three levels turned out NOT to be
 * past real use: `nohup env sudo bash -c '...'` is four, and at the cap the
 * wrapper went to REST while the excluded stage inside was never seen, so
 * `excluded` came back empty and the deny could not fire (audit 2026-09-13, D3).
 * Recursion terminates on its own because each inner payload is strictly
 * shorter, so the cap only bounds pathological input.
 */
const EX_MAX_DEPTH = 8
/** Every entry is written `<head> *`; the glob is not part of the head. */
const EX_GLOB_SUFFIX = ' *'

/**
 * Heads drive classification; `excludedText` / `restText` carry each stage's
 * own text (redirects kept, trimmed) so the deny can name the two-call rewrite.
 */
type Stages = { excluded: string[]; rest: string[]; excludedText: string[]; restText: string[] }

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
    const words = splitWords(seg).slice(1)
    if (words.some((w) => FILE_FLAGS.has(w.value) || [...FILE_FLAGS].some((f) => f.startsWith('--') && w.value.startsWith(f + '=')))) {
        return false
    }
    const operands = words
        .filter((w) => !(w.value.startsWith('-') && w.value.length > 1) && !FLAG_VALUE.test(w.value))
    return operands.length <= (PATTERN_CONSUMERS.has(head) ? 1 : 0)
}

/** Split a command into its excluded stages and every other stage that acts. */
function classifyStages(command: string, entries: readonly string[], depth: number): Stages {
    const out: Stages = { excluded: [], rest: [], excludedText: [], restText: [] }
    for (const head of heads(command)) {
        const seg = segment(command, head.at)
        if (excludedAs(seg, head.word, entries) !== null) {
            out.excluded.push(head.word)
            out.excludedText.push(stageText(command, head.at))
            continue
        }
        if (EX_TRANSPARENT.has(head.word)) { continue }
        if (head.piped && readsOnlyStdin(head.word, seg)) { continue }
        if (depth < EX_MAX_DEPTH && EX_WRAPPERS.has(head.word)) {
            const inner = innerCommand(splitWords(seg))
            if (inner !== null) {
                const nested = classifyStages(inner, entries, depth + 1)
                out.excluded.push(...nested.excluded)
                out.rest.push(...nested.rest)
                out.excludedText.push(...nested.excludedText)
                out.restText.push(...nested.restText)
                continue
            }
        }
        out.rest.push(head.word)
        out.restText.push(stageText(command, head.at))
    }
    return out
}

/**
 * The stage starting at `at` as the user wrote it, trimmed. Unlike `segment`,
 * a redirect does not end it: `git fetch -q origin 2>&1` stays whole instead of
 * being cut to `git fetch -q origin 2>` at the `&`.
 */
function stageText(command: string, at: number): string {
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
        if (c === '>' || c === '<') { i = skipRedirect(command, i); continue }
        if (SEP.has(c)) { break }
        i += 1
    }
    return command.slice(at, i).trim()
}

function quoted(texts: readonly string[]): string {
    return texts.map((t) => '"' + t + '"').join(', ')
}

/**
 * The deny reason for a compound that mixes an excluded stage with one that
 * acts, or null. On 2.1.295 the whole compound runs sandboxed (see the header),
 * so the excluded stage is the one that breaks; the text says so and names the
 * two-call rewrite.
 */
function excludedDeny(command: string, entries: readonly string[]): string | null {
    if (entries.length === 0) { return null }
    const { excludedText, restText } = classifyStages(command, entries, 0)
    if (excludedText.length === 0 || restText.length === 0) { return null }
    const ex = quoted(excludedText)
    return 'rails: ' + ex + ' would run INSIDE the sandbox here (a compound is never exempt) and cannot '
        + 'authenticate/reach the host; run ' + ex + ' alone, then ' + quoted(restText)
        + ' as a separate Bash call'
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

/**
 * rails: rule routing (docs/design/2026-10-08-rule-routing.md)
 *
 * Every rule in `~/repos/.claude/rules/` declares `load:` (rules.ts parses it).
 * A routed rule is dropped from the engine's bulk load (`instructions` at
 * session start, `nested_memory` mid-session) and injected once per loop when
 * its trigger fires: a prompt, a tool, a Bash statement. A file the bulk load
 * already delivered under one spelling is dropped when it arrives again under
 * another. Any failure sets a latch that turns the router off for the session
 * and re-asks every attachment, which brings back today's full load.
 */

/** The ledger's shapes are rails' `$.state` contract, in `types/index.d.ts`. */
type LoopLedger = RailsLoopLedger
type RuleLedger = RailsRuleLedger

const LEDGER = { plugin: 'rails', key: 'ruleLedger' } as const
const ROUTING_OFF = { plugin: 'rails', key: 'routingOff' } as const

const MAIN_LOOP = 'main'
/** Where the rule index lives, under $HOME; the per-file symlinks `manifest.yml` lays down. */
const RULES_DIR = '/repos/.claude/rules'
const ROUTED_TYPES = new Set(['instructions', 'nested_memory'])
const DRAFT_CLAUSE = 'If your text changes after reading it, show Scott the new draft before sending.'

/** What a routed rule's index entry needs at run time: its body, frontmatter stripped. */
type Rules = { index: RuleIndex; bodies: Record<string, string> }

/** One file section of a bulk load and what the router made of it. */
type Verdict = 'keep' | 'routed' | 'duplicate'
type FileDecision = { path: string; real: string; verdict: Verdict }

function loopOf(agentId: string | undefined): string {
    return agentId ?? MAIN_LOOP
}

function baseName(path: string): string {
    return path.slice(path.lastIndexOf('/') + 1)
}

/** A rule's text minus its frontmatter, as the engine hands a rule's content on. */
function ruleBody(text: string): string {
    let body = text
    if (text.startsWith('---\n')) {
        const close = text.indexOf('\n---', 3)
        if (close >= 0) {
            const eol = text.indexOf('\n', close + 4)
            body = eol < 0 ? '' : text.slice(eol + 1)
        }
    }
    return body.replace(/^\n+/, '').replace(/\s+$/, '')
}

/** An injected rule, framed the way the engine frames a nested load. */
function framed(path: string, body: string): string {
    return 'Contents of ' + path + ':\n\n' + body
}

/** FNV-1a over the attachment's type and text: which attachment kept a file. */
function fingerprint(type: string, text: string): string {
    let h = 0x811c9dc5
    const s = type + '\u0000' + text
    for (let i = 0; i < s.length; i += 1) {
        h ^= s.charCodeAt(i)
        h = Math.imul(h, 0x01000193) >>> 0
    }
    return type + ':' + s.length + ':' + h.toString(16)
}

function loopLedger(ledger: RuleLedger, loop: string): LoopLedger {
    const l = ledger[loop] ?? { kept: {}, rules: {} }
    ledger[loop] = l
    return l
}

/**
 * Keep, or drop as routed or as a duplicate, each file of one bulk-load
 * attachment, recording what was kept. Mutates `ledger`.
 *
 * Routed means a rule-index file whose `load:` is a trigger map. Duplicate
 * means a real path some other attachment of this loop already delivered, or
 * one this attachment carries twice; files outside the rule index are never
 * routed but are de-duplicated all the same.
 */
function decideFiles(
    index: RuleIndex, ledger: RuleLedger, loop: string,
    files: readonly { path: string; real: string }[], owner: string,
): FileDecision[] {
    const l = loopLedger(ledger, loop)
    const seen = new Set<string>()
    return files.map((f): FileDecision => {
        if (isRouted(index, f.real)) { return { ...f, verdict: 'routed' } }
        const keeper = l.kept[f.real]
        if (seen.has(f.real) || (keeper !== undefined && keeper !== owner)) { return { ...f, verdict: 'duplicate' } }
        seen.add(f.real)
        l.kept[f.real] = owner
        return { ...f, verdict: 'keep' }
    })
}

/**
 * The `instructions` blob without the dropped sections: every path-less part
 * (the preamble, `<managed-settings>`) kept, the kept sections byte for byte.
 * Dropping the last section would leave its predecessor's separator dangling,
 * so the result ends in exactly the trailing newlines the blob ended in.
 */
function rejoin(blob: string, parts: readonly InstructionPart[], dropped: ReadonlySet<InstructionPart>): string {
    const joined = joinInstructions(parts.filter((p) => !dropped.has(p)))
    const tail = /\n*$/.exec(blob)?.[0] ?? ''
    return joined.replace(/\n+$/, '') + tail
}

/**
 * Mark every rule not yet seen in this loop as delivered; returns those it marked.
 *
 * Only a prompt inject is delivered on the spot: it rides the user turn, which
 * reaches the model before any tool call of that turn can exist.
 */
function claimDelivered(ledger: RuleLedger, loop: string, paths: readonly string[]): string[] {
    const l = loopLedger(ledger, loop)
    const claimed = paths.filter((p) => l.rules[p] === undefined)
    for (const p of claimed) { l.rules[p] = 'delivered' }
    return claimed
}

/**
 * Mark every rule not yet seen in this loop as pending; returns those it marked.
 *
 * A tool result's `context[]` reaches the model only with the next request,
 * so a sibling call in the same model response has not read it. Pending makes
 * that sibling's gate wait ("delivered above") until `turn.step` promotes it;
 * marking it delivered here let `git log -1` + `git push` in one response push
 * before git.md was read (implementation audit round 1, X6CMQgQe).
 */
function claimPending(ledger: RuleLedger, loop: string, paths: readonly string[]): string[] {
    const l = loopLedger(ledger, loop)
    const claimed = paths.filter((p) => l.rules[p] === undefined)
    for (const p of claimed) { l.rules[p] = 'pending' }
    return claimed
}

/** Undo `claimDelivered` (or `claimPending`) for rules whose carrier never reached the model. */
function releaseClaimed(ledger: RuleLedger, loop: string, paths: readonly string[], state: 'delivered' | 'pending'): void {
    const l = loopLedger(ledger, loop)
    for (const p of paths) {
        if (l.rules[p] === state) { delete l.rules[p] }
    }
}

/**
 * The gate rules this call must wait for: `fresh` ones were never seen and
 * are now pending (the deny carries their text); `waiting` ones are pending
 * from an earlier deny the model has not read yet. Delivered ones pass.
 */
function claimGate(ledger: RuleLedger, loop: string, paths: readonly string[]): { fresh: string[]; waiting: string[] } {
    const l = loopLedger(ledger, loop)
    const fresh = paths.filter((p) => l.rules[p] === undefined)
    const waiting = paths.filter((p) => l.rules[p] === 'pending')
    for (const p of fresh) { l.rules[p] = 'pending' }
    return { fresh, waiting }
}

/** A model request is starting: every deny this loop returned is in it now. */
function promotePending(ledger: RuleLedger, loop: string): string[] {
    const l = ledger[loop]
    if (l === undefined) { return [] }
    const promoted = Object.keys(l.rules).filter((p) => l.rules[p] === 'pending')
    for (const p of promoted) { l.rules[p] = 'delivered' }
    return promoted
}

/** The deny text for a gated call: the fresh rules whole, a pointer for the waiting. */
function gateDeny(fresh: readonly { path: string; body: string }[], waiting: readonly string[]): string {
    const lines: string[] = []
    if (fresh.length > 0) {
        lines.push('rails: ' + fresh.map((r) => baseName(r.path)).join(', ')
            + ' must be in context before this call runs, so it did not run. Read the rule below, then retry the call.')
        for (const r of fresh) { lines.push(framed(r.path, r.body)) }
    }
    if (waiting.length > 0) {
        lines.push('rails: ' + waiting.map(baseName).join(', ') + ': rule delivered above, retry after reading it.')
    }
    lines.push(DRAFT_CLAUSE)
    return lines.join('\n\n')
}

/** Rails' own statement split, the one the Bash hooks use: one string per simple command. */
function statements(command: string): string[] {
    return heads(command).map((h) => segment(command, h.at))
}

/**
 * The router log (Phase 6): every router line, timestamped and tagged with its
 * loop, in `~/.local/share/rails/router/<sessionId>.log`, so a session run
 * without `--debug` still says what the router dropped and why it latched.
 *
 * `$.fs.write` writes whole files only, so the session's lines live here and
 * every flush rewrites the file: one write in flight, at most one queued, the
 * queued one taking whatever the buffer holds when it starts. Past `LOG_CAP`
 * the oldest lines go and the file opens with a count of them.
 */
const LOG_DIR = '/.local/share/rails/router'
const LOG_CAP = 1024 * 1024
const LOG_KEEP_MS = 14 * 24 * 60 * 60 * 1000
const DROPPED_MARKER = /^\.\.\. (\d+) earlier lines dropped$/

/** Where the buffer goes, bound to the newest `$` a line arrived with. */
type LogSink = { write: (text: string) => Promise<void>; note: (text: string) => void }

type RouterLog = {
    /** The session's file; null until opened, and for good when it cannot be. */
    path: string | null
    opened: Promise<void> | null
    lines: string[]
    /** UTF-8 bytes of `lines`, a newline after each. */
    bytes: number
    dropped: number
    sink: LogSink | null
    inFlight: Promise<void> | null
    queued: boolean
    /** A write failure is noted in the debug log once, then only swallowed. */
    noted: boolean
}

function newRouterLog(): RouterLog {
    return { path: null, opened: null, lines: [], bytes: 0, dropped: 0, sink: null, inFlight: null, queued: false, noted: false }
}

function utf8Length(s: string): number {
    let n = 0
    for (let i = 0; i < s.length; i += 1) {
        const c = s.charCodeAt(i)
        if (c < 0x80) { n += 1 } else if (c < 0x800) { n += 2 } else if (c >= 0xd800 && c <= 0xdbff) { n += 4; i += 1 } else { n += 3 }
    }
    return n
}

function droppedMarker(dropped: number): string {
    return '... ' + dropped + ' earlier lines dropped'
}

/** The file's whole content: the dropped-lines marker when any were, then every line. */
function logContent(log: RouterLog): string {
    const head = log.dropped > 0 ? droppedMarker(log.dropped) + '\n' : ''
    return head + log.lines.map((l) => l + '\n').join('')
}

/** Drop the oldest lines until the file, marker included, fits `cap`; one line always stays. */
function trimLog(log: RouterLog, cap: number): void {
    const markerBytes = (d: number): number => (d > 0 ? utf8Length(droppedMarker(d)) + 1 : 0)
    while (log.lines.length > 1 && log.bytes + markerBytes(log.dropped) > cap) {
        const oldest = log.lines.shift() as string
        log.bytes -= utf8Length(oldest) + 1
        log.dropped += 1
    }
}

function appendLine(log: RouterLog, line: string, cap: number = LOG_CAP): void {
    log.lines.push(line)
    log.bytes += utf8Length(line) + 1
    trimLog(log, cap)
}

/** Put an earlier copy's file (a hot reload) ahead of what this copy buffered. */
function seedLog(log: RouterLog, prior: string, cap: number = LOG_CAP): void {
    const old = prior.split('\n').filter((l) => l !== '')
    const marker = DROPPED_MARKER.exec(old[0] ?? '')
    if (marker !== null) {
        log.dropped += Number(marker[1])
        old.shift()
    }
    log.lines = [...old, ...log.lines]
    log.bytes += old.reduce((n, l) => n + utf8Length(l) + 1, 0)
    trimLog(log, cap)
}

function noteLogFailure(log: RouterLog, err: unknown): void {
    if (log.noted) { return }
    log.noted = true
    const message = err instanceof Error ? err.message : String(err)
    try {
        log.sink?.note('rules: router log write failed (' + (log.path ?? 'no path') + '): ' + message)
    } catch {
        // Nowhere left to say it.
    }
}

/** Write the buffer out, serialized: a flush while one runs only queues one more. */
function pumpLog(log: RouterLog): void {
    if (log.inFlight !== null) {
        log.queued = true
        return
    }
    if (log.sink === null) { return }
    log.inFlight = (async () => {
        do {
            log.queued = false
            const sink = log.sink
            if (sink === null) { break }
            try {
                await sink.write(logContent(log))
            } catch (err) {
                noteLogFailure(log, err)
            }
        } while (log.queued)
        log.inFlight = null
    })()
}

/** Resolves once nothing is in flight or queued. */
async function logIdle(log: RouterLog): Promise<void> {
    while (log.inFlight !== null) { await log.inFlight }
}

/** The `*.log` files in the log directory last written before `now - LOG_KEEP_MS`. */
function staleLogs(entries: readonly { name: string; kind: string; mtimeMs: number }[], now: number): string[] {
    return entries
        .filter((e) => e.kind === 'file' && e.name.endsWith('.log') && e.mtimeMs < now - LOG_KEEP_MS)
        .map((e) => e.name)
}

/**
 * The router's per-session memory.
 *
 * The working copy of the ledger and the latch lives here, so every claim is
 * one synchronous step and two calls in one batch cannot both take a rule.
 * `$.state` holds the durable copy, written through on every change and read
 * back once after a hot reload. The rule index is built once per session.
 */
type Router = {
    routing: boolean
    verbose: boolean
    loaded: Promise<void> | null
    ledger: RuleLedger
    off: string | null
    rules: Promise<Rules> | null
    realPaths: Map<string, string>
    log: RouterLog
    started: Promise<void> | null
}

function newRouter(routing: boolean, verbose: boolean): Router {
    return {
        routing, verbose, loaded: null, ledger: {}, off: null, rules: null, realPaths: new Map(),
        log: newRouterLog(), started: null,
    }
}

/** Point the log at this `$`, the newest one: a queued write runs on it. */
function bindLog($: EngineInterface, log: RouterLog): void {
    const path = log.path
    if (path === null) { return }
    log.sink = {
        write: (text) => $.fs.write(path, text),
        note: (text) => { $.ui.log(text, { to: 'debug' }) },
    }
}

/**
 * One router line: the debug log always, the transcript too when `debug` is
 * on, and the router log file, stamped with the time and the loop.
 */
function say($: EngineInterface, r: Router, line: string, loop: string = MAIN_LOOP): void {
    try {
        if (r.verbose) { $.ui.log(line) } else { $.ui.log(line, { to: 'debug' }) }
    } catch {
        // A log line is never worth failing a hook over.
    }
    try {
        appendLine(r.log, new Date().toISOString() + ' ' + loop + ' ' + line)
        if (r.log.path === null) { return }
        bindLog($, r.log)
        pumpLog(r.log)
    } catch (err) {
        noteLogFailure(r.log, err)
    }
}

/**
 * Find the session's log file, take in what an earlier copy of the module
 * wrote there, and flush what this copy buffered. Never throws: a log that
 * cannot open stays a memory buffer, noted once.
 */
async function openLog($: EngineInterface, r: Router): Promise<void> {
    if (r.log.opened === null) {
        r.log.opened = (async () => {
            try {
                const home = await $.env.get('HOME')
                if (home === undefined || home === '') { throw new Error('HOME is unset') }
                const id = await $.session.id()
                const path = home + LOG_DIR + '/' + id + '.log'
                const prior = await $.fs.read(path).catch(() => '')
                seedLog(r.log, typeof prior === 'string' ? prior : '')
                r.log.path = path
                bindLog($, r.log)
                pumpLog(r.log)
            } catch (err) {
                const message = err instanceof Error ? err.message : String(err)
                try { $.ui.log('rules: router log off: ' + message, { to: 'debug' }) } catch { /* nowhere to say it */ }
                r.log.noted = true
            }
        })()
    }
    return r.log.opened
}

/** Once per module copy: open the log and say which session, whether routing is on, and the engine; `loop` is the first hook's. */
async function startRouter($: EngineInterface, r: Router, loop: string): Promise<void> {
    if (r.started === null) {
        r.started = (async () => {
            await openLog($, r)
            const id = await $.session.id().catch(() => 'unknown')
            const version = await $.session.version().then((v) => v.version).catch(() => 'unknown')
            const on = r.off === null && r.routing
            say($, r, 'rules: session ' + id + ' start, routing ' + (on ? 'on' : 'off') + ', CC ' + version, loop)
        })()
    }
    return r.started
}

/** Delete the router logs older than `LOG_KEEP_MS`; best effort, never fails the index. */
async function pruneLogs($: EngineInterface, r: Router, home: string, loop: string): Promise<void> {
    try {
        const dir = home + LOG_DIR
        const stale = staleLogs(await $.fs.list(dir), Date.now())
        if (stale.length === 0) { return }
        const run = await $.process.run(['rm', '-f', '--', ...stale.map((n) => dir + '/' + n)])
        say($, r, 'rules: pruned ' + stale.length + ' router logs older than 14 days'
            + (run.exitCode === 0 ? '' : ' (rm exit ' + run.exitCode + ': ' + run.stderr.trim().slice(0, 80) + ')'), loop)
    } catch {
        // No directory yet, or nothing to list: nothing to prune.
    }
}

/** Read the latch and the ledger back from `$.state`, once per module load. */
async function loadRouter($: EngineInterface, r: Router): Promise<void> {
    if (r.loaded === null) {
        r.loaded = (async () => {
            const held = await $.state.get(ROUTING_OFF)
            if (held.value !== undefined && r.off === null) { r.off = held.value }
            const stored = await $.state.get(LEDGER)
            if (stored.value !== undefined) { r.ledger = stored.value }
        })()
    }
    return r.loaded
}

async function persist($: EngineInterface, r: Router): Promise<void> {
    await $.state.set(LEDGER, r.ledger)
}

/**
 * Turn routing off for the session and re-ask every attachment, so each
 * dropped file comes back (from the next turn on, Phase 0 (h)). Memory
 * first: the latch holds in this process even if the engine calls fail.
 * `status` is the line shown on screen; a toggle turned off shows none.
 */
async function latch($: EngineInterface, r: Router, why: string, status: string | null, loop: string): Promise<void> {
    if (r.off !== null) { return }
    r.off = why
    say($, r, 'rules: routing off: ' + why, loop)
    if (status !== null) { $.ui.status(status) }
    $.ui.invalidate('prompt.attachment')
    await $.state.set(ROUTING_OFF, why)
}

/** The on-screen line for a router failure: where, the message's first 80 characters, and the log. */
function failedStatus(where: string, message: string, logPath: string | null): string {
    return 'rules: router failed (' + where + ': ' + message.slice(0, 80) + '), full load restored; log '
        + (logPath ?? 'unavailable')
}

/** True when routing is off for this session, latching it the first time the toggle reads false. */
async function routingOff($: EngineInterface, r: Router, loop: string): Promise<boolean> {
    if (r.off !== null) { return true }
    await loadRouter($, r)
    await startRouter($, r, loop)
    if (r.off !== null) { return true }
    if (!r.routing) {
        await latch($, r, 'rule_routing is false', null, loop)
        return true
    }
    return false
}

/** Any router failure: name it in the debug log and the router log, and latch routing off. */
async function routerFailed($: EngineInterface, r: Router, where: string, err: unknown, loop: string): Promise<void> {
    const message = err instanceof Error ? err.message : String(err)
    say($, r, 'rules: ' + where + ' failed: ' + message, loop)
    try {
        await latch($, r, where + ' failed: ' + message, failedStatus(where, message, r.log.path), loop)
    } catch {
        // The latch is set in memory; the engine calls behind it are best effort.
    }
}

/** Run `fn` unless routing is off; any throw latches and answers null (pass through). */
async function guarded<T>(
    $: EngineInterface, r: Router, where: string, agentId: string | undefined, fn: () => Promise<T>,
): Promise<T | null> {
    const loop = loopOf(agentId)
    try {
        if (await routingOff($, r, loop)) { return null }
        return await fn()
    } catch (err) {
        await routerFailed($, r, where, err, loop)
        return null
    }
}

/** A `.catch` handler's latch: never on a re-entry, where `$` calls reject and the hook judged nothing. */
async function caught(
    $: EngineInterface, r: Router, where: string, agentId: string | undefined, kind: string, message: string | undefined,
): Promise<void> {
    if (kind === 're-entry') { return }
    await routerFailed($, r, where, new Error(kind + (message === undefined ? '' : ': ' + message)), loopOf(agentId))
}

/** Where a path lands, every link followed; the spelling itself when it cannot be resolved. */
async function realPathOf($: EngineInterface, r: Router, path: string): Promise<string> {
    const known = r.realPaths.get(path)
    if (known !== undefined) { return known }
    const stat = await $.fs.stat(path, { resolve: true }).catch(() => undefined)
    const landed = stat?.realPath ?? path
    r.realPaths.set(path, landed)
    return landed
}

async function ruleIndex($: EngineInterface, r: Router, loop: string): Promise<Rules> {
    if (r.rules === null) { r.rules = buildRules($, r, loop) }
    return r.rules
}

/** The rule index from `~/repos/.claude/rules`, keyed by real path, with each rule's body. */
async function buildRules($: EngineInterface, r: Router, loop: string): Promise<Rules> {
    const home = await $.env.get('HOME')
    if (home === undefined || home === '') { throw new Error('HOME is unset, so ~' + RULES_DIR + ' cannot be found') }
    await pruneLogs($, r, home, loop)
    const dir = home + RULES_DIR
    if (!(await $.fs.exists(dir))) {
        say($, r, 'rules: no rule index at ' + dir + ', nothing to route', loop)
        return { index: { rules: [] }, bodies: {} }
    }
    const names = (await $.fs.list(dir)).filter((e) => e.name.endsWith('.md')).map((e) => e.name).sort()
    const files: { path: string; text: string }[] = []
    for (const name of names) {
        const path = dir + '/' + name
        // A link left behind when its rule moved (cli.md, logging.md went to
        // refs/ in ba21860) loads nothing for the engine either: not a rule.
        const stat = await $.fs.stat(path, { resolve: true }).catch(() => undefined)
        if (stat?.realPath === undefined || stat.kind !== 'file') {
            say($, r, 'rules: skip ' + name + ' (leads to no file) ' + path, loop)
            continue
        }
        r.realPaths.set(path, stat.realPath)
        files.push({ path: stat.realPath, text: await $.fs.read(path) })
    }
    const built = buildIndex(files)
    const bodies: Record<string, string> = {}
    for (const f of files) { bodies[f.path] = ruleBody(f.text) }
    const broken = built.rules.filter((rule) => rule.error !== undefined)
    for (const rule of broken) { say($, r, 'rules: ' + baseName(rule.path) + ' load: unusable (' + rule.error + '), kept as always', loop) }
    if (broken.length > 0) {
        $.ui.status('rules: load: unusable in ' + broken.map((rule) => baseName(rule.path)).join(', ') + ', kept as always')
    }
    say($, r, 'rules: index of ' + built.rules.length + ' files, routed '
        + built.rules.filter((rule) => rule.triggers !== undefined).map((rule) => baseName(rule.path)).join(' '), loop)
    return { index: built, bodies }
}

function logDecisions($: EngineInterface, r: Router, decisions: readonly FileDecision[], loop: string): void {
    for (const d of decisions) {
        const verb = d.verdict === 'keep' ? 'keep' : 'drop'
        const reason = d.verdict === 'keep' ? 'bulk' : d.verdict
        say($, r, 'rules: ' + verb + ' ' + baseName(d.path) + ' (' + reason + ') ' + d.real, loop)
    }
}

/**
 * What to answer for one bulk-load attachment: `pass` to hand it on
 * unchanged, `{ text: null }` to leave it out, or the rewritten text.
 */
async function routeAttachment(
    $: EngineInterface, r: Router, type: string, text: string, agentId: string | undefined,
): Promise<'pass' | { text: string | null }> {
    const loop = loopOf(agentId)
    const { index } = await ruleIndex($, r, loop)
    const owner = fingerprint(type, text)
    if (type === 'nested_memory') {
        const path = nestedPath(text)
        if (path === undefined) { throw new Error('nested_memory: no `Contents of <path>:` header') }
        const decisions = decideFiles(index, r.ledger, loop, [{ path, real: await realPathOf($, r, path) }], owner)
        await persist($, r)
        logDecisions($, r, decisions, loop)
        return decisions[0]?.verdict === 'keep' ? 'pass' : { text: null }
    }
    const parts = splitInstructions(text)
    const files: { part: InstructionPart; path: string; real: string }[] = []
    for (const part of parts) {
        if (part.path !== undefined) { files.push({ part, path: part.path, real: await realPathOf($, r, part.path) }) }
    }
    const decisions = decideFiles(index, r.ledger, loop, files, owner)
    await persist($, r)
    logDecisions($, r, decisions, loop)
    const dropped = new Set(files.filter((_, i) => decisions[i]?.verdict !== 'keep').map((f) => f.part))
    return dropped.size === 0 ? 'pass' : { text: rejoin(text, parts, dropped) }
}

/** Rules owed to the model, as real paths and their framed text. */
type Owed = { paths: string[]; texts: string[] }

/** The framed rules a prompt triggers, marked delivered for the main loop. */
async function promptRules($: EngineInterface, r: Router, text: string): Promise<Owed> {
    const { index, bodies } = await ruleIndex($, r, MAIN_LOOP)
    const paths = claimDelivered(r.ledger, MAIN_LOOP, matchPrompt(index, text))
    if (paths.length > 0) { await persist($, r) }
    for (const p of paths) { say($, r, 'rules: inject ' + baseName(p) + ' (prompt) ' + p) }
    return { paths, texts: paths.map((p) => framed(p, bodies[p] ?? '')) }
}

/** What one tool call owes: a deny carrying its gate rules, or rules to append to its result. */
async function toolRules(
    $: EngineInterface, r: Router, tool: string, input: unknown, agentId: string | undefined,
): Promise<Owed & { deny?: string }> {
    const loop = loopOf(agentId)
    const { index, bodies } = await ruleIndex($, r, loop)
    const m = matchTool(index, tool, input, statements)
    if (m.gate.length === 0 && m.after.length === 0) { return { paths: [], texts: [] } }
    const { fresh, waiting } = claimGate(r.ledger, loop, m.gate)
    if (fresh.length > 0 || waiting.length > 0) {
        await persist($, r)
        for (const p of fresh) { say($, r, 'rules: gate ' + baseName(p) + ' (deny ' + tool + ') ' + p, loop) }
        for (const p of waiting) { say($, r, 'rules: gate ' + baseName(p) + ' (pending, deny ' + tool + ') ' + p, loop) }
        return { deny: gateDeny(fresh.map((p) => ({ path: p, body: bodies[p] ?? '' })), waiting), paths: [], texts: [] }
    }
    const paths = claimPending(r.ledger, loop, m.after)
    if (paths.length > 0) { await persist($, r) }
    for (const p of paths) { say($, r, 'rules: inject ' + baseName(p) + ' (' + tool + ') ' + p, loop) }
    return { paths, texts: paths.map((p) => framed(p, bodies[p] ?? '')) }
}

/** The call or prompt that carried these rules was refused: they never reached the model. */
async function releaseRules(
    $: EngineInterface, r: Router, agentId: string | undefined, paths: readonly string[], state: 'delivered' | 'pending',
): Promise<void> {
    const loop = loopOf(agentId)
    releaseClaimed(r.ledger, loop, paths, state)
    for (const p of paths) { say($, r, 'rules: release ' + baseName(p) + ' (carrier refused) ' + p, loop) }
    await persist($, r)
}

/** A model request of this loop is starting: its pending denies are delivered now. */
async function promoteRules($: EngineInterface, r: Router, agentId: string | undefined): Promise<void> {
    const loop = loopOf(agentId)
    const promoted = promotePending(r.ledger, loop)
    if (promoted.length === 0) { return }
    for (const p of promoted) { say($, r, 'rules: delivered ' + baseName(p) + ' (turn.step) ' + p, loop) }
    await persist($, r)
}

/** This loop's compaction installed: what it kept and was given is gone from context. */
async function clearLoop($: EngineInterface, r: Router, agentId: string | undefined): Promise<void> {
    const loop = loopOf(agentId)
    if (r.ledger[loop] === undefined) { return }
    delete r.ledger[loop]
    say($, r, 'rules: ledger cleared for ' + loop + ' (compacted)', loop)
    await persist($, r)
}

export const register: Register = (on, options) => {
    const persona = options['gh_persona'] !== false
    const rkvr = options['rm_rkvr'] !== false
    const compound = options['excluded_compound'] !== false
    const pkill = options['pkill_bracket'] !== false
    const verbose = options['debug'] === true
    let excluded: Promise<string[]> | null = null

    // Rule routing. Registered first, so it judges the call the model wrote
    // and its context lands outermost. With the toggle off the hooks still
    // run: the first one latches routing off and re-asks every attachment.
    const rr = newRouter(options['rule_routing'] !== false, verbose)

    on('prompt.attachment', async ($, e, next) => {
        if (!ROUTED_TYPES.has(e.type)) { return next(e) }
        const answer = await guarded($, rr, 'prompt.attachment', e.agentId, () => routeAttachment($, rr, e.type, e.text, e.agentId))
        if (answer === null || answer === 'pass') { return next(e) }
        if (answer.text === null) { return { text: null } }
        return next({ ...e, text: answer.text })
    }).catch(async ($, e, next) => {
        await caught($, rr, 'prompt.attachment', e.agentId, next.error.kind, next.error.message).catch(() => undefined)
        return next(e)
    })

    on('prompt.submit', async ($, e, next) => {
        const add = await guarded($, rr, 'prompt.submit', undefined, () => promptRules($, rr, e.text))
        if (add === null || add.texts.length === 0) { return next(e) }
        const r = await next({ ...e, context: [...(e.context ?? []), ...add.texts] })
        if (r.drop !== undefined) { await guarded($, rr, 'prompt.submit', undefined, () => releaseRules($, rr, undefined, add.paths, 'delivered')) }
        return r
    }).catch(async ($, e, next) => {
        await caught($, rr, 'prompt.submit', undefined, next.error.kind, next.error.message).catch(() => undefined)
        return next(e)
    })

    on('tool.call', async ($, e, next) => {
        const owed = await guarded($, rr, 'tool.call', e.agentId, () => toolRules($, rr, String(e.tool), e, e.agentId))
        if (owed === null) { return next(e) }
        if (owed.deny !== undefined) { return { deny: owed.deny } }
        if (owed.texts.length === 0) { return next(e) }
        const r = await next(e)
        if (r.deny !== undefined) {
            await guarded($, rr, 'tool.call', e.agentId, () => releaseRules($, rr, e.agentId, owed.paths, 'pending'))
            return r
        }
        return { ...r, context: [...(r.context ?? []), ...owed.texts] }
    }).catch(async ($, e, next) => {
        await caught($, rr, 'tool.call', e.agentId, next.error.kind, next.error.message).catch(() => undefined)
        return next(e)
    })

    on('turn.step', async function* ($, e, next) {
        await guarded($, rr, 'turn.step', e.agentId, () => promoteRules($, rr, e.agentId))
        return yield* next(e)
    }).catch(async function* ($, e, next) {
        await caught($, rr, 'turn.step', e.agentId, next.error.kind, next.error.message).catch(() => undefined)
        if (next.called) { return undefined }
        return yield* next(e)
    })

    on('session.compact', async ($, e, next) => {
        const r = await next(e)
        if (e.trigger !== 'precompute' && r.messages !== undefined) {
            await guarded($, rr, 'session.compact', e.agentId, () => clearLoop($, rr, e.agentId))
        }
        return r
    }).catch(async ($, e, next) => {
        await caught($, rr, 'session.compact', e.agentId, next.error.kind, next.error.message).catch(() => undefined)
        return next(e)
    })

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
        if (!pkill || typeof command !== 'string') { return next(e) }
        if (!PKILL_INTEREST.test(command)) { return next(e) }

        const r = pkillRewrite(command)
        if ('deny' in r) {
            debug($, verbose, 'pkill-bracket', 'deny: ' + command)
            return { deny: r.deny }
        }
        if (r.note === '') { return next(e) }
        debug($, verbose, 'pkill-bracket', r.note + ' | ' + r.command)
        if (r.command === command) { return withContext(await next(e), r.note) }
        return withContext(await next({ ...e, command: r.command }), r.note)
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
    pkillRewrite,
    pkillArgs,
    ruleBody,
    framed,
    fingerprint,
    decideFiles,
    rejoin,
    claimDelivered,
    claimPending,
    releaseClaimed,
    claimGate,
    promotePending,
    gateDeny,
    statements,
    newRouterLog,
    appendLine,
    seedLog,
    logContent,
    pumpLog,
    logIdle,
    staleLogs,
    failedStatus,
    utf8Length,
    LOG_CAP,
}
