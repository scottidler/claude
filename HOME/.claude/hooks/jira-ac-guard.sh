#!/bin/bash
# jira-ac-guard.sh: PreToolUse guard for Jira creates and edits, through the
# Atlassian MCP tools and through `acli jira workitem` in Bash.
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
# acli (checked against `acli jira workitem <sub> --help` / `--generate-json`
# 2026-09-26): no flag sets a custom field. Only `create --from-json` can, via
# additionalAttributes; `edit` and `create-bulk` cannot at all. So an acli
# Story/Epic create in a listed project must use --from-json with the field
# set. The description check reads the command text plus every file named by
# --description-file, --from-file/-f, --from-json and --from-csv.

JIRA_AC_PROJECTS="${JIRA_AC_PROJECTS:-SEC SRE}"
AC_FIELD="customfield_10118"

# A section heading or label line: optional markdown/wiki heading or bold,
# the words, optional colon.
AC_HEAD='[[:space:]]*(#{1,6}[[:space:]]*|\*\*|h[1-6]\.[[:space:]]*)?acceptance criteria[[:space:]]*:?[[:space:]]*(\*\*)?[[:space:]]*:?[[:space:]]*'
# MCP payloads: a line of markdown, or a text node inside ADF JSON.
AC_RE_MCP='(^|\\n|"text":")'"$AC_HEAD"'($|\\n|")'
# Shell commands: also the start or end of a quoted argument.
AC_RE_SHELL='(^|\\n|"text":"|["'"'"'])'"$AC_HEAD"'($|\\n|["'"'"'])'

input=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$input")

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

allow() {
  echo '{}'
  exit 0
}

ac_project() {
  local p
  for p in $JIRA_AC_PROJECTS; do
    [ "$1" = "$p" ] && return 0
  done
  return 1
}

needs_ac() {
  [[ "$2" == "story" || "$2" == "epic" ]] && ac_project "$1"
}

FIX_MCP="Put the criteria in the custom field instead: on createJiraIssue pass additional_fields {\"$AC_FIELD\": \"- item\\n- item\"}; on editJiraIssue pass fields {\"$AC_FIELD\": \"...\"}. A \"- \" bullet list of 3-7 assertable items, and drop the section from the description."
FIX_ACLI="acli flags cannot set $AC_FIELD, and acli edit/create-bulk cannot set custom fields at all. Use mcp__atlassian__createJiraIssue with additional_fields {\"$AC_FIELD\": \"- item\\n- item\"} (or mcp__atlassian__editJiraIssue with fields {\"$AC_FIELD\": \"...\"}), or acli jira workitem create --from-json with additionalAttributes.$AC_FIELD set. A bullet list of 3-7 assertable items, and no Acceptance Criteria section in the description."

case "$tool" in
  mcp__atlassian__createJiraIssue|mcp__atlassian__editJiraIssue)
    if [ "$tool" = "mcp__atlassian__createJiraIssue" ]; then
      description=$(jq -r '.tool_input.description // "" | if type == "string" then . else tojson end' <<<"$input")
    else
      description=$(jq -r '.tool_input.fields.description // "" | if type == "string" then . else tojson end' <<<"$input")
    fi
    if grep -qiE "$AC_RE_MCP" <<<"$description"; then
      deny "Blocked: the description contains an Acceptance Criteria section. Jira Acceptance Criteria live in $AC_FIELD, not the description. $FIX_MCP"
    fi
    if [ "$tool" = "mcp__atlassian__createJiraIssue" ]; then
      ac=$(jq -r --arg f "$AC_FIELD" '.tool_input.additional_fields // {} | (.[$f] // .["Acceptance Criteria"] // "") | if type == "string" then . else tojson end' <<<"$input")
      project=$(jq -r '.tool_input.projectKey // "" | ascii_upcase' <<<"$input")
      issue_type=$(jq -r '.tool_input.issueTypeName // "" | ascii_downcase' <<<"$input")
      if needs_ac "$project" "$issue_type" && [ -z "$(tr -d '[:space:]' <<<"$ac")" ]; then
        deny "Blocked: a $project ${issue_type^} needs Acceptance Criteria in $AC_FIELD, and it is empty. $FIX_MCP"
      fi
    fi
    allow
    ;;
  Bash) ;;
  *) allow ;;
