#!/bin/bash
# emdash.sh: PreToolUse hook that DENIES a literal em-dash (U+2014) at the tool
# boundary, before it reaches a file, a commit message, a PR body or an outward
# post. The ban is in writing in rules/safety.md (plus voice.md, edges.md and
# nine SKILL.md files) and the 2026-09-12 audit measured it in 31% of September
# assistant turns anyway: 2,926 Write/Edit calls, 2,206 Bash commands and 423
# tool inputs carried the character AFTER the rule landed. This is the layer
# that cannot be forgotten.
#
# WIRING: registered in ~/.claude/settings.json on three PreToolUse matchers:
#   Write|Edit|MultiEdit|NotebookEdit                      written content
#   Bash                                                   commit and gh bodies
#   mcp__slack__* | mcp__atlassian__* | mcp__marquee__*    outward posts
# The harness pipes the tool-call JSON to stdin before the call runs; this
# script prints {} to allow, or a deny decision whose reason the agent sees
# verbatim.
#
# CLI (run manually, no stdin needed):
#   emdash.sh --help        print this documentation
#   emdash.sh --self-test   run the fixture matrix (emdash-test.sh, same dir)
#
# THE PREDICATE: any literal U+2014 in the scanned strings is a deny. The escape
# forms \u{2014} and \x{2014} are the SUBSTITUTE for the literal (safety.md:28),
# never a companion to it, so their presence exempts nothing: a payload carrying
# both is still denied. There is no quoting exemption: a verbatim excerpt that
# needs the character is recast, or it is written under a path in the allowlist.
#
# WHAT IS SCANNED, per tool:
#   Write         content
#   Edit          new_string           (old_string is what is being REMOVED)
#   MultiEdit     edits[].new_string
#   NotebookEdit  new_source
#   Bash          the whole command, heredoc bodies INCLUDED, but only when an
#                 outward stage is present: git commit, gh pr create/edit/
#                 comment, gh issue, or gh api ... comments. So `rg` for the
#                 character passes and `git commit -m` carrying it does not.
#   mcp__*        every string value in tool_input, at any depth
#
# PATH ALLOWLIST, the only carve-out: tests/fixtures/, *.golden, *.json.
#
# MECHANICS: the Bash branch strips heredoc bodies BEFORE looking for an outward
# stage (a commit message line reading "git commit" is prose, not a command),
# then splits on && || ; | and newlines. Same shape as git-release-guard.sh,
# whose stripper this is a copy of. Stage detection runs on the stripped text;
# the character scan runs on the RAW command, because the message body is
# exactly where the character lives.
#
# FAILING OPEN: an empty or unparseable payload prints {} plus one stderr line.
# A guard that cannot read its input must not wedge the session.
#
# This file carries no literal U+2014: the character is built from its bash
# escape, or the hook would deny its own source (rules/safety.md).
#
# PROVENANCE: docs/design/2026-09-13-enforcement-core.md, phase 3. Harness facts
# in docs/design/2026-09-13-enforcement-core-phase0/evidence.md (0b: the
# Write|Edit|MultiEdit|NotebookEdit matcher fires on Write and on Edit, and not
# on Read; the payload carries tool_name and tool_input).

case "${1:-}" in
  -h|--help)
    # Print the leading comment block (this documentation), sans shebang.
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit 0
    ;;
  --self-test)
    exec bash "$(dirname "$0")/emdash-test.sh"
    ;;
esac

# The banned character itself, built from its escape so this file carries no
# literal U+2014 (rules/safety.md: the escape is the substitute, never a
# companion).
EMDASH=$'\u2014'

# An outward stage: the forms whose text leaves this machine under Scott's name.
# `git -c k=v` and `git -C <dir>` may sit between `git` and `commit`.
OUTWARD='(^|[^[:alnum:]_/-])git([[:space:]]+-[cC][[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)|(^|[^[:alnum:]_/-])gh[[:space:]]+pr[[:space:]]+(create|edit|comment)([[:space:]]|$)|(^|[^[:alnum:]_/-])gh[[:space:]]+issue([[:space:]]|$)|(^|[^[:alnum:]_/-])gh[[:space:]]+api\b.*comments'

