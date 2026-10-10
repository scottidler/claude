import { describe, expect, test } from 'bun:test'
import { homedir } from 'node:os'
import { internals } from './index.ts'
import { buildIndex, joinInstructions, splitInstructions } from './rules.ts'
import type { InstructionPart, RuleIndex } from './rules.ts'

const { ghSpots, headSpots, segment, personaFor, inject, inWorkTree } = internals
const { splitWords, stageComment, resolvePath, rmRewrite } = internals
const { excludedHeads, excludedDeny, classifyStages, readsOnlyStdin } = internals
const { pkillRewrite, pkillArgs } = internals

/** The rewritten command, failing the test if the rule denied instead. */
function pkillOut(command: string): string {
    const r = pkillRewrite(command)
    if ('deny' in r) { throw new Error('unexpected deny: ' + r.deny) }
    return r.command
}

/** The deny reason, failing the test if the rule did not deny. */
function pkillDenied(command: string): string {
    const r = pkillRewrite(command)
    if (!('deny' in r)) { throw new Error('expected a deny, got: ' + r.command) }
    return r.deny
}

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
    test('git rm is not this rule s business: the content stays in git history', async () => {
        const r = await rmRewrite('git rm x', env())
        expect(r.command).toBe('git rm x')
        expect(r.note).toBe('')
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
    test('review-panel runs/ is scratch in tilde and absolute form; rounds/ is not', async () => {
        const runs = await rmRewrite('sudo rm -rf ~/.cache/review-panel/runs/x', env())
        expect(runs.deny).toBeUndefined()
        const abs = await rmRewrite('sudo rm -rf ' + homedir() + '/.cache/review-panel/runs/x', env())
        expect(abs.deny).toBeUndefined()
        const rounds = await rmRewrite('sudo rm -rf ~/.cache/review-panel/rounds/x', env())
        expect(rounds.deny).toBeDefined()
        const roundsAbs = await rmRewrite('sudo rm -rf ' + homedir() + '/.cache/review-panel/rounds/x', env())
        expect(roundsAbs.deny).toBeDefined()
    })
    test('a wrapper that deletes nothing is not this rule s business', async () => {
        const r = await rmRewrite('sudo systemctl restart sccache', env())
        expect(r.deny).toBeUndefined()
        expect(r.note).toBe('')
    })
    test('docker rm and docker compose rm are the tool s own verb, not a delegated rm', async () => {
        const a = await rmRewrite('docker rm c1 c2', env())
        expect(a.deny).toBeUndefined()
        expect(a.command).toBe('docker rm c1 c2')
        const b = await rmRewrite('docker compose rm -f', env())
        expect(b.deny).toBeUndefined()
        expect(b.command).toBe('docker compose rm -f')
    })
    test('docker exec still delegates, so it stays denied', async () => {
        expect((await rmRewrite('docker exec c rm -rf /x', env())).deny).toBeDefined()
    })
})

/**
 * Fixture list for the classification logic, already stripped of the ` *` glob. It keeps `cargo`,
 * `otto` and `journalctl` as stand-in heads although the shipped settings.json dropped them on
 * 2026-10-09; SHIPPED_EXCLUDED below is what the shipped file must read as.
 */
const EXCLUDED = [
    'cargo', 'otto', 'aws-vault', 'bump', 'systemctl', 'journalctl', 'crontab', 'ssh',
    'git push', 'git fetch', 'git pull', 'git ls-remote', 'git clone', 'slack',
    '~/.claude/skills/architect/script.sh', '~/.claude/skills/staff-engineer/script.sh',
]

const SHIPPED_EXCLUDED = [
    'aws-vault', 'bump', 'systemctl', 'crontab', 'ssh',
    'git push', 'git fetch', 'git pull', 'git ls-remote', 'git clone', 'slack',
    '~/.claude/skills/architect/script.sh', '~/.claude/skills/staff-engineer/script.sh',
]

describe('excludedHeads', () => {
    test('the trailing glob is stripped and the order is kept', () => {
        expect(excludedHeads({ sandbox: { excludedCommands: ['cargo *', 'otto *'] } })).toEqual(['cargo', 'otto'])
    })
    test('an entry with no glob is taken as written', () => {
        expect(excludedHeads({ sandbox: { excludedCommands: ['git commit *', 'crontab'] } }))
            .toEqual(['git commit', 'crontab'])
    })
    test('absent or wrongly typed settings yield no entries', () => {
        expect(excludedHeads({})).toEqual([])
        expect(excludedHeads({ sandbox: {} })).toEqual([])
        expect(excludedHeads({ sandbox: { excludedCommands: 'cargo *' } })).toEqual([])
        expect(excludedHeads({ sandbox: { excludedCommands: [1, '', 'ssh *'] } })).toEqual(['ssh'])
    })
    test('the settings.json this repo ships reads as the shipped list', async () => {
        const path = import.meta.dir + '/../../../settings.json'
        expect(excludedHeads(JSON.parse(await Bun.file(path).text()))).toEqual(SHIPPED_EXCLUDED)
    })
})

