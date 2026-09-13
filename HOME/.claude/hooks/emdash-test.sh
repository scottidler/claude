#!/bin/bash
# emdash-test.sh: regression matrix for emdash.sh.
#
# Feeds synthetic PreToolUse payloads through the hook and asserts deny/allow
# for every scanned surface: Write/Edit/MultiEdit/NotebookEdit content, the
# Bash outward stages (git commit, gh pr, gh issue) including heredoc bodies,
# and MCP post bodies at any depth. Also pins the two things the design doc is
# explicit about: the escape text exempts nothing, and the path allowlist
# (tests/fixtures/, *.golden) is the only carve-out.
#
# Run directly, or via: emdash.sh --self-test
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/emdash.sh"

EMDASH=$'\u2014'
ESCAPE_TEXT='\u{2014}'

# ---------- payload builders ----------
write_p() { jq -n --arg p "$1" --arg c "$2" \
  '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$p,content:$c}}'; }
edit_p()  { jq -n --arg p "$1" --arg o "$2" --arg n "$3" \
  '{hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n}}'; }
multi_p() { jq -n --arg p "$1" --arg a "$2" --arg b "$3" \
  '{hook_event_name:"PreToolUse",tool_name:"MultiEdit",tool_input:{file_path:$p,edits:[{old_string:"x",new_string:$a},{old_string:"y",new_string:$b}]}}'; }
nb_p()    { jq -n --arg p "$1" --arg s "$2" \
  '{hook_event_name:"PreToolUse",tool_name:"NotebookEdit",tool_input:{notebook_path:$p,cell_id:"c1",new_source:$s}}'; }
bash_p()  { jq -n --arg c "$1" \
  '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
mcp_p()   { jq -n --arg t "$1" --argjson i "$2" \
  '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:$i}'; }

# ---------- runner ----------
pass=0; fail=0
run() {  # run <expect deny|allow> <label> <payload-json>
  local expect="$1" label="$2" payload="$3" out decision
  out=$(printf '%s' "$payload" | bash "$HOOK" 2>/dev/null)
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
  if [ "$decision" = "$expect" ]; then
    pass=$((pass+1)); printf 'PASS  [%s] %s\n' "$expect" "$label"
  else
    fail=$((fail+1)); printf 'FAIL  [want %s got %s] %s\n      -> %s\n' \
      "$expect" "$decision" "$label" \
      "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // .' 2>/dev/null | head -c 200)"
  fi
}

echo "=== Write ==="
run deny "literal U+2014 in content" \
  "$(write_p "docs/note.md" "The fix landed${EMDASH}CI is green.")"
run allow "the escape text with no literal" \
  "$(write_p "docs/note.md" "Assert absence with the ${ESCAPE_TEXT} form.")"
run allow "literal under tests/fixtures/ (relative)" \
  "$(write_p "tests/fixtures/sample.md" "A quoted log line${EMDASH}verbatim.")"
run allow "literal under tests/fixtures/ (absolute)" \
  "$(write_p "/home/saidler/repos/scottidler/x/tests/fixtures/sample.md" "verbatim${EMDASH}line")"
run deny "literal PLUS the escape text (the escape exempts nothing)" \
  "$(write_p "docs/note.md" "Write it as ${ESCAPE_TEXT}, not as ${EMDASH} itself.")"
run allow "literal in a .golden file" \
  "$(write_p "crates/x/golden/out.golden" "rendered${EMDASH}output")"
run deny "literal in a plain .json file (no longer exempt)" \
  "$(write_p "data/fixture.json" "{\"s\":\"a${EMDASH}b\"}")"

run allow "literal in a .json UNDER tests/fixtures/" \
  "$(write_p "tests/fixtures/payload.json" "{\"s\":\"a${EMDASH}b\"}")"
run allow "clean content" \
  "$(write_p "docs/note.md" "The fix landed: CI is green.")"

echo "=== Edit / MultiEdit / NotebookEdit ==="
run deny "Edit new_string carries it" \
  "$(edit_p "docs/note.md" "old text" "new${EMDASH}text")"
run allow "Edit REMOVING it: only old_string carries it" \
  "$(edit_p "docs/note.md" "old${EMDASH}text" "old: text")"
run deny "MultiEdit second edit carries it" \
  "$(multi_p "docs/note.md" "clean one" "second${EMDASH}edit")"
run allow "MultiEdit, neither edit carries it" \
  "$(multi_p "docs/note.md" "clean one" "clean two")"
run deny "NotebookEdit new_source carries it" \
  "$(nb_p "nb.ipynb" "# heading${EMDASH}subtitle")"

echo "=== Bash: outward stages only ==="
run deny "git commit -m carrying it" \
  "$(bash_p "git commit -m \"fix the thing${EMDASH}it was broken\"")"
run allow "rg for the character, no outward stage" \
  "$(bash_p "rg -n '${EMDASH}' docs/")"
run allow "git commit with a clean message" \
  "$(bash_p "git add -A && git commit -m 'fix the thing: it was broken'")"
run deny "git -C <dir> commit carrying it" \
  "$(bash_p "git -C /home/saidler/repos/scottidler/claude commit -m \"a${EMDASH}b\"")"
run deny "commit message arriving by heredoc" \
  "$(bash_p "$(printf 'git commit -F - <<%sMSG%s\nfeat(x): thing\n\nbody line%sstill the body\nMSG\n' "'" "'" "${EMDASH}")")"
run allow "heredoc body mentions git commit, the command is a cat" \
  "$(bash_p "$(printf 'cat > notes.md <<%sEOF%s\nrun git commit after the%sfix\nEOF\n' "'" "'" "${EMDASH}")")"
run deny "gh pr create --title carrying it" \
  "$(bash_p "gh pr create --title \"feat(hooks): em-dash guard${EMDASH}phase 3\" --body-file body.md")"
run deny "gh issue comment carrying it" \
  "$(bash_p "gh issue comment 12 --body 'landed${EMDASH}see the PR'")"
run allow "git log grepping for it (not an outward stage)" \
  "$(bash_p "git log --oneline | grep -F '${EMDASH}'")"
run allow "empty command" "$(bash_p "")"

echo "=== MCP posts ==="
run deny "slack chat_post_message text" \
  "$(mcp_p "mcp__slack__chat_post_message" "$(jq -n --arg t "shipped${EMDASH}green CI" '{channel_id:"C123",text:$t}')")"
run allow "slack chat_post_message, clean text" \
  "$(mcp_p "mcp__slack__chat_post_message" '{"channel_id":"C123","text":"shipped: green CI"}')"
run deny "atlassian confluence page, nested string" \
  "$(mcp_p "mcp__atlassian__createConfluencePage" "$(jq -n --arg t "a${EMDASH}b" '{spaceKey:"ENG",title:"t",body:{representation:"storage",value:$t}}')")"
run deny "marquee publish body" \
  "$(mcp_p "mcp__marquee__marquee_publish" "$(jq -n --arg t "a${EMDASH}b" '{space:"~scott-idler",slug:"s",content:$t}')")"

echo "=== pass-throughs ==="
run allow "an unmatched tool (Read) carrying it" \
  "$(jq -n --arg p "docs/a${EMDASH}b.md" '{hook_event_name:"PreToolUse",tool_name:"Read",tool_input:{file_path:$p}}')"
run allow "malformed payload" 'not json at all'
run allow "empty payload" ''

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
