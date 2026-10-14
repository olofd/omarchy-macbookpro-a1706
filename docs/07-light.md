# 7. Ambient light sensor, automatic brightness and keyboard backlight

Once the T1 is running ([04-touchbar](04-touchbar.md)), the ambient light sensor next to the camera shows up
as a normal Linux IIO device:

```sh
cat /sys/bus/iio/devices/iio:device0/name              # als
cat /sys/bus/iio/devices/iio:device0/in_illuminance_raw
```

`iio-sensor-proxy` (installed by Omarchy) also sees it (`HasAmbientLight` is true), but nothing uses it on
Omarchy by default. The t1-revive notes say the sensor is "unavailable under t1bridge"; that is about t1bridge's
own sensor path. The kernel's HID sensor driver exposes it fine.

## The raw scale on this sensor

Measured with a 42-second test (uncovered, covered with a finger, a phone flashlight):

| Condition | Raw reading |
| --- | --- |
| Covered | `0` |
| An indoor room, evening | about `16` to `20` |
| Phone flashlight on the sensor | `360` to `700` |

It is not lux, and the scale is small at the dark end, so thresholds are set in raw counts.

## Install

```sh
sudo sh scripts/install-light.sh
```

This installs two small services (`systemd`, system level), each a short shell loop reading the sensor
every second or two with a moving average so a hand passing over it does not change anything:

- **`kbd-auto-backlight`**: the keyboard light (`/sys/class/leds/spi::kbd_backlight`, 0 to 255). Under raw
  `3` the light is full, under `30` medium, above that off. Tune in `/etc/kbd-auto-backlight.conf`
  (`DARK`, `DIM`, `ON`, `MID`).
- **`screen-auto-brightness`**: the screen (`/sys/class/backlight/acpi_video0`, 0 to 90 on this Mac).
  A curve from dark (`MIN`) through a room (`ROOM`) to daylight (`MAXB`), eased two steps per second so it
  never jumps. Tune by creating `/etc/screen-auto-brightness.conf` (not installed; the defaults are at the top of
  `scripts/screen-auto-brightness.sh`: `MIN`, `ROOM`, `MAXB`, `DARKLUX`, `ROOMLUX`, `SUNLUX`, `STEP`, and
  `HOLD`, `FACTOR` below; `HOLD` and `FACTOR` also work in `/etc/kbd-auto-backlight.conf`).
- After changing either file: `sudo systemctl restart kbd-auto-backlight screen-auto-brightness`.

**A change by hand wins.** If you change the brightness by hand (the Touch Bar keys or slider), the service
sees a value it did not set and **holds off for an hour** (`HOLD=3600`). It takes over earlier only if the room
light changes a lot: four times brighter or darker than when you set it (`FACTOR=4`), for half a minute (going
outside, switching the lamp off). Then it eases back to its curve. This is how phones and Macs treat it: your
setting stays until the situation changes. (Before, a change by hand became a lasting offset and the level kept
moving with the light, so it drifted away from what you set.) The hold is kept in `/run`, so it survives the
services' restart at every wake, and time asleep counts. `journalctl -t screen-auto-brightness -t
kbd-auto-backlight` shows when a hold starts and ends.

**After a wake** the sensor (on the T1) is gone for a moment while the T1 comes back on USB. A missing sensor
is treated as no reading: it was read as 0, darkness, which dimmed the screen to its minimum and turned the
keyboard light on full right after a wake. The service looks the sensor up again, ignores its first readings
after a start, and restarts if the sensor stays gone for a minute.

**The lock screen** blanks the display (brightness 0) and turns the keyboard light off, and puts both back at
unlock: the services leave them alone while the display is blanked and do not take those changes for ones by
hand.

The sleep hook stops both services before sleep and starts them after, so they do not fight the hook when it
switches the keyboard light off.

## Other tools

[`wluma`](https://github.com/maximbaz/wluma) (AUR) does the screen part with learning and screen-content
awareness; it was considered and replaced by the small service above to keep the setup short and to control
the thresholds directly.