describe('classifyStages', () => {
    test('an excluded stage and an ordinary one are told apart', () => {
        const s = classifyStages('$TMPDIR/marker.sh; ssh -V', EXCLUDED, 0)
        expect(s.excluded).toEqual(['ssh'])
        expect(s.rest).toEqual(['$TMPDIR/marker.sh'])
    })
    test('cd, export, true, echo and bare assignments carry no behavior', () => {
        const s = classifyStages('X=1; cd r && export A=b; true; echo hi; cargo test', EXCLUDED, 0)
        expect(s.excluded).toEqual(['cargo'])
        expect(s.rest).toEqual([])
    })
})

describe('excludedDeny: compounds that smuggle a stage out of the sandbox', () => {
    test('an excluded stage trailing, which is what rules prefix matching out', () => {
        const deny = excludedDeny('$TMPDIR/marker.sh; ssh -V', EXCLUDED)
        expect(deny).toContain('"ssh -V" would run INSIDE the sandbox here')
        expect(deny).toContain('then "$TMPDIR/marker.sh" as a separate Bash call')
    })
    test('an excluded stage leading', () => {
        expect(excludedDeny('ssh -V; $TMPDIR/marker.sh', EXCLUDED)).not.toBeNull()
    })
    test('a pipe into a shell beside an excluded stage', () => {
        expect(excludedDeny('curl x | sh; cargo --version', EXCLUDED)).not.toBeNull()
    })
    test('a wrapper carries its inner command, so the -c payload is scanned', () => {
        expect(excludedDeny("bash -c 'ssh -V; $TMPDIR/marker.sh'", EXCLUDED)).not.toBeNull()
        expect(excludedDeny("sh -c 'cargo build'", EXCLUDED)).toBeNull()
    })
    test('command substitution is a stage of its own', () => {
        expect(excludedDeny('$TMPDIR/marker.sh $(cargo --version)', EXCLUDED)).not.toBeNull()
    })
    test('sudo and env carry an inner head too', () => {
        expect(excludedDeny('sudo systemctl restart sccache', EXCLUDED)).toBeNull()
        expect(excludedDeny('env FOO=1 cargo build', EXCLUDED)).toBeNull()
        expect(excludedDeny('sudo $TMPDIR/marker.sh; ssh -V', EXCLUDED)).not.toBeNull()
    })
})

describe('excludedDeny: normal use passes untouched', () => {
    test('a single excluded command', () => {
        expect(excludedDeny('cargo test', EXCLUDED)).toBeNull()
    })
    test('cd into a repo then build', () => {
        expect(excludedDeny('cd r && cargo test', EXCLUDED)).toBeNull()
    })
    test('ssh with arguments is one command, not a compound', () => {
        expect(excludedDeny('ssh host ls', EXCLUDED)).toBeNull()
    })
    test('a leading assignment is not a stage', () => {
        expect(excludedDeny('X=1 bump -m', EXCLUDED)).toBeNull()
    })
    test('a pure excluded compound', () => {
        expect(excludedDeny('cargo build && cargo test', EXCLUDED)).toBeNull()
    })
    test('a compound with no excluded stage at all', () => {
        expect(excludedDeny('git status && rg todo', EXCLUDED)).toBeNull()
    })
    test('an empty list makes the rule inert', () => {
        expect(excludedDeny('$TMPDIR/marker.sh; ssh -V', [])).toBeNull()
    })
    test('a heredoc body is data, so its stages never deny', () => {
        expect(excludedDeny("cat <<'EOF'\nssh -V\nmarker.sh\nEOF", EXCLUDED)).toBeNull()
    })
})

describe('readsOnlyStdin', () => {
    test('a consumer with flags only', () => {
        expect(readsOnlyStdin('tail', 'tail -50')).toBe(true)
        expect(readsOnlyStdin('tail', 'tail -n 50')).toBe(true)
        expect(readsOnlyStdin('wc', 'wc -l')).toBe(true)
        expect(readsOnlyStdin('less', 'less')).toBe(true)
    })
    test('a pattern consumer may carry its one pattern, never a path after it', () => {
        expect(readsOnlyStdin('rg', 'rg fail')).toBe(true)
        expect(readsOnlyStdin('jq', 'jq -r .login')).toBe(true)
        expect(readsOnlyStdin('sed', "sed -n '1,5p'")).toBe(true)
        expect(readsOnlyStdin('rg', 'rg fail tests/')).toBe(false)
    })
    test('a file operand disqualifies', () => {
        expect(readsOnlyStdin('tail', 'tail -50 ci.log')).toBe(false)
        expect(readsOnlyStdin('cat', 'cat ~/.ssh/identities/home/id_ed25519')).toBe(false)
    })
    test('tee can never qualify: a file operand is its whole purpose', () => {
        expect(readsOnlyStdin('tee', 'tee out.log')).toBe(false)
        expect(readsOnlyStdin('tee', 'tee')).toBe(false)
    })
})

