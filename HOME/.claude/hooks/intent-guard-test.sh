#!/bin/bash
# intent-guard-test.sh: the matrix for intent-guard.sh.
#
# Wired into `.otto.yml`'s test task by glob (`*-test.sh`), so it needs no
# .otto.yml edit of its own. The lint task's FILES array is explicit and does.
#
# Every irreversible deny runs through shapes.sh's wrap_shapes, 18 spellings,
# because a guard that only holds for the bare form is not a guard. The
# exception is any fixture carrying a single quote: shapes.sh:45 states that a
# command with a single quote or a newline cannot ride the quoted wrapper
# shapes, so those are asserted directly.

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
HOOK="$HOOKS/intent-guard.sh"
. "$HOOKS/shapes.sh" || exit 1
pass=0
fail=0

# The payload carries run_in_background on every fixture, because it is a field
# of the real one and SLEEP's unconditional allow reads it. It had zero hits in
# this file, in intent-guard.sh and in lib.sh before this phase, so the wiring
# is asserted here rather than assumed.
run() { # run <expect deny|allow> <command> [run_in_background true|false]
  local expect="$1" cmd="$2" bg="${3:-false}" out decision label
  out=$(jq -n --arg c "$cmd" --arg d "$PWD" --argjson b "$bg" \
    '{tool_name:"Bash",tool_input:{command:$c,run_in_background:$b},cwd:$d}' | bash "$HOOK")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  label="$cmd"
  [ "$bg" = "true" ] && label="(run_in_background) $cmd"
  if [ "$decision" = "$expect" ]; then
    pass=$((pass + 1))
    printf 'PASS  [%s] %s\n' "$expect" "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL  [want %s got %s] %s\n' "$expect" "$decision" "$label"
  fi
}

runwrapped() { # runwrapped <command>
  local w
  while IFS= read -r w; do run deny "$w"; done < <(wrap_shapes "$1")
}

# A COMPOUND command cannot ride all 18 spellings: `for`, `while` and `until`
# are reserved words, so `timeout 5 %s`, `nohup %s`, `\%s` and `"%s"` produce
# strings bash cannot parse, and asserting a deny on an unparseable string tests
# nothing. The four are skipped rather than passed vacuously, and the COUNT is
# itself asserted, so a shape that becomes parseable later fails here instead of
# silently dropping out of the sweep.
runwrappedloop() { # runwrappedloop <compound command>
  local w total=0 invalid=0
  while IFS= read -r w; do
    total=$((total + 1))
    if bash -n <<<"$w" 2>/dev/null; then
      run deny "$w"
    else
      invalid=$((invalid + 1))
    fi
  done < <(wrap_shapes "$1")
  if [ "$total" -eq 18 ] && [ "$invalid" -eq 4 ]; then
    pass=$((pass + 1))
    printf 'PASS  [shapes total=%s invalid=%s] %s\n' "$total" "$invalid" "$1"
  else
    fail=$((fail + 1))
    printf 'FAIL  [shapes want total=18 invalid=4, got total=%s invalid=%s] %s\n' "$total" "$invalid" "$1"
  fi
}

echo "=== the two founding incidents deny, in every shape bash offers ==="
runwrapped 'gh api -X DELETE repos/tatari-tv/valet/branches/main/protection/enforce_admins'
runwrapped 'acli jira workitem delete --key SEC-2997 --yes'

echo "=== method parse: four spellings, last wins, case-insensitive ==="
run deny  'gh api -XDELETE repos/o/r/branches/main/protection'
run deny  'gh api --method=DELETE repos/o/r/rulesets/5'
run deny  'gh api -X delete repos/o/r/rulesets'
run deny  'gh api repos/o/r -X GET -X DELETE'
run deny  'gh api -X=DELETE repos/o/r'
run allow 'gh api --method GET repos/o/r -f x=1'
run deny  'gh api --field description=x repos/o/r'
run deny  'gh api /repos/o/r -X PATCH'
run deny  'gh api repos/{owner}/{repo} -X PATCH'

