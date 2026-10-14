#!/bin/sh
# Keyboard backlight from the ambient light sensor (the A1706's iBridge "als" IIO device).
# Dark -> on, bright -> off, smoothed so it does not flicker.
# A change by hand (the Touch Bar keys) wins: automatic control holds off for HOLD seconds (an hour), or until
# the room light changes a lot (FACTOR times brighter or darker than when you set it, for half a minute). The
# hold is kept in /run: it survives the restart of this service at every wake, and the time asleep counts.
# The sensor is on the T1, which leaves USB and comes back at a wake: a missing sensor is no reading (not
# darkness, which turned the light on full right after a wake), and it is looked up again.
# The lock screen turns this light and the display off (display brightness 0) and back on at unlock: hands off
# while the display is at 0, and those changes are not taken for ones by hand.
# Thresholds and brightness steps are in /etc/kbd-auto-backlight.conf (raw sensor counts, 0-255 light).
LED=/sys/class/leds/spi::kbd_backlight
DISPLAY_BL=/sys/class/backlight/acpi_video0/brightness
CONF=/etc/kbd-auto-backlight.conf
DARK=3; DIM=30; ON=200; MID=90      # the same as files/kbd-auto-backlight.conf
HOLD=3600; FACTOR=4
[ -r "$CONF" ] && . "$CONF"
STATE=/run/kbd-auto-backlight.hold      # "UNTIL LIGHT": no automatic changes until UNTIL, set at LIGHT
[ -w "$LED/brightness" ] || { echo "no keyboard light" >&2; exit 1; }

find_als() { grep -l '^als$' /sys/bus/iio/devices/iio:device*/name 2>/dev/null | head -n 1 | xargs -r dirname; }
ALS=$(find_als)
# read_light: the raw reading, or nothing when the sensor is gone or not back yet.
read_light() {
  [ -n "$ALS" ] && [ -r "$ALS/in_illuminance_raw" ] || ALS=$(find_als)
  [ -n "$ALS" ] && cat "$ALS/in_illuminance_raw" 2>/dev/null
}

blanked() { [ "$(cat "$DISPLAY_BL" 2>/dev/null || echo 1)" -eq 0 ]; }
last=$(cat $LED/brightness); smooth=; missing=0; seen=0; far=0; blank=0; grace=0
while :; do
  sleep 2
  cur=$(cat $LED/brightness)
  # The lock screen: while the display is blanked, leave the light; its restore (within 6 s) is not by hand.
  if blanked; then blank=1; last=$cur; continue; fi
  if [ "$blank" = 1 ]; then blank=0; grace=$(( $(date +%s) + 6 )); fi
  [ "$cur" != "$last" ] && [ "$(date +%s)" -lt "$grace" ] && last=$cur
  # It turns this light off just before the display: wait a moment before taking a change for one by hand.
  if [ "$cur" != "$last" ]; then sleep 1; if blanked; then blank=1; last=$(cat $LED/brightness); continue; fi; fi
  # A change that is not ours: by hand. Hold off from here, remembering the light it was set in.
  if [ "$cur" != "$last" ]; then
    echo "$(( $(date +%s) + HOLD )) ${smooth:--1}" > "$STATE"; last=$cur; far=0
    echo "set by hand to $cur: automatic control holds off for $((HOLD / 60)) min" | logger -t kbd-auto-backlight
  fi
  raw=$(read_light)
  if [ -z "$raw" ]; then
    missing=$((missing + 1))
    [ "$missing" -lt 30 ] || { echo "light sensor gone for a minute" >&2; exit 1; }   # systemd restarts it
    continue
  fi
  missing=0
  # Moving average: fast to follow, slow enough to ignore a hand passing over the sensor.
  smooth=${smooth:-$raw}
  smooth=$(( (smooth * 3 + raw) / 4 ))
  # The first readings after a start (every wake) only fill the average.
  seen=$((seen + 1)); [ "$seen" -gt 2 ] || continue
  if [ -r "$STATE" ]; then
    read -r until at < "$STATE"
    # set before the first reading: the light it was set in is the first one
    [ "$at" -ge 0 ] 2>/dev/null || { at=$smooth; echo "$until $at" > "$STATE"; }
    if [ "$smooth" -gt $(( at * FACTOR + 10 )) ] || [ $(( smooth * FACTOR + 1 )) -lt "$at" ]; then
      far=$((far + 1))
    else far=0; fi
    [ "$(date +%s)" -ge "$until" ] || [ "$far" -ge 15 ] || continue
    rm -f "$STATE"
    echo "automatic again (light $smooth, set at $at)" | logger -t kbd-auto-backlight
  fi
  if   [ "$smooth" -lt "$DARK" ]; then target=$ON
  elif [ "$smooth" -lt "$DIM" ];  then target=$MID
  else target=0; fi
  if [ "$target" != "$cur" ]; then
    echo "light=$raw avg=$smooth -> $target" | logger -t kbd-auto-backlight
    echo "$target" > $LED/brightness
    last=$target
  fi
done
