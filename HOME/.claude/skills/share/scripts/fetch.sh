#!/usr/bin/env bash
# Print a plain-text digest source for one URL: type line, then content (capped).
set -euo pipefail

url="${1:?usage: fetch.sh <url>}"
cap=30000

case "$url" in
  *youtube.com/watch*|*youtube.com/shorts/*|*youtu.be/*)
    echo "TYPE: youtube"
    yt-dlp --no-playlist --skip-download --print "TITLE: %(title)s" --print "CHANNEL: %(channel)s" --print "DURATION: %(duration_string)s" "$url"
    echo "--- transcript ---"
    ytx "$url" | head -c "$cap"
    ;;
  https://github.com/*/*)
    path="${url#https://github.com/}"
    path="${path%%\?*}"
    owner="${path%%/*}"
    rest="${path#*/}"
    repo="${rest%%/*}"
    if [[ "$rest" == "$repo" || "$rest" == "$repo/" ]]; then
      echo "TYPE: github"
      gh repo view "$owner/$repo" --json description,stargazerCount,primaryLanguage,pushedAt,licenseInfo \
        --template 'DESCRIPTION: {{.description}}{{"\n"}}STARS: {{.stargazerCount}}{{"\n"}}LANGUAGE: {{with .primaryLanguage}}{{.name}}{{end}}{{"\n"}}LAST PUSH: {{.pushedAt}}{{"\n"}}LICENSE: {{with .licenseInfo}}{{.name}}{{end}}{{"\n"}}'
      echo "--- readme ---"
      gh api "repos/$owner/$repo/readme" -H "Accept: application/vnd.github.raw" | head -c "$cap"
      exit 0
    fi
    echo "TYPE: web"
    curl -fsS "https://r.jina.ai/$url" | head -c "$cap"
    ;;
  *)
    echo "TYPE: web"
    curl -fsS "https://r.jina.ai/$url" | head -c "$cap"
    ;;
esac
