#!/bin/sh
# A chime when the charger is plugged in (and a softer one when it is pulled), like macOS.
# Runs as a user service: it listens for power-supply events from udev and plays the two sounds in
# ~/.local/share/charger-chime through PipeWire, or the freedesktop sounds if those are missing (macOS's own
# chime is Apple's, so this is a small bell synthesised for the purpose; replace the files with any short sound).
D=$HOME/.local/share/charger-chime
PLUG=$D/plug.wav; UNPLUG=$D/unplug.wav          # a soft two-note bell, made for this (scripts/mkchime.py)
[ -r "$PLUG" ] || PLUG=/usr/share/sounds/freedesktop/stereo/power-plug.oga
[ -r "$UNPLUG" ] || UNPLUG=/usr/share/sounds/freedesktop/stereo/power-unplug.oga
VOLUME=0.35            # 0 to 1; lower is quieter (set it in ~/.config/charger-chime.conf: VOLUME=0.2)
if [ -r "$HOME/.config/charger-chime.conf" ]; then
  v=$(sed -n 's/^VOLUME=//p' "$HOME/.config/charger-chime.conf" | head -n 1); VOLUME=${v:-$VOLUME}
fi
mains() {
  for p in /sys/class/power_supply/*; do
    [ "$(cat $p/type 2>/dev/null)" = Mains ] && cat $p/online && return
  done
}
last=$(mains)
udevadm monitor --udev --subsystem-match=power_supply 2>/dev/null | while read -r _; do
  now=$(mains)
  if [ -n "$now" ] && [ "$now" != "$last" ]; then
    if [ "$now" = 1 ]; then pw-play --volume="$VOLUME" "$PLUG" >/dev/null 2>&1 &
    else pw-play --volume="$VOLUME" "$UNPLUG" >/dev/null 2>&1 &
    fi
    last=$now
  fi
done
