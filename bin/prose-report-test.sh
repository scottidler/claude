#!/bin/bash
# prose-report-test.sh: fixture matrix for bin/prose-report. Builds decision logs
# in the shape prose.sh writes and asserts on the report's lines and exit codes.
set -u
REPORT="$(cd "$(dirname "$0")" && pwd)/prose-report"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/prose-report-test.XXXXXX")
pass=0; fail=0
# The mod's log dir defaults to this host's real one: point it at an empty scratch dir.
export VOICE_GUARD_LOG_DIR="$ROOT/no-mod-logs"

rec() {  # rec <ts> <verdict> <source> <p|null> <reason|null> <ms> <prompt> <final>
  jq -nc --arg ts "$1" --arg v "$2" --arg s "$3" --argjson p "$4" --argjson reason "$5" \
    --argjson ms "$6" --arg prompt "$7" --arg final "$8" \
    '{ts:$ts, session:"s", event:"Stop", verdict:$v, source:$s, p:$p, reason:$reason,
      ms:$ms, threshold:0.5, prompt:$prompt, final:$final}'
}

expect() {  # expect <label> <want-rc> <grep -E pattern | -> -- <args...>
  local label="$1" want="$2" pat="$3"; shift 4
  local out rc
  out=$(python3 -I "$REPORT" "$@" 2>&1); rc=$?
  if [ "$rc" -eq "$want" ] && { [ "$pat" = "-" ] || printf '%s\n' "$out" | grep -Eq "$pat"; }; then
    pass=$((pass+1)); printf 'PASS  %s\n' "$label"
  else
    fail=$((fail+1)); printf 'FAIL  %s (rc=%s)\n%s\n' "$label" "$rc" "$(printf '%s\n' "$out" | head -20 | sed 's/^/      /')"
  fi
}
reject() {  # reject <label> <grep -E pattern> -- <args...>: pattern must NOT appear
  local label="$1" pat="$2"; shift 3
  if python3 -I "$REPORT" "$@" 2>&1 | grep -Eq "$pat"; then
    fail=$((fail+1)); printf 'FAIL  %s\n' "$label"
  else
    pass=$((pass+1)); printf 'PASS  %s\n' "$label"
  fi
}

MIXED="$ROOT/mixed.jsonl"
{ rec 2026-10-01T10:00:00Z allow jev 0.05 null 180 "do we have separate worktrees?" "Want me to"
  rec 2026-10-02T10:00:00Z block jev 0.95 null 220 "fix the build" "Want me to push it"
  rec 2026-10-03T10:00:00Z block jev 0.55 null 400 "check again" "Building can wait on your call"
  rec 2026-10-04T10:00:00Z block verbs null '"curl-exit-28"' 3001 "run it" "Say go"
  rec 2026-10-05T10:00:00Z block slash null null 0 "/babysit the PR" "Want me to merge"
  echo 'not json'
} > "$MIXED"

echo "=== health ==="
expect "counts jev answers" 0 '^  jev answered   3$' -- --log "$MIXED"
expect "counts fallbacks" 0 '^  fallback       1$' -- --log "$MIXED"
expect "names the fallback reason" 0 '^    curl-exit-28 +1$' -- --log "$MIXED"
expect "jev latency percentiles over jev records only" 0 'p50 220  p90 400  max 400' -- --log "$MIXED"
expect "reports unparseable lines" 0 '\[1 unparseable lines skipped\]' -- --log "$MIXED"
reject "no stale warning when Jev is answering" 'WARN' -- --log "$MIXED"

DEAD="$ROOT/dead.jsonl"
for i in 1 2 3 4 5; do rec "2026-10-0${i}T10:00:00Z" block verbs null '"no-key"' 0 "run it" "Say go"; done > "$DEAD"
expect "warns when the last 5 all fell back" 0 'WARN: the last 5 decisions all fell back to the verb list \(no-key\)' -- --log "$DEAD"