echo "=== round 4's two live bypasses, executed against the endpoint ==="
# gh api -XDELETE -p -XGET /rate_limit --verbose sent DELETE while a parse over
# round 3's hand-listed skip set resolved GET. Same for --header, the long alias
# of the -H that round 3 had just fixed in its short form only.
run deny 'gh api -XDELETE -p -XGET repos/o/r'
run deny 'gh api -XDELETE --preview -XGET repos/o/r'
run deny 'gh api -XDELETE --header -XGET repos/o/r'

echo "=== one operand-skip fixture per value-taking flag ==="
# Each: an explicit DELETE, then a flag whose OPERAND is shaped like a method
# flag. The operand must be consumed, so DELETE stands and the call denies. A
# flag missing from VALUE_FLAGS fails here instead of shipping as a bypass.
for f in --cache -F --field -H --header --hostname --input -q --jq -p --preview -f --raw-field -t --template; do
  run deny "gh api -XDELETE $f -XGET repos/o/r"
done

echo "=== guarded paths, and the ones that are not ==="
run deny  'gh api orgs/tatari-tv/rulesets -X POST'
run deny  'gh api repos/o/r -X PATCH'
run allow 'gh api repos/o/r/pulls/1 -X PATCH -f body=x'
run allow 'gh api repos/tatari-tv/philo/pulls/1 -X PATCH -f body=x'
run allow 'gh api repos/o/r'
run allow 'gh api /rate_limit'
run allow 'gh api -XDELETE -p -XGET /rate_limit'
run allow 'gh api repos/o/r/branches/main/protection'

echo "=== gh repo edit is the same settings surface through another door ==="
run deny  'gh repo edit tatari-tv/mcp-io-rs --visibility public'
run allow 'gh pr create --title x --head flat-slug'
run allow 'gh repo view tatari-tv/philo'

echo "=== DELETE-OUT, and the --help carve-out ==="
run deny  'acli confluence page delete --id 12345'
run allow 'acli jira workitem delete --help'
run allow 'acli jira workitem view --key SEC-2997'
# The permissions.deny entries this phase adds carry no --help carve-out and are
# evaluated independently of what a hook returns, so the COMBINED behaviour of
# `acli jira workitem delete --help` is whatever the permission layer decides.
# This asserts the hook's half only; the combined result is recorded in the
# design doc as a fixture rather than an assumption.

echo "=== LN: the cycle is target-ancestor-of-link ==="
runcwd() { # runcwd <expect> <cwd> <command>
  local expect="$1" cwd="$2" cmd="$3" out decision
  out=$(jq -n --arg c "$cmd" --arg d "$cwd" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | bash "$HOOK")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  if [ "$decision" = "$expect" ]; then
    pass=$((pass + 1)); printf 'PASS  [%s] (cwd=%s) %s\n' "$expect" "$cwd" "$cmd"
  else
    fail=$((fail + 1)); printf 'FAIL  [want %s got %s] (cwd=%s) %s\n' "$expect" "$decision" "$cwd" "$cmd"
  fi
}
runcwd deny  /tmp 'ln -s /tmp /tmp/loop'
runcwd deny  /tmp 'ln -s .. parent_dir'
runcwd deny  /tmp 'ln -s / /rootlink'
runcwd deny  /home/saidler 'ln -s /tmp/loopprobe/looped /tmp/loopprobe/looped/a/self'
runcwd deny  /home/saidler 'ln -s /tmp/lp2/loop /tmp/lp2/loop/d1/self'
# `ln -s . 5626` publishes a URL prefix and was deliberate, but it is the
# ancestor shape without qualification: it yields 5626/5626/5626 without bound.
# A deny is correct and Scott re-runs it with `!`, the same disposition
# GH-WRITE takes for his own protection changes.
runcwd deny  /home/saidler/repos/milwaukie-youth-football/5626/public 'ln -s . 5626'

echo "=== LN: the cycle deny holds in every shape bash offers ==="
# Added by the chunk's acceptance walk. Criterion 1 asks for quote-free deny
# fixtures riding the full sweep, and the LN rule had deny fixtures that never
# rode it. Both hold 18 of 18.
runwrapped 'ln -s . 5626'
runwrapped 'ln -s /tmp /tmp/loop'

