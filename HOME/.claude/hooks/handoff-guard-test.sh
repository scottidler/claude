#!/bin/bash
# handoff-guard-test.sh: fixture matrix for handoff-guard.sh.
#
# Each case feeds the hook a `UserPromptSubmit` payload on stdin and asserts the
# outcome: SILENT is exit 0 with empty stdout, FIRE is exit 0 plus the emitted
# text with the trigger interpolated verbatim. The hook cannot deny, so fire-or-
# silent plus the exact string is the whole contract.
#
# Fire 2 needs a filesystem, so the fire-2 block builds throwaway git repos
# under a temp dir and removes them on exit. Every repo is created by this
# script; nothing outside the temp dir is touched.
#
# No `shapes.sh` sweep: its templates wrap a command word in shell, and this
# hook consumes a prompt string.
set -u
export LC_ALL=C

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
HOOK="$HOOKS/handoff-guard.sh"
pass=0
fail=0

TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

want_fire1() { # want_fire1 <quoted path>
  printf '%s' "handoff hook: this prompt names a handoff document, quoted verbatim from it: $1.

Decide from the prompt's own wording:
- asking to resume, continue, or pick up that work -> read it, then run \`Skill(handoff)\`, which will put you in RESUME mode: do the work, re-test every blocker it claims with a command, and do NOT write a second handoff.
- naming it in passing (reviewing it, editing it, quoting it, asking where it lives) -> resolve nothing. This line is context, not an order."
}

feed() { # feed <prompt> [cwd]
  jq -n --arg p "$1" --arg c "${2:-/nonexistent-cwd-for-tests}" \
    '{cwd:$c,hook_event_name:"UserPromptSubmit",permission_mode:"auto",prompt:$p,prompt_id:"test",session_id:"test",transcript_path:"/dev/null"}' \
    | bash "$HOOK" 2>/dev/null
  return "${PIPESTATUS[1]}"
}

ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL  %s\n' "$1"; }

ctx_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null; }

silent() { # silent <label> <prompt> [cwd]
  local label="$1" out rc
  out=$(feed "$2" "${3:-}")
  rc=$?
  if [ "$rc" -ne 0 ]; then bad "$label: exit $rc, wanted 0"; return; fi
  if [ -n "$out" ]; then bad "$label: wanted silence, got ${out:0:120}"; return; fi
  ok
}

fires1() { # fires1 <label> <prompt> <expected quoted path>
  local label="$1" out rc got want
  out=$(feed "$2")
  rc=$?
  if [ "$rc" -ne 0 ]; then bad "$label: exit $rc, wanted 0"; return; fi
  if [ -z "$out" ]; then bad "$label: wanted a fire, got silence"; return; fi
  got=$(ctx_of "$out")
  want=$(want_fire1 "$3")
  if [ "$got" != "$want" ]; then
    bad "$label: emitted text differs from the design doc's copy"
    return
  fi
  ok
}

echo "=== fire 1: the prompt names a handoff document ==="
fires1 'bare handoff path'        'pick up docs/handoff/session-recall.md'            'docs/handoff/session-recall.md'
fires1 'resume phrasing'          'continue from docs/handoff/f2-handoff.md please'   'docs/handoff/f2-handoff.md'
fires1 'absolute path'            'read /home/x/repos/y/docs/handoff/topic.md first'  '/home/x/repos/y/docs/handoff/topic.md'
fires1 'handoff in the basename'  'see my-handoff-notes.md'                           'my-handoff-notes.md'
fires1 'capitalized basename'     'open HANDOFF.md'                                   'HANDOFF.md'

echo "=== fire 1: the class this hook exists to NOT hit ==="
# The design doc that specified this hook matches a bare *handoff*.md glob.
silent 'this doc, review request' 'review docs/design/2026-09-18-handoff-and-waiting-discipline.md'
silent 'this doc, absolute'       'read /home/saidler/repos/scottidler/claude/docs/design/2026-09-18-handoff-and-waiting-discipline.md'
silent 'design doc, edit request' 'fix the typo in docs/design/2026-09-18-handoff-and-waiting-discipline.md:142'
silent 'no .md extension'         'the handoff process needs work'
silent 'handoff word alone'       'write me a handoff'

echo "=== fire 1: the bails ==="
silent 'leading angle bracket'    '<task-notification>docs/handoff/x.md</task-notification>'
silent 'agent delivery'           'Another Claude session sent a message: docs/handoff/x.md'
silent 'fenced block'             'here is a diff:
```
+ docs/handoff/x.md
```'
silent 'You are opener'           'You are a reviewer. Read docs/handoff/x.md'
silent 'summarizer opener'        'Summarize this Claude Code session: docs/handoff/x.md'
silent 'security opener'          'Review this change for security: docs/handoff/x.md'
silent 'analyze opener'           'Analyze the following: docs/handoff/x.md'

echo "=== fire 1: multiple paths, first wins ==="
fires1 'design doc then handoff'  'compare docs/design/2026-09-18-handoff-and-waiting-discipline.md with docs/handoff/f2.md' 'docs/handoff/f2.md'

echo "=== fire 2: a handoff newer than HEAD ==="
mkrepo() { # mkrepo <name> -> prints path
  local d="$TMP/$1"
  mkdir -p "$d"
  git -C "$d" init --quiet --initial-branch=work
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  printf 'x\n' > "$d/file.txt"
  git -C "$d" add file.txt
  git -C "$d" commit --quiet -m init
  printf '%s' "$d"
}

repo=$(mkrepo fresh)
mkdir -p "$repo/docs/handoff"
printf 'next action\n' > "$repo/docs/handoff/work.md"
touch -d '+1 hour' "$repo/docs/handoff/work.md"
out=$(feed 'what should I do next' "$repo")
if [ -z "$out" ]; then
  bad 'fire 2: a handoff newer than HEAD did not fire'
elif ctx_of "$out" | grep -q 'docs/handoff/work.md is newer than the last commit'; then
  ok
else
  bad "fire 2: wrong text: $(ctx_of "$out" | head -c 100)"
fi

repo=$(mkrepo stale)
mkdir -p "$repo/docs/handoff"
printf 'old\n' > "$repo/docs/handoff/work.md"
touch -d '-1 hour' "$repo/docs/handoff/work.md"
silent 'fire 2: handoff older than HEAD' 'what should I do next' "$repo"

repo=$(mkrepo wrongbranch)
mkdir -p "$repo/docs/handoff"
printf 'other\n' > "$repo/docs/handoff/some-other-branch.md"
touch -d '+1 hour' "$repo/docs/handoff/some-other-branch.md"
silent 'fire 2: handoff keyed on another branch' 'what should I do next' "$repo"

repo=$(mkrepo nohandoff)
silent 'fire 2: no handoff at all' 'what should I do next' "$repo"

repo=$(mkrepo detached)
mkdir -p "$repo/docs/handoff"
printf 'next\n' > "$repo/docs/handoff/work.md"
touch -d '+1 hour' "$repo/docs/handoff/work.md"
git -C "$repo" checkout --quiet --detach HEAD
silent 'fire 2: detached HEAD is silent' 'what should I do next' "$repo"

mkdir -p "$TMP/nocommits"
git -C "$TMP/nocommits" init --quiet --initial-branch=work
mkdir -p "$TMP/nocommits/docs/handoff"
printf 'next\n' > "$TMP/nocommits/docs/handoff/work.md"
silent 'fire 2: repo with no commits is silent' 'what should I do next' "$TMP/nocommits"

mkdir -p "$TMP/notarepo/docs/handoff"
printf 'next\n' > "$TMP/notarepo/docs/handoff/work.md"
silent 'fire 2: not a git repo is silent' 'what should I do next' "$TMP/notarepo"

echo "=== fire 1 still works where fire 2 is silent ==="
fires1 'no repo, prompt names a handoff' 'resume from docs/handoff/topic.md' 'docs/handoff/topic.md'

echo "=== malformed payloads fail OPEN ==="
malformed() { # malformed <label> <raw stdin>
  local label="$1" out rc
  out=$(printf '%s' "$2" | bash "$HOOK" 2>/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then bad "$label: exit $rc, wanted 0"; return; fi
  if [ -n "$out" ]; then bad "$label: wanted no fire, got ${out:0:120}"; return; fi
  ok
}
malformed 'empty stdin'         ''
malformed 'not json'            'this is not json at all'
malformed 'bare array'          '[]'
malformed 'bare null'           'null'
malformed 'bare number'         '42'
malformed 'no prompt key'       '{"hook_event_name":"UserPromptSubmit"}'
malformed 'prompt is a number'  '{"prompt":42}'
malformed 'prompt is null'      '{"prompt":null}'
malformed 'prompt is an object' '{"prompt":{"text":"docs/handoff/x.md"}}'
malformed 'cwd is a number'     '{"prompt":"hi","cwd":42}'

echo "=== the CLI surface ==="
if bash "$HOOK" --help | head -1 | grep -q 'handoff-guard.sh: UserPromptSubmit hook'; then
  ok
else
  bad '--help does not print the documentation block'
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
