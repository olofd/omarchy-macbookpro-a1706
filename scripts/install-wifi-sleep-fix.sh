#!/bin/sh
# 5 GHz Wi-Fi and Bluetooth after sleep (BCM43602): a patched brcmfmac driver, as a DKMS module that is rebuilt
# for every new kernel. The chip loses power in s2idle, and the stock driver brings it back up without the setup
# Apple's EFI did at boot (antenna/amplifier GPIOs); the patch restores it. See docs/06-wifi-after-sleep.md.
#   sudo sh install-wifi-sleep-fix.sh            install (a few minutes the first time), then reboot
#   sudo sh install-wifi-sleep-fix.sh remove     back to the kernel's own driver, then reboot
# Works on any distribution with DKMS (Arch/Omarchy, Debian/Ubuntu, Fedora, openSUSE): it installs dkms, git and
# patch with the system's package manager. Needs the headers of the running kernel and internet once per kernel
# version (the driver source comes from the stable kernel tree). It never unloads the running driver: on this card that kills
# Wi-Fi until reboot. Details: brcmfmac-apple-resume/README.md.
set -eu
NAME=brcmfmac-apple-resume
VER=1.0
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../$NAME
DEST=/usr/src/$NAME-$VER
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo sh $0" >&2; exit 1; }

if [ "${1:-}" = remove ]; then
  dkms remove "$NAME/$VER" --all 2>/dev/null || true
  rm -rf "$DEST" "/var/cache/$NAME"
  depmod -a
  echo "Removed. Reboot to go back to the kernel's own brcmfmac."
  exit 0
fi

KVER=$(uname -r)
[ -f "/lib/modules/$KVER/build/.config" ] || {
  echo "the headers for kernel $KVER are missing: install them first (Omarchy: linux-omarchy-headers;" >&2
  echo "Arch: linux-headers; Debian/Ubuntu: linux-headers-$KVER; Fedora: kernel-devel-$KVER)" >&2
  exit 1
}
if command -v pacman >/dev/null; then pacman -S --needed --noconfirm dkms git patch
elif command -v apt-get >/dev/null; then apt-get install -y dkms git patch
elif command -v dnf >/dev/null; then dnf install -y dkms git patch
elif command -v zypper >/dev/null; then zypper --non-interactive install dkms git patch
fi
for t in dkms git patch make; do
  command -v "$t" >/dev/null || { echo "$t is missing: install it, then run this again" >&2; exit 1; }
done
lspci -nd 14e4: 2>/dev/null | grep -q . || echo "note: no Broadcom PCI device found; this fix is for Macs with a BCM43602"

# An earlier hand-built brcmfmac in updates/ would shadow the DKMS one: keep it aside.
for f in "/lib/modules/$KVER/updates/brcmfmac.ko" "/lib/modules/$KVER/updates/brcmfmac.ko.zst"; do
  [ -f "$f" ] && mkdir -p "/var/lib/$NAME" && mv "$f" "/var/lib/$NAME/$(basename "$f").$KVER" &&
    echo "moved the hand-built $f to /var/lib/$NAME/"
done

dkms remove "$NAME/$VER" --all >/dev/null 2>&1 || true
rm -rf "$DEST"
mkdir -p "$DEST"
cp "$SRC/dkms.conf" "$SRC/dkms-build.sh" "$SRC"/*.patch "$DEST/"
dkms add "$NAME/$VER"
dkms install "$NAME/$VER" -k "$KVER"
depmod -a "$KVER"
echo "Installed. Reboot, then check:  modinfo -F parm brcmfmac | grep mac_efi_restore"
echo "After a sleep the log shows:     journalctl -k -b | grep \"restored the chip setup\""
echo "A new kernel rebuilds it automatically (it needs internet once). If that happened offline: sudo dkms autoinstall"