echo "=== LN: the reinstall shape must survive, which realpath -m breaks ==="
# realpath -m FOLLOWS an existing link, so link and target resolve identically
# on every `ln -sf` reinstall and an equality test fires on the single most
# common legitimate shape in the corpus. The basename is never dereferenced.
runcwd allow /home/saidler 'ln -sf /home/saidler/repos/scottidler/claude/HOME/.claude/hooks/x.sh /home/saidler/.claude/hooks/x.sh'
runcwd allow /home/saidler 'ln -sfn /home/saidler/repos/scottidler/claude/HOME/.claude/hooks/lib.sh /home/saidler/.claude/hooks/lib.sh'
runcwd allow /tmp 'ln -s /etc/hosts /tmp/hosts-link'
runcwd allow /tmp 'ln -s ../elsewhere/file link-name'

echo "=== LN: ~/Claude is symlink-free by policy ==="
runcwd deny  /home/saidler 'ln -s /etc/hosts /home/saidler/Claude/hosts'
runcwd deny  /home/saidler 'ln -s /etc/hosts Claude/hosts'

echo "=== LN: cwd resolution, and where it fails closed ==="
# An unexpanded operand is not knowable here, so the PAIR is skipped. Dropping
# such tokens from the operand list instead shifts which token becomes the link
# path, which turned this corpus command into a self-link and denied it.
runcwd allow /tmp/otto-p1/nopy 'mkdir -p /tmp/otto-p1/nopy && cd /tmp/otto-p1/nopy && for b in bash sh echo cat env ln rm mkdir; do ln -sf $(command -v $b) . 2>/dev/null; done'
runcwd allow /home/saidler 'ln -sf plain-token.age "$SP/.secrets/alias-token.age"'
# The paren stop is positional. A `$( )` AFTER the ln must not discard the cd
# chain before it: this exact corpus command lost its `cd /tmp/wt-385b`, fell
# back to the payload cwd, and the relative link path landed on the target.
runcwd allow /home/saidler/repos/tatari-tv/platform-templates 'cd /tmp/wt-385b && ln -s /home/saidler/repos/tatari-tv/platform-templates/node_modules node_modules && echo "head=$(git rev-parse --short HEAD)"'
runcwd allow /home/saidler 'cd /home/saidler/repos/scottidler/claude && cd HOME && ln -s .claude/hooks/x.sh /tmp/x.sh'
# A subshell opened BEFORE the ln, with a relative link path: the cwd is not
# knowable and a fallback would be a confident wrong answer, so this denies.
runcwd deny  /home/saidler/repos/otto-rs/otto '(cd "$S" && ln -sf /home/saidler/repos/otto-rs/otto/target target 2>/dev/null; true)'
runcwd deny  '' 'ln -s /etc/hosts relative-link'

echo "=== INGEST: command scope, because stmts splits the incident apart ==="
# V is assembled rather than written, for the same reason the design doc's own
# INGEST section is a self-reference hazard: a fixture file containing the
# literal verb makes THIS test script trip the rule it is testing.
V="sb borg in""gest"
run allow "$V --tags x -- https://one.url"
run deny  "$V --file urls.txt"
run deny  "sb borg reingest --all"
run allow "sb borg reingest-failed --dry-run"
run allow "sb borg reingest-failed"
run allow "sb borg log"
run allow "sb borg audit"
# Round 4, both seats independently: step 2 said read-only verbs "always allow"
# with no scope, so this returned allow for the whole command and never reached
# the deny clauses. Read-only operations are dropped from the operation list now.
run deny  "sb borg log; $V --file urls.txt"
run deny  "for url in a b; do $V -- \"\$url\"; done"
run deny  "cat urls.txt | xargs -n1 $V --"
run deny  "$V -- https://a.url; $V -- https://b.url"
# A glob needs a trailing space and misses `while;`. The doc names this one.
run deny  "echo while; $V -- https://one.url"
# The operand is not in the command, so it cannot be the thing a human named.
run deny  "$V --tags x -- \"\$url\""

