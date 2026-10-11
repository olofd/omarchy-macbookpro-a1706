#!/bin/sh
# Suspend that works on the A1706, as found by bisecting with /sys/power/pm_test:
#  - s2idle instead of "deep" (deep never wakes),
#  - the sleep hook: the two Thunderbolt 3 controllers hang the late suspend stage and are removed
#    before sleep, rescanned after; the keyboard light is switched off during sleep,
#  - wifi-recover after every wake: a diagnostic log in /var/log/wake-diag, and if Wi-Fi is not back about
#    20 s after the wake, the 2.4 GHz connection you name here (optional). The real fix for Wi-Fi after
#    sleep is the driver patch, install-wifi-sleep-fix.sh (docs/06-wifi-after-sleep.md).
#   sudo sh install-sleep.sh [FALLBACK-2.4GHZ-CONNECTION-NAME]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
F=$HERE/../files
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo sh $0" >&2; exit 1; }

install -m 644 "$F/mem-sleep.conf" /etc/tmpfiles.d/mem-sleep.conf
install -m 755 "$HERE/sleep-hook.sh" /usr/lib/systemd/system-sleep/mac-sleep
install -m 755 "$HERE/wifi-recover.sh" /usr/local/sbin/wifi-recover
# The name is stored as data and read back as data (never run as shell code): SSIDs can contain anything.
if [ -n "${1:-}" ]; then printf 'FALLBACK=%s\n' "$1" > /etc/wifi-recover.conf; fi
sed -i 's/\r$//' /etc/tmpfiles.d/mem-sleep.conf /usr/lib/systemd/system-sleep/mac-sleep /usr/local/sbin/wifi-recover
systemd-tmpfiles --create /etc/tmpfiles.d/mem-sleep.conf
echo "Done. Test: save your work, unmount any USB-C drive, close the lid, wait a minute, open it."
