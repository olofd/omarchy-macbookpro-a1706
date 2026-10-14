#!/bin/sh
# Screen brightness from the ambient light sensor (the A1706's iBridge "als" IIO device).
# Dark room -> dim, bright room -> bright, eased a few steps at a time so it never jumps.
# A change by hand (the Touch Bar keys or slider) wins, as on a phone or a Mac: automatic control holds off
# for HOLD seconds (an hour), or until the room light changes a lot (FACTOR times brighter or darker than when
# you set it, for half a minute: going outside, the lamp off), then eases back to the curve. The hold is kept
# in /run: it survives the restart of this service at every wake, and the time asleep counts.
# The sensor is on the T1, which leaves USB and comes back at a wake: a missing sensor is no reading (not
# darkness, which dimmed the screen to its minimum after a wake), and it is looked up again.
# The lock screen blanks the display (brightness 0) and puts it back at unlock: hands off while it is at 0,
# and the change back is not taken for one by hand.
# Curve and limits: /etc/screen-auto-brightness.conf (sensor: covered 0, a room about 16, daylight 300+).
BL=/sys/class/backlight/acpi_video0
CONF=/etc/screen-auto-brightness.conf
MIN=12; ROOM=40; MAXB=90      # backlight steps (hardware max is 90)
DARKLUX=3; ROOMLUX=30; SUNLUX=300; STEP=2
HOLD=3600; FACTOR=4
[ -r "$CONF" ] && . "$CONF"
STATE=/run/screen-auto-brightness.hold      # "UNTIL LIGHT": no automatic changes until UNTIL, set at LIGHT
[ -w "$BL/brightness" ] || { echo "no backlight" >&2; exit 1; }
hw=$(cat $BL/max_brightness); [ "$MAXB" -gt "$hw" ] && MAXB=$hw

find_als() { grep -l '^als$' /sys/bus/iio/devices/iio:device*/name 2>/dev/null | head -n 1 | xargs -r dirname; }
ALS=$(find_als)
# read_light: the raw reading, or nothing when the sensor is gone or not back yet.
read_light() {
  [ -n "$ALS" ] && [ -r "$ALS/in_illuminance_raw" ] || ALS=$(find_als)
  [ -n "$ALS" ] && cat "$ALS/in_illuminance_raw" 2>/dev/null
}

last=$(cat $BL/brightness); smooth=; missing=0; seen=0; far=0; blank=0; grace=0
while :; do
  sleep 1
  cur=$(cat $BL/brightness)
  # Blanked by the lock screen: leave it, and take its restore (within 5 s) as not by hand.
  if [ "$cur" -eq 0 ]; then blank=1; last=0; continue; fi
  if [ "$blank" = 1 ]; then blank=0; grace=$(( $(date +%s) + 5 )); fi
  [ "$cur" != "$last" ] && [ "$(date +%s)" -lt "$grace" ] && last=$cur
  # A change that is not ours: by hand. Hold off from here, remembering the light it was set in.
  if [ "$cur" != "$last" ]; then
    echo "$(( $(date +%s) + HOLD )) ${smooth:--1}" > "$STATE"; last=$cur; far=0
    echo "set by hand to $cur: automatic control holds off for $((HOLD / 60)) min" |
      logger -t screen-auto-brightness
  fi
  raw=$(read_light)
  if [ -z "$raw" ]; then
    missing=$((missing + 1))
    [ "$missing" -lt 60 ] || { echo "light sensor gone for a minute" >&2; exit 1; }   # systemd restarts it
    continue
  fi
  missing=0
  smooth=${smooth:-$raw}
  smooth=$(( (smooth * 7 + raw) / 8 ))      # slow average: a hand over the sensor does not dim the screen
  # The first readings after a start (every wake) only fill the average.
  seen=$((seen + 1)); [ "$seen" -gt 3 ] || continue
  if [ -r "$STATE" ]; then
    read -r until at < "$STATE"
    # set before the first reading: the light it was set in is the first one
    [ "$at" -ge 0 ] 2>/dev/null || { at=$smooth; echo "$until $at" > "$STATE"; }
    if [ "$smooth" -gt $(( at * FACTOR + 10 )) ] || [ $(( smooth * FACTOR + 1 )) -lt "$at" ]; then
      far=$((far + 1))
    else far=0; fi
    [ "$(date +%s)" -ge "$until" ] || [ "$far" -ge 30 ] || continue
    rm -f "$STATE"
    echo "automatic again (light $smooth, set at $at)" | logger -t screen-auto-brightness
  fi
  if   [ "$smooth" -le "$DARKLUX" ]; then t=$MIN
  elif [ "$smooth" -le "$ROOMLUX" ]; then t=$(( MIN + (smooth - DARKLUX) * (ROOM - MIN) / (ROOMLUX - DARKLUX) ))
  elif [ "$smooth" -le "$SUNLUX" ];  then t=$(( ROOM + (smooth - ROOMLUX) * (MAXB - ROOM) / (SUNLUX - ROOMLUX) ))
  else t=$MAXB; fi
  if   [ "$t" -gt "$cur" ]; then n=$(( cur + STEP )); [ "$n" -gt "$t" ] && n=$t
  elif [ "$t" -lt "$cur" ]; then n=$(( cur - STEP )); [ "$n" -lt "$t" ] && n=$t
  else n=$cur; fi
  if [ "$n" != "$cur" ]; then echo "$n" > $BL/brightness; last=$n; fi
done
