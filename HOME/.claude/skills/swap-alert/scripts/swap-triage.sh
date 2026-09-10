#!/usr/bin/env bash
# One-shot memory/swap triage for desk.lan. Read-only.
#
# Must run OUTSIDE the Claude Code bash sandbox: the sandbox has its own PID
# namespace, so every per-process section is empty inside it.
#
#   swap-triage.sh              live snapshot + verdict
#   swap-triage.sh --at HH:MM [YYYYMMDD]   per-process swap at that time from atop logs
set -uo pipefail

section() { printf '\n== %s ==\n' "$1"; }
kb_g() { awk -v k="$1" 'BEGIN{printf "%.1f", k/1024/1024}'; }

if [ "${1:-}" = "--at" ]; then
  t="${2:?HH:MM}"; day="${3:-$(date +%Y%m%d)}"
  log="/var/log/atop/atop_${day}"
  [ -r "$log" ] || { echo "no atop log at $log"; exit 1; }
  end=$(date -d "$day $t 1 minute" +%H:%M)
  section "per-process swap at $day $t (atop)"
  atop -r "$log" -b "$t" -e "$end" -P PRM 2>/dev/null | awk '
    $1=="PRM" { i=8; while ($i !~ /\)$/ && i<NF) i++; name=$8; for (j=9;j<=i;j++) name=name" "$j
      rss=$(i+4); swap=$(i+13); isproc=$(i+15)
      if (isproc=="y" && swap+0>200000) printf "%6d MB swap %6d MB rss  pid=%-8s %s\n", swap/1024, rss/1024, $7, name }' \
    | sort -rn | head -15
  section "memory timeline that day (atopsar, hourly; swpfree column is total swap free)"
  atopsar -r "$log" -m 2>/dev/null | awk 'NR==5 || /^[0-9][0-9]:00:/' | cut -c1-100
  exit 0
fi

if [ "$(ps -o comm= -p 1 2>/dev/null)" != "systemd" ]; then
  echo "WARNING: PID 1 is not systemd -> inside the sandbox; per-process sections will be empty. Re-run with the sandbox disabled." >&2
fi

