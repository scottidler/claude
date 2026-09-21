#!/bin/bash
# handoff-guard.sh: UserPromptSubmit hook that grounds a session in the handoff
# it is supposed to be resuming from.
#
# 95 sessions open by pasting a handoff path by hand (rising: Jun 10, Jul 39,
# Aug 17, Sep 29) and 265 resumption gaps over six hours were measured in 215
# sessions. Nothing in the setup pointed at the handoff, because chunk E proved
# there is no way to make a hook FIRE a skill: `$.skill.*` does not exist and
# `$.command.run` is refused from `prompt.submit`. So this is a grounding hook,
# not a trigger, the same shape F1 shipped as `session-recall-guard.sh`. It adds
# context; the model invokes.
#
# WIRING: registered in ~/.claude/settings.json under hooks.UserPromptSubmit on
# matcher `*`, third in the chain after inline-skill-tokens.py and
# session-recall-guard.sh. Exit 0 plus JSON on stdout carrying
# hookSpecificOutput.additionalContext. It cannot deny and does not try.
#
# CLI (run manually, no stdin needed):
#   handoff-guard.sh --help        print this documentation
#   handoff-guard.sh --self-test   run the fixture matrix
#                                  (handoff-guard-test.sh, same dir)
#
# TWO FIRES.
#
# Fire 1, the prompt asks to resume from a handoff. NOT the bare glob
# `*handoff*.md`: the design doc that specified this hook is itself named
# `2026-09-18-handoff-and-waiting-discipline.md`, so a naive predicate injects
# "invoke the handoff skill in resume mode" into any prompt that reviews it.
# Two things keep that out. A path under a `docs/design/` directory is a design
# doc and is excluded mechanically, and the emitted text carries an explicit
# decline branch, which is `session-recall-guard.sh:121`'s request-versus-
# reference discrimination reused rather than re-derived.
#
# Fire 2, a handoff for this branch exists and is NEWER than the last commit.
# `docs/handoff/<branch>.md` versus `git log -1 --format=%ct`. This is the fire
# that justifies a hook at all: prose can ask the model to remember to look,
# only a hook can stat the file. Mtime beats content: a handoff written and then
# committed has an mtime at or before HEAD's commit time, so committing the
# handoff with the work is what turns this fire off, which is the behaviour we
# want.
#
# BAILS, run first, same family as F1's for the same measured reason (pasted
# diffs and machine deliveries are the false-fire population):
#   1. the prompt begins with `<`
#   2. the prompt begins with `Another Claude session sent a message:`
#   3. the prompt carries a fenced code block
#   4. the prompt opens agent-shaped: `You are `, `Summarize this Claude Code`,
#      `Review this change for security`, `Analyze the following`
# The bails suppress fire 1 only. Fire 2 is a fact about the filesystem, not
# about the prompt, so a machine-delivered prompt in a repo with a fresh handoff
# still gets grounded.
#
# SILENT, exit 0, no output, for fire 2 in three cases: cwd is not a git repo,
# HEAD is detached (no branch name to key on), or the repo has no commits so
# `git log -1` fails. Fire 1 still works in all three, since it reads only the
# prompt.
#
# NO STATE. A pure function of the prompt plus two filesystem reads. No cache,
# no ledger, nothing to clean up.
#
# FAILING OPEN: an empty or unparseable payload emits nothing and exits 0. A
# raising UserPromptSubmit hook is a prompt that will not submit, and this hook
# only ever ADDS context, so going quiet costs exactly the feature.
#
# PROVENANCE: docs/design/2026-09-18-handoff-and-waiting-discipline.md, phase 3.
set -uo pipefail
export LC_ALL=C

case "${1:-}" in
  -h|--help)
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit 0
    ;;
  --self-test)
    exec bash "$(dirname "$(readlink -f "$0")")/handoff-guard-test.sh"
    ;;
esac

emit() { # emit <context text>
  jq -n --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
  exit 0
}

PAYLOAD=$(cat)
PROMPT=$(printf '%s' "$PAYLOAD" \
  | jq -r 'if type == "object" and (.prompt | type) == "string" then .prompt else "" end' 2>/dev/null)
CWD=$(printf '%s' "$PAYLOAD" \
  | jq -r 'if type == "object" and (.cwd | type) == "string" then .cwd else "" end' 2>/dev/null)

# ---- Fire 1: the prompt names a handoff document -------------------------
fire1_path=""
if [ -n "$PROMPT" ]; then
  bail=0
  case "$PROMPT" in
    '<'*) bail=1 ;;
    'Another Claude session sent a message:'*) bail=1 ;;
    *'```'*) bail=1 ;;
    'You are '*) bail=1 ;;
    'Summarize this Claude Code'*) bail=1 ;;
    'Review this change for security'*) bail=1 ;;
    'Analyze the following'*) bail=1 ;;
  esac
  if [ "$bail" -eq 0 ]; then
    # A path-shaped token ending in .md whose basename carries `handoff`, with
    # any `docs/design/...` path excluded: this hook's own design doc lives
    # there and matches the basename test.
    fire1_path=$(printf '%s' "$PROMPT" \
      | grep -oiP '(?<![\w/.-])[\w./-]*handoff[\w./-]*\.md\b' \
      | grep -viP '(^|/)docs/design/' \
      | head -1)
  fi
fi

if [ -n "$fire1_path" ]; then
  emit "handoff hook: this prompt names a handoff document, quoted verbatim from it: $fire1_path.

Decide from the prompt's own wording:
- asking to resume, continue, or pick up that work -> read it, then run \`Skill(handoff)\`, which will put you in RESUME mode: do the work, re-test every blocker it claims with a command, and do NOT write a second handoff.
- naming it in passing (reviewing it, editing it, quoting it, asking where it lives) -> resolve nothing. This line is context, not an order."
fi

# ---- Fire 2: a handoff for this branch is newer than HEAD ----------------
[ -n "$CWD" ] || exit 0
[ -d "$CWD" ] || exit 0

branch=$(git -C "$CWD" symbolic-ref --quiet --short HEAD 2>/dev/null) || exit 0
[ -n "$branch" ] || exit 0

root=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$root" ] || exit 0

doc="$root/docs/handoff/$branch.md"
[ -f "$doc" ] || exit 0

head_ct=$(git -C "$CWD" log -1 --format=%ct 2>/dev/null) || exit 0
[ -n "$head_ct" ] || exit 0

doc_mt=$(stat -c %Y -- "$doc" 2>/dev/null) || exit 0
[ -n "$doc_mt" ] || exit 0

if [ "$doc_mt" -gt "$head_ct" ]; then
  rel="docs/handoff/$branch.md"
  emit "handoff hook: $rel is newer than the last commit on \`$branch\`, so work was handed off after that commit and has not been picked up yet.

Read it before doing anything else, then run \`Skill(handoff)\`, which will put you in RESUME mode: do the work it names, re-test every blocker it claims with a command before believing it, and do NOT write a second handoff. If the user's prompt is plainly unrelated to that work, say in one line that the handoff is outstanding and carry on with what they asked."
fi

exit 0
