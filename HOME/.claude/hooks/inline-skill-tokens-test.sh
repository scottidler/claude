#!/bin/bash
# inline-skill-tokens-test.sh: regression matrix for inline-skill-tokens.py,
# the UserPromptSubmit hook that turns an inline `/name` into a declinable
# instruction.
#
# Scope: what a shell matrix CAN decide. The hook's own behavior (which
# prompts it injects on, which tokens it names, the shape of the JSON, the
# fact that it never fails a prompt submission) is all asserted here. What a
# shell matrix CANNOT decide is whether the MODEL acts on the injected line,
# which is the split Phase 7's success criteria draw: the two discussion
# prompts below must still INJECT here (no lexical suppressor exists, and the
# design doc rejects one as Alternative 6), and the criterion that they invoke
# nothing is a live-session measurement recorded in the implementation notes.
# So what this file pins about them is the wording that earns the decline:
# the tokens quoted verbatim, and the "only talked about -> invoke nothing"
# branch.
#
# Hooked into `otto ci` by NAME alone, same as the two prior inline test
# scripts: the `test` task globs HOME/.claude/hooks/*-test.sh.
set -u

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ROOT="$(cd "$HOOKS/../../.." && pwd)"
HOOK="$HOOKS/inline-skill-tokens.py"
SETTINGS="$ROOT/HOME/.claude/settings.json"

SCRATCH="${TMPDIR:-/tmp}/inline-skill-tokens-test.$$"
mkdir -p "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

# The hook appends one line per invocation to ~/.cache/claude/ by default.
# Redirected so the matrix never writes to the live log.
export INLINE_SKILL_TOKENS_LOG="$SCRATCH/hook.log"

pass=0
fail=0

ok()  { printf 'PASS  %s\n' "$*"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s\n' "$*"; fail=$((fail + 1)); }

# run <prompt>: the hook's stdout, and the hook's own exit code, so a caller
# can write `out=$(run ...); rc=$?`.
run() {
  jq -n --arg p "$1" '{
    cwd:"/home/saidler/repos/scottidler/claude",
    hook_event_name:"UserPromptSubmit",
    permission_mode:"default",
    prompt:$p,
    prompt_id:"p-test",
    session_id:"s-test",
    transcript_path:"/dev/null"
  }' | python3 "$HOOK" 2>"$SCRATCH/err"
}

context_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty'; }

# injects <label> <prompt> <token>...
# Asserts additionalContext is emitted and names exactly the given tokens.
injects() {
  local label="$1" prompt="$2"; shift 2
  local out ctx tok
  out=$(run "$prompt")
  ctx=$(context_of "$out")
  if [ -z "$ctx" ]; then
    bad "$label: expected an injection, got none (stdout: ${out:-empty})"
    return
  fi
  for tok in "$@"; do
    if ! printf '%s' "$ctx" | grep -qF -- "\`/$tok\`"; then
      bad "$label: injected text does not quote /$tok verbatim: $ctx"
      return
    fi
  done
  local named
  named=$(printf '%s' "$ctx" | grep -oE '`/[A-Za-z0-9][A-Za-z0-9_-]*`' | wc -l)
  if [ "$named" -ne "$#" ]; then
    bad "$label: expected $# token(s) named, found $named: $ctx"
    return
  fi
  ok "$label: injects and names $*"
}

# silent <label> <prompt>
silent() {
  local label="$1" prompt="$2" out rc
  out=$(run "$prompt"); rc=$?
  if [ -n "$out" ]; then
    bad "$label: expected no output, got: $out"
  elif [ "$rc" -ne 0 ]; then
    bad "$label: silent but exited $rc"
  else
    ok "$label: silent"
  fi
}

# ---- the invocation class ---------------------------------------------------
injects "multi-clause imperative" \
  'merge, pull main, /bump, install, /cli-shakedown' bump cli-shakedown

injects "single inline token" 'then /cli-shakedown it' cli-shakedown

# One token twice is one name: the injected list is a set, so the model is not
# told to invoke the same skill twice.
injects "repeated token deduped" 'merge, then /bump, and /bump again after install' bump

# ---- the discussion class: still injects, and the wording earns the decline --
# Phase 7's negative criteria are about what the MODEL does with these, not
# about the hook going quiet. A hook that suppressed them would be the lexical
# suppressor the design doc rejects (Alternative 6).
injects "discussion: a question about the skill" \
  'is chunk E ready to build, or do I need to /create-design-doc on it first?' create-design-doc

injects "discussion: a name in a statistic" \
  '13 of the 15 costliest sessions are /how-to-execute-a-plan' how-to-execute-a-plan

out=$(run 'is chunk E ready to build, or do I need to /create-design-doc on it first?')
ctx=$(context_of "$out")
if printf '%s' "$ctx" | grep -qF 'invoke nothing'; then
  ok "wording: carries the decline branch"
else
  bad "wording: no decline branch, so the discussion class has no way out: $ctx"
fi
if printf '%s' "$ctx" | grep -qF 'invoke it with the Skill tool now'; then
  ok "wording: carries the invoke branch"
else
  bad "wording: no invoke branch, so the feature cannot fire: $ctx"
fi

