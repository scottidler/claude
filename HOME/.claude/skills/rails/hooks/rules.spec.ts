import { describe, expect, test } from 'bun:test'
import { readdirSync, readFileSync } from 'node:fs'
import { basename, join, resolve } from 'node:path'
import { internals } from './index.ts'
import {
    buildIndex, frontmatter, isRouted, joinInstructions, matchPrompt, matchTool,
    nestedPath, normalizeStatement, parseLoad, ruleAt, splitInstructions,
} from './rules.ts'
import type { RuleIndex } from './rules.ts'

const HOME_DIR = resolve(import.meta.dir, '../../../..')
const RULES_DIR = join(HOME_DIR, 'repos/.claude/rules')
const SETTINGS = join(HOME_DIR, '.claude/settings.json')

/** rails' own statement split, the one the Bash hooks already use. */
const split = (command: string): string[] => internals.heads(command).map((h) => internals.segment(command, h.at))

type InstructionsFixture = { files: { path: string; type: string }[]; text: string }
type NestedFixture = { rows: { line: number; path: string; text: string }[] }

const instructions = JSON.parse(
    readFileSync(join(import.meta.dir, 'fixtures/instructions-2b8aebe2.json'), 'utf8'),
) as InstructionsFixture
const nested = JSON.parse(
    readFileSync(join(import.meta.dir, 'fixtures/nested-e9ef7f18.json'), 'utf8'),
) as NestedFixture

const ruleFiles = readdirSync(RULES_DIR).filter((f) => f.endsWith('.md')).sort()

/** The live rule files, keyed under `dir` (the transcripts' real rules dir, or this checkout's). */
function liveIndex(dir: string): RuleIndex {
    return buildIndex(ruleFiles.map((f) => ({ path: join(dir, f), text: readFileSync(join(RULES_DIR, f), 'utf8') })))
}

/*
 * The fixtures were recorded with the repo at /home/saidler/repos/scottidler/claude,
 * so their real paths name that rules dir. The index is built from this
 * checkout's rule text but keyed under the recorded dir, so the fixture tests
 * hold wherever the repo is cloned.
 */
const RECORDED_RULES_DIR = '/home/saidler/repos/scottidler/claude/HOME/repos/.claude/rules'
const index = liveIndex(RECORDED_RULES_DIR)
const rule = (name: string): string => join(RECORDED_RULES_DIR, name + '.md')

const ROUTED = ['git', 'marquee', 'otto', 'voice']
const ALWAYS = ['general', 'interaction', 'pr', 'recall', 'search', 'secrets', 'taste']
const NATIVE = ['comments', 'fleet-plugins', 'js-ts', 'python', 'rust', 'safety', 'terraform', 'yaml']

describe('frontmatter', () => {
    test('the block between the --- lines', () => {
        expect(frontmatter('---\na: 1\nload: always\n---\n# Body\n')).toBe('a: 1\nload: always\n')
    })
    test('no frontmatter', () => {
        expect(frontmatter('# Body\n')).toBeUndefined()
    })
    test('an unclosed block is not frontmatter', () => {
        expect(frontmatter('---\nload: always\n# Body\n')).toBeUndefined()
    })
    test('a --- that is not a whole line does not close it', () => {
        expect(frontmatter('---\nload: always\n----x\n')).toBeUndefined()
    })
})

