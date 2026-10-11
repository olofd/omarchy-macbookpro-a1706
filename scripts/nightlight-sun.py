#!/usr/bin/env python3
"""Night light from sunset to sunrise, at the place set in Omarchy's weather widget.

Reads the place name from ~/.local/state/omarchy/settings/weather.json (e.g. "stockholm"), finds its coordinates
with Open-Meteo's geocoding (the service the weather widget itself uses; looked up once and cached until the
name changes), works out today's sunrise and sunset locally (NOAA formulas, no network), and writes them as
hyprsunset profiles: 4000 K (Omarchy's night light) from sunset, no tint from sunrise. hyprsunset is restarted
only when the times changed. Run daily and at login by nightlight-sun.timer (scripts/install-nightlight.sh).

  nightlight-sun            update hyprsunset.conf for today
  nightlight-sun --print    only show today's times
"""
import datetime as dt
import json
import math
import os
import subprocess
import sys
import urllib.parse
import urllib.request

HOME = os.path.expanduser("~")
WEATHER = os.path.join(HOME, ".local/state/omarchy/settings/weather.json")
CACHE = os.path.join(HOME, ".cache/nightlight-sun.json")
CONF = os.path.join(HOME, ".config/hypr/hyprsunset.conf")
NIGHT_TEMP = 4000          # Omarchy's own night light temperature (omarchy-toggle-nightlight ON_TEMP)


def place():
    try:
        with open(WEATHER) as fh:
            name = (json.load(fh).get("name") or "").strip()
    except (OSError, ValueError):
        name = ""
    return name


def coordinates(name):
    """(lat, lon, label) for the place, from the cache or Open-Meteo's geocoding."""
    try:
        with open(CACHE) as fh:
            c = json.load(fh)
        if c.get("name") == name:
            return c["lat"], c["lon"], c["label"]
    except (OSError, ValueError, KeyError):
        pass
    url = "https://geocoding-api.open-meteo.com/v1/search?" + urllib.parse.urlencode(
        {"name": name, "count": 1, "language": "en", "format": "json"})
    with urllib.request.urlopen(url, timeout=15) as r:
        res = (json.load(r).get("results") or [None])[0]
    if not res:
        raise SystemExit("nightlight-sun: no coordinates found for %r" % name)
    label = ", ".join(x for x in (res.get("name"), res.get("admin1"), res.get("country")) if x)
    c = {"name": name, "lat": res["latitude"], "lon": res["longitude"], "label": label}
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, "w") as fh:
        json.dump(c, fh)
    return c["lat"], c["lon"], label


def sun_times(lat, lon, day):
    """(sunrise, sunset) as local datetimes for the date `day`, or None in polar day/night (NOAA algorithm)."""
    n = day.timetuple().tm_yday
    g = 2 * math.pi / 365 * (n - 1)                                   # fractional year at noon
    eqtime = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g)
                       - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
    decl = (0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g) - 0.006758 * math.cos(2 * g)
            + 0.000907 * math.sin(2 * g) - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g))
    cos_ha = (math.cos(math.radians(90.833)) / (math.cos(math.radians(lat)) * math.cos(decl))
              - math.tan(math.radians(lat)) * math.tan(decl))
    if not -1 <= cos_ha <= 1:
        return None
    ha = math.degrees(math.acos(cos_ha))
    midnight = dt.datetime(day.year, day.month, day.day, tzinfo=dt.timezone.utc)

    def at(minutes):
        return (midnight + dt.timedelta(minutes=minutes)).astimezone()
    return at(720 - 4 * (lon + ha) - eqtime), at(720 - 4 * (lon - ha) - eqtime)


def render(sunrise, sunset, label):
    return ("# Written by nightlight-sun (omarchy-macbookpro-a1706 scripts/nightlight-sun.py) for %s, %s.\n"
            "# Night light %d K from sunset to sunrise; rewritten daily, edits here are replaced.\n"
            "profile {\n    time = %s\n    identity = true\n}\n\n"
            "profile {\n    time = %s\n    temperature = %d\n}\n"
            % (label, dt.date.today().isoformat(), NIGHT_TEMP, sunrise.strftime("%H:%M"), sunset.strftime("%H:%M"), NIGHT_TEMP))


def main():
    name = place()
    if not name:
        print("nightlight-sun: no place set in the weather widget; nothing changed")
        return 0
    lat, lon, label = coordinates(name)
    times = sun_times(lat, lon, dt.date.today())
    if not times:
        print("nightlight-sun: no sunrise/sunset today at %s; nothing changed" % label)
        return 0
    sunrise, sunset = times
    print("%s (%.3f, %.3f): sunrise %s, sunset %s" % (label, lat, lon, sunrise.strftime("%H:%M"), sunset.strftime("%H:%M")))
    if "--print" in sys.argv:
        return 0
    new = render(sunrise, sunset, label)
    old = open(CONF).read() if os.path.exists(CONF) else ""
    running = subprocess.run(["pgrep", "-x", "hyprsunset"], stdout=subprocess.DEVNULL).returncode == 0
    if old.split("\n", 2)[2:] == new.split("\n", 2)[2:] and running:   # same profiles (dated header aside)
        return 0
    if old and "nightlight-sun" not in old and not os.path.exists(CONF + ".before-nightlight-sun"):
        with open(CONF + ".before-nightlight-sun", "w") as fh:
            fh.write(old)
    with open(CONF, "w") as fh:
        fh.write(new)
    subprocess.run(["omarchy", "restart", "hyprsunset"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("hyprsunset updated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