esac

cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
# acli at command position only (line start, or after ; & | ( or env
# assignments), so a commit message or grep that quotes an acli line passes.
sub=$(grep -oE '(^|[;&|(])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*acli[[:space:]]+jira[[:space:]]+workitem[[:space:]]+(create-bulk|create|edit)\b' <<<"$cmd" | head -1 | awk '{print $NF}')
[ -n "$sub" ] || allow
cwd=$(jq -r '.cwd // ""' <<<"$input")
seg="acli${cmd#*acli}"

# flag_value 'long|short': the first value given to any of those flags.
flag_value() {
  grep -oE -- "(^|[[:space:]])($1)(=|[[:space:]]+)(\"[^\"]*\"|'[^']*'|[^[:space:]]+)" <<<"$seg" | head -1 |
    sed -E "s/^[[:space:]]*($1)(=|[[:space:]]+)//; s/^[\"'](.*)[\"']\$/\1/"
}

# flag_file 'long|short': sets $file to the named file's path, empty when the
# flag is absent. Not called in $(...), so its deny exits the hook.
flag_file() {
  file=$(flag_value "$1")
  [ -n "$file" ] || return 0
  file="${file/#\~/$HOME}"
  [[ "$file" = /* ]] || file="$cwd/$file"
  [ -r "$file" ] || deny "Blocked: acli names a file this guard cannot read ($file), so its Acceptance Criteria placement cannot be checked. Pass an absolute path to an existing file."
}

flag_file '--description-file'; desc_file="$file"
flag_file '--from-file|-f'; text_file="$file"
flag_file '--from-json'; json_file="$file"
flag_file '--from-csv'; csv_file="$file"

description="$cmd"
for f in "$desc_file" "$text_file" "$json_file" "$csv_file"; do
  [ -n "$f" ] && description+=$'\n'"$(cat "$f")"
done
if grep -qiE "$AC_RE_SHELL" <<<"$description"; then
  deny "Blocked: the acli description contains an Acceptance Criteria section. Jira Acceptance Criteria live in $AC_FIELD, not the description. $FIX_ACLI"
fi

case "$sub" in
  create)
    if [ -n "$json_file" ]; then
      project=$(jq -r '.projectKey // "" | ascii_upcase' "$json_file" 2>/dev/null)
      issue_type=$(jq -r '.type // "" | ascii_downcase' "$json_file" 2>/dev/null)
      ac=$(jq -r --arg f "$AC_FIELD" '.additionalAttributes // {} | .[$f] // "" | if type == "string" then . else tojson end' "$json_file" 2>/dev/null)
    else
      project=$(flag_value '--project|-p' | tr '[:lower:]' '[:upper:]')
      issue_type=$(flag_value '--type|-t' | tr '[:upper:]' '[:lower:]')
      ac=""
    fi
    if needs_ac "$project" "$issue_type" && [ -z "$(tr -d '[:space:]' <<<"$ac")" ]; then
      deny "Blocked: a $project ${issue_type^} needs Acceptance Criteria in $AC_FIELD, and this acli create leaves it empty. $FIX_ACLI"
    fi
    ;;
  create-bulk)
    hit=""
    if [ -n "$json_file" ]; then
      while read -r project issue_type; do
        needs_ac "$project" "$issue_type" && hit="$project ${issue_type^}"
      done < <(jq -r '.issues[]? | "\(.projectKey // "" | ascii_upcase) \(.issueType // "" | ascii_downcase)"' "$json_file" 2>/dev/null)
    fi
    if [ -n "$csv_file" ]; then
      for p in $JIRA_AC_PROJECTS; do
        grep -iE "(^|,)\"?$p\"?(,|\$)" "$csv_file" | grep -qiE '(^|,)"?(story|epic)"?(,|$)' && hit="$p Story/Epic"
      done
    fi
    [ -n "$hit" ] && deny "Blocked: acli create-bulk includes a $hit, which needs Acceptance Criteria in $AC_FIELD, and create-bulk's input format carries no custom fields. $FIX_ACLI"
    ;;
esac

allow