/**
 * Option C, Scott 2026-09-13: a consumer is transparent only when it is a PIPE
 * target AND names no file. Keying on the name alone reopens the hole in a worse
 * shape, because every consumer also takes file operands.
 */
describe('excludedDeny: a pipe target that reads only stdin is transparent', () => {
    test('the CI-reading pattern this repo uses constantly', () => {
        expect(excludedDeny('otto ci 2>&1 | tail -50', EXCLUDED)).toBeNull()
        expect(excludedDeny('cargo test | rg fail', EXCLUDED)).toBeNull()
    })
    test('a file operand after the pattern is a path, so it denies', () => {
        expect(excludedDeny('cargo test | rg fail tests/', EXCLUDED)).not.toBeNull()
    })
    test('tee writes a file, so it denies even piped', () => {
        expect(excludedDeny('cd r && cargo build 2>&1 | tee $TMPDIR/ci.log', EXCLUDED)).not.toBeNull()
    })
    test('a semicolon-joined consumer is never transparent, whatever its name', () => {
        const deny = excludedDeny('cargo --version; tail ~/.ssh/identities/home/id_ed25519', EXCLUDED)
        expect(deny).toContain('then "tail ~/.ssh/identities/home/id_ed25519" as a separate Bash call')
    })
    test('a bare consumer after a semicolon denies even with no operand', () => {
        expect(excludedDeny('cargo --version; tail -50', EXCLUDED)).not.toBeNull()
    })
    test('an ordinary stage beside an excluded one still denies', () => {
        expect(excludedDeny('git -C p status && cargo test', EXCLUDED)).not.toBeNull()
        expect(excludedDeny('curl x | sh; cargo --version', EXCLUDED)).not.toBeNull()
        expect(excludedDeny('$TMPDIR/marker.sh; ssh -V', EXCLUDED)).not.toBeNull()
    })
    test('a chain of consumers is transparent all the way down', () => {
        expect(excludedDeny('cargo test | rg fail | wc -l', EXCLUDED)).toBeNull()
    })
})

describe('excludedDeny: the text tells the 2.1.295 truth (retro fix 7, 2026-10-08)', () => {
    // Classified against the shipped list, where `git fetch` stays excluded.
    test('a git net verb chained to an acting stage names both stages and INSIDE the sandbox', () => {
        const deny = excludedDeny('git fetch -q origin && git rev-list --count HEAD', SHIPPED_EXCLUDED)
        expect(deny).toContain('"git fetch -q origin"')
        expect(deny).toContain('"git rev-list --count HEAD"')
        expect(deny).toContain('INSIDE the sandbox')
        expect(deny).toContain('run "git fetch -q origin" alone, then "git rev-list --count HEAD"')
        expect(deny).not.toContain('unsandboxed')
    })
    test('a redirect stays inside the stage text instead of cutting it at the &', () => {
        const deny = excludedDeny('git fetch -q origin 2>&1; git rev-list --count HEAD', SHIPPED_EXCLUDED)
        expect(deny).toContain('run "git fetch -q origin 2>&1" alone')
    })
    test('a git net verb piped into a stdin-only consumer still passes (regression guard)', () => {
        expect(excludedDeny('git fetch -q origin 2>&1 | tail -5', SHIPPED_EXCLUDED)).toBeNull()
        expect(excludedDeny('git fetch -q origin 2>&1 | tail -5', EXCLUDED)).toBeNull()
    })
    test('a wrapped stage is named by its inner command', () => {
        const deny = excludedDeny('sudo $TMPDIR/marker.sh; ssh -V', SHIPPED_EXCLUDED)
        expect(deny).toContain('run "ssh -V" alone, then "$TMPDIR/marker.sh"')
    })
})

describe('heads: redirections are not stages', () => {
    test('2>&1 does not open a stage headed 1', () => {
        expect(internals.heads('cargo test 2>&1 | tail -50').map((h) => h.word))
            .toEqual(['cargo', 'tail'])
    })
    test('a redirection target is never a head', () => {
        expect(internals.heads('cargo build > out.log').map((h) => h.word)).toEqual(['cargo'])
        expect(internals.heads('cargo build >> "a b.log" && ssh -V').map((h) => h.word))
            .toEqual(['cargo', 'ssh'])
    })
    test('only a single pipe marks a piped head', () => {
        const piped = (c: string) => internals.heads(c).map((h) => h.piped)
        expect(piped('a | b')).toEqual([false, true])
        expect(piped('a || b')).toEqual([false, false])
        expect(piped('a && b')).toEqual([false, false])
        expect(piped('a; b')).toEqual([false, false])
    })
})