describe('parseLoad', () => {
    test('always and native', () => {
        expect(parseLoad('alwaysApply: true\nload: always\n')).toBe('always')
        expect(parseLoad('paths:\n  - "**/*"\nload: native\n')).toBe('native')
    })
    test('a block trigger map with flow items and comments', () => {
        const fm = [
            'load:',
            "  prompt: ['\\bslack\\b', 'it''s']",
            '  tools:',
            "    - { match: '^(Write|Edit)$', path: '\\.md$', gate: true }",
            "    - { match: '^ToolSearch$', query: 'slack' }",
            '  bash:',
            "    - '^git\\b'                       # after",
            "    - { match: '^git push\\b', gate: true } # before",
            'other: x',
        ].join('\n')
        expect(parseLoad(fm)).toEqual({
            prompt: ['\\bslack\\b', "it's"],
            tools: [
                { match: '^(Write|Edit)$', path: '\\.md$', gate: true },
                { match: '^ToolSearch$', query: 'slack' },
            ],
            bash: ['^git\\b', { match: '^git push\\b', gate: true }],
        })
    })
    test('an inline flow map', () => {
        expect(parseLoad('load: { bash: ["^otto"] }')).toEqual({ bash: ['^otto'] })
    })
    test('a missing load: is an error', () => {
        const r = parseLoad('alwaysApply: true\n')
        expect(r).toBeInstanceOf(Error)
        expect((r as Error).message).toBe('no load: key')
    })
    test('an unknown scalar is an error', () => {
        expect(parseLoad('load: sometimes')).toBeInstanceOf(Error)
    })
    test('an unknown trigger key is an error', () => {
        expect((parseLoad("load:\n  files: ['x']") as Error).message).toContain('unknown key files')
    })
    test('an unknown tools key is an error', () => {
        expect((parseLoad("load:\n  tools:\n    - { match: 'x', gates: true }") as Error).message)
            .toContain('unknown key gates')
    })
    test('a regex that does not compile is an error naming it', () => {
        const r = parseLoad("load:\n  bash:\n    - '^git ('")
        expect(r).toBeInstanceOf(Error)
        expect((r as Error).message).toContain('load.bash[0]: regex does not compile')
    })
    test('a trigger map with no triggers is an error', () => {
        expect(parseLoad('load: {}')).toBeInstanceOf(Error)
    })
    test('a non-boolean gate is an error', () => {
        expect((parseLoad("load: { bash: [{ match: 'x', gate: yes }] }") as Error).message)
            .toContain('gate must be true or false')
    })
    test('load: twice is an error', () => {
        expect(parseLoad('load: always\nload: native')).toBeInstanceOf(Error)
    })
    test('a block map item spread over lines is refused, not misread', () => {
        expect(parseLoad("load:\n  tools:\n    - match: 'x'\n      gate: true")).toBeInstanceOf(Error)
    })
    test('an unterminated flow sequence is an error', () => {
        expect(parseLoad("load:\n  prompt: ['x'")).toBeInstanceOf(Error)
    })
})

describe('the live rules dir', () => {
    test('holds the 19 rules the design classifies', () => {
        expect(ruleFiles.map((f) => basename(f, '.md'))).toEqual([...ALWAYS, ...NATIVE, ...ROUTED].sort())
    })
    for (const f of ruleFiles) {
        test(f + ': load: parses and every regex compiles', () => {
            const fm = frontmatter(readFileSync(join(RULES_DIR, f), 'utf8'))
            expect(fm).toBeDefined()
            const load = parseLoad(fm as string)
            if (load instanceof Error) { throw new Error(f + ': ' + load.message) }
            const name = basename(f, '.md')
            if (ALWAYS.includes(name)) { expect(load).toBe('always') }
            if (NATIVE.includes(name)) { expect(load).toBe('native') }
            if (ROUTED.includes(name)) { expect(typeof load).toBe('object') }
        })
    }
    test('the index carries no load: errors and routes exactly git, marquee, otto, voice', () => {
        const live = liveIndex(RULES_DIR)
        expect(live.rules.filter((r) => r.error !== undefined)).toEqual([])
        expect(live.rules.filter((r) => r.triggers !== undefined).map((r) => basename(r.path, '.md'))).toEqual(ROUTED)
    })
})

/** `prefix(a|b)suffix` -> prefixa suffix, prefixbsuffix, one group at a time. */
function expand(pattern: string): string[] {
    const parts: string[] = []
    let depth = 0
    let from = 0
    for (let i = 0; i < pattern.length; i += 1) {
        const c = pattern.charAt(i)
        if (c === '(') { depth += 1 }
        if (c === ')') { depth -= 1 }
        if (c === '|' && depth === 0) { parts.push(pattern.slice(from, i)); from = i + 1 }
    }
    parts.push(pattern.slice(from))
    if (parts.length > 1) { return parts.flatMap(expand) }
    const open = pattern.indexOf('(')
    if (open < 0) { return [pattern] }
    let close = open
    for (let d = 0; close < pattern.length; close += 1) {
        if (pattern.charAt(close) === '(') { d += 1 }
        if (pattern.charAt(close) === ')') { d -= 1; if (d === 0) { break } }
    }
    const head = pattern.slice(0, open)
    const tail = pattern.slice(close + 1)
    return expand(pattern.slice(open + 1, close)).flatMap((alt) => expand(head + alt + tail))
}

