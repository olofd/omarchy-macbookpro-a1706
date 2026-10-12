#!/bin/bash
# Touch Bar, camera and ambient light sensor on the A1706 (Apple T1 chip) under Omarchy.
#
# The T1 has no firmware of its own: macOS keeps it in the EFI partition (EFI/APPLE/EMBEDDEDOS) and
# Apple's boot firmware loads it at every power-on. A Linux install that formats the whole disk
# erases it, and the T1 then shows up as USB 05ac:1281 "Recovery Mode". Two steps fix that:
#   1. t1-revive (github.com/niconistal/t1-revive) rebuilds the firmware data from Apple's servers
#      and stages it on the EFI partition, no macOS needed.
#   2. t1bridge (github.com/standardagents/t1bridge) is the driver that draws the Touch Bar.
#
#   sudo bash install-touchbar.sh [USER]       (default: the user who ran sudo)
# Needs: mains power, a network connection, the machine awake, an up-to-date system (run `omarchy update` and
# reboot first: this installs packages with a full sync, never a partial upgrade). About 10 minutes.
# BACK UP /boot/EFI/APPLE afterwards:  sudo tar -C /boot/EFI -czf efi-apple.tgz APPLE
set -euo pipefail
U=${1:-${SUDO_USER:-}}
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo bash $0" >&2; exit 1; }
[ -n "$U" ] && id "$U" >/dev/null 2>&1 || { echo "give the user name: sudo bash $0 USER" >&2; exit 1; }
HOME_DIR=$(getent passwd "$U" | cut -d: -f6)
KEY_FPR=35B166F78B063B04DE1E3D913E6C4216EB03D371
say() { printf '\n== %s\n' "$*"; }
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

say "Checks"
grep -qs 1 /sys/class/power_supply/*/online || { echo "Plug in the charger first." >&2; exit 1; }
if usb_present 05ac:8600; then echo "T1 already running (05ac:8600)."; T1_OK=1
elif usb_present 05ac:1281; then
  echo "T1 is in recovery mode (05ac:1281): firmware will be regenerated."; T1_OK=0
else echo "No T1 chip found on USB: is this a 2016/2017 Touch Bar MacBook Pro?" >&2; exit 1; fi

say "t1bridge package repository"
if ! grep -q '^\[standardagents\]' /etc/pacman.conf; then
  d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
  curl -fSLo "$d/k.asc" https://linux.standardagents.ai/arch/standardagents/x86_64/t1bridge-signing-key.asc
  got=$(gpg --show-keys --with-colons "$d/k.asc" | awk -F: '$1=="fpr"{print $10; exit}')
  [ "$got" = "$KEY_FPR" ] || { echo "signing key fingerprint mismatch: $got" >&2; exit 1; }
  pacman-key --add "$d/k.asc"; pacman-key --lsign-key "$KEY_FPR"
  printf '\n[standardagents]\nSigLevel = Required DatabaseRequired\n%s\n' \
    'Server = https://linux.standardagents.ai/arch/$repo/$arch' >> /etc/pacman.conf
fi
kpkg=$(pacman -Qqo "/usr/lib/modules/$(uname -r)/vmlinuz" 2>/dev/null) ||
  { echo "the running kernel $(uname -r) is no longer installed (updated without a reboot): reboot first" >&2
    exit 1; }
# One full transaction (-Syu): the new repository is synced and nothing is installed against stale package
# lists, which would be a partial upgrade. Omarchy's guard asks for `omarchy update`; this is the same sync.
OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -Syu --needed --noconfirm \
  base-devel dkms git "${kpkg}-headers" acpi_call-dkms \
  t1bridge t1bridge-dkms usbutils

if [ "$T1_OK" = 0 ]; then
  say "Regenerating the T1 firmware (t1-revive)"
  work=$HOME_DIR/t1-revive
  [ -d "$work/.git" ] || sudo -u "$U" git clone https://github.com/niconistal/t1-revive "$work"
  (cd "$work" && sudo -u "$U" bash build.sh)
  (cd "$work" && bin/t1-revive preflight --install)
  (cd "$work" && bin/t1-revive regenerate --no-confirm)
fi

say "Enable"
systemd-sysusers /usr/lib/sysusers.d/t1bridge.conf
systemd-tmpfiles --create /usr/lib/tmpfiles.d/t1bridge.conf
usermod -aG t1bridge "$U"
systemctl daemon-reload
systemctl enable t1-touchbar-hw.service
# The renderer runs in the user's session; enable it for the user (it starts at every login).
sudo -u "$U" env XDG_RUNTIME_DIR="/run/user/$(id -u "$U")" systemctl --user enable --now t1-touchbar.service || \
  echo "Log in graphically once, then run:  systemctl --user enable --now t1-touchbar.service"

say "Volume, mute, media and brightness on the Touch Bar (Omarchy provider)"
sudo -u "$U" install -d "$HOME_DIR/.local/bin" "$HOME_DIR/.config/systemd/user/t1-touchbar.service.d"
sudo -u "$U" curl -fsSL \
  https://raw.githubusercontent.com/niconistal/t1-revive/main/contrib/omarchy/t1bridge-omarchy-provider.sh \
  -o "$HOME_DIR/.local/bin/t1bridge-omarchy-provider"
chmod 755 "$HOME_DIR/.local/bin/t1bridge-omarchy-provider"
printf '[Service]\nEnvironment=T1BRIDGE_DESKTOP_PROVIDER=%%h/.local/bin/t1bridge-omarchy-provider\n' \
  > "$HOME_DIR/.config/systemd/user/t1-touchbar.service.d/omarchy-provider.conf"
chown -R "$U:" "$HOME_DIR/.config/systemd/user/t1-touchbar.service.d"

echo
echo "Done. Log out and back in (or reboot). Then:  sudo t1bridge status   (touchbar: ready)"
echo "Back up the firmware data now:  sudo tar -C /boot/EFI -czf efi-apple.tgz APPLE"
