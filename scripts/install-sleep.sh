#!/bin/sh
# Suspend that works on the A1706, as found by bisecting with /sys/power/pm_test:
#  - "deep" (S3) sleep, which uses about a tenth of the battery s2idle does (s2idle: under 10 hours from full),
#  - the sleep hook: the two Thunderbolt 3 controllers hang the late suspend stage and are removed
#    before sleep, rescanned after; the keyboard light is switched off during sleep; after a deep sleep the T1
#    is told the Mac is awake (ACPI ASOC.SOCW, through acpi_call), or the Touch Bar and Touch ID stay dark,
#  - wifi-recover after every wake: a diagnostic log in /var/log/wake-diag, and if Wi-Fi is not back about
#    20 s after the wake, the 2.4 GHz connection you name here (optional). The real fix for Wi-Fi after
#    sleep is the driver patch, install-wifi-sleep-fix.sh (docs/06-wifi-after-sleep.md),
#  - when hibernation is set up (Omarchy's installer makes a swapfile and a resume device): the lid does
#    suspend-then-hibernate, deep sleep that turns into hibernation after 12 hours on battery. Wi-Fi survives
#    the restore only with the driver patch (install-wifi-sleep-fix.sh, patch 0002).
#   sudo sh install-sleep.sh [FALLBACK-2.4GHZ-CONNECTION-NAME]
#   sudo sh install-sleep.sh remove      undo (then reboot; without the hook, suspend hangs again)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
F=$HERE/../files
. "$HERE/lib.sh"
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo sh $0" >&2; exit 1; }

case "${1:-}" in remove|--remove)
  rm -f /usr/lib/systemd/system-sleep/mac-sleep /usr/local/sbin/wifi-recover /etc/wifi-recover.conf \
    /etc/tmpfiles.d/mem-sleep.conf /etc/systemd/sleep.conf.d/50-a1706-hibernate.conf \
    /etc/systemd/logind.conf.d/50-a1706-lid.conf
  systemctl reload systemd-logind 2>/dev/null || true
  echo "Removed. Reboot to go back to the kernel's default sleep mode (it hangs without the hook)."
  exit 0 ;;
esac

# acpi_call, for the T1 wake call after a deep sleep (a DKMS module; Arch/Omarchy package acpi_call-dkms)
if ! modprobe acpi_call 2>/dev/null; then
  command -v pacman >/dev/null && { pacman -S --needed --noconfirm acpi_call-dkms || true; }
  modprobe acpi_call 2>/dev/null ||
    echo "note: acpi_call is missing; without it the Touch Bar stays dark after a deep sleep" >&2
fi
put_file "$F/mem-sleep.conf" /etc/tmpfiles.d/mem-sleep.conf 644
put_file "$HERE/sleep-hook.sh" /usr/lib/systemd/system-sleep/mac-sleep 755
put_file "$HERE/wifi-recover.sh" /usr/local/sbin/wifi-recover 755
# The name is stored as data and read back as data (never run as shell code): SSIDs can contain anything.
if [ -n "${1:-}" ]; then
  put_text /etc/wifi-recover.conf 644 <<EOF
FALLBACK=$1
EOF
fi
SLEEP_CHANGED=$CHANGED; CHANGED=0
# Suspend-then-hibernate, only where the kernel can resume from a hibernation image.
if grep -qw disk /sys/power/state && [ "$(cat /sys/power/resume 2>/dev/null)" != 0:0 ]; then
  put_file "$F/sleep-then-hibernate.conf" /etc/systemd/sleep.conf.d/50-a1706-hibernate.conf 644
  put_file "$F/logind-lid.conf" /etc/systemd/logind.conf.d/50-a1706-lid.conf 644
  [ -e /usr/src/brcmfmac-apple-resume-1.0/0002-brcmfmac-pcie-survive-restoring-from-hibernation.patch ] ||
    echo "note: without the Wi-Fi driver patch (install-wifi-sleep-fix.sh), Wi-Fi is gone after a hibernation"
else
  echo "No hibernation set up (no resume device): the lid stays on plain suspend."
  for f in /etc/systemd/sleep.conf.d/50-a1706-hibernate.conf /etc/systemd/logind.conf.d/50-a1706-lid.conf; do
    [ -e "$f" ] && rm -f "$f" && CHANGED=1
  done
fi
# logind reads its configuration again on reload (no restart: that would end the session).
[ "$CHANGED" = 1 ] && systemctl reload systemd-logind
[ "$SLEEP_CHANGED" = 1 ] || [ "$CHANGED" = 1 ] || { echo "Sleep: already up to date."; exit 0; }
systemd-tmpfiles --create /etc/tmpfiles.d/mem-sleep.conf
echo "Done. Test: save your work, unmount any USB-C drive, close the lid, wait a minute, open it."
