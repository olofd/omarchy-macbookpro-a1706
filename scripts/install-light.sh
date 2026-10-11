#!/bin/sh
# Automatic keyboard backlight and screen brightness from the ambient light sensor
# (the iBridge "als" IIO device, present once the T1 firmware is restored: see docs/04-touchbar.md).
# Manual changes (the Touch Bar keys) are kept as an offset. Tune in /etc/*.conf.
#   sudo sh install-light.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
F=$HERE/../files
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo sh $0" >&2; exit 1; }
install -m 755 "$HERE/kbd-auto-backlight.sh" /usr/local/sbin/kbd-auto-backlight
install -m 755 "$HERE/screen-auto-brightness.sh" /usr/local/sbin/screen-auto-brightness
install -m 644 "$F/kbd-auto-backlight.service" /etc/systemd/system/
install -m 644 "$F/screen-auto-brightness.service" /etc/systemd/system/
[ -f /etc/kbd-auto-backlight.conf ] || install -m 644 "$F/kbd-auto-backlight.conf" /etc/kbd-auto-backlight.conf
sed -i 's/\r$//' /usr/local/sbin/kbd-auto-backlight /usr/local/sbin/screen-auto-brightness /etc/systemd/system/kbd-auto-backlight.service /etc/systemd/system/screen-auto-brightness.service /etc/kbd-auto-backlight.conf
systemctl daemon-reload
systemctl enable kbd-auto-backlight.service screen-auto-brightness.service
systemctl restart kbd-auto-backlight.service screen-auto-brightness.service
echo "Done. Cover the sensor (next to the camera) to see the keyboard light come on."