/** Every tool name settings.json registers: permission entries and PreToolUse/PostToolUse matchers. */
function settingsToolNames(): Set<string> {
    const s = JSON.parse(readFileSync(SETTINGS, 'utf8')) as {
        permissions: Record<string, unknown>
        hooks: Record<string, { matcher?: string }[]>
    }
    const names = new Set<string>()
    for (const key of ['allow', 'deny', 'ask']) {
        for (const entry of (s.permissions[key] as string[] | undefined) ?? []) {
            names.add(entry.split('(')[0] as string)
        }
    }
    for (const event of ['PreToolUse', 'PostToolUse']) {
        for (const h of s.hooks[event] ?? []) {
            if (h.matcher !== undefined && h.matcher !== '' && h.matcher !== '*') {
                for (const n of expand(h.matcher)) { names.add(n) }
            }
        }
    }
    return names
}

/*
 * ToolSearch is the engine's own deferred-tool loader. Nothing in
 * settings.json permits or hooks it, so it is the one name taken on faith.
 */
const BUILTIN_TOOLS = ['ToolSearch']

describe('tools[].match against settings.json', () => {
    const names = [...settingsToolNames(), ...BUILTIN_TOOLS]
    test('the settings.json name list is not empty', () => {
        expect(names).toContain('mcp__multi-account-github__create_pr')
        expect(names).toContain('mcp__marquee__marquee_publish')
        expect(names).toContain('Write')
    })
    for (const r of liveIndex(RULES_DIR).rules) {
        const load = r.load
        if (typeof load !== 'object') { continue }
        for (const t of load.tools ?? []) {
            test(basename(r.path) + ' ' + t.match + ' names a registered tool', () => {
                const re = new RegExp(t.match, 'i')
                expect(names.filter((n) => re.test(n)).length).toBeGreaterThan(0)
            })
        }
    }
    test('a wrong server name would fail: mcp__github__ matches nothing', () => {
        expect(names.filter((n) => /^mcp__github__/i.test(n))).toEqual([])
    })
})

describe('buildIndex', () => {
    test('a broken load: is indexed as always with the reason', () => {
        const idx = buildIndex([
            { path: '/r/bad.md', text: "---\nload:\n  bash: ['^(']\n---\nbody\n" },
            { path: '/r/none.md', text: '# no frontmatter\n' },
            { path: '/r/ok.md', text: "---\nload: { bash: ['^otto'] }\n---\nbody\n" },
        ])
        expect(ruleAt(idx, '/r/bad.md')).toMatchObject({ load: 'always' })
        expect(ruleAt(idx, '/r/bad.md')?.error).toContain('regex does not compile')
        expect(ruleAt(idx, '/r/none.md')?.error).toBe('no frontmatter')
        expect(isRouted(idx, '/r/bad.md')).toBe(false)
        expect(isRouted(idx, '/r/ok.md')).toBe(true)
        expect(isRouted(idx, '/r/missing.md')).toBe(false)
    })
})

describe('normalizeStatement', () => {
    test('env, an assignment and git -C are stripped', () => {
        expect(normalizeStatement('env X=1 git -C repo push')).toBe('git push')
    })
    test('git -c k=v is stripped', () => {
        expect(normalizeStatement('git -c k=v tag -d v1')).toBe('git tag -d v1')
    })
    test('a leading assignment is stripped', () => {
        expect(normalizeStatement('GIT_DIR=x git branch -D b')).toBe('git branch -D b')
    })
    test('--git-dir=, --no-pager and a quoted -C value are stripped', () => {
        expect(normalizeStatement('git --no-pager --git-dir=/x/.git -C "a b" push  origin')).toBe('git push origin')
    })
    test('env options and a quoted assignment', () => {
        expect(normalizeStatement('env -i -u HOME A="x y" git push')).toBe('git push')
    })
    test('a non-git command is only re-spaced', () => {
        expect(normalizeStatement('echo   git push')).toBe('echo git push')
        expect(normalizeStatement('gitk --all')).toBe('gitk --all')
    })
    test('an empty statement', () => {
        expect(normalizeStatement('')).toBe('')
    })
})

