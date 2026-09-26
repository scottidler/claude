#!/bin/bash
# jira-ac-guard.sh: PreToolUse guard for Atlassian MCP Jira creates and edits.
#
# Tatari's SEC and SRE projects carry Acceptance Criteria in a custom field,
# customfield_10118 ("Acceptance Criteria", a textarea). Agents keep writing an
# "## Acceptance Criteria" section into the description instead, which leaves
# the field empty and the board blind to it. Scott caught it on SEC-3099 and
# SEC-3100 (2026-09-26) and called it endemic across every agent, so this is a
# block, not a rule-file bullet.
#
# Denies when:
#   1. a create or edit puts an Acceptance Criteria section in the description
#      (any Jira project: the section belongs in the field, or nowhere), or
#   2. a create of a Story or Epic in a project that has the field leaves
#      customfield_10118 empty.
#
# Projects known to carry the field (verified with getJiraIssueTypeMetaWithFields
# 2026-09-26): SEC, SRE. Extend JIRA_AC_PROJECTS when another project is verified.
#
# Not covered: `acli jira workitem create` through Bash. That path has its own
# flags and needs its own fixtures before it is guarded.

JIRA_AC_PROJECTS="${JIRA_AC_PROJECTS:-SEC SRE}"
AC_FIELD="customfield_10118"

input=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$input")

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

case "$tool" in
  mcp__atlassian__createJiraIssue)
    description=$(jq -r '.tool_input.description // "" | if type == "string" then . else tojson end' <<<"$input")
    ac=$(jq -r --arg f "$AC_FIELD" '.tool_input.additional_fields // {} | (.[$f] // .["Acceptance Criteria"] // "") | if type == "string" then . else tojson end' <<<"$input")
    project=$(jq -r '.tool_input.projectKey // "" | ascii_upcase' <<<"$input")
    issue_type=$(jq -r '.tool_input.issueTypeName // "" | ascii_downcase' <<<"$input")
    ;;
  mcp__atlassian__editJiraIssue)
    description=$(jq -r '.tool_input.fields.description // "" | if type == "string" then . else tojson end' <<<"$input")
    ac=""
    project=""
    issue_type=""
    ;;
  *)
    echo '{}'
    exit 0
    ;;
esac

FIX="Put the criteria in the custom field instead: on createJiraIssue pass additional_fields {\"$AC_FIELD\": \"- item\\n- item\"}; on editJiraIssue pass fields {\"$AC_FIELD\": \"...\"}. A \"- \" bullet list of 3-7 assertable items, and drop the section from the description."

# A section heading or label line, in markdown or as text inside ADF JSON.
if grep -qiE '(^|\\n|"text":")[[:space:]]*(#{1,6}[[:space:]]*|\*\*|h[1-6]\.[[:space:]]*)?acceptance criteria[[:space:]]*:?[[:space:]]*(\*\*)?[[:space:]]*:?[[:space:]]*($|\\n|")' <<<"$description"; then
  deny "Blocked: the description contains an Acceptance Criteria section. Jira Acceptance Criteria live in $AC_FIELD, not the description. $FIX"
fi

if [ "$tool" = "mcp__atlassian__createJiraIssue" ] && [[ "$issue_type" == "story" || "$issue_type" == "epic" ]]; then
  for p in $JIRA_AC_PROJECTS; do
    if [ "$project" = "$p" ] && [ -z "$(tr -d '[:space:]' <<<"$ac")" ]; then
      deny "Blocked: a $project ${issue_type^} needs Acceptance Criteria in $AC_FIELD, and it is empty. $FIX"
    fi
  done
fi

echo '{}'
exit 0
