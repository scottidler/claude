#!/bin/bash
# session-recall-guard.sh: UserPromptSubmit hook that points at
# Skill(session-recall) when the prompt names a prior session.
#
# 73 sessions open by asking Claude to go find a previous session and nothing in
# the setup encoded that. The audit's prescribed trigger ("a URL, a path, or how
# do I") was measured at 38.2% of typed prompts and is NOT built. This predicate
# fires on 0.41%: 48 non-meta human prompts on Phase 2's frozen snapshot, and
# zero across all 6,843 non-human records. (Design-time figures were 46 and
# 6,820 on round 3's smaller extraction; AC2 in the design doc pins the snapshot
# figure and reconciles the two.)
#
# WIRING: registered in ~/.claude/settings.json under hooks.UserPromptSubmit on
# matcher `*`. The harness pipes the prompt payload to stdin. This hook emits
# exit 0 plus JSON on stdout carrying hookSpecificOutput.additionalContext, the
# same contract inline-skill-tokens.py uses (:183-192). It CANNOT deny, and it
# does not try: a UserPromptSubmit hook only ever adds context.
#
# CLI (run manually, no stdin needed):
#   session-recall-guard.sh --help        print this documentation
#   session-recall-guard.sh --self-test   run the fixture matrix
#                                         (session-recall-guard-test.sh, same dir)
#
# THE PREDICATE: five bails, then two triggers. The bails run FIRST and
# short-circuit, which matters because pasted diffs are the longest prompts in
# the corpus and they are exactly what the bails drop.
#
#   1. the prompt begins with `<`
#   2. the prompt begins with `Another Claude session sent a message:`
#   3. the prompt carries a fenced code block
#   4. the prompt names `clyde`
#   5. the prompt opens agent-shaped: `You are `, `Summarize this Claude Code`,
#      `Review this change for security`, `Analyze the following`
#
# Bails 1 and 2 are prefix tests on HOW THE HARNESS DELIVERS a record, not
# guesses about what a machine prompt looks like, and that is why they replaced
# a wider opener list. Together they take all 30 measured false fires to 0 and
# leave human fires unchanged; all 30 suppressed records were read (task
# notifications, bash stdout, agent deliveries) and none was a genuine recall
# ask. Bail 1 costs no slash command: Phase 0's probe 3 measured the live
# `prompt` value for `/doctor`, for a nonexistent command and for a command with
# arguments, and all three arrive as raw pre-expansion text. The `<command-*>`
# wrapper is a transcript artifact, so there is no `<command-` carve-out here.
#
# Bail 4 is case-insensitive and drops 29 records. Naming the tool makes the
# HOOK INJECTION redundant, not the skill: all 29 were read, 13 reached the MCP
# tools, 10 the CLI, 6 neither and all 6 accounted for.
#
# Bail 3 is ONE clause, deliberately. An earlier form also tested for `const `,
# `&str` and ">3 lines starting +". Measured with bails 1, 2, 4 and 5 in place,
# fence-only and the full four-part form score identically (46 non-meta human /
# 0 false on round 3's extraction), so the Rust literals and the diff-line count
# are dead weight.
# Dropping the fence clause entirely DOES move the number, to 49, and its 12
# suppressed records are 9 skill preambles, 2 summarizer prompts and 1
# compaction continuation. So it earns its place by suppressing MACHINE
# RECORDS, not by catching humans who paste code.
#
# THE ID ARM is the regex below, verbatim from the design doc. The lookarounds
# exclude `/`, any word character, `-`, `"` and `'`. That is load-bearing: the
# prose form "not adjacent to /, \" or '" omits `\w` and `-` and scores 50
# rather than 46. The test separates a session id from a string literal
# (`const SID: &str = "9d4c1f28-..."`) and from `image-cache/<uuid>/1.png`. A
# naive match scores 849; this scores 154 before the bails.
#
# THE PHRASE ARM is enumerated rather than described, because an unenumerated
# list is unreproducible and this is the arm Phase 0 existed to decide:
#   previous|last|prior|earlier  followed by  session|conversation|chat
#   the session where
#   that doc|design|spec  we  wrote|made|did
# "yesterday" is NOT in it: 14 of its fires are diff text and it names no
# target. Both arms ship. Phase 0 measured both against the injection policy
# and neither drew a refusal, so the id-only 38 branch is not taken.
#
# THE EMITTED TEXT names Skill(session-recall), never a raw clyde tool name.
# The clyde MCP tools are deferred, so `mcp__clyde__session_grep` in an injected
# line is a name the session cannot call until something runs ToolSearch, and
# the skill already owns that step. Naming the tools in both places would also
# be two copies of one fact that drift (rules/taste.md: a derived field).
#
# THE TRIGGER IS QUOTED VERBATIM, never a count and never a paraphrase, and the
# text carries an explicit DECLINE branch. Both come from measurement, not
# style: 0b-3a recorded the model refusing an injected line that referenced
# nothing the user had typed ("Flagging per prompt-injection policy rather than
# acting on it"), and there is no provenance field in the payload (seven keys at
# 2.1.276: cwd, hook_event_name, permission_mode, prompt, prompt_id, session_id,
# transcript_path), so this hook cannot tell a typed prompt from a
# harness-submitted one. The decline branch is load-bearing rather than polite.
#
# NO STATE. The hook is a pure function of the prompt string: no cache, no
# ledger, no file. Nothing to clean up, unlike chunk D's ledger.
#
# FAILING OPEN: an empty or unparseable payload emits nothing and exits 0. The
# failure mode of a raising UserPromptSubmit hook is a prompt that will not
# submit, and this hook only ever ADDS context, so going quiet costs exactly the
# feature and nothing else.
#
# PROVENANCE: docs/design/2026-09-17-session-recall.md, phase 2. Harness facts
# in docs/design/2026-09-17-session-recall-phase0/evidence.md.
set -uo pipefail
export LC_ALL=C