describe('matchTool, Bash', () => {
    const git = rule('git')
    const voice = rule('voice')
    const bash = (command: string) => matchTool(index, 'Bash', { command }, split)

    for (const command of ['env X=1 git -C repo push', 'git -c k=v tag -d v1', 'GIT_DIR=x git branch -D b']) {
        test(command + ' reaches the git gate', () => {
            expect(bash(command).gate).toEqual([git])
        })
    }
    test('git log is after, not gate', () => {
        expect(bash('git log --oneline -3')).toEqual({ gate: [], after: [git] })
    })
    test('gitk and echo git push match nothing', () => {
        expect(bash('gitk --all')).toEqual({ gate: [], after: [] })
        expect(bash('echo git push')).toEqual({ gate: [], after: [] })
    })
    test('a gated statement later in a compound command still gates', () => {
        expect(bash('cd repo && git status; git push origin main').gate).toEqual([git])
    })
    test('git commit gates voice and rides git', () => {
        expect(bash('git commit -m "x"')).toEqual({ gate: [voice], after: [git] })
    })
    test('otto and marquee ride after', () => {
        expect(bash('otto ci').after).toEqual([rule('otto')])
        expect(bash('marquee list').after).toEqual([rule('marquee')])
    })
    test('marquee publish gates voice', () => {
        expect(bash('marquee publish x.md').gate).toEqual([voice])
    })
    test('a heredoc body is data, not a statement', () => {
        expect(bash('cat <<EOF\ngit push\nEOF')).toEqual({ gate: [], after: [] })
    })
    test('bash triggers ignore a non-Bash tool with a command field', () => {
        expect(matchTool(index, 'Task', { command: 'git push' }, split)).toEqual({ gate: [], after: [] })
    })
})

describe('matchTool, named tools', () => {
    const tool = (name: string, input: unknown = {}) => matchTool(index, name, input, split)
    test('a Slack post gates voice', () => {
        expect(tool('mcp__slack__chat_schedule_message')).toEqual({ gate: [rule('voice')], after: [] })
    })
    test('a Slack read matches nothing', () => {
        expect(tool('mcp__slack__conversations_history')).toEqual({ gate: [], after: [] })
    })
    test('create_pr gates git and voice', () => {
        expect(tool('mcp__multi-account-github__create_pr').gate.sort()).toEqual([rule('git'), rule('voice')])
    })
    test('a GitHub read rides git', () => {
        expect(tool('mcp__multi-account-github__get_pr')).toEqual({ gate: [], after: [rule('git')] })
    })
    test('marquee publish gates voice and rides marquee', () => {
        expect(tool('mcp__marquee__marquee_publish')).toEqual({ gate: [rule('voice')], after: [rule('marquee')] })
    })
    test('Write of a .md gates voice; of a .rs or with no path, nothing', () => {
        expect(tool('Write', { file_path: '/x/README.md' }).gate).toEqual([rule('voice')])
        expect(tool('Write', { file_path: '/x/main.rs' })).toEqual({ gate: [], after: [] })
        expect(tool('Edit', {})).toEqual({ gate: [], after: [] })
    })
    test('ToolSearch rides voice only when the query names a surface', () => {
        expect(tool('ToolSearch', { query: 'select:mcp__slack__chat_post_message' }).after).toEqual([rule('voice')])
        expect(tool('ToolSearch', { query: 'notebook' })).toEqual({ gate: [], after: [] })
    })
    test('a non-object input matches name-only triggers', () => {
        expect(tool('mcp__marquee__marquee_list', 'x')).toEqual({ gate: [], after: [rule('marquee')] })
    })
})