echo "=== INGEST: the door is a CEILING and it is compared ==="
# Round 3 called <n> a maximum and never compared it, so =0 allowed and =1
# allowed five. Counted by TARGET, so the ceiling means what a reader expects.
FIVE="$V -- https://a.url https://b.url https://c.url https://d.url https://e.url"
run deny  "$FIVE"
run allow "BULK_INGEST_ORDERED_BY_SCOTT=5 $FIVE"
run deny  "BULK_INGEST_ORDERED_BY_SCOTT=1 $FIVE"
run deny  "BULK_INGEST_ORDERED_BY_SCOTT=0 $V -- https://one.url"
run deny  "BULK_INGEST_ORDERED_BY_SCOTT=yes $V -- https://one.url"
run allow "BULK_INGEST_ORDERED_BY_SCOTT=1 $V -- https://one.url"

echo "=== INGEST: heredoc bodies, bounded to a .sh redirect target ==="
# The 164-URL incident never looped the verb: it wrote a script with a QUOTED
# heredoc and ran it. The run statement's command word is $S/ingest.sh so no
# verb matcher sees it, and the quoted delimiter means heredoc_expanded never
# emits it. Denying at CREATION is what stops the sequence.
run deny "$(printf 'cat > "$S/in%s.sh" <<%sEOF%s\nwhile IFS= read -r url; do\n  out=$(%s --tags x -- "$url" 2>&1)\ndone\nEOF' 'gest' "'" "'" "$V")"
run deny "$(printf 'cat > run.sh <<%sEOF%s\n%s --file urls.txt\nEOF' "'" "'" "$V")"
# The bound exists because THIS repo's design doc carries both a `while IFS=
# read -r url` line and the verb in its own prose. A .md target is not scanned.
run allow "$(printf 'cat > docs/design/notes.md <<%sEOF%s\nwhile IFS= read -r url; do\n  %s --tags x -- "$url"\ndone\nEOF' "'" "'" "$V")"
# A fenced marker in a body cannot open the door, per chunk C's rule.
run allow "$(printf 'cat > notes.md <<%sEOF%s\n\`\`\`\nBULK_INGEST_ORDERED_BY_SCOTT=5\n\`\`\`\n%s --file urls.txt\nEOF' "'" "'" "$V")"

echo "=== PUBLIC-REPO: against real repos, because none of it is textual ==="
# The scratch repo has to live under ~/repos/scottidler/ because that IS the
# rule's scope test. It is created here and archived with `rkvr rmrf` at the end
# (rules/safety.md): it is not build output, so it does not get a plain rm even
# though this test made it thirty seconds ago.
PR_ROOT="$HOME/repos/scottidler/.intent-guard-test-$$"
PR_BARE="${TMPDIR:-/tmp}/intent-guard-test-$$.git"
PR_VIS="$HOME/.cache/intent-guard/visibility"

pr_cleanup() {
  [ -d "$PR_ROOT" ] && rkvr rmrf "$PR_ROOT" >/dev/null 2>&1
  [ -d "$PR_BARE" ] && rkvr rmrf "$PR_BARE" >/dev/null 2>&1
  [ -n "$PR_KEY" ] && rm -f "$PR_VIS/$PR_KEY" 2>/dev/null
  return 0
}
trap pr_cleanup EXIT

runrepo() { # runrepo <expect> <label> <command>
  local expect="$1" label="$2" cmd="$3" out decision
  out=$(jq -n --arg c "$cmd" --arg d "$PR_ROOT" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | bash "$HOOK")
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  if [ "$decision" = "$expect" ]; then
    pass=$((pass + 1)); printf 'PASS  [%s] %s\n' "$expect" "$label"
  else
    fail=$((fail + 1)); printf 'FAIL  [want %s got %s] %s\n' "$expect" "$decision" "$label"
  fi
}

mkdir -p "$PR_ROOT" && git init -q -b main "$PR_ROOT" && git init -q --bare "$PR_BARE"
git -C "$PR_ROOT" config user.email t@t
git -C "$PR_ROOT" config user.name t
mkdir -p "$PR_ROOT/docs" "$PR_ROOT/voice" "$PR_ROOT/secrets"
echo base > "$PR_ROOT/README.md"; echo v > "$PR_ROOT/voice/VOICE.md"
echo s > "$PR_ROOT/secrets/new.txt"; echo d > "$PR_ROOT/docs/a.md"
git -C "$PR_ROOT" add README.md docs/a.md >/dev/null 2>&1
git -C "$PR_ROOT" commit -qm init >/dev/null 2>&1
git -C "$PR_ROOT" remote add origin "$PR_BARE"
git -C "$PR_ROOT" push -q origin main >/dev/null 2>&1
PR_KEY=$(printf '%s' "$PR_ROOT" | sha256sum | awk '{print $1}')
mkdir -p "$PR_VIS"
printf 'visibility=public\nepoch=%s\n' "$(date +%s)" > "$PR_VIS/$PR_KEY"

