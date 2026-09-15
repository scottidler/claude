#!/bin/bash
# panel-round-guard.sh: PreToolUse(Agent) guard: a review-panel round past the
# cap is DENIED, not discouraged.
#
# rules/interaction.md capped panel rounds at 3 on 2026-09-08. The cap was
# prose and prose did not hold: 10 of 19 measured runs blew it, one reached 14,
# with zero prompts from Scott. One parent wrote in its own transcript
# "Tenth crossing, and I am not going to tell Scott". This is the hook.
#
# WIRING: PreToolUse on matcher `Agent`, narrowed to
# tool_input.subagent_type == "review-panel". Everything else allows before any
# other work. The seam is the Agent DISPATCH and not the seat scripts, for two
# measured reasons: review-panel.md:79-83 mints a fresh $RUN_DIR per dispatch
# (272 of 328 historical run dirs were single-round), so a per-run-dir counter
# reads zero on round 4; and the seat scripts run INSIDE the panel subagent,
# whose final turn is measured as not reaching its caller, while the party that
# overruns IS the caller. Phase 0 proved the Agent payload carries
# subagent_type, prompt and cwd, and that a deny here blocks the dispatch and
# lands its text in the caller's context.
#
# THE KEY is (doc, mode), not doc alone. A doc gets its design-review rounds
# before it is built and its implementation-audit rounds after, and
# review-panel.md:90 Step 1.2 already distinguishes them by the doc's Status
# line. Keyed on the doc alone, a doc that used all 3 design rounds would have
# its first implementation audit denied at dispatch.
#
# THE COUNTER lives at ~/.cache/review-panel/rounds/ (PANEL_ROUND_CACHE_DIR
# overrides it, which is how the test matrix stays out of the user's cache).
# Plain text, three lines, so it is debuggable with `cat`. /tmp was rejected:
# it is tmpfs here and every counter would die at reboot. The increment is a
# read-modify-write with no lock: two dispatches racing on one (doc, mode) can
# both read 2 and both write 3, costing one extra round, once. Stated so no
# reader assumes atomicity.
#
# THE DOOR (mirroring git-release-guard.sh:75's BUMP_ORDERED_BY_SCOTT, Scott
# approved 2026-07-10) is PANEL_ROUNDS_ORDERED_BY_SCOTT=<n> in the dispatch
# prompt. It must be a NONBLANK LINE OF ITS OWN, matched
# ^PANEL_ROUNDS_ORDERED_BY_SCOTT=[0-9]+$, never at a word boundary anywhere in
# the prompt. The design doc this guard was built from carries that literal
# marker followed by an integer four times, in its own prose, and quoting prior
# findings is the normal shape of a round-4 prompt: an "anywhere" match would
# let the document being guarded raise its own cap, invisibly, which is exactly
# the failure this hook exists to kill. The value is a CEILING, not a boolean,
# so =5 grants five and still denies six.
#
# Honest about what the door is: visible and auditable, not unforgeable. An
# agent can type the prefix. What it cannot do is open the door without leaving
# PANEL_ROUNDS_ORDERED_BY_SCOTT=<n> in the transcript for Scott to grep. Not a
# security boundary, and nothing here should be read as one.
#
# FAIL OPEN, deliberately, against rules/taste.md's usual fail-closed default:
# an unparseable doc path allows and warns on stderr. A guard that denied what
# it cannot read would block every panel dispatch on every machine whose prompt
# it fails to parse. Phase 0 measured the extractor at 97.4% over all 348 real
# dispatches; the 2.6% miss set is entirely docless Mode 2 audits, which the
# design names as an uncapped Non-Goal.
#
# Allow is exit 0 with NO stdout (AC1/AC2 assert empty), which is why this one
# does not echo the siblings' '{}'.
#
# Debug: PANEL_ROUND_GUARD_DEBUG=1 traces every decision to stderr.
#
# Emits a PreToolUse "deny" decision (with a reason Claude sees), or nothing.

case "${1:-}" in
  -h|--help)
    # Print the leading comment block (this documentation), sans shebang.
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit 0
    ;;
  --self-test)
    exec bash "$(dirname "$0")/panel-round-guard-test.sh"
    ;;
esac

# The shared parser, sourced AFTER the CLI dispatch so --help and --self-test
# work with or without it, and fail-open so a missing library passes the
# dispatch through rather than denying every panel run in the session. Nothing
# in lib.sh is used below: it parses COMMAND text and this guard consumes a
# prompt, where there is no shell and no command word. It is sourced because
# the house contract for a hook in this directory says every hook sources it,
# and a hook that silently opted out would be the one nobody remembers to fix
# when the contract changes.
. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0

