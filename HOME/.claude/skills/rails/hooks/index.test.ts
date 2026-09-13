import { describe, expect, test } from 'bun:test'
import { internals } from './index.ts'

const { ghSpots, headSpots, segment, personaFor, inject, inWorkTree } = internals
const { splitWords, stageComment, resolvePath, rmRewrite } = internals

const WORK_CWD = '/home/saidler/repos/tatari-tv/philo'
const HOME_CWD = '/home/saidler/repos/scottidler/claude'

/** What the hook does end to end, minus the engine. */
function rewrite(command: string, cwd: string): string {
    const picked = ghSpots(command)
        .map((at) => ({ at, verdict: personaFor(segment(command, at), cwd) }))
        .filter((s) => s.verdict.persona !== null)
        .map((s) => ({ at: s.at, persona: s.verdict.persona as 'work' | 'home' }))
    return inject(command, picked)
}

describe('ghSpots', () => {
    test('a bare gh command', () => {
        expect(ghSpots('gh api user')).toEqual([0])
    })
    test('after an env assignment', () => {
        expect(ghSpots('FOO=1 gh api user')).toEqual([6])
    })
    test('after every separator', () => {
        expect(ghSpots('cd /tmp && gh api user')).toEqual([11])
        expect(ghSpots('gh api user | jq .login')).toEqual([0])
        expect(ghSpots('echo $(gh api user)')).toEqual([7])
        expect(ghSpots('true; gh api user')).toEqual([6])
    })
    test('two invocations', () => {
        expect(ghSpots('gh api a && gh api b')).toEqual([0, 12])
    })
    test('not inside quotes', () => {
        expect(ghSpots('git commit -m "; gh api user"')).toEqual([])
        expect(ghSpots("git commit -m '; gh api user'")).toEqual([])
    })
    test('not a heredoc body', () => {
        expect(ghSpots("gh pr create --body-file - <<'EOF'\ngh api user\nEOF")).toEqual([0])
    })
    test('not a word that merely starts with gh', () => {
        expect(ghSpots('echo ghost')).toEqual([])
        expect(ghSpots('gh-work api user')).toEqual([])
        expect(ghSpots('echo went through')).toEqual([])
    })
    test('not an argument that happens to be gh', () => {
        expect(ghSpots('command -v gh')).toEqual([])
    })
})

describe('headSpots', () => {
    test('the scanner takes any head word, not just gh', () => {
        expect(headSpots('rm -rf x', 'rm')).toEqual([0])
        expect(headSpots('cd /tmp && rm -rf x', 'rm')).toEqual([11])
        expect(headSpots('sudo rm -rf x', 'rm')).toEqual([])
        expect(headSpots('sudo rm -rf x', 'sudo')).toEqual([0])
    })
})

describe('segment', () => {
    test('cut at the next separator', () => {
        expect(segment('gh api user | jq .login', 0)).toBe('gh api user ')
    })
    test('a quoted separator does not cut', () => {
        expect(segment('gh pr create -t "a | b"', 0)).toBe('gh pr create -t "a | b"')
    })
})

describe('personaFor', () => {
    test('cwd decides when the args name no org', () => {
        expect(personaFor('gh pr list', WORK_CWD).persona).toBe('work')
        expect(personaFor('gh pr list', HOME_CWD).persona).toBe('home')
    })
    test('the args beat the cwd both ways', () => {
        expect(personaFor('gh api repos/tatari-tv/philo', HOME_CWD).persona).toBe('work')
        expect(personaFor('gh pr create -R scottidler/claude', WORK_CWD).persona).toBe('home')
    })
    test('both orgs named is left alone', () => {
        const v = personaFor('gh api repos/tatari-tv/philo -q scottidler', HOME_CWD)
        expect(v.persona).toBeNull()
        expect(v.why).toContain('both orgs')
    })
    test('a destructive verb still gets a persona: deny rules survive the prefix', () => {
        expect(personaFor('gh cache delete x', WORK_CWD).persona).toBe('work')
        expect(personaFor('gh repo delete scottidler/x', HOME_CWD).persona).toBe('home')
    })
})