echo "=== verdicts ==="
expect "jev block/allow split" 0 '^  jev +block 2 +allow 1$' -- --log "$MIXED"
expect "jev probability bands" 0 '<0.3: 1   0.3-0.7: 1 \(review band\)   >=0.7: 1' -- --log "$MIXED"

echo "=== review ==="
expect "review lists every record by default" 0 '^review \(5 rows' -- --log "$MIXED"
expect "fallback rows show their reason in the p column" 0 'block +verbs +curl-exit-28' -- --log "$MIXED"
expect "--uncertain keeps only the 0.3-0.7 band" 0 '^review \(1 rows' -- --log "$MIXED" --uncertain
expect "--uncertain row is the 0.55 one" 0 '0\.55 .*check again' -- --log "$MIXED" --uncertain
expect "--rows keeps the newest N" 0 '^review \(2 rows' -- --log "$MIXED" --rows 2
expect "--since drops older records" 0 '^records  2 ' -- --log "$MIXED" --since 2026-10-04

echo "=== exit codes ==="
expect "missing log exits 1 with a reason" 1 'no decision log at' -- --log "$ROOT/never-written.jsonl"
: > "$ROOT/empty.jsonl"
expect "empty log exits 1" 1 'has no records' -- --log "$ROOT/empty.jsonl"
expect "--since past every record exits 1" 1 'has no records since 2027-01-01' -- --log "$MIXED" --since 2027-01-01
if PROSE_LOG="$MIXED" python3 -I "$REPORT" 2>&1 | grep -q '^records  5 '; then
  pass=$((pass+1)); echo "PASS  PROSE_LOG env var is the default log"
else
  fail=$((fail+1)); echo "FAIL  PROSE_LOG env var is the default log"
fi

echo "=== voice-guard logs ==="
MOD="$ROOT/mod"; mkdir -p "$MOD"
modrow() {  # modrow <rule|null> <modVerdict> <chainResult> <chainSource|null>
  jq -nc --argjson rule "$1" --arg mv "$2" --arg cr "$3" --argjson cs "$4" \
    '{ts:"2026-10-06T10:00:00Z", session:"s", event:"tool.call", surface:"write", tool:"Write",
      rule:$rule, modVerdict:$mv, chainResult:$cr, chainSource:$cs, mode:"shadow"}'
}
{ modrow '"emdash"' deny deny '"settings"'; modrow null allow allow null; echo '{"event":"dropped","count":3}'; } > "$MOD/s1.111-aaa.jsonl"
{ modrow '"emdash"' deny allow null; } > "$MOD/s2.222-bbb.jsonl"
expect "counts rows from both files" 0 '^  prose.sh     5 rows$' -- --log "$MIXED" --mod-dir "$MOD"
expect "counts the mod's rows across the glob, minus dropped markers" 0 '^  voice-guard  3 rows$' -- --log "$MIXED" --mod-dir "$MOD"
expect "mod section names the file count" 0 '^voice-guard  \(3 rows in 2 files\)' -- --log "$MIXED" --mod-dir "$MOD"
expect "mod section counts chainSource" 0 'chainSource  null 2  settings 1' -- --log "$MIXED" --mod-dir "$MOD"
expect "mod rows alone are enough (no prose.sh file)" 0 '^  prose.sh     0 rows$' -- --log "$ROOT/never-written.jsonl" --mod-dir "$MOD"
VOICE_GUARD_LOG_DIR="$MOD" expect "VOICE_GUARD_LOG_DIR is the default mod dir" 0 '^  voice-guard  3 rows$' -- --log "$MIXED"
reject "no mod rows, no mod section" '^voice-guard  \(' -- --log "$MIXED"
expect "--since filters the mod's rows too" 1 'has no records since 2027-01-01' -- --log "$MIXED" --mod-dir "$MOD" --since 2027-01-01

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
