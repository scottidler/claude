# Gotchas

Measured traps from past sessions. Each names the symptom, the cause, and the fix.

## systemd: `Persistent=true` stalls a timer after reinstall

- Symptom: a timer stops firing after a stop, disable, and reinstall cycle.
- Cause: `Persistent=true` stalls it on this systemd version, even for a timer with no `OnCalendar=` trigger. `man systemd.timer` says `Persistent` only affects `OnCalendar=` timers. The manual is wrong here (A/B tested on throwaway timers, eratosthenes, 2026-11-12).
- Fix: delete the `Persistent=true` line. Do not add `OnActiveSec=` instead.
- Open: `eratosthenes-triage.timer` still carries `Persistent=true` with an `OnCalendar=` trigger. It fires today. Drop the line if it ever stalls.

## zsh 5.9-8ubuntu3: reading `/dev/zero` segfaults the shell

- Symptom: a recurring zsh SIGSEGV.
- Cause: Ubuntu zsh 5.9-8ubuntu3 crashes in `bin_read` on `/dev/zero` reads. A review-panel agent's sleep-substitute pattern triggered it.
- Fix: `hooks/intent-guard.sh` denies the pattern. Do not write a `read` from `/dev/zero` in a zsh command.