describe('inWorkTree', () => {
    test('positive and negative', () => {
        expect(inWorkTree('/home/saidler/repos/tatari-tv/philo')).toBe(true)
        expect(inWorkTree('/home/saidler/repos/tatari-tv')).toBe(true)
        expect(inWorkTree('/home/saidler/repos/scottidler/claude')).toBe(false)
        expect(inWorkTree('/tmp')).toBe(false)
    })
})

describe('rewrite', () => {
    test('home cwd', () => {
        expect(rewrite('gh api user --jq .login', HOME_CWD)).toBe('GH_PERSONA=home gh api user --jq .login')
    })
    test('work cwd', () => {
        expect(rewrite('gh pr list', WORK_CWD)).toBe('GH_PERSONA=work gh pr list')
    })
    test('the documented pwd miss: work repo from outside the work tree', () => {
        expect(rewrite('gh api repos/tatari-tv/philo', '/tmp')).toBe('GH_PERSONA=work gh api repos/tatari-tv/philo')
    })
    test('two invocations get their own persona', () => {
        expect(rewrite('gh api repos/tatari-tv/a && gh api repos/scottidler/b', '/tmp'))
            .toBe('GH_PERSONA=work gh api repos/tatari-tv/a && GH_PERSONA=home gh api repos/scottidler/b')
    })
    test('keeps the env assignment order valid', () => {
        expect(rewrite('FOO=1 gh api user', HOME_CWD)).toBe('FOO=1 GH_PERSONA=home gh api user')
    })
    test('leaves a command naming both orgs untouched', () => {
        const cmd = 'gh api repos/tatari-tv/a -q scottidler'
        expect(rewrite(cmd, HOME_CWD)).toBe(cmd)
    })
    test('leaves a non-gh command untouched', () => {
        expect(rewrite('git status', HOME_CWD)).toBe('git status')
    })
})

const REPO = '/home/saidler/repos/scottidler/rkvr'

/** A fake plugin filesystem: the files that exist, and a fixed session cwd. */
function env(files: readonly string[] = [], cwd: string = REPO) {
    const set = new Set(files)
    return {
        cwd: async () => cwd,
        exists: async (path: string) => set.has(path),
        list: async (dir: string) =>
            [...set]
                .filter((f) => f.startsWith(dir + '/') && !f.slice(dir.length + 1).includes('/'))
                .map((f) => f.slice(dir.length + 1)),
    }
}

const REWRITE_NOTE = 'rails: rm -> rkvr rmrf (rules/safety.md); archive at /var/tmp/rmrf; if this was regenerable build output, re-issue with a trailing `# regenerable`'
const SET_NOTE = 'rails: rm kept, regenerable build output (rules/safety.md)'
const MARKER_NOTE = 'rails: rm kept, model asserted regenerable'

describe('splitWords', () => {
    test('quotes are stripped from the value and kept in the raw text', () => {
        const words = splitWords('rm -rf "a b/c"')
        expect(words.map((w) => w.value)).toEqual(['rm', '-rf', 'a b/c'])
        expect(words[2]?.raw).toBe('"a b/c"')
        expect(words[2]?.quoted).toBe(true)
    })
    test('a backslash escape keeps the next character', () => {
        expect(splitWords('rm -rf a\\ b').map((w) => w.value)).toEqual(['rm', '-rf', 'a b'])
    })
})

describe('stageComment', () => {
    test('an unquoted hash starting a word opens a comment', () => {
        expect(stageComment('rm -rf x # regenerable')?.text).toBe('# regenerable')
    })
    test('a hash mid-word opens nothing, same as bash', () => {
        expect(stageComment('rm -rf precious a# regenerable')).toBeNull()
    })
    test('a quoted hash is data', () => {
        expect(stageComment('rm -rf "x # regenerable"')).toBeNull()
        expect(stageComment("rm -rf 'x # regenerable'")).toBeNull()
    })
    test('no comment at all', () => {
        expect(stageComment('rm -rf x')).toBeNull()
    })
})

describe('resolvePath', () => {
    test('relative resolves against the cwd and normalizes', () => {
        expect(resolvePath(REPO, './target/')).toBe(REPO + '/target')
        expect(resolvePath(REPO, 'a/../b')).toBe(REPO + '/b')
    })
    test('absolute is kept', () => {
        expect(resolvePath(REPO, '/opt/x')).toBe('/opt/x')
    })
    test('a variable, a tilde or a glob is unresolvable', () => {
        expect(resolvePath(REPO, '$TMPDIR/x')).toBeNull()
        expect(resolvePath(REPO, '~/x')).toBeNull()
        expect(resolvePath(REPO, 'target/*')).toBeNull()
    })
})