# The index is EMPTY at hook time. PreToolUse fires before the whole Bash call,
# so `git diff --cached` cannot see the command's own `git add`, and the draft's
# version would have allowed the leak the rule is named after.
runrepo deny  'the founding incident: add voice/ && commit, empty index' \
  'git add voice/VOICE.md && git commit -m "add voice corpus"'
runrepo deny  'git add x && git commit -am (round 3 fixed this row)' \
  'git add secrets/new.txt && git commit -am update'
runrepo deny  'git add x && git commit --include (round 4 found this one)' \
  'git add secrets/new.txt && git commit --include README.md -m update'
runrepo allow 'a docs-only add and commit' \
  'git add docs/a.md && git commit -m docs'
runrepo allow 'commit --only README.md does not union the index' \
  'git commit --only README.md -m x'
runrepo deny  'git add . is expanded by asking git, not by globbing' \
  'git add . && git commit -m all'

git -C "$PR_ROOT" checkout -q -b feat
git -C "$PR_ROOT" add secrets/new.txt >/dev/null 2>&1
git -C "$PR_ROOT" commit -qm "add secret" >/dev/null 2>&1
runrepo deny  'push feat:newbranch, destination absent so the whole history is the range' \
  'git push origin feat:newbranch'
runrepo deny  "push feat:main, this chunk's own landing refspec shape" \
  'git push origin feat:main'
runrepo deny  'a push source ref that does not resolve fails closed' \
  'git push origin nosuchref:main'
git -C "$PR_ROOT" checkout -q main
runrepo allow 'push main, only docs in range' 'git push origin main'

echo "=== the false-positive class lib.sh exists to kill ==="
# Observed live 2026-09-15T19:41: a naive acli.*delete pattern matched the
# regex TEXT inside a quoted heredoc in scan5.py.
run allow 'echo "gh api -XDELETE repos/o/r"'
run allow "$(printf "cat <<'EOF'\nacli jira workitem delete --key X\nEOF")"
run allow '# gh api -X DELETE repos/o/r/rulesets'

echo "=== round-6 audit regressions: bypasses each phase claimed to cover ==="
# M1: gh accepts the ATTACHED long body form and the exact-token tables missed
# it, so the call read as a bare GET and allowed.
run deny  'gh api repos/o/r/rulesets --field=name=x'
run deny  'gh api orgs/tatari-tv/rulesets --raw-field=name=x'
run deny  'gh api repos/o/r/branches/main/protection --input=p.json'
run allow 'gh api users/scottidler'
run allow 'gh api repos/o/r --jq=.name'

# M11: `--` is the end-of-options marker, not an option, so the cwd still moves.
run deny  'cd -- /home/saidler/Claude && ln -s /home/saidler/repos/x y'
run allow 'cd -- /tmp && ln -s /home/saidler/repos/x y'

# M6: the door was a command-wide flag, so one `=1` statement laundered every
# later ingest in the same command.
run deny  'BULK_INGEST_ORDERED_BY_SCOTT=1 sb borg ingest https://a; sb borg ingest --file urls.txt'
run deny  'BULK_INGEST_ORDERED_BY_SCOTT=1 sb borg ingest https://a && sb borg reingest --all'
run allow 'BULK_INGEST_ORDERED_BY_SCOTT=1 sb borg ingest https://a'

# Ruling 2: the wrapper spellings. `stmts` already emits the payload as its own
# statement; the clauses were reading the whole command quote-masked.
run deny  'eval "sb borg reingest --all"'
run deny  'bash -c "sb borg reingest --all"'

# C4: the op COUNT read the unquoted copy while the clauses read the masked one,
# so quoted prose denied. This fired on three of the audit's own commands.
run allow 'echo "sb borg ingest https://a and sb borg ingest https://b"'

# `--all` was covered for `reingest` only, so the sibling verb walked through.
run deny  'sb borg ingest --all'