allow() { echo '{}'; exit 0; }
deny()  {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
note()  { printf 'emdash.sh: %s\n' "$1" >&2; }

# Truncate through jq, which slices by CODEPOINT. Bash substring and `cut -c`
# count bytes under a C locale and would hand jq a split multibyte character,
# which is exactly the case this hook always hits.
head_chars() { printf '%s' "$1" | jq -Rr ".[0:$2]" 2>/dev/null; }

input=$(cat)
[ -z "$input" ] && { note "empty payload, failing open"; allow; }

field() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

tool=$(field '.tool_name // ""')
[ -z "$tool" ] && { note "no tool_name in the payload, failing open"; allow; }

reason() {  # reason <field-label> <offending-line>
  printf '%s' "em-dash (U+2014) in $1; recast with a colon, parens, comma, or a split sentence (rules/safety.md). The offending text: \"$(head_chars "$2" 200)\""
}

# ---- path allowlist -------------------------------------------------------
# Verbatim material that must keep the character lives under a fixtures path, a
# golden file, or JSON data. Everything else is prose the rule owns.
path=$(field '.tool_input.file_path // .tool_input.notebook_path // ""')
case "$path" in
  tests/fixtures/*|*/tests/fixtures/*|*.golden|*.json) allow ;;
esac

# ---- Bash: outward stages only -------------------------------------------
# Heredoc bodies are NOT statements: a commit message line that happens to read
# "git commit" is prose (the same false positive that denied an innocent commit
# in otto-rs/otto b428680). Strip them before deciding whether an outward stage
# exists, then scan the RAW command, bodies included.
strip_heredocs() {
  awk '
  BEGIN {
    n = 0
    PH = sprintf("%c", 1)                 # placeholder: neutralize <<< herestrings
    SQ = sprintf("%c", 39)
    RE = "<<-?[ \t]*(\"[^\"]*\"|" SQ "[^" SQ "]*" SQ "|[A-Za-z_][A-Za-z0-9_-]*)"
  }
  {
    line = $0
    if (n > 0) {                          # inside a heredoc body: find its terminator
      t = line
      if (dash[1]) sub(/^[ \t]+/, "", t)  # <<- allows an indented terminator
      sub(/[ \t]+$/, "", t)
      if (t == delim[1]) {
        for (i = 1; i < n; i++) { delim[i] = delim[i+1]; dash[i] = dash[i+1] }
        n--
      }
      next                                # body and terminator are never statements
    }
    rest = line
    gsub(/<<</, PH, rest)
    while (match(rest, RE)) {             # queue every opener on this line, in order
      tok = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
      n++
      dash[n] = (substr(tok, 3, 1) == "-") ? 1 : 0
      w = tok
      sub(/^<<-?[ \t]*/, "", w)
      gsub(/"/, "", w)
      gsub(SQ, "", w)
      delim[n] = w
    }
    print line
  }'
}

if [ "$tool" = "Bash" ]; then
  cmd=$(field '.tool_input.command // ""')
  [ -z "$cmd" ] && allow
  stages=$(printf '%s\n' "$cmd" | strip_heredocs | sed -E 's/&&/\n/g; s/\|\|/\n/g; s/;/\n/g; s/\|/\n/g')
  printf '%s\n' "$stages" | grep -Eq "$OUTWARD" || allow
  printf '%s' "$cmd" | grep -qF "$EMDASH" || allow
  line=$(printf '%s\n' "$cmd" | grep -F -m1 "$EMDASH")
  deny "$(reason "the Bash command (it carries a git commit / gh stage, so this text leaves the machine)" "$line")"
fi

# ---- everything else: a label plus the string it names --------------------
case "$tool" in
  Write)        SEL='[{label:"Write content",              text:(.tool_input.content    // "")}]' ;;
  Edit)         SEL='[{label:"Edit new_string",            text:(.tool_input.new_string // "")}]' ;;
  NotebookEdit) SEL='[{label:"NotebookEdit new_source",    text:(.tool_input.new_source // "")}]' ;;
  MultiEdit)    SEL='[ (.tool_input.edits // []) | to_entries[]
                       | {label:("MultiEdit edits[\(.key)].new_string"),
                          text:(.value.new_string // "")} ]' ;;
  mcp__*)       SEL='[ .tool_input | paths(type=="string") as $p
                       | {label:("\($tool) " + ($p|map(tostring)|join("."))),
                          text:getpath($p)} ]' ;;
  *)            allow ;;
esac

FILTER='map(select((.text|type)=="string" and (.text|contains($d))))
        | first
        | if . == null then empty
          else {label:.label, line:([.text|split("\n")[]|select(contains($d))]|first)}
          end'

hit=$(printf '%s' "$input" | jq -c --arg d "$EMDASH" --arg tool "$tool" "$SEL | $FILTER" 2>/dev/null)
[ -z "$hit" ] && allow

label=$(printf '%s' "$hit" | jq -r '.label')
line=$(printf '%s' "$hit" | jq -r '.line')
deny "$(reason "$label" "$line")"