describe('rmRewrite: rewrite to rkvr rmrf', () => {
    test('a home path', async () => {
        const r = await rmRewrite('rm -rf ~/x', env())
        expect(r.command).toBe('rkvr rmrf ~/x')
        expect(r.note).toBe(REWRITE_NOTE)
    })
    test('two paths, -r only', async () => {
        expect((await rmRewrite('rm -r a b', env())).command).toBe('rkvr rmrf a b')
    })
    test('a scratch path still goes through rkvr: no scratch exception for plain rm', async () => {
        expect((await rmRewrite('rm -rf $TMPDIR/x', env())).command).toBe('rkvr rmrf $TMPDIR/x')
    })
    test('only the rm stage of a chain is touched', async () => {
        expect((await rmRewrite('cd $TMPDIR && rm -rf x', env())).command).toBe('cd $TMPDIR && rkvr rmrf x')
    })
    test('quoting is preserved', async () => {
        expect((await rmRewrite('rm -rf "a b/c"', env())).command).toBe('rkvr rmrf "a b/c"')
    })
    test('a flagless rm is still unreproducible data', async () => {
        expect((await rmRewrite('rm notes.md', env())).command).toBe('rkvr rmrf notes.md')
    })
})

describe('rmRewrite: regenerable set, matched positionally', () => {
    test('target next to Cargo.toml is kept', async () => {
        const r = await rmRewrite('rm -rf target/', env([REPO + '/Cargo.toml']))
        expect(r.command).toBe('rm -rf target/')
        expect(r.note).toBe(SET_NOTE)
    })
    test('two regenerable paths with two different anchors', async () => {
        const r = await rmRewrite('rm -rf ./target node_modules', env([REPO + '/Cargo.toml', REPO + '/package.json']))
        expect(r.command).toBe('rm -rf ./target node_modules')
        expect(r.note).toBe(SET_NOTE)
    })
    test('a tracked source module named target has no anchor beside it', async () => {
        const r = await rmRewrite('rm -rf crates/loopr/src/target', env([REPO + '/Cargo.toml']))
        expect(r.command).toBe('rkvr rmrf crates/loopr/src/target')
        expect(r.note).toBe(REWRITE_NOTE)
    })
    test('the name alone is never enough: no anchor in the cwd', async () => {
        expect((await rmRewrite('rm -rf target', env())).command).toBe('rkvr rmrf target')
    })
    test('one non-regenerable path makes the whole stage rkvr', async () => {
        const r = await rmRewrite('rm -rf target src', env([REPO + '/Cargo.toml']))
        expect(r.command).toBe('rkvr rmrf target src')
        expect(r.note).toBe(REWRITE_NOTE)
    })
    test('__pycache__ is regenerable anywhere, with no anchor', async () => {
        const r = await rmRewrite('rm -rf a/b/__pycache__', env())
        expect(r.command).toBe('rm -rf a/b/__pycache__')
        expect(r.note).toBe(SET_NOTE)
    })
    test('an egg-info directory matches the suffix entry', async () => {
        const r = await rmRewrite('rm -rf thing.egg-info', env([REPO + '/setup.py']))
        expect(r.note).toBe(SET_NOTE)
    })
    test('.terraform needs any *.tf in the parent, found by listing it', async () => {
        const kept = await rmRewrite('rm -rf infra/.terraform', env([REPO + '/infra/main.tf']))
        expect(kept.note).toBe(SET_NOTE)
        const gone = await rmRewrite('rm -rf infra/.terraform', env([REPO + '/infra/readme.md']))
        expect(gone.command).toBe('rkvr rmrf infra/.terraform')
    })
    test('pom.xml is not an anchor for target', async () => {
        const r = await rmRewrite('rm -rf target', env([REPO + '/pom.xml']))
        expect(r.command).toBe('rkvr rmrf target')
    })
})

