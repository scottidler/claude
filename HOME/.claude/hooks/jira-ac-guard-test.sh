#!/bin/bash
# jira-ac-guard-test.sh: the matrix for jira-ac-guard.sh.
#
# Wired into `.otto.yml`'s test task by glob (`*-test.sh`). Each case feeds a
# PreToolUse payload on stdin and asserts deny or allow.

HOOKS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
HOOK="$HOOKS/jira-ac-guard.sh"
pass=0
fail=0

check() {
  local want="$1" name="$2" payload="$3" got
  if "$HOOK" <<<"$payload" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; then
    got=deny
  else
    got=allow
  fi
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL [$name]: want $want, got $got"
  fi
}

create() {
  jq -nc --arg p "$1" --arg t "$2" --arg d "$3" --argjson af "$4" \
    '{tool_name:"mcp__atlassian__createJiraIssue",tool_input:{cloudId:"x",projectKey:$p,issueTypeName:$t,summary:"s",description:$d,additional_fields:$af}}'
}

edit() {
  jq -nc --argjson f "$1" '{tool_name:"mcp__atlassian__editJiraIssue",tool_input:{cloudId:"x",issueIdOrKey:"SEC-1",fields:$f}}'
}

AC='{"customfield_10118":"- a\n- b"}'
NOAC='{}'

# The SEC-3099 shape: AC as a markdown section in the description.
check deny "md h2 section" "$(create SEC Story $'## Context\n\nwhy\n\n## Acceptance Criteria\n\n- a\n- b' "$AC")"
check deny "md h3 section" "$(create SRE Story $'### Acceptance Criteria\n- a' "$AC")"
check deny "bold label" "$(create SEC Story $'**Acceptance Criteria:**\n- a' "$AC")"
check deny "plain label with colon" "$(create SEC Story $'Acceptance criteria:\n- a' "$AC")"
check deny "wiki h2" "$(create SEC Story $'h2. Acceptance Criteria\n* a' "$AC")"
check deny "other project section" "$(create DAT Story $'## Acceptance Criteria\n- a' "$NOAC")"
check deny "ADF heading" "$(jq -nc '{tool_name:"mcp__atlassian__createJiraIssue",tool_input:{projectKey:"SEC",issueTypeName:"Story",summary:"s",additional_fields:{customfield_10118:"- a"},description:{type:"doc",content:[{type:"heading",content:[{type:"text",text:"Acceptance Criteria"}]}]}}}')"

# Missing field on a Story or Epic in a project that has it.
check deny "SEC story no field" "$(create SEC Story $'## Context\nwhy' "$NOAC")"
check deny "SRE epic no field" "$(create SRE Epic 'why' "$NOAC")"
check deny "SEC story blank field" "$(create SEC Story 'why' '{"customfield_10118":"  \n "}')"
check deny "lowercase project key" "$(create sec story 'why' "$NOAC")"

# Allowed.
check allow "SEC story with field" "$(create SEC Story $'## Context\nwhy' "$AC")"
check allow "field by name" "$(create SRE Story 'why' '{"Acceptance Criteria":"- a"}')"
check allow "SEC spike no field" "$(create SEC Spike 'time-boxed' "$NOAC")"
check allow "SEC subtask no field" "$(create SEC Sub-task 'x' "$NOAC")"
check allow "other project no field" "$(create DAT Story 'why' "$NOAC")"
check allow "mention in prose" "$(create SEC Story 'The acceptance criteria below are in the field.' "$AC")"
check allow "linked ticket phrase" "$(create SEC Story $'See the Acceptance Criteria field for scope.' "$AC")"
check allow "edit sets field" "$(edit '{"customfield_10118":"- a"}')"
check allow "edit description without section" "$(edit '{"description":"## Context\nwhy"}')"
check allow "other tool" '{"tool_name":"mcp__atlassian__getJiraIssue","tool_input":{"issueIdOrKey":"SEC-1"}}'

# Edits that add the section back.
check deny "edit adds section" "$(edit '{"description":"## Context\nwhy\n\n## Acceptance Criteria\n- a"}')"

# acli through Bash.
FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT

bash_cmd() {
  jq -nc --arg c "$1" --arg d "$FIX" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}'
}