describe('excludedDeny: a quoted head is still a head (audit 2026-09-13)', () => {
    // Live-proven bypass: `cargo --version >/dev/null 2>&1; "python3" -c '<probe>'`
    // ran UNSANDBOXED because the scanner emitted no Head for a quoted word, so
    // REST was empty and the deny could not fire. Two quote characters defeated
    // the mitigation the whole OQ3 option D decision rests on.
    test('a double-quoted head does not hide the stage', () => {
        expect(excludedDeny(`cargo --version; "python3" -c x`, EXCLUDED)).not.toBeNull()
    })
    test('a single-quoted head does not hide the stage', () => {
        expect(excludedDeny(`cargo --version; 'python3' -c x`, EXCLUDED)).not.toBeNull()
    })
    test('a partially quoted head is joined the way the shell joins it', () => {
        expect(excludedDeny(`cargo --version; "pyth"on3 -c x`, EXCLUDED)).not.toBeNull()
        expect(excludedDeny(`cargo --version; py"thon3" -c x`, EXCLUDED)).not.toBeNull()
    })
    test('the redirection that carried the live bypass does not hide it either', () => {
        expect(excludedDeny(`cargo --version >/dev/null 2>&1; "python3" -c x`, EXCLUDED)).not.toBeNull()
    })
    test('a quoted EXCLUDED head alone still has no REST, so it passes', () => {
        expect(excludedDeny(`"cargo" --version`, EXCLUDED)).toBeNull()
    })
    test('quoting does not defeat EX_TRANSPARENT either', () => {
        expect(excludedDeny(`"cd" r && cargo test`, EXCLUDED)).toBeNull()
    })
    test('heads reports the unquoted text so downstream matching still works', () => {
        expect(headSpots(`"rm" -rf x`, 'rm')).toEqual([0])
        expect(headSpots(`'sudo' rm -rf x`, 'sudo')).toEqual([0])
    })
})

describe('excludedDeny: wait is transparent (audit 2026-09-13, finding M2)', () => {
    // review-panel.md:120-135 mandates `script.sh & ... wait $APID` and explains
    // that splitting it gets the children reaped. Adding script.sh to
    // excludedCommands made the compound deny fire on that documented block.
    test('a wait joining an excluded background stage passes', () => {
        const ex = new Set([...EXCLUDED, 'script.sh'])
        expect(excludedDeny('script.sh a & script.sh b & wait', ex)).toBeNull()
    })
    test('wait does not launder a non-excluded stage through', () => {
        const ex = new Set([...EXCLUDED, 'script.sh'])
        expect(excludedDeny('script.sh a & wait; python3 -c x', ex)).not.toBeNull()
    })
})

describe('excludedDeny: audit round 1 gaps (2026-09-13)', () => {
    test('C1: a -f operand is a path, not the pattern slot', () => {
        expect(excludedDeny('cargo test | sed -f prog.sed', EXCLUDED)).not.toBeNull()
        expect(excludedDeny('cargo test | rg -f patterns.txt', EXCLUDED)).not.toBeNull()
        expect(excludedDeny('cargo test | rg --file=patterns.txt', EXCLUDED)).not.toBeNull()
    })
    test('C1: a genuine stdin-only consumer still passes', () => {
        expect(excludedDeny('cargo test | rg fail', EXCLUDED)).toBeNull()
        expect(excludedDeny('otto ci 2>&1 | tail -50', EXCLUDED)).toBeNull()
    })
    test('D3: nesting deeper than three wrappers is still scanned', () => {
        expect(excludedDeny(`nohup env sudo bash -c "ssh -V; printf x"`, EXCLUDED)).not.toBeNull()
    })
    test('D4: kubectl and docker carry an inner command', () => {
        expect(excludedDeny('kubectl exec pod -- $TMPDIR/marker.sh; ssh -V', EXCLUDED)).not.toBeNull()
        expect(excludedDeny('docker run img $TMPDIR/marker.sh; ssh -V', EXCLUDED)).not.toBeNull()
    })
})

describe('rmRewrite: the regenerable anchor is resolved against the tool cwd (D2)', () => {
    // Pinned deliberately: a cd-prefixed or variable path hides the Cargo.toml
    // anchor, so the stage archives instead of passing. Conservative direction,
    // no data loss, recorded rather than fixed (audit 2026-09-13, D2).
    test('a cd-prefixed target does not see the anchor beside it', async () => {
        const out = await rmRewrite('cd /some/crate && rm -rf target', env())
        expect(out.command).toContain('rkvr rmrf')
    })
})

describe('pkillRewrite: the phase 14 criteria (retro 2026-10-08, fix 10)', () => {
    test('a double-quoted pattern with a literal first char is bracketed', () => {
        expect(pkillOut('pkill -f "quartz.*4173"')).toBe('pkill -f "[q]uartz.*4173"')
    })
    test('an already bracketed pattern is untouched', () => {
        const r = pkillRewrite("pkill -f '[b]ump'")
        expect(r).toEqual({ command: "pkill -f '[b]ump'", note: '' })
    })
    test('-x is untouched', () => {
        expect(pkillRewrite('pkill -x foo')).toEqual({ command: 'pkill -x foo', note: '' })
    })
    test('no -f is untouched', () => {
        expect(pkillRewrite('pkill foo')).toEqual({ command: 'pkill foo', note: '' })
    })
    test('an alternation is denied, naming the bracketed form of each alternative', () => {
        const why = pkillDenied("pkill -f 'foo|bar'")
        expect(why).toContain('[f]oo|[b]ar')
        expect(why).toContain('own shell')
    })
    test('a leading metacharacter is denied', () => {
        const why = pkillDenied("pkill -f '.*x'")
        expect(why).toContain('".*x" starts with a regex metacharacter')
    })
})

