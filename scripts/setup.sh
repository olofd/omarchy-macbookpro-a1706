#!/bin/sh
# The whole guide in one go, in the right order. Run it after installing Omarchy (and `omarchy update`, then a
# reboot), and again after every `git pull`: each step checks what is there and only does what is missing or
# changed, so on an up-to-date Mac it changes nothing. Steps that need a reboot are done; the steps that
# depend on them wait, and the end says so: reboot and run it again to continue.
#
#   sh scripts/setup.sh [--fallback CONNECTION] [--no-touchid] [--no-extras]
#
# Run it as your user in a terminal in the desktop (not with sudo: it asks for sudo where it needs it).
#   --fallback NAME   a 2.4 GHz NetworkManager connection the wake check falls back to (docs/05-sleep.md)
#   --no-touchid      leave Touch ID out (docs/09-touch-id.md)
#   --no-extras       leave the desktop extras out (docs/10-desktop-extras.md)
# Touch ID needs two steps by hand, which it prints when it gets there: enrolling a finger, and adding Touch
# ID to sudo (keep a root shell open while you test that).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
[ "$(id -u)" -ne 0 ] || { echo "run it as your user (it uses sudo itself): sh $0" >&2; exit 1; }
[ -n "${WAYLAND_DISPLAY:-}" ] || { echo "run it from a terminal in the desktop" >&2; exit 1; }
FALLBACK=; TOUCHID=1; EXTRAS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --fallback) [ $# -ge 2 ] || { echo "--fallback needs a connection name" >&2; exit 2; }; FALLBACK=$2; shift 2 ;;
    --no-touchid) TOUCHID=0; shift ;;
    --no-extras) EXTRAS=0; shift ;;
    *) echo "usage: sh $0 [--fallback CONNECTION] [--no-touchid] [--no-extras]" >&2; exit 2 ;;
  esac
done

# In the user's runtime folder: root may not write a user's file in /tmp (fs.protected_regular).
REBOOT_FILE=$(mktemp -p "${XDG_RUNTIME_DIR:-/tmp}")
FAILED=; WAITING=
trap 'rm -f "$REBOOT_FILE"' EXIT
step() { printf '\n== %s\n' "$*"; }
# root CMD...: run as root, passing on where installers note "needs a reboot".
root() { sudo env A1706_REBOOT_FILE="$REBOOT_FILE" "$@"; }
# try NAME CMD...: run a step; a failure is reported at the end and the other steps still run.
try() { _n=$1; shift; "$@" || { echo "!! $_n failed (see above)"; FAILED="$FAILED
  - $_n"; }; }
wait_for() { echo "Waits for: $2"; WAITING="$WAITING
  - $1 (after $2)"; }
t1_running() { usb_present 05ac:8600; }
light_sensor() { grep -qs '^als$' /sys/bus/iio/devices/iio:device*/name; }

model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)
case "$model" in
  MacBookPro13,[123]|MacBookPro14,[123]) echo "This is a $model." ;;
  *) echo "note: this guide is for the 2016/2017 Touch Bar MacBook Pro; this is a $model" ;;
esac
sudo -v

step "1. Sound (docs/02)"
try "Sound" root sh "$HERE/install-sound.sh"

step "2. Wi-Fi: 5 GHz (docs/03)"
try "Wi-Fi" root sh "$HERE/install-wifi.sh"

step "3. Touch Bar, camera and light sensor: the T1 (docs/04)"
if pacman -Q t1bridge t1bridge-dkms acpi_call-dkms >/dev/null 2>&1 && t1_running &&
   [ -x "$HOME/.local/bin/t1bridge-omarchy-provider" ] && systemctl --user -q is-enabled t1-touchbar.service
then
  echo "Touch Bar: already set up."
else
  echo "Needs mains power and about 10 minutes."
  if root bash "$HERE/install-touchbar.sh" "$(id -un)"; then
    echo "the Touch Bar" >> "$REBOOT_FILE"
    echo "Back up the T1 firmware it restored, off this machine:  sudo tar -C /boot/EFI -czf efi-apple.tgz APPLE"
  else
    echo "!! Touch Bar failed (see above)"; FAILED="$FAILED
  - Touch Bar"
  fi
fi

step "4. Sleep (docs/05)"
if [ -n "$FALLBACK" ]; then try "Sleep" root sh "$HERE/install-sleep.sh" "$FALLBACK"
else try "Sleep" root sh "$HERE/install-sleep.sh"; fi

step "5. Wi-Fi and Bluetooth after sleep: the driver fix (docs/06)"
try "Wi-Fi sleep fix" root sh "$HERE/install-wifi-sleep-fix.sh"

step "6. Light sensor: keyboard light and screen brightness (docs/07)"
if light_sensor; then try "Light sensor" root sh "$HERE/install-light.sh"
else wait_for "Light sensor" "the Touch Bar step and a reboot"; fi

step "7. Trackpad (docs/08)"
try "Trackpad" sh "$HERE/install-input.sh"

if [ "$TOUCHID" = 1 ]; then
  step "8. Touch ID (docs/09)"
  if ! t1_running; then
    wait_for "Touch ID" "the Touch Bar step and a reboot"
  elif ! pacman -Q libfprint-t1bridge fprintd-t1bridge >/dev/null 2>&1; then
    if root sh "$HERE/install-touchid.sh" install; then echo "Touch ID" >> "$REBOOT_FILE"
    else echo "!! Touch ID failed (see above)"; FAILED="$FAILED
  - Touch ID"; fi
  elif ! fprintd-list "$(id -un)" 2>/dev/null | grep -q ' - #'; then
    echo "Next, by hand: enroll a finger:  sh $HERE/install-touchid.sh enroll"
    WAITING="$WAITING
  - Touch ID: enroll a finger (sh scripts/install-touchid.sh enroll)"
  elif ! grep -qs 'install-touchid.sh' /etc/pam.d/sudo; then
    echo "Next, by hand: open a root shell in another terminal (sudo -s), then:"
    echo "  sudo sh $HERE/install-touchid.sh pam      and test sudo with your finger and with the password"
    WAITING="$WAITING
  - Touch ID for sudo (sudo sh scripts/install-touchid.sh pam)"
  else
    echo "Touch ID: already set up."
  fi
fi

if [ "$EXTRAS" = 1 ]; then
  step "9. Desktop extras: overview, dock, night light, charger chime (docs/10)"
  try "Overview" sh "$HERE/install-overview.sh"
  command -v nwg-dock-hyprland >/dev/null || try "Dock package" omarchy pkg add nwg-dock-hyprland
  if command -v nwg-dock-hyprland >/dev/null; then try "Dock" sh "$HERE/install-dock.sh"; fi
  try "Night light" sh "$HERE/install-nightlight.sh"
  try "Charger chime" sh "$HERE/install-chime.sh"
fi

step "Summary"
if [ -n "$FAILED" ]; then echo "Failed:$FAILED"; fi
if [ -s "$REBOOT_FILE" ]; then
  echo "Reboot for: $(sort -u "$REBOOT_FILE" | paste -sd, - | sed 's/,/, /g')."
  echo "Then run this again to continue:  sh $HERE/setup.sh"
fi
if [ -n "$WAITING" ]; then echo "Still to do:$WAITING"; fi
if [ -z "$FAILED" ] && [ ! -s "$REBOOT_FILE" ] && [ -z "$WAITING" ]; then
  echo "All done: this Mac is set up as the guide describes."
fi
[ -z "$FAILED" ]
