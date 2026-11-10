#!/usr/bin/env bash
# Regression matrix for seats/watchdog.sh and its wiring into both seat scripts.
# Fake gemini/codex binaries on PATH stand in for the models, so this runs in
# seconds with no network. Each case pins one way the watchdog can be wrong:
#   - a silent seat must die on the idle limit, not the ceiling
#   - a seat that keeps writing must NOT die on the idle limit
#   - a seat that keeps writing past the ceiling dies on the ceiling
#   - a healthy seat still returns its review
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/watchdog-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
pass=0
fail=0
check() {
  if [ "$1" = ok ]; then pass=$((pass + 1)); echo "  PASS  $2"; else fail=$((fail + 1)); echo "  FAIL  $2"; fi
}

# shellcheck source=watchdog.sh
. "$HERE/watchdog.sh"

echo "== seat_seconds =="
[ "$(seat_seconds 90)" = 90 ] && [ "$(seat_seconds 45s)" = 45 ] && [ "$(seat_seconds 8m)" = 480 ] \
  && [ "$(seat_seconds 1h)" = 3600 ] && check ok "parses N, Ns, Nm, Nh" || check no "parses N, Ns, Nm, Nh"
seat_seconds 5x >/dev/null 2>&1 && check no "rejects 5x" || check ok "rejects 5x"
seat_seconds '' >/dev/null 2>&1 && check no "rejects empty" || check ok "rejects empty"

echo "== watch_progress =="
export SEAT_POLL_SECS=1
T="$WORK/trace"
: >"$T"
timeout 30s sleep 25 &
start=$(date +%s)
watch_progress "$!" "$T" 2
el=$(( $(date +%s) - start ))
[ "$SEAT_IDLE_KILLED" = 1 ] && [ "$el" -lt 10 ] && check ok "silent child killed on idle (${el}s)" \
  || check no "silent child killed on idle (killed=$SEAT_IDLE_KILLED, ${el}s)"

: >"$T"
timeout 30s bash -c "for i in 1 2 3 4 5 6; do echo tick >>'$T'; sleep 1; done" &
watch_progress "$!" "$T" 3
rc=$?
[ "$SEAT_IDLE_KILLED" = 0 ] && [ "$rc" = 0 ] && check ok "writing child survives past idle limit (max gap ${SEAT_MAX_GAP}s)" \
  || check no "writing child survives (killed=$SEAT_IDLE_KILLED rc=$rc)"

echo "== seat scripts, end to end =="
BIN="$WORK/bin"
mkdir -p "$BIN"
# FAKE_MODE: ok | silent | chatty. gemini emits stream-json; codex writes -o.
cat >"$BIN/gemini" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo '{"type":"init"}'
case "$FAKE_MODE" in
  silent) sleep 60 ;;
  chatty) while :; do echo '{"type":"tool_use"}'; sleep 1; done ;;
esac
echo '{"type":"message","role":"assistant","content":"FAKE REVIEW"}'
echo '{"type":"result","status":"success"}'
EOF
cat >"$BIN/codex" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
out=""
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
echo "exec"
case "$FAKE_MODE" in
  silent) sleep 60 ;;
  chatty) while :; do echo "exec"; sleep 1; done ;;
esac
echo "FAKE REVIEW" >"$out"
EOF
chmod +x "$BIN/gemini" "$BIN/codex"
echo "# doc" >"$WORK/doc.md"

for seat in architect staff-engineer; do
  envp=ARCHITECT; [ "$seat" = staff-engineer ] && envp=STAFF_ENGINEER
  run() {
    env PATH="$BIN:$PATH" TMPDIR="$WORK" FAKE_MODE="$1" \
      "${envp}_IDLE=$2" "${envp}_WALL_CLOCK=$3" "${envp}_PIDFILE=$WORK/$seat.pid" \
      bash "$HERE/$seat/script.sh" "$WORK/doc.md" "review it" "" >"$WORK/out" 2>"$WORK/err"
  }
  run ok 5s 30s; rc=$?
  [ "$rc" = 0 ] && rg -q 'FAKE REVIEW' "$WORK/out" && check ok "$seat: healthy run returns review" \
    || check no "$seat: healthy run (rc=$rc)"
  run silent 3s 30s; rc=$?
  [ "$rc" = 124 ] && rg -q 'killed as hung' "$WORK/err" && check ok "$seat: silent run dies on idle" \
    || check no "$seat: silent run (rc=$rc: $(head -c 300 "$WORK/err"))"
  start=$(date +%s)
  run chatty 3s 6s; rc=$?
  el=$(( $(date +%s) - start ))
  [ "$rc" = 124 ] && rg -q 'ceiling' "$WORK/err" && [ "$el" -lt 20 ] && check ok "$seat: chatty run dies on ceiling, not idle (${el}s)" \
    || check no "$seat: chatty run (rc=$rc ${el}s: $(head -c 300 "$WORK/err"))"
done

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
