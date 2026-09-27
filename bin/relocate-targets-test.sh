#!/bin/bash
# relocate-targets-test.sh: fixture matrix for the relocate-targets skill script.
#
# Every case gets a fresh ROOT (a plain dir) and a fresh DEST (its own tmpfs),
# inside a rootless user+mount namespace. DEST's st_dev differs from ROOT's, so
# the script's mount guard passes, and a full DEST is a kernel ENOSPC, not a
# stub. PATH shims stand in for notify-send (no desktop toasts), stat (a
# foreign-owned source: a rootless namespace cannot chown), ln (a pause at the
# commit point), tar (a pause mid-copy) and mv (a failed set-aside rename).
# Processes that must reach a state before the test acts signal it over a fifo;
# nothing syncs on a sleep.
#
# RELOCATE_TARGETS overrides the script under test, so a mutated copy can prove
# a case bites.
set -u
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
RT="$(realpath "${RELOCATE_TARGETS:-${HERE}/../HOME/.claude/skills/relocate-targets/scripts/relocate-targets}")"

if [ -z "${RT_TEST_IN_NS:-}" ]; then
  exec unshare -rm env RT_TEST_IN_NS=1 RELOCATE_TARGETS="${RT}" bash "$0" "$@"
fi

pass=0
fail=0

eq() { # eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$1"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n      want [%s]\n      got  [%s]\n' "$1" "$2" "$3"
  fi
}

W="$(realpath "$(mktemp -d "${TMPDIR:-/tmp}/relocate-targets-test.XXXXXX")")"
cleanup() {
  local m
  for m in "$W"/case*/dest; do umount -l "$m" 2>/dev/null; done
  rm -rf -- "$W"   # regenerable: this run's own mktemp fixtures
}
trap cleanup EXIT

REAL_LN="$(command -v ln)"
REAL_STAT="$(command -v stat)"
REAL_TAR="$(command -v tar)"
REAL_MV="$(command -v mv)"

SHIMS="$W/shims"
mkdir -p "$SHIMS" "$W/stat-shim" "$W/ln-shim" "$W/tar-shim" "$W/mv-shim"
cat > "$SHIMS/notify-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$RT_TOASTS"
EOF
cat > "$W/stat-shim/stat" <<EOF
#!/bin/bash
for a in "\$@"; do [ "\$a" = "%u" ] && { echo 65534; exit 0; }; done
exec "$REAL_STAT" "\$@"
EOF
cat > "$W/ln-shim/ln" <<EOF
#!/bin/bash
echo ready > "\$RT_READY"
read -r cmd < "\$RT_GO"
[ "\$cmd" = go ] && exec "$REAL_LN" "\$@"
exit 1
EOF
cat > "$W/tar-shim/tar" <<EOF
#!/bin/bash
case " \$* " in
  *" -xpf "*) "$REAL_TAR" "\$@" || exit; echo ready > "\$RT_READY"; read -r _ < "\$RT_GO" ;;
  *) exec "$REAL_TAR" "\$@" ;;
esac
EOF
cat > "$W/mv-shim/mv" <<EOF
#!/bin/bash
case " \$* " in
  *.relocated-*) echo "mv: shim refuses \$*" >&2; exit 1 ;;
  *) exec "$REAL_MV" "\$@" ;;
