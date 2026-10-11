#!/bin/sh
# Screen brightness from the ambient light sensor (the A1706's iBridge "als" IIO device).
# Dark room -> dim, bright room -> bright, eased a few steps at a time so it never jumps. If the
# brightness is changed by hand (the Touch Bar keys), the change is kept as an offset: automatic control
# keeps following the light, always that many steps above or below the curve.
# Curve and limits: /etc/screen-auto-brightness.conf (sensor: covered 0, a room about 16, daylight 300+).
BL=/sys/class/backlight/acpi_video0
ALS=$(grep -l '^als$' /sys/bus/iio/devices/iio:device*/name 2>/dev/null | head -n 1 | xargs -r dirname)
CONF=/etc/screen-auto-brightness.conf
MIN=12; ROOM=40; MAXB=90      # backlight steps (hardware max is 90)
DARKLUX=3; ROOMLUX=30; SUNLUX=300; STEP=2
[ -r "$CONF" ] && . "$CONF"
[ -n "$ALS" ] && [ -w "$BL/brightness" ] || { echo "no light sensor or backlight" >&2; exit 1; }
hw=$(cat $BL/max_brightness); [ "$MAXB" -gt "$hw" ] && MAXB=$hw

last=$(cat $BL/brightness); offset=0; smooth=
while :; do
  cur=$(cat $BL/brightness)
  if [ "$cur" != "$last" ]; then offset=$(( offset + cur - last )); last=$cur; fi
  raw=$(cat $ALS/in_illuminance_raw 2>/dev/null || echo 0)
  smooth=${smooth:-$raw}
  smooth=$(( (smooth * 7 + raw) / 8 ))      # slow average: a hand over the sensor does not dim the screen
  if   [ "$smooth" -le "$DARKLUX" ]; then t=$MIN
  elif [ "$smooth" -le "$ROOMLUX" ]; then t=$(( MIN + (smooth - DARKLUX) * (ROOM - MIN) / (ROOMLUX - DARKLUX) ))
  elif [ "$smooth" -le "$SUNLUX" ];  then t=$(( ROOM + (smooth - ROOMLUX) * (MAXB - ROOM) / (SUNLUX - ROOMLUX) ))
  else t=$MAXB; fi
  t=$(( t + offset )); [ "$t" -lt 1 ] && t=1; [ "$t" -gt "$MAXB" ] && t=$MAXB
  if   [ "$t" -gt "$cur" ]; then n=$(( cur + STEP )); [ "$n" -gt "$t" ] && n=$t
  elif [ "$t" -lt "$cur" ]; then n=$(( cur - STEP )); [ "$n" -lt "$t" ] && n=$t
  else n=$cur; fi
  if [ "$n" != "$cur" ]; then echo "$n" > $BL/brightness; last=$n; fi
  sleep 1
done
