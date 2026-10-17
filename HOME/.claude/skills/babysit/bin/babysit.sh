#!/usr/bin/env bash
# Block until one PR needs the model, then print one report and exit.
# The wait happens here, in a background process, so it costs no model turns.
# shellcheck disable=SC2016
set -euo pipefail

INTERVAL=30
MAX_MINUTES=180
CR_GRACE_MINUTES=5
MAX_CONSECUTIVE_ERRORS=5
NO_CHECKS_GRACE_SECONDS=120

usage() {
    cat <<'EOF'
Usage: babysit.sh <pr-url> [--interval SECONDS] [--max-minutes N] [--cr-grace-minutes N]

Polls one PR and exits on the first event that needs the model:
  merged | closed | ci-failed | threads | settled | coderabbit-silent | timeout | error

Run it with run_in_background; the exit wakes the session. Exit 0 = actionable
event, 1 = error, 2 = timeout. Report goes to stdout as key=value lines.
Needs: gh, jq, GITHUB_PAT_WORK, GITHUB_PAT_HOME in the environment.
EOF
}

PR_URL=""
while [ $# -gt 0 ]; do
    case "$1" in
        --interval) INTERVAL="$2"; shift 2 ;;
        --max-minutes) MAX_MINUTES="$2"; shift 2 ;;
        --cr-grace-minutes) CR_GRACE_MINUTES="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "unknown flag: $1" >&2; usage >&2; exit 1 ;;
        *) PR_URL="$1"; shift ;;
    esac
done

if [[ ! "$PR_URL" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    echo "expected https://github.com/<owner>/<repo>/pull/<n>, got: ${PR_URL:-<none>}" >&2
    exit 1
fi
OWNER="${BASH_REMATCH[1]}"
REPO="${BASH_REMATCH[2]}"
NUMBER="${BASH_REMATCH[3]}"

# gh() in .zshenv picks the token by persona, but a bash script never sees that function.
if [ "$OWNER" = "tatari-tv" ]; then
    TOKEN="${GITHUB_PAT_WORK:-}"
else
    TOKEN="${GITHUB_PAT_HOME:-}"
fi
if [ -z "$TOKEN" ]; then
    echo "event=error"
    echo "reason=no token in env for owner $OWNER (GITHUB_PAT_WORK / GITHUB_PAT_HOME)"
    exit 1
fi

# first:100 on threads and contexts: a PR past that needs pagination before this is trustworthy.
QUERY='
query($owner:String!,$repo:String!,$number:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      state headRefOid baseRefName
      reviewThreads(first:100){nodes{isResolved}}
      reviews(last:50){nodes{author{login} commit{oid}}}
      commits(last:1){nodes{commit{statusCheckRollup{contexts(first:100){nodes{
        __typename
        ... on CheckRun{name status conclusion}
        ... on StatusContext{context state}
      }}}}}}
    }
  }
}'

