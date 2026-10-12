#!/bin/sh
# Night light on a schedule from the place set in Omarchy's weather widget: 4000 K from sunset to
# sunrise, times worked out every day (nightlight-sun.py). Runs at login and daily just after midnight
# (systemd user timer). The manual night light toggle keeps working.
#
#   sh install-nightlight.sh             (as the user)        sh install-nightlight.sh --remove     to undo
set -eu
[ "$(id -u)" -ne 0 ] || { echo "run as the user, not root" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
UNITS=$HOME/.config/systemd/user

if [ "${1:-}" = "--remove" ] || [ "${1:-}" = remove ]; then
  systemctl --user disable --now nightlight-sun.timer 2>/dev/null || true
  rm -f "$UNITS/nightlight-sun.service" "$UNITS/nightlight-sun.timer" "$HOME/.local/bin/nightlight-sun"
  systemctl --user daemon-reload
  if [ -f "$HOME/.config/hypr/hyprsunset.conf.before-nightlight-sun" ]; then
    mv "$HOME/.config/hypr/hyprsunset.conf.before-nightlight-sun" "$HOME/.config/hypr/hyprsunset.conf"
  elif [ -f /usr/share/omarchy/config/hypr/hyprsunset.conf ]; then
    cp /usr/share/omarchy/config/hypr/hyprsunset.conf "$HOME/.config/hypr/hyprsunset.conf"
  fi
  rm -f "$HOME/.cache/nightlight-sun.json"
  omarchy restart hyprsunset >/dev/null 2>&1 || true
  echo "Night light schedule removed."
  exit 0
fi

put_file "$HERE/nightlight-sun.py" "$HOME/.local/bin/nightlight-sun" 755
put_text "$UNITS/nightlight-sun.service" 644 <<EOF
[Unit]
Description=Night light from sunset to sunrise (omarchy-macbookpro-a1706 install-nightlight.sh)
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/nightlight-sun
EOF
put_text "$UNITS/nightlight-sun.timer" 644 <<EOF
[Unit]
Description=Update the night light times daily and at login

[Timer]
OnStartupSec=20s
OnCalendar=*-*-* 00:05
Persistent=true

[Install]
WantedBy=timers.target
EOF
if [ "$CHANGED" = 0 ] && systemctl --user -q is-enabled nightlight-sun.timer 2>/dev/null; then
  echo "Night light schedule: already up to date."; exit 0
fi
systemctl --user daemon-reload
systemctl --user enable --now nightlight-sun.timer
"$HOME/.local/bin/nightlight-sun"
