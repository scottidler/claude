#!/bin/bash
# session-recall-guard-test.sh: fixture matrix for session-recall-guard.sh.
#
# Each case feeds the hook a `UserPromptSubmit` payload on stdin and asserts on
# the outcome: BAIL is exit 0 with EMPTY stdout, FIRE is exit 0 plus the doc's
# emitted text with the trigger interpolated verbatim. This hook cannot deny, so
# there are no deny-style fixtures; fire-or-bail plus the exact emitted string
# is the whole contract.
#
# The ten classes the design doc's acceptance criterion 1 enumerates are labelled
# `class N` below, in its order:
#   1 id paste (fires)                       6 fenced block carrying an id (bails)
#   2 phrase-only (fires)                    7 prompt naming clyde (bails)
#   3 quoted UUID in a diff (bails)          8 `You are ...` summarizer (bails)
#   4 `image-cache/` UUID (bails)            9 leading `<` tag (bails)
#   5 "yesterday" in diff text (bails)      10 `Another Claude...` wrapper (bails)
#
# Everything after the ten classes is the edge work each clause needs to stay
# honest: the lookaround set one character at a time, the case behaviour of each
# arm, the remaining two agent-shaped openers, and the malformed payloads that
# have to fail OPEN rather than wedge a prompt.
#
# No `shapes.sh` sweep. Its templates wrap a COMMAND WORD in shell; this hook
# consumes a prompt string, so there is no command word and no shell to wrap.
set -u
export LC_ALL=C

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
HOOK="$HOOKS/session-recall-guard.sh"
pass=0
fail=0

# The emitted text, built once here from the design doc's `Emitted text` section.
# A drift between the hook's copy and this one is the failure this asserts.
want_context() { # want_context <quoted trigger>
  printf '%s' "session-recall hook: this prompt names a prior session, quoted verbatim from it: $1.

Decide from the prompt's own wording:
- asking about that session's content (what was decided, what was built, where a file went) -> resolve it with \`Skill(session-recall)\` before answering, and cite \`path:line\`.
- naming it in passing (a statistic, an aside, a session you are already reading) -> resolve nothing. This line is context, not an order."
}

feed() { # feed <prompt>
  jq -n --arg p "$1" \
    '{cwd:"/home/saidler/repos/scottidler/claude",hook_event_name:"UserPromptSubmit",permission_mode:"auto",prompt:$p,prompt_id:"test",session_id:"test",transcript_path:"/dev/null"}' \
    | bash "$HOOK" 2>/dev/null
  return "${PIPESTATUS[1]}"
}

ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); printf 'FAIL  %s\n' "$1"; }

bails() { # bails <label> <prompt>
  local label="$1" prompt="$2" out rc
  out=$(feed "$prompt")
  rc=$?
  if [ "$rc" -ne 0 ]; then
    bad "$label: exit $rc, want 0"
    return
  fi
  if [ -n "$out" ]; then
    bad "$label: wanted no fire, got stdout: ${out:0:120}"
    return
  fi
  ok
}

fires() { # fires <label> <prompt> <expected quoted trigger>
  local label="$1" prompt="$2" quoted="$3" out rc event got
  out=$(feed "$prompt")
  rc=$?
  if [ "$rc" -ne 0 ]; then
    bad "$label: exit $rc, want 0"
    return
  fi
  if [ -z "$out" ]; then
    bad "$label: wanted a fire, got no stdout"
    return
  fi
  event=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // "missing"')
  if [ "$event" != "UserPromptSubmit" ]; then
    bad "$label: hookEventName is '$event', want UserPromptSubmit"
    return
  fi
  got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""')
  if [ "$got" != "$(want_context "$quoted")" ]; then
    bad "$label: additionalContext is not the doc's emitted text"
    printf '  got:  %s\n' "$got"
    printf '  want: %s\n' "$(want_context "$quoted")"
    return
  fi
  ok
}

SID='0aa23bbf-8c16-4fc0-bf57-b18649f8542e'

echo "=== the ten classes from acceptance criterion 1 ==="

# class 1: an id pasted into a question about that session.
fires 'class 1, id paste' \
  "what did we decide in session $SID about the always-on rules budget?" "$SID"

# class 2: the phrase arm alone, naming no id at all. Phase 0 measured this arm
# against the injection policy and it drew no refusal, so it ships.
fires 'class 2, phrase only' \
  'pull up the session where we argued about the panel round cap' 'the session where'

# class 3: a UUID inside a quoted string literal in a pasted diff. The `"` in the
# lookaround set is what bails this, NOT the fence clause: there is no fence here.
bails 'class 3, quoted UUID in a diff' \
  "-    const SID_SHARED: &str = \"9d4c1f28-3f77-4a1e-9f0e-2b5a6c8d1e4f\";
+    const SID_SHARED: &str = \"$SID\";"

# class 4: a path-embedded UUID. The `/` in the lookaround set bails it, and this
# is the single case that separates 154 matches from 849.
bails 'class 4, image-cache path UUID' \
  "look at image-cache/$SID/1.png and tell me what changed"

# class 5: "yesterday" is deliberately NOT in the phrase list: 14 of its fires
# are diff text and it names no target.
bails 'class 5, yesterday in diff text' \
  '+  // regenerated yesterday, do not hand-edit
-  // regenerated yesterday by the old script
 unchanged line about yesterday'

# class 6: a fenced block carrying an id. The fence clause earns its place by
# suppressing machine records (9 skill preambles, 2 summarizer prompts, 1
# compaction continuation), and dropping it moves the corpus count 46 -> 49.
bails 'class 6, fenced block carrying an id' \
  "here is the log I was reading