SUMMARY_JQ='
.data.repository.pullRequest as $pr
| ($pr.commits.nodes[0].commit.statusCheckRollup.contexts.nodes // []) as $ctx
| ($ctx | map(
    if .__typename == "CheckRun" then
      {name: .name,
       bucket: (if .status != "COMPLETED" then "pending"
                elif (.conclusion | IN("FAILURE","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE")) then "failed"
                else "ok" end)}
    else
      {name: .context,
       bucket: (if (.state | IN("PENDING","EXPECTED")) then "pending"
                elif (.state | IN("FAILURE","ERROR")) then "failed"
                else "ok" end)}
    end)) as $checks
| {
    state: $pr.state,
    head: $pr.headRefOid,
    base: $pr.baseRefName,
    unresolved: ([$pr.reviewThreads.nodes[] | select(.isResolved | not)] | length),
    n_checks: ($checks | length),
    failed: [$checks[] | select(.bucket == "failed") | .name],
    pending: [$checks[] | select(.bucket == "pending") | .name],
    cr_active: ([$checks[] | select(.name | test("coderabbit"; "i"))] | length > 0),
    cr_checks_done: ([$checks[] | select(.name | test("coderabbit"; "i")) | select(.bucket == "pending")] | length == 0),
    cr_reviewed_head: ([$pr.reviews.nodes[]
        | select(.author.login | test("^coderabbit"; "i"))
        | select(.commit.oid == $pr.headRefOid)] | length > 0)
  }'

report() {
    local event="$1" extra="${2:-}"
    echo "event=$event"
    echo "pr=$PR_URL"
    jq -r '"state=\(.state)\nhead=\(.head)\nbase=\(.base)\nunresolved=\(.unresolved)\nfailed=\(.failed | join(","))\npending=\(.pending | join(","))\ncr_reviewed_head=\(.cr_reviewed_head)"' <<<"$SUMMARY"
    [ -n "$extra" ] && echo "$extra"
    return 0
}

started_at=$(date +%s)
deadline=$(( started_at + MAX_MINUTES * 60 ))
cr_wait_started=0
errors=0
SUMMARY='{"state":"UNKNOWN","head":"","base":"","unresolved":0,"failed":[],"pending":[],"cr_reviewed_head":false}'

while :; do
    if RAW=$(GH_TOKEN="$TOKEN" gh api graphql -f query="$QUERY" \
            -F owner="$OWNER" -F repo="$REPO" -F number="$NUMBER" 2>&1) \
        && SUMMARY_NEW=$(jq -c "$SUMMARY_JQ" <<<"$RAW" 2>&1); then
        errors=0
        SUMMARY="$SUMMARY_NEW"
    else
        errors=$(( errors + 1 ))
        echo "poll failed ($errors/$MAX_CONSECUTIVE_ERRORS): ${RAW:0:200}" >&2
        if [ "$errors" -ge "$MAX_CONSECUTIVE_ERRORS" ]; then
            report error "reason=${RAW:0:300}"
            exit 1
        fi
        sleep "$INTERVAL"
        continue
    fi

    state=$(jq -r .state <<<"$SUMMARY")
    unresolved=$(jq -r .unresolved <<<"$SUMMARY")
    n_failed=$(jq -r '.failed | length' <<<"$SUMMARY")
    n_pending=$(jq -r '.pending | length' <<<"$SUMMARY")
    cr_active=$(jq -r .cr_active <<<"$SUMMARY")
    cr_done=$(jq -r .cr_checks_done <<<"$SUMMARY")
    cr_reviewed=$(jq -r .cr_reviewed_head <<<"$SUMMARY")

    case "$state" in
        MERGED) report merged; exit 0 ;;
        CLOSED) report closed; exit 0 ;;
    esac
    if [ "$n_failed" -gt 0 ]; then report ci-failed; exit 0; fi
    if [ "$unresolved" -gt 0 ]; then report threads; exit 0; fi

    if [ "$cr_active" = "true" ] && [ "$cr_reviewed" = "false" ] && [ "$cr_done" = "true" ]; then
        [ "$cr_wait_started" -eq 0 ] && cr_wait_started=$(date +%s)
        if [ $(( $(date +%s) - cr_wait_started )) -ge $(( CR_GRACE_MINUTES * 60 )) ]; then
            report coderabbit-silent "reason=CodeRabbit check is terminal but no review on this head after ${CR_GRACE_MINUTES}m"
            exit 0
        fi
    else
        cr_wait_started=0
    fi

    # A fresh push has no checks for a moment; empty is "not registered yet", not "all green".
    n_checks=$(jq -r .n_checks <<<"$SUMMARY")
    no_checks_yet=false
    if [ "$n_checks" -eq 0 ] && [ $(( $(date +%s) - started_at )) -lt "$NO_CHECKS_GRACE_SECONDS" ]; then
        no_checks_yet=true
    fi

    if [ "$no_checks_yet" = "false" ] && [ "$n_pending" -eq 0 ] \
        && { [ "$cr_active" = "false" ] || [ "$cr_reviewed" = "true" ]; }; then
        report settled
        exit 0
    fi

    if [ "$(date +%s)" -ge "$deadline" ]; then
        report timeout "reason=no event in ${MAX_MINUTES}m"
        exit 2
    fi
    sleep "$INTERVAL"
done