mem_total=$(awk '/^MemTotal/{print $2}' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable/{print $2}' /proc/meminfo)
swap_total=$(awk '/^SwapTotal/{print $2}' /proc/meminfo)
swap_free=$(awk '/^SwapFree/{print $2}' /proc/meminfo)
swap_used=$((swap_total - swap_free))
sw=$(swapon --show=NAME,USED --bytes --noheadings 2>/dev/null)
disk_mb=$(awk '$1=="/swap.img"{printf "%d", $2/1024/1024}' <<<"$sw"); disk_mb=${disk_mb:-0}
zram_mb=$(awk '$1=="/dev/zram0"{printf "%d", $2/1024/1024}' <<<"$sw"); zram_mb=${zram_mb:-0}
read -r _ _ zphys zlim _ < <(cat /sys/block/zram0/mm_stat 2>/dev/null || echo 0 0 0 0 0)
psi_some=$(awk '/^some/{print $2, $3, $4}' /proc/pressure/memory)
psi_full=$(awk '/^full/{print $2, $3, $4}' /proc/pressure/memory)
psi_full60=$(awk '/^full/{split($3,a,"="); print a[2]}' /proc/pressure/memory)

section "headline  $(hostname)  $(date '+%F %T')"
printf 'RAM        total %sG   available %sG (%d%%)\n' "$(kb_g "$mem_total")" "$(kb_g "$mem_avail")" $((mem_avail*100/mem_total))
printf 'swap       used %sG of %sG\n' "$(kb_g "$swap_used")" "$(kb_g "$swap_total")"
printf 'zram0      %dM logical used, %dM physical of %dM limit   (prio 100: fast tier, filling it is by design)\n' "$zram_mb" $((zphys/1024/1024)) $((zlim/1024/1024))
printf '/swap.img  %dM used   (prio -1: disk overflow; swap-watch alerts on this number)\n' "$disk_mb"
printf 'PSI some   %s\nPSI full   %s   (ground truth: >0 means tasks actually stalled)\n' "$psi_some" "$psi_full"
printf 'sysctl     vm.swappiness=%s vm.page-cluster=%s\n' "$(cat /proc/sys/vm/swappiness)" "$(cat /proc/sys/vm/page-cluster)"

read -r in0 out0 < <(awk '/^pswpin/{i=$2} /^pswpout/{o=$2} END{print i, o}' /proc/vmstat)
sleep 5
read -r in1 out1 < <(awk '/^pswpin/{i=$2} /^pswpout/{o=$2} END{print i, o}' /proc/vmstat)
si=$(( (in1-in0)*4/5 )); so=$(( (out1-out0)*4/5 ))
section "swap I/O (5s sample)"
printf 'swap-in %d KB/s   swap-out %d KB/s\n' "$si" "$so"

section "verdict"
if awk -v v="$psi_full60" 'BEGIN{exit !(v>=1.0)}'; then
  echo "REAL PRESSURE: PSI full avg60=${psi_full60}% -> tasks are stalled on memory"
elif [ "$mem_avail" -lt $((8*1024*1024)) ]; then
  echo "REAL PRESSURE: only $(kb_g "$mem_avail")G available"
elif [ "$si" -gt 2048 ]; then
  echo "ACTIVE THRASH: swapping in at ${si} KB/s"
else
  echo "BENIGN: pages parked in swap, nothing stalling, $(kb_g "$mem_avail")G available"
fi
need_kb=$(( (disk_mb + zram_mb + 8192) * 1024 ))
if [ "$si" -lt 512 ] && [ "$so" -lt 512 ] && [ "$mem_avail" -gt "$need_kb" ]; then
  echo "drain (swapoff -a && swapon -a): SAFE now -- idle swap I/O, available RAM covers all swapped pages + 8G"
else
  echo "drain (swapoff -a && swapon -a): NOT SAFE now -- active swap I/O or insufficient headroom"
fi

# ---- per-process table: pid ppid rss_kb swap_kb name cmd
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
for p in /proc/[0-9]*; do
  pid=${p#/proc/}
  awk -v pid="$pid" '/^Name:/{n=$2} /^PPid:/{pp=$2} /^VmRSS:/{r=$2} /^VmSwap:/{s=$2}
    END{ if (r+s > 51200) printf "%s\t%s\t%d\t%d\t%s\n", pid, pp, r, s, n }' "$p/status" 2>/dev/null
done | while IFS=$'\t' read -r pid pp r s n; do
  cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-110)
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$pid" "$pp" "$r" "$s" "$n" "$cmd"
done > "$tmp"

classify() { awk -F'\t' -v re="$1" 'tolower($6) ~ re || tolower($5) ~ re' "$tmp"; }
sum() { awk -F'\t' '{n++; r+=$3; s+=$4} END{printf "%3d procs  %6.1fG rss  %6.1fG swap\n", n, r/1048576, s/1048576}'; }

section "by class (procs >50M rss+swap)"
printf 'firefox        '; classify 'firefox' | sum
printf 'rust-analyzer  '; classify 'rust-analyzer' | sum
printf 'claude         '; awk -F'\t' '$5=="claude"' "$tmp" | sum
printf 'mcp servers    '; classify 'mcp serve' | sum
printf 'sb daemons     '; awk -F'\t' '$5=="sb"' "$tmp" | sum
printf 'everything     '; sum < "$tmp"
ff=$(pgrep -o -x firefox-bin 2>/dev/null || true)
[ -n "$ff" ] && printf 'firefox cgroup %s\n' "$(sed 's|.*/||' "/proc/$ff/cgroup" 2>/dev/null)"

section "rust-analyzer instances -> owning claude session"
awk -F'\t' '$5=="rust-analyzer"{print $1}' "$tmp" | while read -r ra; do
  age=$(ps -o etimes= -p "$ra" 2>/dev/null | tr -d ' ')
  rss=$(awk -F'\t' -v p="$ra" '$1==p{printf "%.1f", $3/1048576}' "$tmp")
  swp=$(awk -F'\t' -v p="$ra" '$1==p{printf "%.1f", $4/1048576}' "$tmp")
  cwd=$(readlink "/proc/$ra/cwd" 2>/dev/null)
  anc=$ra; owner="(no claude ancestor)"
  for _ in 1 2 3 4 5 6; do
    anc=$(ps -o ppid= -p "$anc" 2>/dev/null | tr -d ' '); [ -z "$anc" ] || [ "$anc" -le 1 ] && break
    if [ "$(ps -o comm= -p "$anc" 2>/dev/null)" = "claude" ]; then
      owner="claude pid=$anc age=$(( $(ps -o etimes= -p "$anc" | tr -d ' ')/3600 ))h args='$(ps -o args= -p "$anc" | cut -c1-40)'"; break
    fi
  done
  printf 'pid=%-8s %5sG rss %5sG swap age=%dh cwd=%s\n           owner: %s\n' "$ra" "$rss" "$swp" $(( ${age:-0}/3600 )) "${cwd:-?}" "$owner"
done

section "top 12 by swap"
sort -t$'\t' -k4,4nr "$tmp" | head -12 | awk -F'\t' '{printf "%6.0fM swap %6.0fM rss  pid=%-8s %-16s %s\n", $4/1024, $3/1024, $1, $5, substr($6,1,70)}'
section "top 10 by rss"
sort -t$'\t' -k3,3nr "$tmp" | head -10 | awk -F'\t' '{printf "%6.0fM rss  %6.0fM swap pid=%-8s %-16s %s\n", $3/1024, $4/1024, $1, $5, substr($6,1,70)}'

section "oomd / OOM kills (24h)"
# systemctl reports the limit as a fraction of 2^32, not a percent.
printf 'oomd ManagedOOMMemoryPressureLimit: %d%%\n' "$(( $(systemctl show user@1000.service -p ManagedOOMMemoryPressureLimit --value 2>/dev/null || echo 0) * 100 / 4294967296 ))"
journalctl --since '24 hours ago' --no-pager -o short-iso 2>/dev/null | grep -i 'systemd-oomd killed' | tail -5
printf 'kernel OOM kills: %s\n' "$(journalctl -k --since '24 hours ago' --no-pager 2>/dev/null | grep -ic 'out of memory')"

section "alerters"
printf 'swap-watch state: %s\n' "$(tr '\n' ' ' < ~/.cache/swap-watch/state 2>/dev/null)"
systemctl --user list-timers swap-watch.timer --no-pager 2>/dev/null | sed -n 2p
printf 'memwatch cron:    %s\n' "$(crontab -l 2>/dev/null | grep -c memwatch) entry, last: $(tail -1 ~/.cache/memwatch.log 2>/dev/null | cut -c1-100)"

section "history"
echo "atop keeps 10-min samples in /var/log/atop/. For the moment the alert fired:  swap-triage.sh --at HH:MM [YYYYMMDD]"
