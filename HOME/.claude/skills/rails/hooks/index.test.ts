import { describe, expect, test } from 'bun:test'
import { internals } from './index.ts'

const { ghSpots, segment, personaFor, inject, inWorkTree } = internals

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
