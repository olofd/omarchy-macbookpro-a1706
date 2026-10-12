#!/bin/sh
# A soft bell when the charger is plugged in (and a softer one when it is pulled), like macOS: charger-chime.sh
# as a systemd user service, with the two sounds made by mkchime.py. Volume: VOLUME=0.35 by default, set in
# ~/.config/charger-chime.conf.
#   sh install-chime.sh              (as your user, not with sudo)
#   sh install-chime.sh --remove     undo
set -eu
[ "$(id -u)" -ne 0 ] || { echo "run as your user, not root" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
if [ "${1:-}" = "--remove" ] || [ "${1:-}" = remove ]; then
  systemctl --user disable --now charger-chime.service 2>/dev/null || true
  rm -f "$HOME/.local/bin/charger-chime" "$HOME/.config/systemd/user/charger-chime.service"
  rm -rf "$HOME/.local/share/charger-chime"
  systemctl --user daemon-reload
  echo "Charger chime removed."
  exit 0
fi
install -Dm755 "$HERE/charger-chime.sh" "$HOME/.local/bin/charger-chime"
install -Dm644 "$HERE/../files/charger-plug.wav" "$HOME/.local/share/charger-chime/plug.wav"
install -Dm644 "$HERE/../files/charger-unplug.wav" "$HOME/.local/share/charger-chime/unplug.wav"
install -Dm644 "$HERE/../files/charger-chime.service" "$HOME/.config/systemd/user/charger-chime.service"
systemctl --user daemon-reload
systemctl --user enable --now charger-chime.service
echo "Charger chime on: plug the charger in to hear it."