echo "=== round-6 C3: a .md heredoc body must not arm the .sh extractor ==="
# The extractor entered body state only for a `.sh` target, so the body of a
# `.md` heredoc was still scanned line by line and any line inside it ending in
# `.sh` before a `<<` re-armed capture. Measured on the real artifact: writing
# `2026-09-15-intent-guards.md` through a quoted heredoc made the OLD extractor
# emit 1145 lines and deny; the two-state form emits 0.
#
# Carries single quotes and newlines, so it is asserted directly rather than
# through wrap_shapes (shapes.sh:45).
MD_HEREDOC=$(printf '%s\n' \
  "cat > notes.md <<'DOC'" \
  "The incident wrote a script:" \
  "    cat > \"\$S/ingest.sh\" <<'EOF'" \
  "    while IFS= read -r url; do sb borg ingest \"\$url\"; done" \
  "    EOF" \
  "DOC")
SH_HEREDOC=$(printf '%s\n' \
  "cat > \"\$S/ingest.sh\" <<'EOF'" \
  "while IFS= read -r url; do sb borg ingest \"\$url\"; done" \
  "EOF")
run allow "$MD_HEREDOC"
run deny  "$SH_HEREDOC"

echo "=== PUBLIC-REPO push: redirects are not refspecs ==="
# Walking EVERY refspec instead of just the second operand (M5) made the tokens
# of a redirect into refspecs of their own, so `git push origin <branch>:main
# 2>&1 | tail -5` denied on a source ref that cannot resolve. It denied the
# push of this very branch. The redirect operator AND its operand are stripped
# before tokenising now, attached (`2>&1`) or separated (`> /dev/null`).
#
# These assert the PARSE, not repo state: run outside a git repo with a
# sensitive path, they exercise the refspec walk and must not deny on a
# redirect token. The repo-state cases live in the scratch-repo probe.
run allow 'git push origin main 2>&1'
run allow 'git push origin main 2>&1 | tail -5'
run allow 'git push origin HEAD:main > /dev/null 2>&1'
run allow 'git push origin main >/dev/null'

echo "=== SLEEP: the three bypass classes the native statement-0 check misses ==="
# `validateInput` runs BEFORE the PreToolUse chain (probed 2026-09-20 on
# 2.1.278), so a bare `sleep 26` is refused by the harness and never reaches
# this hook. Everything asserted here is a shape the native check lets through.
runwrapped     'echo A; sleep 26'
runwrapped     'sleep 24; sleep 24'
runwrappedloop 'for i in 1 2 3; do sleep 30; done'
runwrappedloop 'for i in {1..30}; do sleep 60; done'
runwrappedloop 'for i in $(seq 1 30); do sleep 60; done'
runwrappedloop 'while true; do sleep 30; done'

echo "=== SLEEP: cardinality, where the multiplication alone decides ==="
# Every fixture above carries a per-iteration sleep already over 25, so all of
# them pass against an implementation that computes no bound at all. These do
# not: 30 x 0.5 is 15s and must allow, 60 x 0.5 is 30s and must deny, in each of
# the three computable bound forms. A build that skips the bound fails one half.
LIST30=$(seq 1 30 | tr '\n' ' ')
LIST60=$(seq 1 60 | tr '\n' ' ')
run allow "for i in $LIST30; do sleep 0.5; done"
run deny  "for i in $LIST60; do sleep 0.5; done"
run allow 'for i in {1..30}; do sleep 0.5; done'
run deny  'for i in {1..60}; do sleep 0.5; done'
run allow 'for i in $(seq 1 30); do sleep 0.5; done'
run deny  'for i in $(seq 1 60); do sleep 0.5; done'
# seq's other literal forms are arithmetic too, not opaque bounds.
run deny  'for i in $(seq 60); do sleep 0.5; done'
run deny  'for i in $(seq 1 2 120); do sleep 0.5; done'
run allow 'for i in $(seq 1 2 59); do sleep 0.5; done'

echo "=== SLEEP: sleeps sum inside one iteration too, so B2 cannot be rebuilt there ==="
run deny  'for i in 1 2 3; do sleep 4; sleep 5; done'
run allow 'for i in 1 2 3; do sleep 4; sleep 4; done'

