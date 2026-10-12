#!/bin/sh
# Keyboard backlight from the ambient light sensor (the A1706's iBridge "als" IIO device).
# Dark -> on, bright -> off, smoothed so it does not flicker. If the keyboard brightness is changed by
# hand (the Touch Bar keys), the change is kept as an offset: automatic control keeps following the
# light, always that far above or below its own level.
# Thresholds and brightness steps are in /etc/kbd-auto-backlight.conf (raw sensor counts, 0-255 light).
LED=/sys/class/leds/spi::kbd_backlight
ALS=$(grep -l '^als$' /sys/bus/iio/devices/iio:device*/name 2>/dev/null | head -n 1 | xargs -r dirname)
CONF=/etc/kbd-auto-backlight.conf
DARK=3; DIM=30; ON=200; MID=90      # the same as files/kbd-auto-backlight.conf
[ -r "$CONF" ] && . "$CONF"
[ -n "$ALS" ] && [ -w "$LED/brightness" ] || { echo "no light sensor or keyboard light" >&2; exit 1; }

MAX=$(cat $LED/max_brightness 2>/dev/null || echo 255)
last=$(cat $LED/brightness); offset=0; smooth=
while :; do
  cur=$(cat $LED/brightness)
  if [ "$cur" != "$last" ]; then offset=$(( offset + cur - last )); last=$cur; fi
  raw=$(cat $ALS/in_illuminance_raw 2>/dev/null || echo 0)
  # Moving average: fast to follow, slow enough to ignore a hand passing over the sensor.
  smooth=${smooth:-$raw}
  smooth=$(( (smooth * 3 + raw) / 4 ))
  if   [ "$smooth" -lt "$DARK" ]; then target=$ON
  elif [ "$smooth" -lt "$DIM" ];  then target=$MID
  else target=0; fi
  # The offset is kept inside what the light can show: unbounded, turning it off in the dark left it so far
  # below the curve that brightness up in a bright room only paid it back and the light stayed off.
  [ $(( target + offset )) -lt 0 ] && offset=$(( -target ))
  [ $(( target + offset )) -gt "$MAX" ] && offset=$(( MAX - target ))
  target=$(( target + offset ))
  if [ "$target" != "$cur" ]; then
    echo "light=$raw avg=$smooth -> $target" | logger -t kbd-auto-backlight
    echo "$target" > $LED/brightness
    last=$target
  fi
  sleep 2
done
