#!/usr/bin/env python3
"""Derive the Phase 3 measurement variants from the guard ON DISK.

Variant A is the shipped guard, copied byte for byte. The harvested
`phase0/replay/variantA.sh` is NOT usable as the baseline arm: its
`posting_intent` greps the raw prompt (`variantA.sh:354-356`) while the shipped
guard strips harness tags first (`slack-post-guard.sh:396-405`), so scoring a
post-fix variant against it would measure the tag fix, not the TARGET rule.

Variants B and C carry Phase 4's `resolve_names` change (the `dms` map replaces
the `.users` DM branch in BOTH jq programs) and differ only in the TARGET loop:

  B  name-mandatory for non-exempt DMs, posting_intent still rescues channels
  C  name-mandatory for every non-exempt recipient, posting_intent gone

Nothing here is a proposal for what Phase 4 ships. These are measurement arms.
"""
import pathlib
import shutil
import sys

HERE = pathlib.Path(__file__).resolve().parent
SHIPPED = HERE.parent.parent.parent / "HOME/.claude/hooks/slack-post-guard.sh"

# ---- the `dms` clause, both jq programs -----------------------------------

# Program 1 (`resolve_names`, the id/label program). `.users` is `D… -> handle`
# and holds 18 keys from a retired tool; `.dms` is `D… -> U…` and holds 232.
PROG1_OLD = """    | ( .users // {} ) as $dm
"""
PROG1_NEW = """    | ( .dms // {} ) as $dm
"""

PROG1_ITS_OLD = """    # dm: by dm id, or by the handle it holds
    | ( [ $dm | to_entries[] | select(.key == $s or .value == $b) ] ) as $dmits
"""
PROG1_ITS_NEW = """    # dm: by dm id, which the dms map takes straight to a user id
    | ( [ $dm | to_entries[] | select(.key == $s) ] ) as $dmits
"""

PROG1_EMIT_OLD = """        ( $dmits[] | .key, .value ),
        ( $dmits[] | .value as $h | $hd | to_entries[] | select(.value == $h) | .key ),
"""
PROG1_EMIT_NEW = """        ( $dmits[] | .key, .value, ( $hd[.value] // empty ) ),
"""

# Program 2 (the first-name program).
PROG2_OLD = """    | ( .users // {} ) as $dm
    | ( .handles // {} ) as $hd
    | ( .profiles // {} ) as $pr
    | [ ( $dm | to_entries[] | select(.key == $s or .value == $b) | .value ),
        ( $hd | to_entries[] | select(.key == $s or .value == $b) | .value ) ] as $handles
    | ( [ $handles[] as $h | $hd | to_entries[] | select(.value == $h) | .key ] ) as $uids
"""
PROG2_NEW = """    | ( .dms // {} ) as $dm
    | ( .handles // {} ) as $hd
    | ( .profiles // {} ) as $pr
    | ( [ $dm | to_entries[] | select(.key == $s) | .value ] ) as $dmuids
    | [ ( $dmuids[] | $hd[.] // empty ),
        ( $hd | to_entries[] | select(.key == $s or .value == $b) | .value ) ] as $handles
    | ( [ $handles[] as $h | $hd | to_entries[] | select(.value == $h) | .key ]
        + $dmuids ) as $uids
"""

# ---- is_dm_spelling, variant B only ---------------------------------------

ANCHOR = """# ------------------------------------------------------------ the prompt ---
"""

IS_DM = """# is_dm_spelling <spelling> -> 0 when this recipient is a person, not a channel
#
# Variant B's discriminator. A `D…` or `U…` id is a DM by construction; a bare
# spelling is a DM when it resolves to a handle and NOT to a channel, which is
# how a `dm_mentioned` fan-out recipient arrives. An unresolvable spelling is
# treated as not-a-DM, so the weak condition still covers it.
is_dm_spelling() {
  local s="$1" b="${s#@}"
  case "$s" in
    \\#*) return 1 ;;
    D[A-Z0-9][A-Z0-9][A-Z0-9]*) return 0 ;;
    U[A-Z0-9][A-Z0-9][A-Z0-9]*) return 0 ;;
  esac
  [ -r "$IDS" ] || return 1
  jq -e --arg s "$s" --arg b "$b" '
    ( .channels // {} ) as $ch
    | ( .handles // {} ) as $hd
    | if ( [ $ch | to_entries[] | select(.key == $s or .value == $b) ] | length ) > 0
      then false
      else ( [ $hd | to_entries[] | select(.key == $s or .value == $b) ] | length ) > 0
      end
  ' "$IDS" >/dev/null 2>&1
}

"""

# ---- the TARGET loop -------------------------------------------------------

LOOP_OLD = """if ! posting_intent "$prompt"; then
  for r in "${nonexempt[@]}"; do
    mapfile -t names < <(resolve_names "$r")
    if ! prompt_names "$prompt" "${names[@]}"; then
      deny "slack-post-guard: no typed turn in the last $PROMPT_WINDOW asked for a Slack post, and nothing in them names \\`$r\\`. A post goes where Scott asked for it. Ask him, or post to #clipboard."
    fi
  done
fi
"""

LOOP_B = """for r in "${nonexempt[@]}"; do
  mapfile -t names < <(resolve_names "$r")
  prompt_names "$prompt" "${names[@]}" && continue
  if is_dm_spelling "$r"; then
    deny "slack-post-guard: nothing in the last $PROMPT_WINDOW typed turns names \\`$r\\`. A DM goes to the person Scott named. Ask him, or post to #clipboard."
  fi
  posting_intent "$prompt" && continue
  deny "slack-post-guard: no typed turn in the last $PROMPT_WINDOW asked for a Slack post, and nothing in them names \\`$r\\`. A post goes where Scott asked for it. Ask him, or post to #clipboard."
done
"""

LOOP_C = """for r in "${nonexempt[@]}"; do
  mapfile -t names < <(resolve_names "$r")
  prompt_names "$prompt" "${names[@]}" && continue
  deny "slack-post-guard: nothing in the last $PROMPT_WINDOW typed turns names \\`$r\\`. A post goes where Scott named it. Ask him, or post to #clipboard."
done
"""


def sub(text, old, new, label):
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected exactly 1 match, found {text.count(old)}")
    return text.replace(old, new)


def main():
    shipped = SHIPPED.read_text()
    shutil.copy2(SHIPPED, HERE / "variant-a.sh")

    # Program 2 first: its `.users` line is identical to program 1's, and the
    # longer block around it is what makes each replacement unambiguous.
    dms = sub(shipped, PROG2_OLD, PROG2_NEW, "prog2")
    dms = sub(dms, PROG1_OLD, PROG1_NEW, "prog1 .users")
    dms = sub(dms, PROG1_ITS_OLD, PROG1_ITS_NEW, "prog1 $dmits")
    dms = sub(dms, PROG1_EMIT_OLD, PROG1_EMIT_NEW, "prog1 emit")

    b = sub(dms, ANCHOR, IS_DM + ANCHOR, "is_dm_spelling")
    b = sub(b, LOOP_OLD, LOOP_B, "loop B")
    c = sub(dms, LOOP_OLD, LOOP_C, "loop C")

    for name, body in (("variant-b.sh", b), ("variant-c.sh", c)):
        path = HERE / name
        path.write_text(body)
        path.chmod(0o755)
        print(f"wrote {path.name}  {len(body)} bytes")
    print(f"wrote variant-a.sh  {len(shipped)} bytes (byte copy of {SHIPPED})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