echo "=== SLEEP: an uncomputable bound fails closed and the deny names the shape ==="
run deny  'for f in *.txt; do sleep 30; done'
run deny  'for f in $(cat list); do sleep 30; done'
run deny  'for ((i=0; i<30; i++)); do sleep 1; done'
run deny  'for f in $FILES; do sleep 30; done'
run deny  'for f; do sleep 30; done'
# No sleep, no business of this rule: the bound being opaque is not the offence.
run allow 'for f in *.txt; do echo "$f"; done'
run allow 'for f in $(cat list); do wc -l "$f"; done'

echo "=== SLEEP: the break carve-out, asserted in both directions ==="
# Syntactic presence, not reachability. `while true; do true && break; sleep 1;
# done` and the `|| break` form that never terminates flatten to the identical
# token stream, so the operators that decide reachability are gone before the
# guard sees the command. This is the one place the rule fails OPEN, taken
# because denying the class would deny Monitor's own `gh pr checks` example.
run deny  'while true; do sleep 30; done'
run allow 'while true; do check && break; sleep 30; done'
run deny  'while :; do sleep 30; done'
run allow 'while :; do check || break; sleep 30; done'

echo "=== SLEEP: a terminating while/until allows at ANY interval (T2 is withdrawn) ==="
# Monitor's own description mandates "30s+ for remote APIs (rate limits)", so a
# per-iteration cap at 25 would deny the pacing the harness prescribes.
run allow 'until [ -f /tmp/ready ]; do sleep 60; done'
run allow 'while read -r line; do sleep 30; done < input'
# A BOUNDED loop nested inside a terminating one still has a computable total.
run deny  'until [ -f /tmp/ready ]; do for i in {1..100}; do sleep 30; done; done'

echo "=== SLEEP: the boundary is >=, matching the native Dpn = 25 ==="
run allow 'echo A; sleep 24'
run deny  'echo A; sleep 25'
run deny  'echo A; sleep 25s'
run allow 'echo A; sleep 0.4m'
run deny  'echo A; sleep 0.5m'

echo "=== SLEEP: run_in_background allows unconditionally, matching the native predicate ==="
run deny  'for i in 1 2 3; do sleep 30; done'
run allow 'for i in 1 2 3; do sleep 30; done' true
run deny  'sleep 24; sleep 24'
run allow 'sleep 24; sleep 24' true
run allow 'while true; do sleep 30; done' true

echo "=== SLEEP: the allow-controls, drawn from the harness's own recommended patterns ==="
# Verbatim from Monitor's description and from the native deny's own example, so
# the guard can never contradict the deny it complements.
run allow 'until grep -q "Ready in" dev.log; do sleep 0.5; done'
run allow 'while true; do gh pr checks 4821 | grep -q pending || break; sleep 30; done'
run allow 'until gh pr checks 4821 --json state -q ".[].state" | grep -qv PENDING; do sleep 30; done'
run allow 'sleep 24'
run allow 'sleep 900' true

echo "=== SLEEP: the false-positive classes lib.sh and the cmdword gate exist to kill ==="
# A heredoc BODY carrying the word sleep is chunk D's class: the body is never a
# statement, so no sleep is ever in executable position.
run allow "$(printf "cat > wait.sh <<'EOF'\nsleep 900\nfor i in 1 2 3; do sleep 30; done\nEOF")"
run allow '# for i in 1 2 3; do sleep 30; done'
run allow 'echo "for i in 1 2 3; do sleep 30; done"'
run allow 'echo "sleep 900"'
run allow 'bash -c "grep sleep /etc/crontab"'
run allow 'rg -n "sleep 30" HOME/.claude/hooks'
# `for` as data opens no loop: a header that never reaches its `done` is not a
# loop at all, so the frame dissolves and this is priced as the 10s it is.
run allow 'echo for; sleep 10'
run deny  'echo for; sleep 30'
# The named residual hole: a non-literal duration cannot be computed, so it
# contributes nothing rather than denying. Same class as the variable-verb limit
# chunk B handed on, and it is a fixture so the hole is visible, not folklore.
run allow 'for i in 1 2 3; do sleep "$INTERVAL"; done'

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