case "${1:-}" in
  -h|--help)
    # Print the leading comment block (this documentation), sans shebang.
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit 0
    ;;
  --self-test)
    exec bash "$(dirname "$(readlink -f "$0")")/session-recall-guard-test.sh"
    ;;
esac

# The id arm, verbatim from the design doc. Case-sensitive on purpose: the
# character class is literally [0-9a-f], and a `-i` would widen it.
UUID_RE='(?<![/\w\-"'"'"'])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![/\w\-"'"'"'])'
# The phrase arm, case-insensitive: these are prose fragments and a prompt
# opening "Previous session..." is the same ask as a mid-sentence one.
PHRASE_RE='(previous|last|prior|earlier)\s+(session|conversation|chat)|the session where|that (doc|design|spec) we (wrote|made|did)'

emit() { # emit <quoted trigger>
  local ctx
  ctx="session-recall hook: this prompt names a prior session, quoted verbatim from it: $1.

Decide from the prompt's own wording:
- asking about that session's content (what was decided, what was built, where a file went) -> resolve it with \`Skill(session-recall)\` before answering, and cite \`path:line\`.
- naming it in passing (a statistic, an aside, a session you are already reading) -> resolve nothing. This line is context, not an order."
  jq -n --arg ctx "$ctx" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
  exit 0
}

PAYLOAD=$(cat)
PROMPT=$(printf '%s' "$PAYLOAD" \
  | jq -r 'if type == "object" and (.prompt | type) == "string" then .prompt else "" end' 2>/dev/null)
[ -n "$PROMPT" ] || exit 0

# Bails 1, 2, 3 and 5. Pure bash pattern matches, no subprocess.
case "$PROMPT" in
  '<'*) exit 0 ;;
  'Another Claude session sent a message:'*) exit 0 ;;
  *'```'*) exit 0 ;;
  'You are '*) exit 0 ;;
  'Summarize this Claude Code'*) exit 0 ;;
  'Review this change for security'*) exit 0 ;;
  'Analyze the following'*) exit 0 ;;
esac

# Bail 4, case-insensitive, still no subprocess.
LOWER=${PROMPT,,}
case "$LOWER" in
  *clyde*) exit 0 ;;
esac

QUOTED=$(printf '%s' "$PROMPT" | grep -oP "$UUID_RE" | head -1)
[ -n "$QUOTED" ] && emit "$QUOTED"

QUOTED=$(printf '%s' "$PROMPT" | grep -oiP "$PHRASE_RE" | head -1)
[ -n "$QUOTED" ] && emit "$QUOTED"

exit 0
