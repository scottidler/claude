#!/bin/bash
# must-deny.sh: Phase 3's third success criterion, run against all three arms.
#
# The replay cannot answer this one. The 2026-07-10 marker post in the corpus
# went to Scott's own DM (`D01G4Q7AWLV`, the exempt id), so it allows by design,
# and the driver wipes the ledger per post so no RESEND deny can ever appear.
# These three cases are therefore asserted directly, on a fixture HOME.
#
# The fixture cache carries `dms`, not the legacy `.users` DM keys, so the
# recipient RESOLVES under variants B and C and the TARGET rule passes. That is
# deliberate: a deny that lands because the id no longer resolves would prove
# nothing about whether TEST-TEXT and RESEND still bite.
#
# Usage: must-deny.sh [variant.sh ...]   (defaults to all three)

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
VARIANTS=("$@")
[ "${#VARIANTS[@]}" -eq 0 ] && VARIANTS=("$HERE/variant-a.sh" "$HERE/variant-b.sh" "$HERE/variant-c.sh")

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
NOW=$(date +%s)
FHOME="$T/home"
mkdir -p "$FHOME/.cache/slack"
cat > "$FHOME/.cache/slack/ids.json" <<JSON
{
  "schema": 2,
  "users_synced_at": $NOW,
  "usergroups_synced_at": $NOW,
  "channels_synced_at": $NOW,
  "channels": { "C0L0DJU56": "engineering" },
  "users": {},
  "dms": { "D02020W2872": "U111" },
  "handles": { "U111": "bruce" },
  "profiles": { "U111": {"display_name": "bruce", "real_name": "Bruce Wayne"} },
  "subteams": {},
  "self": {"dm": "D01G4Q7AWLV"}
}
JSON

transcript() {
  local p="$T/$1.jsonl"
  jq -c -n --arg c "$2" \
    '{type:"user",isSidechain:false,promptId:"P1",promptSource:"typed",message:{content:$c}}' > "$p"
  printf '%s' "$p"
}

payload() {
  jq -c -n --argjson ti "$1" --arg tp "$2" \
    '{hook_event_name:"PreToolUse",tool_name:"mcp__slack__chat_post_message",
      tool_input:$ti,transcript_path:$tp,prompt_id:"P1",cwd:"/home/saidler"}'
}

ask() {  # ask <guard> <payload> -> "allow" | the deny reason
  local out
  out=$(printf '%s' "$2" | HOME="$FHOME" bash "$1")
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // "allow"'
}

pass=0
fail=0
report() {  # report <variant> <case> <verdict>
  if [ "$3" = "allow" ]; then
    printf '  FAIL  %-12s %s\n           ALLOWED\n' "$1" "$2"
    fail=$((fail + 1))
  else
    printf '  PASS  %-12s %s\n           %s\n' "$1" "$2" "${3:0:96}"
    pass=$((pass + 1))
  fi
}

TX_BRUCE=$(transcript bruce 'message bruce about the rollout')
TX_SHAKE=$(transcript shake 'ok PR, /babysit, merge, finish bump, install, and test')
TX_CMD=$(transcript cmd '<command-message>cli-shakedown</command-message><command-name>cli-shakedown</command-name>')

for g in "${VARIANTS[@]}"; do
  v=$(basename "$g" .sh)
  rm -rf "$FHOME/.cache/slack/sent-ledger"

  # 1. the `**MCP write test**` marker, into a coworker's DM the prompt names.
  report "$v" 'MCP write test marker into a named DM' \
    "$(ask "$g" "$(payload '{"channel":"D02020W2872","text":"**MCP write test**\nignore this"}' "$TX_BRUCE")")"

  # 2a. the 2026-07-10 shakedown turn: a shakedown asks for no post.
  rm -rf "$FHOME/.cache/slack/sent-ledger"
  report "$v" '2026-07-10 shakedown turn' \
    "$(ask "$g" "$(payload '{"channel":"C0L0DJU56","text":"the summary"}' "$TX_SHAKE")")"

  # 2b. the same class arriving as a slash-command wrapper, which is the shape
  # the tag-stripping fix exists for: the literal word `message` in the TAG must
  # not authorize the post.
  rm -rf "$FHOME/.cache/slack/sent-ledger"
  report "$v" '/cli-shakedown command wrapper' \
    "$(ask "$g" "$(payload '{"channel":"C0L0DJU56","text":"the summary"}' "$TX_CMD")")"

  # 3. the duplicate body: the first post is authorized and reserves the ledger
  # entry, the second one is the 2026-06-09 class.
  rm -rf "$FHOME/.cache/slack/sent-ledger"
  dup=$(payload '{"channel":"D02020W2872","text":"the rollout is done"}' "$TX_BRUCE")
  first=$(ask "$g" "$dup")
  [ "$first" = "allow" ] || printf '  NOTE  %-12s first post of the duplicate pair denied: %s\n' "$v" "${first:0:80}"
  report "$v" 'duplicate body within the hour' "$(ask "$g" "$dup")"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
