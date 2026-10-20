import { describe, expect, test } from 'bun:test'
import { readdirSync, readFileSync } from 'node:fs'
import { basename, join, resolve } from 'node:path'
import { internals } from './index.ts'
import {
    buildIndex, frontmatter, matchPrompt, matchTool, misplaced, normalizeStatement, parseLoad, ruleAt,
} from './rules.ts'
import type { RuleIndex } from './rules.ts'

const HOME_DIR = resolve(import.meta.dir, '../../../..')
const RULES_DIR = join(HOME_DIR, 'repos/.claude/rules')
const ROUTED_DIR = join(HOME_DIR, 'repos/.claude/routed')
const SETTINGS = join(HOME_DIR, '.claude/settings.json')

/** rails' own statement split, the one the Bash hooks already use. */
const split = (command: string): string[] => internals.heads(command).map((h) => internals.segment(command, h.at))

const mdFiles = (dir: string): string[] => readdirSync(dir).filter((f) => f.endsWith('.md')).sort()
const ruleFiles = mdFiles(RULES_DIR)
const routedFiles = mdFiles(ROUTED_DIR)

/** One directory's rule files, read from this checkout and keyed under `keyDir`. */
function liveIndex(dir: string, keyDir: string = dir): RuleIndex {
    return buildIndex(mdFiles(dir).map((f) => ({ path: join(keyDir, f), text: readFileSync(join(dir, f), 'utf8') })))
}

/*
 * Trigger tests key the index under the dir the live router reads, so a
 * failure names a path that exists on this machine; any clone reads its own
 * rule text. Both directories go in, so "never an always or native rule" is
 * tested against the rules that sit beside the routed ones.
 */
const KEY_ROUTED_DIR = '/home/saidler/repos/scottidler/claude/HOME/repos/.claude/routed'
const KEY_RULES_DIR = '/home/saidler/repos/scottidler/claude/HOME/repos/.claude/rules'
const index: RuleIndex = { rules: [...liveIndex(ROUTED_DIR, KEY_ROUTED_DIR).rules, ...liveIndex(RULES_DIR, KEY_RULES_DIR).rules] }
const rule = (name: string): string => join(KEY_ROUTED_DIR, name + '.md')

const ROUTED = ['git', 'marquee', 'otto', 'voice']
const ALWAYS = ['general', 'interaction', 'pr', 'recall', 'search', 'secrets', 'taste']
const NATIVE = ['comments', 'fleet-plugins', 'js-ts', 'python', 'rust', 'safety', 'terraform', 'yaml']

function expectLoad(dir: string, f: string): void {
    const fm = frontmatter(readFileSync(join(dir, f), 'utf8'))
    expect(fm).toBeDefined()
    const load = parseLoad(fm as string)
    if (load instanceof Error) { throw new Error(f + ': ' + load.message) }
    const name = basename(f, '.md')
    if (ALWAYS.includes(name)) { expect(load).toBe('always') }
    if (NATIVE.includes(name)) { expect(load).toBe('native') }
    if (ROUTED.includes(name)) { expect(typeof load).toBe('object') }
}

describe('the live rules dir (bulk-loaded)', () => {
    test('holds the 15 always and native rules the design classifies', () => {
        expect(ruleFiles.map((f) => basename(f, '.md'))).toEqual([...ALWAYS, ...NATIVE].sort())
    })
    for (const f of ruleFiles) {
        test(f + ': load: parses and every regex compiles', () => { expectLoad(RULES_DIR, f) })
    }
    test('no rule here carries a trigger map', () => {
        const live = liveIndex(RULES_DIR)
        expect(live.rules.filter((r) => r.error !== undefined)).toEqual([])
        expect(misplaced(live, 'rules')).toEqual([])
    })
})

describe('the live routed dir (injected on trigger)', () => {
    test('holds exactly git, marquee, otto, voice', () => {
        expect(routedFiles.map((f) => basename(f, '.md'))).toEqual(ROUTED)
    })
    for (const f of routedFiles) {
        test(f + ': load: parses and every regex compiles', () => { expectLoad(ROUTED_DIR, f) })
    }
    test('every rule here carries a trigger map', () => {
        const live = liveIndex(ROUTED_DIR)
        expect(live.rules.filter((r) => r.error !== undefined)).toEqual([])
        expect(misplaced(live, 'routed')).toEqual([])
    })
})