esac
EOF
chmod +x "$SHIMS"/* "$W"/*-shim/*

n=0
fresh() { # fresh [tmpfs options]: sets C ROOT DEST LOG for a new case
  n=$((n + 1))
  C="$W/case$n"
  ROOT="$C/root"
  DEST="$C/dest"
  LOG="$C/log"
  mkdir -p "$ROOT" "$DEST"
  mount -t tmpfs -o "${1:-size=64m}" tmpfs "$DEST"
  mkfifo "$C/ready" "$C/go"
}

repo() { mkdir -p "$ROOT/$1"; touch "$ROOT/$1/Cargo.toml"; }

build() { # build <repo> <nfiles>: a plain target/ holding n small files
  local i
  mkdir -p "$ROOT/$1/target/debug"
  for i in $(seq "$2"); do printf 'artifact %s\n' "$i" > "$ROOT/$1/target/debug/f$i"; done
}

kind() {
  if [ -L "$1" ]; then echo link
  elif [ -d "$1" ]; then echo dir
  elif [ -e "$1" ]; then echo file
  else echo absent
  fi
}

entries() { find "$1" | wc -l; }
logged() { grep -c -- "$1" "$LOG"; }

# rt [shim dir] -- [args]: exec the script against this case's ROOT and DEST,
# with no free-space floor unless the args set one (a later --min-free wins).
# It execs so that `rt ... & pid=$!` is the script's own pid: a signal sent to
# a backgrounded function's subshell never reaches the script.
rt() {
  local extra="$1"; shift
  [ "${1:-}" = -- ] && shift
  RT_TOASTS="$C/toasts" RT_READY="$C/ready" RT_GO="$C/go" \
    PATH="${extra:+$extra:}$SHIMS:$PATH" \
    exec "$RT" --root "$ROOT" --dest "$DEST" --min-free 0 "$@" 2>>"$LOG"
}
run() { (rt "$@"); }

# Run from somewhere that is neither ROOT nor a link's dir, so a relative link
# resolved against the CWD instead of its own dir would miss.
cd /

echo "=== argument validation ==="
fresh
run "" -- --min-free lots; rc=$?
eq 'a non-integer --min-free exits 2' 2 "$rc"
run "" -- --lock-wait soon; rc=$?
eq 'a non-integer --lock-wait exits 2' 2 "$rc"
run "" -- --lock-wait 010; rc=$?
eq 'a leading-zero --lock-wait exits 2' 2 "$rc"
fresh
repo o/r
build o/r 3
before=$(entries "$ROOT/o/r/target")
run "" -- --min-free 08; rc=$?
eq 'a leading-zero --min-free exits 2' 2 "$rc"
eq 'leading-zero --min-free: source untouched' "$before" "$(entries "$ROOT/o/r/target")"

echo "=== insufficient space ==="
fresh size=64m
repo o/r
build o/r 5
before=$(entries "$ROOT/o/r/target")
run "" -- --min-free 40; rc=$?
eq 'insufficient space: exit 0' 0 "$rc"
eq 'insufficient space: WARN logged' 1 "$(logged 'WARN insufficient space for o/r: need=.* avail=.* floor=40G')"
eq 'insufficient space: source is still a plain dir' dir "$(kind "$ROOT/o/r/target")"
eq 'insufficient space: source untouched' "$before" "$(entries "$ROOT/o/r/target")"
eq 'insufficient space: no dst created' absent "$(kind "$DEST/o/r")"
eq 'insufficient space: the warning count reaches the desktop' 1 "$(grep -c '1 warning(s)' "$C/toasts" 2>/dev/null)"

echo "=== ENOSPC mid-tar (inode-starved DEST) ==="
fresh size=64m,nr_inodes=16
repo o/r
build o/r 40
before=$(entries "$ROOT/o/r/target")
run ""; rc=$?
eq 'ENOSPC: exit 0' 0 "$rc"
eq 'ENOSPC: tar failure logged' 1 "$(logged 'ERROR tar pipe failed')"
eq 'ENOSPC: source is still a plain dir' dir "$(kind "$ROOT/o/r/target")"
eq 'ENOSPC: source intact' "$before" "$(entries "$ROOT/o/r/target")"
eq 'ENOSPC: partial dst removed' absent "$(kind "$DEST/o/r/target")"

echo "=== SIGTERM mid-copy removes the partial dst ==="
fresh
repo o/r
build o/r 5
before=$(entries "$ROOT/o/r/target")
rt "$W/tar-shim" & pid=$!
read -r _ < "$C/ready"
kill -TERM "$pid"
echo go > "$C/go"
wait "$pid"; rc=$?
eq 'mid-copy SIGTERM: exit 143' 143 "$rc"
eq 'mid-copy SIGTERM: interruption logged' 1 "$(logged 'ERROR interrupted mid-copy')"
eq 'mid-copy SIGTERM: partial dst removed' absent "$(kind "$DEST/o/r/target")"
eq 'mid-copy SIGTERM: source intact' "$before" "$(entries "$ROOT/o/r/target")"

echo "=== dangling links into DEST ==="
fresh
repo o/final
mkdir -p "$DEST/o/final"
"$REAL_LN" -s "$DEST/o/final/target" "$ROOT/o/final/target"
repo o/middle
"$REAL_LN" -s "$DEST/o/middle/target" "$ROOT/o/middle/target"
repo o/rel
"$REAL_LN" -s ../../../dest/o/rel/target "$ROOT/o/rel/target"
repo o/outside
"$REAL_LN" -s "$C/elsewhere/target" "$ROOT/o/outside/target"
repo o/escape
"$REAL_LN" -s "$DEST/../escape/target" "$ROOT/o/escape/target"
run ""; rc=$?
eq 'dangling: exit 0' 0 "$rc"
eq 'dangling, final component missing: link resolves' dir "$(kind "$ROOT/o/final/target/.")"
eq 'dangling, middle component missing: link resolves' dir "$(kind "$ROOT/o/middle/target/.")"
eq 'dangling, relative link: resolved against its own dir' dir "$(kind "$DEST/o/rel/target")"
eq 'dangling: three repairs logged' 3 "$(logged 'repaired dangling link')"
eq 'dangling: repaired count in the summary' 1 "$(logged 'repaired=3 ')"
eq 'dangling outside DEST: nothing created' absent "$(kind "$C/elsewhere")"
eq 'dangling DEST/.. escape: nothing created' absent "$(kind "$C/escape")"
eq 'dangling outside DEST: both still WARN' 2 "$(logged 'not into DEST); leaving alone')"

echo "=== --dry-run creates nothing ==="
fresh
repo o/plain
build o/plain 3
repo o/new
repo o/dangling
"$REAL_LN" -s "$DEST/o/dangling/target" "$ROOT/o/dangling/target"
mkdir -p "$ROOT/o/plain/target.relocated-1"
find "$DEST" -exec touch -h -d @1000000000 {} +
touch "$C/stamp"
root_before=$(find "$ROOT" | sort)
run "" -- --dry-run; rc=$?
eq 'dry-run: exit 0' 0 "$rc"
eq 'dry-run: nothing under DEST is newer than the stamp' '' "$(find "$DEST" -newer "$C/stamp")"
eq 'dry-run: ROOT unchanged' "$root_before" "$(find "$ROOT" | sort)"
eq 'dry-run: no lock file' absent "$(kind "$DEST/.relocate.lock")"

echo "=== lock held, released while the run waits ==="
fresh
repo o/r
build o/r 3
flock "$DEST/.relocate.lock" bash -c 'echo held > "$1"; sleep 2' _ "$C/ready" & holder=$!
read -r _ < "$C/ready"
start=$SECONDS
run "" -- --lock-wait 30; rc=$?
waited=$((SECONDS - start))
wait "$holder"
eq 'lock released: exit 0' 0 "$rc"
eq 'lock released: the run waited for it' yes "$([ "$waited" -ge 1 ] && echo yes || echo no)"
eq 'lock released: migrated' link "$(kind "$ROOT/o/r/target")"

echo "=== lock held past --lock-wait ==="
fresh
repo o/r
build o/r 3
flock "$DEST/.relocate.lock" bash -c 'echo held > "$1"; read -r _ < "$2"' _ "$C/ready" "$C/go" & holder=$!
read -r _ < "$C/ready"
run "" -- --lock-wait 1; rc=$?
echo done > "$C/go"
wait "$holder"
eq 'lock timeout: exit 1' 1 "$rc"
eq 'lock timeout: ERROR logged' 1 "$(logged 'ERROR lock held')"
eq 'lock timeout: nothing migrated' dir "$(kind "$ROOT/o/r/target")"
eq 'lock timeout: no dst' absent "$(kind "$DEST/o/r")"

echo "=== source owned by another uid ==="
fresh
repo o/r
build o/r 3
before=$(entries "$ROOT/o/r/target")
run "$W/stat-shim"; rc=$?
eq 'foreign owner: exit 0' 0 "$rc"
eq 'foreign owner: WARN logged' 1 "$(logged "WARN $ROOT/o/r/target not owned by uid $(id -u) (owner=65534)")"
eq 'foreign owner: source untouched' "$before" "$(entries "$ROOT/o/r/target")"
eq 'foreign owner: no dst' absent "$(kind "$DEST/o/r")"

echo "=== source owned by another uid, --remote (the check is local-only) ==="
fresh
repo o/r
build o/r 3
run "$W/stat-shim" -- --remote unused --repo "$ROOT/o/r" --dry-run; rc=$?
eq 'remote foreign owner: exit 0' 0 "$rc"
eq 'remote foreign owner: no ownership WARN' 0 "$(logged 'not owned by uid')"
eq 'remote foreign owner: counted migrated' 1 "$(logged 'migrated=1 ')"

echo "=== setting the source aside fails after a verified copy ==="
fresh
repo o/r
build o/r 5
before=$(entries "$ROOT/o/r/target")
run "$W/mv-shim"; rc=$?
eq 'set-aside failure: exit 0' 0 "$rc"
eq 'set-aside failure: ERROR logged' 1 "$(logged 'ERROR could not set .* aside')"
eq 'set-aside failure: source is still a plain dir' dir "$(kind "$ROOT/o/r/target")"
eq 'set-aside failure: source untouched' "$before" "$(entries "$ROOT/o/r/target")"
eq 'set-aside failure: no link inside the source' absent "$(kind "$ROOT/o/r/target/target")"
eq 'set-aside failure: dst removed' absent "$(kind "$DEST/o/r/target")"
eq 'set-aside failure: not counted migrated' 1 "$(logged 'migrated=0 ')"

echo "=== SIGTERM at the commit point (before the link) ==="
fresh
repo o/r
build o/r 5
before=$(entries "$ROOT/o/r/target")
rt "$W/ln-shim" & pid=$!
read -r _ < "$C/ready"
kill -TERM "$pid"
wait "$pid"; rc=$?
echo abort > "$C/go"
eq 'commit-point SIGTERM: killed' 143 "$rc"
eq 'commit-point SIGTERM: dst present' dir "$(kind "$DEST/o/r/target")"
eq 'commit-point SIGTERM: dst complete' "$before" "$(entries "$DEST/o/r/target")"
eq 'commit-point SIGTERM: target absent, not a plain dir' absent "$(kind "$ROOT/o/r/target")"
eq 'commit-point SIGTERM: source set aside, not deleted' 1 "$(find "$ROOT/o/r" -maxdepth 1 -name 'target.relocated-*' | wc -l)"
run ""; rc=$?
eq 'commit-point rerun: exit 0' 0 "$rc"
eq 'commit-point rerun: re-adopted via the pre-link branch' 1 "$(logged '\[o/r\] no target yet -> pre-linking')"
eq 'commit-point rerun: target links to dst' "$DEST/o/r/target" "$(readlink "$ROOT/o/r/target")"
eq 'commit-point rerun: dst still complete' "$before" "$(entries "$DEST/o/r/target")"
eq 'commit-point rerun: set-aside source removed' 0 "$(find "$ROOT/o/r" -maxdepth 1 -name 'target.relocated-*' | wc -l)"

echo "=== leftover target.relocated-* ==="
fresh
repo o/r
mkdir -p "$ROOT/o/r/target.relocated-99999/debug"
touch "$ROOT/o/r/target.relocated-99999/debug/f"
run ""; rc=$?
eq 'leftover: exit 0' 0 "$rc"
eq 'leftover: removed' absent "$(kind "$ROOT/o/r/target.relocated-99999")"
eq 'leftover: removal logged' 1 "$(logged 'removing leftover')"

echo "=== owner markers ==="
fresh
repo o/pre
repo o/mig
build o/mig 3
repo o/dang
"$REAL_LN" -s "$DEST/o/dang/target" "$ROOT/o/dang/target"
repo o/done
mkdir -p "$DEST/o/done/target"
"$REAL_LN" -s "$DEST/o/done/target" "$ROOT/o/done/target"
repo o/clyde
repo o/clyde.sav
mkdir -p "$DEST/o/clyde/target"
"$REAL_LN" -s "$DEST/o/clyde/target" "$ROOT/o/clyde/target"
"$REAL_LN" -s "$DEST/o/clyde/target" "$ROOT/o/clyde.sav/target"
run ""; rc=$?
run ""; rc2=$?
eq 'markers: both runs exit 0' '0 0' "$rc $rc2"
eq 'marker: pre-link' "$ROOT/o/pre/target" "$(cat "$DEST/o/pre/.relocate-link" 2>/dev/null)"
eq 'marker: migrate' "$ROOT/o/mig/target" "$(cat "$DEST/o/mig/.relocate-link" 2>/dev/null)"
eq 'marker: dangling repair' "$ROOT/o/dang/target" "$(cat "$DEST/o/dang/.relocate-link" 2>/dev/null)"
eq 'marker: already-done visit' "$ROOT/o/done/target" "$(cat "$DEST/o/done/.relocate-link" 2>/dev/null)"
eq 'marker: two links sharing one target, one line each, beside the referent' \
  "$(printf '%s\n%s' "$ROOT/o/clyde.sav/target" "$ROOT/o/clyde/target")" \
  "$(sort "$DEST/o/clyde/.relocate-link" 2>/dev/null)"
eq 'marker: nothing beside the would-be ssd of the second link' absent "$(kind "$DEST/o/clyde.sav")"
eq 'markers: no warnings, so no toast' absent "$(kind "$C/toasts")"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
