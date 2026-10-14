#!/bin/sh
# Real sleeps, woken by the clock, each followed by verify.sh: does everything the guide fixes survive them?
# Each test goes through `systemctl suspend`, so the sleep hook runs exactly as when the lid closes. Leave the Mac
# alone while it runs (a key press or the lid would end a sleep early), on the charger or not as you want to test.
#   sudo sh scripts/sleep-test.sh                      deep:20 deep:120 s2idle:30
#   sudo sh scripts/sleep-test.sh deep:5 deep:600      MODE:SECONDS, MODE deep or s2idle
# The sleep time measured is the time the kernel was really asleep: shorter than asked means something woke the
# Mac early. Results also go to /var/log/sleep-test.log. The sleep mode is set back to deep at the end.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LOG=/var/log/sleep-test.log
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo sh $0" >&2; exit 1; }
U=${SUDO_USER:-}
[ -n "$U" ] || { echo "run it with sudo from your user (verify.sh checks your user services)" >&2; exit 1; }
UID_=$(id -u "$U")
[ $# -gt 0 ] || set -- deep:20 deep:120 s2idle:30
for t in "$@"; do
  case "$t" in deep:[0-9]*|s2idle:[0-9]*) ;; *) echo "bad test $t (MODE:SECONDS, MODE deep or s2idle)" >&2; exit 2 ;; esac
done
# The kernel's PM debug messages name the wake source in the log; on for the test, back to off after.
dbg=$(cat /sys/power/pm_debug_messages 2>/dev/null || echo 0)
echo 1 > /sys/power/pm_debug_messages 2>/dev/null
trap 'echo deep > /sys/power/mem_sleep; echo "$dbg" > /sys/power/pm_debug_messages 2>/dev/null' EXIT
# Seconds the kernel has spent asleep since boot: boot time minus monotonic time.
asleep() { python3 -c 'import time; print(time.clock_gettime(time.CLOCK_BOOTTIME) - time.clock_gettime(time.CLOCK_MONOTONIC))'; }
verify() {
  sudo -u "$U" XDG_RUNTIME_DIR="/run/user/$UID_" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_/bus" \
    sh "$HERE/verify.sh" --since "$1"
}
power() { [ "$(cat /sys/class/power_supply/ADP1/online 2>/dev/null)" = 1 ] && echo charger || echo battery; }
# What woke the Mac: the ACPI GPEs and wakeup sources that counted up during the sleep, and the wake IRQ.
counters() {
  for g in /sys/firmware/acpi/interrupts/gpe[0-9A-F][0-9A-F]; do echo "${g##*/} $(awk '{print $1}' "$g")"; done
  for w in /sys/class/wakeup/wakeup*; do echo "$(cat "$w/name") $(cat "$w/wakeup_count" 2>/dev/null)"; done
}
woken_by() { # before-file after-file
  w=$(awk 'NR == FNR {a[$1] = $2; next} $2 != a[$1] {printf "%s+%d ", $1, $2 - a[$1]}' "$1" "$2")
  echo "irq $(cat /sys/power/pm_wakeup_irq 2>/dev/null || echo ?) ${w:-(no counter moved)}"
}

RESULTS=; FAILS=0
{ echo; date '+== sleep test %F %T'; } >> "$LOG"
for t in "$@"; do
  mode=${t%%:*}; secs=${t#*:}
  echo "$mode" > /sys/power/mem_sleep
  since=$(date '+%F %T')
  exits=$(journalctl -k -b 0 --no-pager -o cat | grep -c 'PM: suspend exit')
  a0=$(asleep)
  counters > /run/sleep-test.before
  printf '\n== %s for %s s on %s: sleeping...\n' "$mode" "$secs" "$(power)"
  rtcwake -m no -s "$secs" >/dev/null
  systemctl suspend
  # Wait for the wake: a new "PM: suspend exit" in the kernel log.
  i=0
  while [ "$(journalctl -k -b 0 --no-pager -o cat | grep -c 'PM: suspend exit')" -le "$exits" ] &&
        [ $i -lt $((secs + 180)) ]; do sleep 1; i=$((i + 1)); done
  slept=$(python3 -c "print(round($(asleep) - $a0, 1))")
  counters > /run/sleep-test.after
  woke=$(woken_by /run/sleep-test.before /run/sleep-test.after)
  echo "  woken by: $woke"
  journalctl -k -b 0 --since "$since" --no-pager -o cat | grep -iE 'wakeup|wake-up|woken|GPE' | grep -v 'disabled' |
    sort | uniq -c | sort -rn | head -6 | sed 's/^/    /'
  echo deep > /sys/power/mem_sleep
  # The USB-C rescan, the Touch Bar restart (10 s) and the Wi-Fi rejoin run after the wake: give them 30 s.
  n=0; out=
  while [ $n -lt 4 ]; do
    sleep 8; n=$((n + 1))
    out=$(verify "$since") && break
  done
  if printf '%s\n' "$out" | grep -q 'All checks passed'; then r=pass; else r=FAIL; FAILS=$((FAILS + 1)); fi
  printf '%s\n' "$out" | grep -E 'FAIL|^All|^Some' | sed 's/^/  /'
  line=$(printf '%-7s %5s s asked, %6s s asleep, %s: %s' "$mode" "$secs" "$slept" "$(power)" "$r")
  echo "  -> $line"
  { echo "$line (woken by: $woke)"; printf '%s\n' "$out" | grep -E 'FAIL|^          '; } >> "$LOG"
  RESULTS="$RESULTS
  $line"
  sleep 5
done
printf '\n== Results%s\n' "$RESULTS"
[ "$FAILS" = 0 ] && echo "All $# sleeps passed." || echo "$FAILS of $# sleeps FAILED (details in $LOG)."
exit "$FAILS"
