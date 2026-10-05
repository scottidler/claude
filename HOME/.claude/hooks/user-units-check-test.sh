#!/bin/bash
# user-units-check-test.sh: fixture matrix for user-units-check.sh. A fake
# `systemctl` on PATH stands in for the user manager; FAKE_MODE picks the case.
set -u

HOOKS_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
HOOK="${USER_UNITS_CHECK_HOOK:-$HOOKS_DIR/user-units-check.sh}"

SCRATCH="${TMPDIR:-/tmp}/user-units-check-test.$$"
mkdir -p "$SCRATCH/bin"
trap 'rm -rf "$SCRATCH"' EXIT

# The fake honors --type=service the way systemctl does: with it, scope units
# are not listed. Without it, a failed scope shows up.
cat > "$SCRATCH/bin/systemctl" <<'FAKE'
#!/bin/bash
case "$*" in
  *list-units*)
    case "$FAKE_MODE" in
      none) exit 0 ;;
      service) echo "eratosthenes.service loaded failed failed Eratosthenes" ;;
      scope)
        case "$*" in
          *--type=service*) ;;
          *) echo "app-com.google.Chrome-123.scope loaded failed failed Chrome" ;;
        esac ;;
      buserr) echo "Failed to connect to bus: No medium found" >&2; exit 1 ;;
    esac ;;
  *show*) echo 203 ;;
esac
exit 0
FAKE
chmod +x "$SCRATCH/bin/systemctl"

pass=0
fail=0
ok()  { printf 'PASS  %s\n' "$*"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s\n' "$*"; fail=$((fail + 1)); }

run() { # run <mode>: sets OUT, ERR, RC
  OUT=$(FAKE_MODE="$1" PATH="$SCRATCH/bin:$PATH" bash "$HOOK" 2>"$SCRATCH/err"); RC=$?
  ERR=$(cat "$SCRATCH/err")
}

run none
if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then ok "no failed services: empty stdout, exit 0"; else bad "no failed services: rc=$RC out=$OUT"; fi

run service
ctx=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
ev=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)
if [ "$RC" -eq 0 ] && [ "$ev" = "SessionStart" ] \
   && printf '%s' "$ctx" | grep -q 'eratosthenes\.service' \
   && printf '%s' "$ctx" | grep -q 'ExecMainStatus=203'; then
  ok "one failed service: additionalContext names unit and ExecMainStatus"
else
  bad "one failed service: rc=$RC out=$OUT"
fi

run scope
if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then ok "failed .scope units only: empty stdout (needs --type=service)"; else bad "failed .scope units only: rc=$RC out=$OUT"; fi

run buserr
if [ -z "$OUT" ] && [ "$RC" -eq 0 ] && ! printf '%s' "$OUT$ERR" | grep -q 'bus'; then
  ok "systemctl bus error, empty stdout: silent, exit 0, bus error not surfaced"
else
  bad "systemctl bus error: rc=$RC out=$OUT err=$ERR"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