\`\`\`
2026-09-18T06:44:01Z session $SID resumed
\`\`\`"

# class 7: naming the tool makes the HOOK INJECTION redundant, not the skill.
bails 'class 7, prompt naming clyde' \
  "clyde session search $SID and tell me what we decided"

# class 8: the provenance-summarizer opener, one of bail 5's four literals.
bails 'class 8, You are ... summarizer' \
  "You are a session summarizer. Summarize the session $SID in one line."

# class 9: bail 1. Tagged records demonstrably reach UserPromptSubmit: the live
# inline-skill-tokens log carries 54 of them.
bails 'class 9, leading tag' \
  "<task-notification> <task-id>b0dj9lrhl</task-id> monitor fired on session $SID"

# class 10: bail 2. The harness prepends this sentence BEFORE the tag, so a
# leading-`<` test alone misses all 2,351 of them.
bails 'class 10, Another Claude session wrapper' \
  "Another Claude session sent a message:
<agent-message from=\"a367fe50\"> look at session $SID </agent-message>"

echo "=== the id arm's lookaround set, one character at a time ==="
bails 'slash before'        "see cache/$SID for the blob"
bails 'slash after'         "see $SID/1.png for the blob"
bails 'double quote before' "the literal \"$SID is what broke"
bails 'double quote after'  "the literal $SID\" is what broke"
bails 'single quote before' "the literal '$SID is what broke"
bails 'single quote after'  "the literal $SID' is what broke"
bails 'hyphen before'       "run-$SID is the job name"
bails 'hyphen after'        "$SID-retry is the job name"
bails 'word char before'    "ffff$SID names nothing"
bails 'word char after'     "${SID}ffff names nothing"
bails 'underscore before'   "job_$SID names nothing"
bails 'underscore after'    "${SID}_retry names nothing"
fires 'space on both sides' "session $SID please" "$SID"
fires 'parenthesised'       "the audit session ($SID) had the number" "$SID"
fires 'sentence-final'      "what changed in $SID." "$SID"
fires 'comma-separated'     "compare $SID, then stop" "$SID"

echo "=== the id arm is case-sensitive: the doc's class is literally [0-9a-f] ==="
bails 'uppercase id'        "what did we decide in 0AA23BBF-8C16-4FC0-BF57-B18649F8542E"
bails 'too short'           "what did we decide in 0aa23bbf-8c16-4fc0-bf57-b18649f854"
bails 'non-hex'             "what did we decide in 0aa23bzz-8c16-4fc0-bf57-b18649f8542e"

echo "=== the phrase arm is case-insensitive: these are prose fragments ==="
fires 'phrase, sentence case'  'Previous session had the answer, find it' 'Previous session'
fires 'phrase, shouted'        'THAT WAS A COPY AND PASTE FROM THE PREVIOUS SESSION' 'PREVIOUS SESSION'
fires 'phrase, last chat'      'dig up the last chat where we sized this' 'last chat'
fires 'phrase, prior conv'     'the prior conversation had the version number' 'prior conversation'
fires 'phrase, earlier session' 'what did the earlier session say about bump' 'earlier session'
fires 'phrase, that doc we wrote' 'find that design we wrote about hooks' 'that design we wrote'
bails 'phrase, no noun'        'what was the last thing you said'
bails 'phrase, no adjective'   'this session is fine as it is'
bails 'phrase, wrong verb'     'that doc we argued about is stale'

echo "=== bail 5's remaining two openers, and bail 4's case folding ==="
bails 'Summarize this Claude Code' "Summarize this Claude Code session $SID in one line"
bails 'Analyze the following'      "Analyze the following transcript from $SID"
bails 'clyde capitalised'          "Clyde had the session $SID indexed"
bails 'clyde uppercase'            "CLYDE indexed $SID"
bails 'clyde mid-word'             "the clydeish index has $SID"
fires 'opener is not a prefix'     "tell me what you are doing with $SID" "$SID"

echo "=== the id arm wins when both arms match, and the quote stays verbatim ==="
fires 'both arms, id quoted' \
  "the session where we landed this is $SID, what did it say" "$SID"
fires 'first id of several' \
  "compare $SID with 1b7f9e21-0c4a-4d3b-8e6f-5a2c9d7b0e13" "$SID"

echo "=== failing open: a malformed payload emits nothing and exits 0 ==="
malformed() { # malformed <label> <raw stdin>
  local label="$1" raw="$2" out rc
  out=$(printf '%s' "$raw" | bash "$HOOK" 2>/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    bad "$label: exit $rc, want 0"
    return
  fi
  if [ -n "$out" ]; then
    bad "$label: wanted no fire, got stdout: ${out:0:120}"
    return
  fi
  ok
}
malformed 'empty stdin'        ''
malformed 'not json'           'this is not json at all'
malformed 'bare array'         '[]'
malformed 'bare null'          'null'
malformed 'bare number'        '42'
malformed 'bare string'        '"x"'
malformed 'no prompt key'      '{"hook_event_name":"UserPromptSubmit"}'
malformed 'prompt is a number' '{"prompt":42}'
malformed 'prompt is null'     '{"prompt":null}'
malformed 'prompt is an object' '{"prompt":{"text":"session 0aa23bbf-8c16-4fc0-bf57-b18649f8542e"}}'
malformed 'prompt is empty'    '{"prompt":""}'

echo "=== the CLI surface ==="
if bash "$HOOK" --help | head -1 | grep -q 'session-recall-guard.sh: UserPromptSubmit hook'; then
  ok
else
  bad '--help does not print the documentation block'
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
