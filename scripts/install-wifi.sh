#!/bin/sh
# 5 GHz Wi-Fi (Broadcom BCM43602). linux-firmware ships no NVRAM for this card, so the driver comes up on
# 2.4 GHz only, with a weak signal and Broadcom's placeholder MAC address. This installs one
# (files/brcmfmac43602-pcie.txt) with a MAC address and the country code. Reboot afterwards.
#   sudo sh install-wifi.sh            country X3, revision 15 (Broadcom's multi-country code; what the tested
#                                      Mac runs). The system's own Wi-Fi country (/etc/conf.d/wireless-regdom)
#                                      is applied on top of it by the driver.
#   sudo sh install-wifi.sh SE         a two-letter country instead (revision 0)
#   sudo sh install-wifi.sh remove     undo (then reboot)
# The file goes to /usr/lib/firmware/updates/brcm/, which the kernel searches first, so it can never clash with
# a linux-firmware package.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../files/brcmfmac43602-pcie.txt
DEST=/usr/lib/firmware/updates/brcm/brcmfmac43602-pcie.txt
NM=/etc/NetworkManager/conf.d/90-no-mac-random.conf
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo sh $0" >&2; exit 1; }

if [ "${1:-}" = remove ]; then
  rm -f "$DEST" "$NM"
  [ -f /etc/modprobe.d/brcmfmac.conf ] && sed -i 's/^#\(options brcmfmac feature_disable\)/\1/' /etc/modprobe.d/brcmfmac.conf
  echo "Removed. Reboot to go back to 2.4 GHz-only Wi-Fi."
  exit 0
fi
case "${1:-}" in
  "") CCODE=X3; REGREV=15 ;;
  [A-Z][A-Z]|00) CCODE=$1; REGREV=0 ;;
  *) echo "country must be two capital letters (e.g. SE), or nothing for the tested default" >&2; exit 2 ;;
esac

iface=$(ls /sys/class/net | grep '^wl' | head -n 1)
[ -n "$iface" ] || { echo "no Wi-Fi interface found" >&2; exit 1; }
# Without NVRAM the card reports Broadcom's placeholder (00:90:4c:...), likely the same on every such Mac: two of
# them on one network would clash. Keep the address from an earlier run, else the card's own if it is real,
# else make a random locally administered one (02:...), once.
mac=$(sed -n 's/^macaddr=//p' "$DEST" 2>/dev/null || true)
case "$mac" in ""|00:00:00:00:00:00|00:90:4c:*|00:90:4C:*) mac= ;; esac
if [ -z "$mac" ]; then
  mac=$(cat "/sys/class/net/$iface/address")
  case "$mac" in 00:90:4c:*|00:90:4C:*)
    mac=$(od -An -N5 -tx1 /dev/urandom | awk '{printf "02:%s:%s:%s:%s:%s", $1, $2, $3, $4, $5}') ;;
  esac
fi
echo "Interface $iface, MAC $mac, country $CCODE/$REGREV"

mkdir -p "$(dirname "$DEST")"
tr -d '\r' < "$SRC" | sed -e "s/^macaddr=.*/macaddr=$mac/" -e "s/^ccode=.*/ccode=$CCODE/" \
  -e "s/^regrev=.*/regrev=$REGREV/" > "$DEST"
install -m 644 "$HERE/../files/nm-no-mac-random.conf" "$NM"
# Omarchy runs the WPA handshake in software on Apple Wi-Fi (brcmfmac feature_disable=0x82000, a workaround for
# WPA2/WPA3 transition networks). On this card the firmware's own handshake is what the tested Mac uses (with the
# software one, early tests saw minutes of rejected joins), so Omarchy's line is commented out.
[ -f /etc/modprobe.d/brcmfmac.conf ] && sed -i 's/^options brcmfmac feature_disable/#&/' /etc/modprobe.d/brcmfmac.conf
# An NVRAM from an earlier version of this guide, in the old place, would be found second: say so.
[ -f /usr/lib/firmware/brcm/brcmfmac43602-pcie.txt ] &&
  echo "note: an older copy is in /usr/lib/firmware/brcm/ (no longer used once this one exists; you can delete it)"
echo "Installed. Reboot, then:  iw phy | grep -c 5180   (more than 0 means 5 GHz is available)"