describe('rmRewrite: the # regenerable marker', () => {
    test('an exact trailing marker keeps the rm', async () => {
        const r = await rmRewrite('rm -rf ~/scratch/big # regenerable', env())
        expect(r.command).toBe('rm -rf ~/scratch/big # regenerable')
        expect(r.note).toBe(MARKER_NOTE)
    })
    test('a near miss is not the marker', async () => {
        const r = await rmRewrite('rm -rf ~/x #regenerable-ish', env())
        expect(r.command).toBe('rkvr rmrf ~/x #regenerable-ish')
        expect(r.note).toBe(REWRITE_NOTE)
    })
    test('a hash mid-word is a filename, not a comment', async () => {
        const r = await rmRewrite('rm -rf precious a# regenerable', env())
        expect(r.command).toBe('rkvr rmrf precious a# regenerable')
    })
    test('a quoted marker is a filename', async () => {
        const r = await rmRewrite('rm -rf "x # regenerable"', env())
        expect(r.command).toBe('rkvr rmrf "x # regenerable"')
    })
    test('a marker in a heredoc body is data; the rm stage before it still rewrites', async () => {
        const cmd = 'rm -rf y && cat <<EOF\n# regenerable\nEOF'
        const r = await rmRewrite(cmd, env())
        expect(r.command).toBe('rkvr rmrf y && cat <<EOF\n# regenerable\nEOF')
        expect(r.note).toBe(REWRITE_NOTE)
    })
})

describe('rmRewrite: forms passed through unchanged', () => {
    test('interactive rm', async () => {
        const r = await rmRewrite('rm -i x', env())
        expect(r.command).toBe('rm -i x')
        expect(r.note).toContain('rm form not rewritten')
    })
    test('the -- form, where the paths are ambiguous', async () => {
        const r = await rmRewrite('rm -- -weird', env())
        expect(r.command).toBe('rm -- -weird')
        expect(r.note).toContain('rm form not rewritten')
    })
    test('git rm is an index operation', async () => {
        const r = await rmRewrite('git rm x', env())
        expect(r.command).toBe('git rm x')
        expect(r.note).toContain('git rm')
    })
    test('rm inside a heredoc body is text', async () => {
        const cmd = "cat <<'EOF'\nrm -rf x\nEOF"
        const r = await rmRewrite(cmd, env())
        expect(r.command).toBe(cmd)
        expect(r.note).toBe('')
    })
    test('a loop body is out of scope for a string rewrite, and the miss is noted', async () => {
        const cmd = 'for f in *; do rm -rf $f; done'
        const r = await rmRewrite(cmd, env())
        expect(r.command).toBe(cmd)
        expect(r.note).toContain('loop body')
    })
    test('a command with no delete in it gets no note', async () => {
        const r = await rmRewrite('git status', env())
        expect(r.command).toBe('git status')
        expect(r.note).toBe('')
    })
})

describe('rmRewrite: wrapper forms are denied', () => {
    test('sudo rm', async () => {
        const r = await rmRewrite('sudo rm -rf /opt/x', env())
        expect(r.deny).toContain('rkvr rmrf')
        expect(r.deny).toContain('rules/safety.md')
    })
    test('find -delete', async () => {
        expect((await rmRewrite("find . -name '*.o' -delete", env())).deny).toBeDefined()
    })
    test('find -exec rm', async () => {
        expect((await rmRewrite("find . -name '*.o' -exec rm {} +", env())).deny).toBeDefined()
    })
    test('xargs rm, which carries no literal path at all', async () => {
        expect((await rmRewrite('xargs rm -rf', env())).deny).toBeDefined()
    })
    test('sh -c with an rm payload', async () => {
        expect((await rmRewrite("sh -c 'rm -rf /x'", env())).deny).toBeDefined()
    })
    test('ssh and docker exec reach another machine or container', async () => {
        expect((await rmRewrite('ssh desk rm -rf /x', env())).deny).toBeDefined()
        expect((await rmRewrite('docker exec c rm -rf /x', env())).deny).toBeDefined()
    })
    test('a wrapper confined to scratch passes, with the miss noted', async () => {
        const r = await rmRewrite('find $TMPDIR -delete', env())
        expect(r.deny).toBeUndefined()
        expect(r.command).toBe('find $TMPDIR -delete')
        expect(r.note).toContain('scratch')
    })
    test('a wrapper that deletes nothing is not this rule s business', async () => {
        const r = await rmRewrite('sudo systemctl restart sccache', env())
        expect(r.deny).toBeUndefined()
        expect(r.note).toBe('')
    })
})
