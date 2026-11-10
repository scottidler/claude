# shellcheck shell=bash
# shellcheck disable=SC2034  # SEAT_* globals are read by the sourcing script
# Progress watchdog shared by seats/architect/script.sh and
# seats/staff-engineer/script.sh. Sourced, never executed.
#
# WHY (2026-11-06, drata-cli v2 endpoint coverage audit). Both seats ran under a
# flat 10m wall clock on the premise that over 10m means hung. That audit killed
# both at 10m while they were still working: codex had run 41 shell commands and
# written a 908 KB trace, gemini was still issuing tool calls. A flat clock
# measures elapsed time, not progress. A hung seat is one whose trace stopped
# growing, so that is what this kills on. The wall clock stays, raised, as a
# ceiling.
#
# The idle limit was set from data, not a guess: across 16 preserved gemini
# traces in $TMPDIR the longest silence between two stream events was 317s
# (twice), in runs that were still making progress. The default idle limit of
# 480s clears that with margin. codex writes no timestamps, so its gaps are
# unmeasured; every run now prints its longest silence so the data accrues.

# seat_seconds <duration>: 90, 90s, 8m or 1h to whole seconds. Fails on garbage
# rather than defaulting, so a typo in an env override is loud.
seat_seconds() {
  local d=$1
  case "$d" in
    *[!0-9smh]* | '' ) echo "error: bad duration '$d' (want N, Ns, Nm or Nh)" >&2; return 2 ;;
    *h) echo $(( ${d%h} * 3600 )) ;;
    *m) echo $(( ${d%m} * 60 )) ;;
    *s) echo "${d%s}" ;;
    *)  echo "$d" ;;
  esac
}

# watch_progress <pid> <trace> <idle_secs>: poll until <pid> exits. If <trace>
# does not grow for <idle_secs>, TERM <pid> (a `timeout` process, which forwards
# the signal to its child and escalates to KILL after its --kill-after).
# Returns <pid>'s exit status. Sets globals:
#   SEAT_IDLE_KILLED  1 if this function killed it for silence, else 0
#   SEAT_MAX_GAP      longest silence seen, in seconds (poll granularity)
# Must not touch errexit: the caller owns it (see run_attempt in each script).
watch_progress() {
  local pid=$1 trace=$2 idle=$3
  local poll="${SEAT_POLL_SECS:-10}"
  local size prev=-1 now last gap rc=0
  SEAT_IDLE_KILLED=0
  SEAT_MAX_GAP=0
  last=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$poll"
    size=$(stat -c %s "$trace" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [ "$size" != "$prev" ]; then
      prev=$size
      last=$now
    fi
    gap=$(( now - last ))
    if [ "$gap" -gt "$SEAT_MAX_GAP" ]; then
      SEAT_MAX_GAP=$gap
    fi
    if [ "$gap" -ge "$idle" ] && kill -0 "$pid" 2>/dev/null; then
      SEAT_IDLE_KILLED=1
      kill -TERM "$pid" 2>/dev/null
      break
    fi
  done
  wait "$pid" || rc=$?
  return "$rc"
}
