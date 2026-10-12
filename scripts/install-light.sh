#!/bin/sh
# Automatic keyboard backlight and screen brightness from the ambient light sensor
# (the iBridge "als" IIO device, present once the T1 firmware is restored: see docs/04-touchbar.md).
# Manual changes (the Touch Bar keys) are kept as an offset. Tune in /etc/*.conf.
#   sudo sh install-light.sh
#   sudo sh install-light.sh remove      undo (the services stop; the lights stay where they are)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
F=$HERE/../files
. "$HERE/lib.sh"
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo sh $0" >&2; exit 1; }
case "${1:-}" in remove|--remove)
  systemctl disable --now kbd-auto-backlight.service screen-auto-brightness.service 2>/dev/null || true
  rm -f /usr/local/sbin/kbd-auto-backlight /usr/local/sbin/screen-auto-brightness \
    /etc/systemd/system/kbd-auto-backlight.service /etc/systemd/system/screen-auto-brightness.service \
    /etc/kbd-auto-backlight.conf
  systemctl daemon-reload
  echo "Removed."
  exit 0 ;;
esac
put_file "$HERE/kbd-auto-backlight.sh" /usr/local/sbin/kbd-auto-backlight 755
put_file "$HERE/screen-auto-brightness.sh" /usr/local/sbin/screen-auto-brightness 755
put_file "$F/kbd-auto-backlight.service" /etc/systemd/system/kbd-auto-backlight.service 644
put_file "$F/screen-auto-brightness.service" /etc/systemd/system/screen-auto-brightness.service 644
# The thresholds are yours to tune: installed once, never overwritten.
[ -f /etc/kbd-auto-backlight.conf ] || put_file "$F/kbd-auto-backlight.conf" /etc/kbd-auto-backlight.conf 644
if [ "$CHANGED" = 0 ] && systemctl -q is-active kbd-auto-backlight.service screen-auto-brightness.service; then
  echo "Light sensor services: already up to date."; exit 0
fi
systemctl daemon-reload
systemctl enable kbd-auto-backlight.service screen-auto-brightness.service
systemctl restart kbd-auto-backlight.service screen-auto-brightness.service
echo "Done. Cover the sensor (next to the camera) to see the keyboard light come on."