# ---- the classes the hook must leave alone ----------------------------------
# The whole-prompt bail, not the per-occurrence one: the matcher's offset-0
# rule would still have matched the SECOND token here.
silent "prompt opening with a slash command" '/bump then /cli-shakedown'
silent "prompt that is only a slash command" '/bump'

silent "generic-word deny list" 'run /status and /run now'
silent "token naming no live skill" 'see /not-a-real-skill-xyz for details'
silent "token inside a code span" 'the literal `/bump` string is what it greps for'
silent "no token at all" 'merge, pull main, install'
silent "empty prompt" ''

# ---- it can never break a prompt submission ---------------------------------
out=$(printf 'not json at all' | python3 "$HOOK" 2>"$SCRATCH/err"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "malformed payload: exits 0 and emits nothing"
else
  bad "malformed payload: rc=$rc out=${out:-empty}"
fi

out=$(printf '{"hook_event_name":"UserPromptSubmit"}' | python3 "$HOOK" 2>"$SCRATCH/err"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "payload with no prompt key: exits 0 and emits nothing"
else
  bad "payload with no prompt key: rc=$rc out=${out:-empty}"
fi

# ---- fail open on every malformed payload shape, not just the parse ---------
# `{"prompt":42}` exited 1 before its guard landed, while every other malformed
# shape exited 0. A non-zero exit from a UserPromptSubmit hook is a prompt that
# will not submit, and this hook runs on every prompt of every session.
# The OUTER payload too, not just its `prompt`. The first cut covered only
# `{"prompt": X}` and the notes claimed "the class is covered", which overstated
# it: a bare `[]`, `null`, `42` or `"x"` still exited 1 on `.get` (round 4 audit, C1).
for payload in '[]' 'null' '42' 'true' '"x"'; do
  out=$(printf '%s' "$payload" | "$HOOK" 2>/dev/null)
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    ok "fail open: bare $payload payload exits 0 and emits nothing"
  else
    bad "fail open: bare $payload payload rc=$rc out=${out:-empty}"
  fi
done

# Namespaced plugin-skill tokens. The candidate regex had no `:` while resolve.py
# resolves ONLY the `plugin:skill` form, so both directions were wrong (round 4
# audit, M1): a resolvable `/slack:read` emitted nothing, and `/babysit:bogus`
# emitted `/babysit` while claiming the tokens were "quoted verbatim from it".
# That false claim is what 0b-3a says gets an injected instruction treated as
# hostile, so the quote must always be a substring of the prompt.
out=$(run 'run /slack:read on that thread')
if printf '%s' "$out" | jq -er '.hookSpecificOutput.additionalContext | contains("`/slack:read`")' >/dev/null 2>&1; then
  ok "namespaced: /slack:read is named whole"
else
  bad "namespaced: /slack:read not named: ${out:-empty}"
fi
out=$(run 'run /babysit:bogus on it')
if [ -z "$out" ]; then
  ok "namespaced: /babysit:bogus emits nothing, never a truncated /babysit"
else
  bad "namespaced: /babysit:bogus emitted something: $out"
fi

for payload in '{"prompt":42}' '{"prompt":[]}' '{"prompt":{"a":1}}' '{"prompt":true}' '{"prompt":null}'; do
  out=$(printf '%s' "$payload" | "$HOOK" 2>/dev/null)
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    ok "fail open: $payload exits 0 and emits nothing"
  else
    bad "fail open: $payload rc=$rc out=${out:-empty}"
  fi
done

# ---- the output shape -------------------------------------------------------
out=$(run 'merge, pull main, /bump, install')
if [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" = "UserPromptSubmit" ]; then
  ok "output: hookEventName is UserPromptSubmit"
else
  bad "output: wrong hookEventName: $out"
fi
if [ "$(printf '%s' "$out" | jq -r '[.hookSpecificOutput|keys[]]|sort|join(",")')" = "additionalContext,hookEventName" ]; then
  ok "output: additionalContext only, no decision field"
else
  bad "output: unexpected keys, this hook must not decide anything: $out"
fi

# ---- the log is the only trace, so it has to carry the decision -------------
if grep -q '	INJECT	' "$INLINE_SKILL_TOKENS_LOG" && grep -q '	BAIL	starts-with-slash	' "$INLINE_SKILL_TOKENS_LOG"; then
  ok "log: records both an INJECT and a BAIL with its reason"
else
  bad "log: missing INJECT or BAIL line: $(cat "$INLINE_SKILL_TOKENS_LOG")"
fi

# ---- registration (acceptance criterion 6, repo-tree half) ------------------
# bin/hooks-resolve already fails CI on a dead hook path; this asserts the
# event and the file, which is what "registered" means for THIS hook.
cmd=$(jq -r '.hooks.UserPromptSubmit[]?.hooks[]?.command' "$SETTINGS")
if [ "$cmd" = "~/.claude/hooks/inline-skill-tokens.py" ]; then
  ok "settings.json: registered under UserPromptSubmit"
else
  bad "settings.json: UserPromptSubmit names '${cmd:-nothing}'"
fi
if [ -x "$HOOK" ]; then
  ok "settings.json: the registered file exists and is executable"
else
  bad "settings.json: $HOOK is missing or not executable"
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