describe('pkillRewrite: quoting is kept faithfully', () => {
    test('single quotes stay single', () => {
        expect(pkillOut("pkill -f 'quartz.*4173'")).toBe("pkill -f '[q]uartz.*4173'")
    })
    test('a bare word is single-quoted so the new bracket cannot glob', () => {
        expect(pkillOut('pkill -f quartz.*4173')).toBe("pkill -f '[q]uartz.*4173'")
    })
    test('a bare word glued to a redirect keeps the redirect live', () => {
        expect(pkillOut('pkill -f vite>/dev/null')).toBe("pkill -f '[v]'ite>/dev/null")
    })
    test('the rest of a double-quoted word is left byte for byte', () => {
        expect(pkillOut('pkill -f "node\\.js serve"')).toBe('pkill -f "[n]ode\\.js serve"')
    })
    test('the note names both forms', () => {
        const r = pkillRewrite('pkill -f vite')
        expect('note' in r && r.note).toContain('vite -> [v]ite')
    })
})

describe('pkillRewrite: where the stage sits and what flags it carries', () => {
    test('inside a compound, only the pkill stage changes', () => {
        expect(pkillOut('sleep 1; pkill -f vite && echo done')).toBe("sleep 1; pkill -f '[v]ite' && echo done")
    })
    test('two stages are both bracketed', () => {
        expect(pkillOut('pkill -f vite; pkill -f "next dev"')).toBe("pkill -f '[v]ite'; pkill -f \"[n]ext dev\"")
    })
    test('a signal, a cluster and a valued flag before the pattern', () => {
        expect(pkillOut('pkill -9 -fe -u saidler vite')).toBe("pkill -9 -fe -u saidler '[v]ite'")
        expect(pkillOut('pkill -KILL --full vite')).toBe("pkill -KILL --full '[v]ite'")
        expect(pkillOut('pkill --signal TERM -f vite')).toBe("pkill --signal TERM -f '[v]ite'")
    })
    test('-fx and --exact are untouched', () => {
        expect(pkillOut('pkill -fx vite')).toBe('pkill -fx vite')
        expect(pkillOut('pkill -f --exact vite')).toBe('pkill -f --exact vite')
    })
    test('an absolute pkill path is still pkill', () => {
        expect(pkillOut('/usr/bin/pkill -f vite')).toBe("/usr/bin/pkill -f '[v]ite'")
    })
    test('a pkill named inside quotes is not a stage', () => {
        expect(pkillOut('echo "pkill -f vite"')).toBe('echo "pkill -f vite"')
    })
    test('a shell expansion is passed with a note, never guessed at', () => {
        const r = pkillRewrite('pkill -f "$PAT"')
        expect(r).toEqual({ command: 'pkill -f "$PAT"', note: expect.stringContaining('shell expansion') })
    })
    test('a pidfile with no pattern is untouched', () => {
        expect(pkillOut('pkill -f -F /run/x.pid')).toBe('pkill -f -F /run/x.pid')
    })
})

describe('pkillRewrite: outside the subset is denied, never half-right', () => {
    test('an alternation with one bracketed side still names both', () => {
        expect(pkillDenied("pkill -f '[f]oo|bar'")).toContain('[f]oo|[b]ar')
    })
    test('every alternative bracketed passes untouched', () => {
        expect(pkillOut("pkill -f '[f]oo|[b]ar'")).toBe("pkill -f '[f]oo|[b]ar'")
    })
    test('a leading anchor or escape is denied', () => {
        expect(pkillDenied("pkill -f '^vite'")).toContain('"^vite" starts with a regex metacharacter')
        expect(pkillDenied("pkill -f '\\.venv'")).toContain('regex metacharacter')
    })
    test('a deny in any stage denies the whole call', () => {
        expect(pkillDenied("pkill -f vite; pkill -f 'a|b'")).toContain('[a]|[b]')
    })
})