CAP_DEFAULT=3
CACHE_DIR="${PANEL_ROUND_CACHE_DIR:-$HOME/.cache/review-panel/rounds}"
# A relative override resolves against the caller's cwd, which scatters counter
# files into whatever repo is being reviewed. The round-1 audit did exactly that
# and left `bin/<sha256>` in this repo's tracked bin/ directory (2026-09-14).
# The warn is deferred because warn() is not defined until below.
CACHE_DIR_RELATIVE=""
case "$CACHE_DIR" in
  /*) ;;
  *)
    CACHE_DIR_RELATIVE="$CACHE_DIR"
    CACHE_DIR="$HOME/.cache/review-panel/rounds"
    ;;
esac

log() { # log <message>
  [ -n "${PANEL_ROUND_GUARD_DEBUG:-}" ] && printf 'panel-round-guard: %s\n' "$*" >&2
  return 0
}

warn() { # warn <message>
  printf 'panel-round-guard: %s\n' "$*" >&2
  return 0
}

if [ -n "$CACHE_DIR_RELATIVE" ]; then
  warn "PANEL_ROUND_CACHE_DIR must be an absolute path, got '$CACHE_DIR_RELATIVE'; using $CACHE_DIR"
fi

deny() { # deny <reason>
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

input=$(cat)

# The narrowing test, first and before any other work: this guard has no
# opinion about any other subagent.
subagent=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // ""' 2>/dev/null)
if [ "$subagent" != "review-panel" ]; then
  log "allow: subagent_type='$subagent' is not review-panel"
  exit 0
fi

prompt=$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""' 2>/dev/null)

# The SESSION's directory, which this hook process's cwd is not guaranteed to
# be. Same fail-open shape branch-name-guard.sh:48 uses. Mandatory here rather
# than optional: Phase 0 measured 34% of real dispatches naming a RELATIVE doc
# path that only resolves against it.
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
log "entry: subagent=review-panel cwd=$cwd prompt_bytes=${#prompt}"

# Every `<path>.md` token in the prompt, in order of appearance. `foo.md:281-288`
# yields `foo.md`, because the match ends at the extension.
md_tokens() { # md_tokens  (prompt on stdin)
  awk '{
    s = $0
    while (match(s, /[A-Za-z0-9_.\/~@+-]*\.md/)) {
      print substr(s, RSTART, RLENGTH)
      s = substr(s, RSTART + RLENGTH)
    }
  }'
}

# Lexical normalization only: `.` and empty segments drop, `..` pops. Done in
# awk rather than with realpath so the answer depends on the path string and
# not on what happens to exist on disk, which is what makes a doc that has not
# been written yet key the same way as one that has.
norm_path() { # norm_path <absolute path>
  printf '%s' "$1" | awk -F/ '{
    n = 0
    for (i = 1; i <= NF; i++) {
      p = $i
      if (p == "" || p == ".") continue
      if (p == "..") { if (n > 0) n--; continue }
      st[++n] = p
    }
    out = ""
    for (i = 1; i <= n; i++) out = out "/" st[i]
    if (out == "") out = "/"
    printf "%s", out
  }'
}

# The Phase 0 reference extractor, four steps, measured at 97.4% over all 348
# real dispatches in ~/.claude/projects. Step 2 is the one the design doc's
# sketch omits and Phase 0 added: a round-2 prompt that cites its own review log
# or implementation notes must still key on the doc, or every round after the
# first counts against a different file.
extract_doc() { # extract_doc  (prompt on stdin)
  local cands filtered pick
  cands=$(md_tokens | grep -v '^$')
  [ -z "$cands" ] && return 1
  filtered=$(printf '%s\n' "$cands" | grep -Ev -- '(-review-log\.md|-implementation-notes\.md)$')
  [ -n "$filtered" ] && cands="$filtered"
  pick=$(printf '%s\n' "$cands" | grep -m1 -E '(^|/)design/')
  [ -z "$pick" ] && pick=$(printf '%s\n' "$cands" | head -1)
  [ -z "$pick" ] && return 1
  case "$pick" in
    "~") pick="$HOME" ;;
    "~/"*) pick="$HOME/${pick#\~/}" ;;
  esac
  case "$pick" in
    /*) ;;
    *) pick="$cwd/$pick" ;;
  esac
  norm_path "$pick"
}

doc=$(printf '%s\n' "$prompt" | extract_doc)
if [ -z "$doc" ]; then
  warn "no .md path found in the dispatch prompt; allowing this round uncounted"
  exit 0
fi

# review-panel.md:90 Step 1.2's test, anchored to a Status LINE rather than run
# as a substring search over the whole file. Same defect class as the door: the
# design doc this guard enforces discusses `Status: Implemented` in its own
# prose twice, so a "contains" test reads an In Review doc as Mode 2 and hands
# it a second set of three rounds. An unreadable or absent doc is Mode 1.
# Scoped to the doc's METADATA BLOCK, everything above the first `## ` heading,
# not the whole file. Audit round 1 (2026-09-14) probed the whole-file read and
# found an In Review doc with a fenced `Status: Implemented` example keying as
# Mode 2. That is worse than a cosmetic miss: the key then fails to change when
# the status genuinely flips, so the first implementation audit inherits the
# exhausted design-review counter and is denied at dispatch.
# Deliberately NOT anchored at the end: `Status: Implemented with a follow-up
# owed` (enforcement-core.md) has to keep reading as Mode 2.
mode=1
if [ -f "$doc" ] && awk '/^## /{exit} {print}' "$doc" \
   | grep -qE '^[[:space:]]*(\*\*)?Status(\*\*)?:(\*\*)?[[:space:]]*Implemented'; then
  mode=2
fi

key=$(printf '%s\n%s' "$doc" "$mode" | sha256sum | awk '{print $1}')
entry="$CACHE_DIR/$key"

rounds=0
if [ -f "$entry" ]; then
  rounds=$(sed -n 's/^rounds=\([0-9][0-9]*\)$/\1/p' "$entry" | head -1)
  case "$rounds" in ''|*[!0-9]*) rounds=0 ;; esac
fi

# The door: a nonblank line of its own, nothing else on it. See the header for
# why a word-boundary match anywhere in the prompt is a defect and not a
# simplification. A trailing CR is stripped so a CRLF prompt is not a silent
# no-door.
# Fenced code blocks are MASKED OUT before the match. This is the
# git-release-guard.sh:298-310 precedent the design doc cites, which reads its
# own marker off a masked copy "so the marker cannot open the door from inside
# a commit message". The same class bites here and audit round 1 (2026-09-14)
# proved it: the doc this guard enforces carries the marker at column 1 inside
# a fence at :165, so a round-4 prompt that quoted the doc's own door section
# raised the cap from 3 to 5. The document was opening its own door, which is
# the exact invisible overrun the control-line rule exists to prevent.
# Indented and blockquoted markers were already rejected by the ^ anchor; the
# fence was the one hole, so the fence is what gets masked.
cap="$CAP_DEFAULT"
# A position rule (marker must be the first or last nonblank line) was tried
# here to close the class rather than the fenced instance, and REVERTED: the
# matrix's own `own-line marker opens the door` fixture puts the marker on its
# own line with a trailing sentence after it, which is the documented contract
# ("its own control line", not "the first or last line") and a legitimate shape.
# Breaking it to close a paste path would trade a real usage for a bypass the
# doc already declares out of scope, since the door "is a visible, auditable
# marker, not an unforgeable one". A fence-stripped paste at column 1 can still
# open it; that is recorded in Open Questions, not silently closed.
door=$(printf '%s\n' "$prompt" | tr -d '\r' \
  | awk '/^[[:space:]]*(```|~~~)/{fence=!fence; next} !fence' \
  | grep -m1 -E '^PANEL_ROUNDS_ORDERED_BY_SCOTT=[0-9]+$')
if [ -n "$door" ]; then
  cap="${door#*=}"
  log "door open: cap raised to $cap by a control line in the prompt"
fi

this_round=$((rounds + 1))
log "doc=$doc mode=$mode rounds=$rounds this_round=$this_round cap=$cap entry=$entry"

if [ "$this_round" -gt "$cap" ]; then
  # The counter path as a human reads it, so the deny text names a file Scott
  # can `cat` rather than a literal `$HOME`.
  shown="$entry"
  case "$shown" in "$HOME"/*) shown="~${shown#"$HOME"}" ;; esac
  log "deny: round $this_round exceeds cap $cap"
  deny "$(printf '%s\n%s\n%s\n%s\n%s' \
    "panel-round-guard: this is round $this_round on $doc; the cap is $cap (rules/interaction.md)." \
    "Rounds 1-$cap produced findings that belong in the doc, not in another round." \
    "If the doc still has open findings, fold them in and build; if Scott has" \
    "ordered more rounds, re-dispatch with PANEL_ROUNDS_ORDERED_BY_SCOTT=<n> in the prompt." \
    "Counter: $shown ($rounds rounds recorded)")"
fi

# Increment on allow, and only here. A cache directory that cannot be created
# or written costs the count, never the dispatch.
if mkdir -p "$CACHE_DIR" 2>/dev/null; then
  printf 'path=%s\nmode=%s\nrounds=%s\n' "$doc" "$mode" "$this_round" > "$entry" 2>/dev/null \
    || warn "could not write the counter at $entry; this round is uncounted"
else
  warn "could not create the counter directory $CACHE_DIR; this round is uncounted"
fi

log "allow: round $this_round of $cap recorded"
exit 0
