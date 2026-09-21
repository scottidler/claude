#!/bin/bash
# AC2's right half: the 20 committed non-handoff controls must all stay silent.
# The left half (set equality against the committed fire list) is extract.py's
# fires.tsv plus counts.json's sha, which is why the id list is a file and not a
# percentage.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
HOOK="$HERE/../../../HOME/.claude/hooks/handoff-guard.sh"
pass=0
fail=0

while IFS= read -r prompt; do
  [ -n "$prompt" ] || continue
  out=$(jq -n --arg p "$prompt" \
    '{cwd:"/nonexistent-cwd-for-controls",hook_event_name:"UserPromptSubmit",permission_mode:"auto",prompt:$p,prompt_id:"c",session_id:"c",transcript_path:"/dev/null"}' \
    | bash "$HOOK" 2>/dev/null)
  if [ -n "$out" ]; then
    fail=$((fail + 1))
    printf 'FAIL  fired on control: %s\n' "$prompt"
  else
    pass=$((pass + 1))
  fi
done < "$HERE/controls.tsv"

printf 'controls pass=%d fail=%d\n' "$pass" "$fail"
[ "$pass" -eq 20 ] || { printf 'FAIL  expected 20 controls, ran %d\n' "$((pass + fail))"; exit 1; }
[ "$fail" -eq 0 ]
