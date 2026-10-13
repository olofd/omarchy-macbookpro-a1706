#!/bin/sh
# Thunderbolt and USB-C through sleep (2016-2017 MacBook Pros, Alpine Ridge): the kernel module tb_ar_shim, as
# DKMS (rebuilt for every new kernel). Without it the controllers can be dead after a wake (USB-C gone until a
# reboot, ~2 min resume stall): the PCI core loses their bridges' configuration, and the firmware cuts their
# power late in S3 entry, so an early wake catches them half off. The module saves the configuration in time,
# cuts and restores the power itself with Apple's ACPI methods (as macOS does), and restores the configuration
# first thing after the wake; for hibernation too. With it loaded, the sleep hook keeps Thunderbolt in instead
# of removing it. See alpine-ridge-sleep/README.md.
#   sudo sh install-thunderbolt-sleep.sh            install and load (no reboot needed)
#   sudo sh install-thunderbolt-sleep.sh remove     remove it (the sleep hook then removes Thunderbolt again)
set -eu
NAME=tb-ar-shim-a1706
VER=1.0.0
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../alpine-ridge-sleep
DEST=/usr/src/$NAME-$VER
FILES="dkms.conf Makefile tb_ar_shim.c"
. "$HERE/lib.sh"
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo sh $0" >&2; exit 1; }

if [ "${1:-}" = remove ] || [ "${1:-}" = --remove ]; then
  dkms remove "$NAME/$VER" --all 2>/dev/null || true
  rm -rf "$DEST"
  depmod -a
  # Unloading puts the bridges back to the PCI core's handling at once; the next sleep removes Thunderbolt.
  rmmod tb_ar_shim 2>/dev/null || true
  echo "Removed."
  exit 0
fi

# Only for an on-board Alpine Ridge controller (the module refuses to load anywhere else anyway).
if ! grep -qsx 0x1578 /sys/bus/pci/devices/*/device; then
  echo "No Alpine Ridge Thunderbolt bridge (8086:1578) here: nothing to do."; exit 0
fi
KVER=$(uname -r)
same=1
for f in $FILES; do cmp -s "$SRC/$f" "$DEST/$f" || same=0; done
if [ "$same" = 1 ] && dkms status -m "$NAME" -v "$VER" -k "$KVER" 2>/dev/null | grep -q ': installed'; then
  if lsmod | grep -q '^tb_ar_shim '; then
    echo "Thunderbolt sleep fix: already up to date (built for $KVER, loaded)."; exit 0
  fi
else
  [ -f "/lib/modules/$KVER/build/.config" ] || {
    echo "the headers for kernel $KVER are missing: install them first (Omarchy: linux-omarchy-headers;" >&2
    echo "Arch: linux-headers; Debian/Ubuntu: linux-headers-$KVER; Fedora: kernel-devel-$KVER)" >&2
    exit 1
  }
  if command -v pacman >/dev/null; then pacman -S --needed --noconfirm dkms
  elif command -v apt-get >/dev/null; then apt-get install -y dkms
  elif command -v dnf >/dev/null; then dnf install -y dkms
  elif command -v zypper >/dev/null; then zypper --non-interactive install dkms
  fi
  command -v dkms >/dev/null || { echo "dkms is missing: install it, then run this again" >&2; exit 1; }
  # A loaded older build keeps running until it is replaced below.
  lsmod | grep -q '^tb_ar_shim ' && rmmod tb_ar_shim
  dkms remove "$NAME/$VER" --all >/dev/null 2>&1 || true
  rm -rf "$DEST"
  mkdir -p "$DEST"
  for f in $FILES; do cp "$SRC/$f" "$DEST/"; done
  dkms add "$NAME/$VER"
  dkms install "$NAME/$VER" -k "$KVER"
  depmod -a "$KVER"
fi
# From the next boot it loads by itself (PCI ID); load it now.
modprobe tb_ar_shim
echo "Thunderbolt sleep fix installed and loaded:"; dmesg | grep "tb_ar_shim: installed" | tail -2
echo "After a sleep the log shows:  journalctl -k -b | grep tb_ar_shim"
