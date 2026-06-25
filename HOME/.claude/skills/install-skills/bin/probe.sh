#!/usr/bin/env bash
# probe.sh — discover installable skills in a GitHub repo and emit a manifest link map.
#
# Reads the repo tree via `gh api` (no clone), finds every SKILL.md, derives the
# skill name from its containing directory, and prints a ready-to-paste manifest.yml
# github entry with collision warnings against ~/.claude/skills.
#
# usage: probe.sh <github-url-or-org/repo>
#   probe.sh https://github.com/addyosmani/agent-skills
#   probe.sh addyosmani/agent-skills
#   probe.sh https://github.com/some/repo/tree/main/skills/foo   # subpath -> just that skill

set -euo pipefail

raw="${1:?usage: probe.sh <github-url-or-org/repo>}"

# normalize to a bare slug: strip protocol/host, .git, trailing slash
slug="$raw"
slug="${slug#https://github.com/}"
slug="${slug#http://github.com/}"
slug="${slug#github.com/}"
slug="${slug%.git}"
slug="${slug%/}"

# capture optional subpath from a /tree/<branch>/<subpath> URL, then strip to org/repo
subpath=""
if [[ "$slug" == */tree/* ]]; then
    after="${slug#*/tree/}"      # <branch>/<subpath...>
    subpath="${after#*/}"        # <subpath...>  (equals branch when no subdir given)
    [[ "$after" != */* ]] && subpath=""
    slug="${slug%%/tree/*}"
fi

[[ "$slug" == */* ]] || { echo "need an org/repo slug, got: $raw" >&2; exit 2; }

org="${slug%%/*}"
repo="${slug#*/}"
repo="${repo%%/*}"

if [[ -z "$org" || -z "$repo" ]]; then
    echo "could not parse org/repo from: $raw" >&2
    exit 2
fi

skills_root="$HOME/.claude/skills"

branch="$(gh api "repos/$org/$repo" --jq .default_branch)"
paths="$(gh api "repos/$org/$repo/git/trees/$branch?recursive=1" --jq '.tree[].path')"

echo "# repo: $org/$repo (branch: $branch)"
[[ -n "$subpath" ]] && echo "# scoped to subpath: $subpath"
echo "# --- paste under the github: section of manifest.yml ---"
echo "  $org/$repo:"
echo "    link:"

found=0
while IFS= read -r p; do
    [[ "$p" == "SKILL.md" || "$p" == */SKILL.md ]] || continue
    if [[ "$p" == "SKILL.md" ]]; then
        dir="."
    else
        dir="${p%/SKILL.md}"
    fi
    # honor subpath filter when the URL pointed at a subdirectory
    if [[ -n "$subpath" && "$dir" != "$subpath" && "$dir" != "$subpath"/* ]]; then
        continue
    fi
    if [[ "$dir" == "." ]]; then
        name="$repo"
    else
        name="$(basename "$dir")"
    fi
    warn=""
    [[ -e "$skills_root/$name" ]] && warn="   # COLLISION: ~/.claude/skills/$name already exists"
    echo "      $dir: ~/.claude/skills/$name$warn"
    found=$((found + 1))
done <<< "$paths"

if [[ "$found" -eq 0 ]]; then
    echo "      # no SKILL.md found — this does not look like a skills repo"
fi
echo "# discovered $found skill(s)"