describe('module loads in the engine', () => {
    // The engine refuses a hooks module that imports anything but its own files
    // and `claude-code`; bun does not, so a `node:os` import passed every test
    // here while rails was dark in every fresh session (36f02a4).
    test('index.ts imports only claude-code and relative files', async () => {
        const src = await Bun.file(new URL('./index.ts', import.meta.url)).text()
        const specs = [...src.matchAll(/^\s*import\s[^'"]*['"]([^'"]+)['"]/gm)].map((m) => m[1])
        expect(specs.length).toBeGreaterThan(0)
        // `../types/index.d.ts` is the plugin's own `$.state` contract, a file of the plugin.
        expect(specs.filter((s) => s !== 'claude-code' && !s?.startsWith('./') && !s?.startsWith('../'))).toEqual([])
    })
    test('an absolute runs/ path under any home is scratch, rounds/ is not', async () => {
        expect((await rmRewrite('sudo rm -rf /home/someone/.cache/review-panel/runs/x', env())).deny).toBeUndefined()
        expect((await rmRewrite('sudo rm -rf /root/.cache/review-panel/runs/x', env())).deny).toBeUndefined()
        expect((await rmRewrite('sudo rm -rf /home/someone/.cache/review-panel/rounds/x', env())).deny).toBeDefined()
        expect((await rmRewrite('sudo rm -rf /srv/.cache/review-panel/runs/x', env())).deny).toBeDefined()
    })
})

describe('pkillArgs', () => {
    test('finds the pattern past -- and reports the flags', () => {
        expect(pkillArgs(splitWords('pkill -f -- -vite'))).toEqual({ full: true, exact: false, pattern: 3 })
        expect(pkillArgs(splitWords('pkill -u1000 -f vite'))).toEqual({ full: true, exact: false, pattern: 3 })
        expect(pkillArgs(splitWords('pkill -f'))).toEqual({ full: true, exact: false, pattern: -1 })
    })
})

// ---------------------------------------------------------------------------
// Rule routing: the pure halves of the hooks (end to end: tests/routing.test.ts
// under `claude plugin test`).
// ---------------------------------------------------------------------------

const { ruleBody, framed, fingerprint, decideFiles, rejoin } = internals
const { claimDelivered, claimPending, releaseClaimed, claimGate, promotePending, gateDeny, statements } = internals

const ROUTING_FIXTURES = new URL('./fixtures/', import.meta.url)
const RECORDED_RULES = '/home/saidler/repos/scottidler/claude/HOME/repos/.claude/rules'
const LIVE_RULES = new URL('../../../../repos/.claude/rules/', import.meta.url)

/** The live rule files keyed under the dir the fixtures recorded, as rules.spec.ts does. */
async function recordedIndex(): Promise<RuleIndex> {
    const names = [...new Bun.Glob('*.md').scanSync(LIVE_RULES.pathname)].sort()
    const files = await Promise.all(names.map(async (n) => ({
        path: RECORDED_RULES + '/' + n,
        text: await Bun.file(new URL(n, LIVE_RULES)).text(),
    })))
    return buildIndex(files)
}

async function fixture<T>(name: string): Promise<T> {
    return JSON.parse(await Bun.file(new URL(name, ROUTING_FIXTURES)).text()) as T
}

const base = (p: string): string => p.slice(p.lastIndexOf('/') + 1)

describe('ruleBody and framed', () => {
    test('frontmatter and the blank lines after it go, the body stays', () => {
        expect(ruleBody('---\nload: always\n---\n\n# Git\n\nBody.\n')).toBe('# Git\n\nBody.')
    })
    test('a rule with no frontmatter is its own body', () => {
        expect(ruleBody('# Git\n')).toBe('# Git')
    })
    test('an unclosed frontmatter block is left as text', () => {
        expect(ruleBody('---\nload: always\n# Git\n')).toBe('---\nload: always\n# Git')
    })
    test('framed uses the engine nested_memory header', () => {
        expect(framed('/r/git.md', '# Git')).toBe('Contents of /r/git.md:\n\n# Git')
    })
})

describe('fingerprint', () => {
    test('stable for the same attachment, different for another text or type', () => {
        expect(fingerprint('instructions', 'abc')).toBe(fingerprint('instructions', 'abc'))
        expect(fingerprint('instructions', 'abc')).not.toBe(fingerprint('instructions', 'abd'))
        expect(fingerprint('instructions', 'abc')).not.toBe(fingerprint('nested_memory', 'abc'))
    })
})

describe('decideFiles over the recorded attachments', () => {
    test('the e9ef7f18 burst: 11 kept, git marquee otto voice dropped as routed', async () => {
        const index = await recordedIndex()
        const burst = await fixture<{ rows: { path: string; text: string }[] }>('nested-e9ef7f18.json')
        const ledger = {}
        const verdicts = burst.rows.map((row) => {
            const d = decideFiles(index, ledger, 'main', [{ path: row.path, real: row.path }], fingerprint('nested_memory', row.text))
            return [base(row.path), d[0]?.verdict]
        })
        expect(verdicts.filter(([, v]) => v === 'keep').length).toBe(11)
        expect(verdicts.filter(([, v]) => v !== 'keep')).toEqual([
            ['marquee.md', 'routed'], ['otto.md', 'routed'], ['git.md', 'routed'], ['voice.md', 'routed'],
        ])
    })

    test('the 2b8aebe2 blob: the 4 routed sections go, preamble and managed tier stay, the rest is byte for byte', async () => {
        const index = await recordedIndex()
        const blob = await fixture<{ text: string }>('instructions-2b8aebe2.json')
        const parts = splitInstructions(blob.text)
        const files = parts.flatMap((part) => (part.path === undefined ? [] : [{ part, path: part.path, real: part.path }]))
        const decisions = decideFiles(index, {}, 'main', files, fingerprint('instructions', blob.text))
        const dropped = new Set(files.filter((_, i) => decisions[i]?.verdict !== 'keep').map((f) => f.part))
        expect([...dropped].map((p) => base(p.path ?? ''))).toEqual(['marquee.md', 'otto.md', 'git.md', 'voice.md'])
        const text = rejoin(blob.text, parts, dropped)
        expect(text).toBe(joinInstructions(parts.filter((p) => !dropped.has(p))))
        expect(text.startsWith('Codebase and user instructions are shown below.')).toBe(true)
        expect(text).toContain('Contents of <managed-settings> (organization-managed policy instructions):')
        expect(text).not.toContain('/rules/git.md (')
        expect(blob.text.length - text.length).toBe([...dropped].reduce((n, p) => n + p.header.length + p.body.length, 0))
    })
})

describe('decideFiles: duplicates', () => {
    const index = buildIndex([{ path: '/r/git.md', text: '---\nload:\n  bash: [\'^git\\b\']\n---\n# Git\n' }])
    test('a real path another attachment kept is a duplicate; the same attachment again is not', () => {
        const ledger = {}
        expect(decideFiles(index, ledger, 'main', [{ path: '/a/CLAUDE.md', real: '/x/CLAUDE.md' }], 'one')[0]?.verdict).toBe('keep')
        expect(decideFiles(index, ledger, 'main', [{ path: '/b/CLAUDE.md', real: '/x/CLAUDE.md' }], 'two')[0]?.verdict).toBe('duplicate')
        expect(decideFiles(index, ledger, 'main', [{ path: '/a/CLAUDE.md', real: '/x/CLAUDE.md' }], 'one')[0]?.verdict).toBe('keep')
    })
    test('one attachment carrying a file twice keeps the first', () => {
        const d = decideFiles(index, {}, 'main', [{ path: '/a', real: '/x' }, { path: '/b', real: '/x' }], 'one')
        expect(d.map((x) => x.verdict)).toEqual(['keep', 'duplicate'])
    })
    test('loops do not share what they kept', () => {
        const ledger = {}
        decideFiles(index, ledger, 'main', [{ path: '/a', real: '/x' }], 'one')
        expect(decideFiles(index, ledger, 'agent-1', [{ path: '/a', real: '/x' }], 'two')[0]?.verdict).toBe('keep')
    })
    test('a routed rule is routed even under a symlink spelling, once resolved', () => {
        expect(decideFiles(index, {}, 'main', [{ path: '/l/git.md', real: '/r/git.md' }], 'one')[0]?.verdict).toBe('routed')
    })
})

describe('rejoin', () => {
    const blob = 'Pre.\n\nContents of /a.md (p):\n\nA\n\nContents of /b.md (p):\n\nB'
    const parts = splitInstructions(blob)
    test('dropping the last section leaves no dangling separator', () => {
        const last = parts[parts.length - 1] as InstructionPart
        expect(rejoin(blob, parts, new Set([last]))).toBe('Pre.\n\nContents of /a.md (p):\n\nA')
    })
    test('the blob own trailing newline is kept', () => {
        const withNl = blob + '\n'
        const p = splitInstructions(withNl)
        expect(rejoin(withNl, p, new Set([p[p.length - 1] as InstructionPart]))).toBe('Pre.\n\nContents of /a.md (p):\n\nA\n')
    })
    test('dropping a middle section keeps the rest byte for byte', () => {
        expect(rejoin(blob, parts, new Set([parts[1] as InstructionPart]))).toBe('Pre.\n\nContents of /b.md (p):\n\nB')
    })
})

describe('delivery state', () => {
    test('claimDelivered takes each rule once per loop; releaseClaimed gives it back', () => {
        const ledger = {}
        expect(claimDelivered(ledger, 'main', ['/g', '/o'])).toEqual(['/g', '/o'])
        expect(claimDelivered(ledger, 'main', ['/g'])).toEqual([])
        expect(claimDelivered(ledger, 'a1', ['/g'])).toEqual(['/g'])
        releaseClaimed(ledger, 'main', ['/g'], 'delivered')
        expect(claimDelivered(ledger, 'main', ['/g'])).toEqual(['/g'])
    })
    test('releaseClaimed of delivered leaves a pending rule pending', () => {
        const ledger = {}
        claimGate(ledger, 'main', ['/g'])
        releaseClaimed(ledger, 'main', ['/g'], 'delivered')
        expect(claimGate(ledger, 'main', ['/g'])).toEqual({ fresh: [], waiting: ['/g'] })
    })
    test('claimPending takes each rule once per loop; releaseClaimed of pending gives it back', () => {
        const ledger = {}
        expect(claimPending(ledger, 'main', ['/g', '/o'])).toEqual(['/g', '/o'])
        expect(claimPending(ledger, 'main', ['/g'])).toEqual([])
        releaseClaimed(ledger, 'main', ['/g'], 'pending')
        expect(claimPending(ledger, 'main', ['/g'])).toEqual(['/g'])
    })
    test('a rule a tool result injected is pending: a sibling gate waits until a step promotes it', () => {
        const ledger = {}
        claimPending(ledger, 'main', ['/g'])
        expect(claimGate(ledger, 'main', ['/g'])).toEqual({ fresh: [], waiting: ['/g'] })
        expect(promotePending(ledger, 'main')).toEqual(['/g'])
        expect(claimGate(ledger, 'main', ['/g'])).toEqual({ fresh: [], waiting: [] })
    })
    test('a gate is fresh, then waiting, then passes once a step promoted it', () => {
        const ledger = {}
        expect(claimGate(ledger, 'main', ['/g'])).toEqual({ fresh: ['/g'], waiting: [] })
        expect(claimGate(ledger, 'main', ['/g'])).toEqual({ fresh: [], waiting: ['/g'] })
        expect(promotePending(ledger, 'main')).toEqual(['/g'])
        expect(claimGate(ledger, 'main', ['/g'])).toEqual({ fresh: [], waiting: [] })
        expect(promotePending(ledger, 'main')).toEqual([])
    })
    test('promotePending on a loop with no ledger is a no-op', () => {
        expect(promotePending({}, 'nobody')).toEqual([])
    })
    test('a rule a prompt delivered never gates', () => {
        const ledger = {}
        claimDelivered(ledger, 'main', ['/g'])
        expect(claimGate(ledger, 'main', ['/g'])).toEqual({ fresh: [], waiting: [] })
    })
})

describe('gateDeny', () => {
    test('fresh rules carry their text, waiting ones one line, and the draft clause ends it', () => {
        const text = gateDeny([{ path: '/r/git.md', body: '# Git' }], ['/r/voice.md'])
        expect(text).toContain('rails: git.md must be in context before this call runs, so it did not run.')
        expect(text).toContain('Contents of /r/git.md:\n\n# Git')
        expect(text).toContain('rails: voice.md: rule delivered above, retry after reading it.')
        expect(text.endsWith('show Scott the new draft before sending.')).toBe(true)
    })
    test('waiting alone carries no rule text', () => {
        expect(gateDeny([], ['/r/git.md'])).not.toContain('Contents of')
    })
})

describe('statements', () => {
    test('one string per simple command, the way the Bash hooks split', () => {
        expect(statements('cd x && git push; echo done')).toEqual(['cd x ', 'git push', 'echo done'])
    })
    test('no command, no statements', () => {
        expect(statements('')).toEqual([])
    })
})

describe('heads: the scan resumes after a heredoc body (audit round 1, X6CMQgQe)', () => {
    test('a command after the terminator line is a statement; the body is not', () => {
        const cmd = "git add -A && git commit -F - <<'EOF'\nmsg\ngit push in the body\nEOF\ngit push origin main"
        expect(statements(cmd)).toEqual(['git add -A ', "git commit -F - <<'EOF'", 'git push origin main'])
    })
    test('the rest of the << line is still scanned', () => {
        expect(statements('cat <<EOF | sh\nbody\nEOF')).toEqual(['cat <<EOF ', 'sh'])
    })
    test('<<- strips leading tabs from the terminator line', () => {
        expect(statements('cat <<-END\n\tbody\n\tEND\necho after')).toEqual(['cat <<-END', 'echo after'])
    })
    test('two heredocs on one line: both bodies are skipped, in order', () => {
        expect(statements('paste <<A <<B\nrm x\nA\nrm y\nB\necho after')).toEqual(['paste <<A <<B', 'echo after'])
    })
    test('a body with no terminator runs to the end', () => {
        expect(statements('cat <<EOF\nrm -rf x\ngit push')).toEqual(['cat <<EOF'])
    })
    test('a line that only starts with the delimiter does not end the body', () => {
        expect(statements('cat <<EOF\nEOF2\nrm x\nEOF\necho after')).toEqual(['cat <<EOF', 'echo after'])
    })
    test('a <<< here-string has no body: the scan goes on', () => {
        expect(statements("grep x <<< 'a b'; echo after")).toEqual(["grep x <<< 'a b'", 'echo after'])
    })
    test('gh after a heredoc is a gh spot; gh in the body is not', () => {
        const cmd = "cat <<'EOF'\ngh api user\nEOF\ngh pr view 1"
        expect(ghSpots(cmd)).toEqual([cmd.indexOf('gh pr view')])
    })
    test('rm after a heredoc is rewritten; rm in the body is not', async () => {
        const r = await rmRewrite("cat <<'EOF'\nrm -rf x\nEOF\nrm -rf y", env())
        expect(r.command).toBe("cat <<'EOF'\nrm -rf x\nEOF\nrkvr rmrf y")
    })
    test('pkill after a heredoc is bracketed; pkill in the body is not', () => {
        expect(pkillOut("cat <<'EOF'\npkill -f foo\nEOF\npkill -f bar")).toBe("cat <<'EOF'\npkill -f foo\nEOF\npkill -f '[b]ar'")
    })
})