printf '## Context\nwhy\n\n## Acceptance Criteria\n- a\n' >"$FIX/desc-ac.md"
printf '## Context\nwhy\n' >"$FIX/desc-ok.md"
jq -n --arg f customfield_10118 '{projectKey:"SEC",type:"Story",summary:"s",additionalAttributes:{($f):"- a"},description:{type:"doc",version:1,content:[{type:"paragraph",content:[{type:"text",text:"why"}]}]}}' >"$FIX/ok.json"
jq -n '{projectKey:"SEC",type:"Story",summary:"s",description:{type:"doc",version:1,content:[]}}' >"$FIX/noac.json"
jq -n --arg f customfield_10118 '{projectKey:"SEC",type:"Story",summary:"s",additionalAttributes:{($f):"- a"},description:{type:"doc",version:1,content:[{type:"heading",content:[{type:"text",text:"Acceptance Criteria"}]}]}}' >"$FIX/adf-ac.json"
jq -n '{issues:[{summary:"s",projectKey:"DAT",issueType:"Task"},{summary:"t",projectKey:"SRE",issueType:"Story"}]}' >"$FIX/bulk-sre.json"
jq -n '{issues:[{summary:"s",projectKey:"DAT",issueType:"Story"}]}' >"$FIX/bulk-dat.json"
printf 'summary,projectKey,issueType\ns,SEC,Epic\n' >"$FIX/bulk-sec.csv"
printf 'summary,projectKey,issueType\ns,SEC,Task\n' >"$FIX/bulk-task.csv"

check deny "acli inline desc section" "$(bash_cmd $'acli jira workitem create -p DAT -t Task -s s -d "## Acceptance Criteria\n- a"')"
check deny "acli inline desc heredoc" "$(bash_cmd $'acli jira workitem edit --key SEC-1 --description "$(cat <<X\n## Context\nwhy\n\n**Acceptance Criteria:**\n- a\nX\n)" --yes')"
check deny "acli description-file section" "$(bash_cmd 'acli jira workitem edit --key SEC-1 --description-file desc-ac.md --yes')"
check deny "acli from-json ADF heading" "$(bash_cmd "acli jira workitem create --from-json $FIX/adf-ac.json")"
check deny "acli SEC story by flags" "$(bash_cmd 'acli jira workitem create --project SEC --type Story -s s --description-file desc-ok.md')"
check deny "acli sre epic short flags" "$(bash_cmd 'cd /tmp && acli jira workitem create -p sre -t epic -s s')"
check deny "acli from-json no field" "$(bash_cmd 'acli jira workitem create --from-json noac.json')"
check deny "acli unreadable file" "$(bash_cmd 'acli jira workitem create --from-json missing.json')"
check deny "acli bulk json SRE story" "$(bash_cmd 'acli jira workitem create-bulk --from-json bulk-sre.json --yes')"
check deny "acli bulk csv SEC epic" "$(bash_cmd "acli jira workitem create-bulk --from-csv '$FIX/bulk-sec.csv'")"

check allow "acli from-json with field" "$(bash_cmd 'acli jira workitem create --from-json ok.json')"
check allow "acli SEC task by flags" "$(bash_cmd 'acli jira workitem create -p SEC -t Task -s s -d "why"')"
check allow "acli other project story" "$(bash_cmd 'acli jira workitem create -p DAT -t Story -s s')"
check allow "acli edit clean desc" "$(bash_cmd 'acli jira workitem edit --key SEC-1 --description-file desc-ok.md --yes')"
check allow "acli bulk json other project" "$(bash_cmd 'acli jira workitem create-bulk --from-json bulk-dat.json')"
check allow "acli bulk csv task" "$(bash_cmd 'acli jira workitem create-bulk --from-csv bulk-task.csv')"
check allow "acli view" "$(bash_cmd 'acli jira workitem view SEC-3099 --fields customfield_10118')"
check allow "acli prose mention" "$(bash_cmd 'acli jira workitem create -p SEC -t Task -s s -d "See the Acceptance Criteria field."')"
check allow "acli quoted in commit message" "$(bash_cmd 'git commit -m "guard acli jira workitem create --from-json sets the field"')"
check deny "acli after cd and env" "$(bash_cmd 'cd /x && FOO=1 acli jira workitem create -p SEC -t Story -s s')"
check deny "acli in subshell" "$(bash_cmd 'out=$(acli jira workitem create -p SEC -t Story -s s)')"
check allow "unrelated bash" "$(bash_cmd 'mkdir -p x && grep -r "Acceptance Criteria" .')"

echo "jira-ac-guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