describe('matchPrompt', () => {
    test('a Slack ask routes voice', () => {
        expect(matchPrompt(index, 'schedule a Slack message to the team')).toEqual([rule('voice')])
    })
    test('otto and git words', () => {
        expect(matchPrompt(index, 'run otto ci then push the tag').sort()).toEqual([rule('git'), rule('otto')])
    })
    test('nothing routed for an unrelated ask', () => {
        expect(matchPrompt(index, 'what time is it in Denver')).toEqual([])
    })
    test('never returns an always or native rule', () => {
        expect(matchPrompt(index, 'search secrets taste safety rust python')).toEqual([])
    })
})

describe('splitInstructions, the 2b8aebe2 instructions blob', () => {
    const parts = splitInstructions(instructions.text)
    const sections = parts.filter((p) => p.header !== '')
    test('one path-less preamble, then 18 file sections (files[] count)', () => {
        expect(parts.length).toBe(19)
        expect(parts[0]?.header).toBe('')
        expect(parts[0]?.path).toBeUndefined()
        expect(parts[0]?.body.startsWith('Codebase and user instructions are shown below.')).toBe(true)
        expect(sections.length).toBe(instructions.files.length)
        expect(sections.length).toBe(18)
    })
    test('the section paths are files[] in order; the managed tier has none', () => {
        expect(sections.map((p) => p.path ?? p.header)).toEqual(instructions.files.map((f) =>
            f.path === '<managed-settings>'
                ? 'Contents of <managed-settings> (organization-managed policy instructions):'
                : f.path))
        expect(sections.filter((p) => p.path !== undefined).length).toBe(17)
    })
    test('join of the split is the blob, byte for byte', () => {
        expect(joinInstructions(parts)).toBe(instructions.text)
    })
    test('dropping the routed sections leaves a blob that splits into the rest', () => {
        const kept = parts.filter((p) => p.path === undefined || !isRouted(index, p.path))
        expect(parts.length - kept.length).toBe(4)
        const again = splitInstructions(joinInstructions(kept))
        expect(again.map((p) => p.path)).toEqual(kept.map((p) => p.path))
        expect(joinInstructions(again)).toBe(joinInstructions(kept))
    })
    test('a blob with no section header throws', () => {
        expect(() => splitInstructions('Codebase and user instructions are shown below.')).toThrow('no `Contents of')
    })
    test('a Contents of line inside a body, not after a blank line, is body', () => {
        const blob = 'pre\n\nContents of /a.md (t):\n\nx\nContents of /b.md (t):\ny'
        expect(splitInstructions(blob).map((p) => p.path)).toEqual([undefined, '/a.md'])
    })
    test('a blob that opens on a header has no preamble part', () => {
        const blob = 'Contents of /a.md (t):\n\nx\n\nContents of /b.md (t):\n\ny'
        const p = splitInstructions(blob)
        expect(p.map((x) => x.path)).toEqual(['/a.md', '/b.md'])
        expect(joinInstructions(p)).toBe(blob)
    })
})

describe('nestedPath, the e9ef7f18 nested_memory burst', () => {
    const paths = nested.rows.map((r) => nestedPath(r.text))
    test('15 rows, each path read from its text equals the attachment path', () => {
        expect(nested.rows.length).toBe(15)
        expect(paths).toEqual(nested.rows.map((r) => r.path))
    })
    test('4 of the 15 are routed: git, marquee, otto, voice', () => {
        const routedHere = (paths as string[]).filter((p) => isRouted(index, p))
        expect(routedHere.map((p) => basename(p, '.md')).sort()).toEqual(ROUTED)
    })
    test('cli, logging and ~/repos/CLAUDE.md are outside the rule index, so kept', () => {
        const outside = (paths as string[]).filter((p) => ruleAt(index, p) === undefined)
        expect(outside.map((p) => basename(p))).toEqual(['CLAUDE.md', 'logging.md', 'cli.md'])
    })
    test('text that does not open on a header has no path', () => {
        expect(nestedPath('hello')).toBeUndefined()
        expect(nestedPath('Contents of relative.md:\n\nx')).toBeUndefined()
        expect(nestedPath('x\nContents of /a.md:\n')).toBeUndefined()
    })
    test('a tier suffix is not part of the path', () => {
        expect(nestedPath('Contents of /a b/c.md (project instructions):\n\nx')).toBe('/a b/c.md')
    })
})