describe('placement', () => {
    const fixture = buildIndex([
        { path: '/r/trig.md', text: "---\nload: { bash: ['^otto'] }\n---\nbody\n" },
        { path: '/r/always.md', text: '---\nload: always\n---\nbody\n' },
        { path: '/r/native.md', text: '---\nload: native\n---\nbody\n' },
        { path: '/r/empty.md', text: '---\nload: {}\n---\nbody\n' },
        { path: '/r/none.md', text: '# no frontmatter\n' },
    ])
    test('a trigger map in rules/ is misplaced', () => {
        expect(misplaced(fixture, 'rules').map((r) => r.path)).toEqual(['/r/trig.md'])
    })
    test('always, native, an empty map or no frontmatter in routed/ is misplaced', () => {
        expect(misplaced(fixture, 'routed').map((r) => r.path)).toEqual(['/r/always.md', '/r/native.md', '/r/empty.md', '/r/none.md'])
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
    const routedTools = liveIndex(ROUTED_DIR).rules.flatMap((r) => typeof r.load === 'object'
        ? (r.load.tools ?? []).map((t) => ({ r, t })) : [])
    test('the routed rules name tools to check at all', () => {
        expect(routedTools.length).toBeGreaterThan(0)
    })
    for (const { r, t } of routedTools) {
        test(basename(r.path) + ' ' + t.match + ' names a registered tool', () => {
            const re = new RegExp(t.match, 'i')
            expect(names.filter((n) => re.test(n)).length).toBeGreaterThan(0)
        })
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
        expect(ruleAt(idx, '/r/bad.md')?.triggers).toBeUndefined()
        expect(ruleAt(idx, '/r/ok.md')?.triggers).toBeDefined()
        expect(ruleAt(idx, '/r/missing.md')).toBeUndefined()
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

describe('normalizeStatement: wrappers and path-qualified heads (audit round 1, X6CMQgQe)', () => {
    test('sudo and its value options are stripped', () => {
        expect(normalizeStatement('sudo git push')).toBe('git push')
        expect(normalizeStatement('sudo -u scott -E git push origin')).toBe('git push origin')
        expect(normalizeStatement('sudo -Eu scott git push')).toBe('git push')
        expect(normalizeStatement('sudo --user=scott -- git push')).toBe('git push')
        expect(normalizeStatement('sudo X=1 git push')).toBe('git push')
    })
    test('sudo -u x echo git push still names echo', () => {
        expect(normalizeStatement('sudo -u x echo git push')).toBe('echo git push')
    })
    test('command and command -p are stripped; command -v and -V only look up', () => {
        expect(normalizeStatement('command git push')).toBe('git push')
        expect(normalizeStatement('command -p git push')).toBe('git push')
        expect(normalizeStatement('command -v git push')).toBe('command -v git push')
        expect(normalizeStatement('command -V git')).toBe('command -V git')
    })
    test('exec and exec -a NAME are stripped', () => {
        expect(normalizeStatement('exec git push')).toBe('git push')
        expect(normalizeStatement('exec -c -a mygit git push')).toBe('git push')
    })
    test('an absolute command path reads as its basename', () => {
        expect(normalizeStatement('/usr/bin/git push')).toBe('git push')
        expect(normalizeStatement('/usr/bin/sudo /usr/bin/env X=1 /usr/bin/git -C r push')).toBe('git push')
        expect(normalizeStatement('cat /usr/bin/git')).toBe('cat /usr/bin/git')
    })
    test('wrappers nest', () => {
        expect(normalizeStatement('sudo env X=1 command git push')).toBe('git push')
    })
    test('env -S re-splits its string as the command', () => {
        expect(normalizeStatement("env -S 'git push'")).toBe('git push')
        expect(normalizeStatement('env -S "X=1 git -C r push" origin')).toBe('git push origin')
        expect(normalizeStatement("env --split-string='git push'")).toBe('git push')
        expect(normalizeStatement("env -S'git push'")).toBe('git push')
        expect(normalizeStatement("env -S 'echo git push'")).toBe('echo git push')
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
    test('a push after a heredoc terminator still gates (audit round 1)', () => {
        expect(bash("git add -A && git commit -F - <<'EOF'\nmsg\nEOF\ngit push origin main").gate).toContain(git)
    })
    for (const command of ['sudo git push', 'command git push', 'exec git push', '/usr/bin/git push', "env -S 'git push'"]) {
        test(command + ' reaches the git gate (audit round 1)', () => {
            expect(bash(command).gate).toEqual([git])
        })
    }
    test('sudo -u x echo git push does not gate', () => {
        expect(bash('sudo -u x echo git push')).toEqual({ gate: [], after: [] })
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
