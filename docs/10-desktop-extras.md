# 10. Desktop extras

Not needed for the hardware, but they make this Mac nicer to use under Omarchy. Each one is a script that is
safe to run again and has a `--remove`. Run them as your user (not with sudo).

## Workspace overview (like Mission Control)

```sh
sh scripts/install-overview.sh
```

Every workspace on one screen with live window previews; drag a window onto another workspace to move it,
`/` to search. It is the Omarchy shell plugin
[itsmoorgrove/omarchy-overview](https://github.com/itsmoorgrove/omarchy-overview) (MIT; its code only reads and
writes `~/.config/hypr/bindings.lua` and never goes online). The script adds a **three-finger swipe up** (three
fingers sideways still switch workspaces) and **Super + the key left of 1** (`section`, the `§` key on Nordic
layouts), in marked blocks of `input.lua`, `bindings.lua` and `hyprland.lua` (backups: `*.before-overview`), and
checks `hyprctl configerrors`.

If clicking a workspace in the overview switches and immediately jumps back: an app is pulling focus back when
the overview closes (Hyprland's `focus_on_activate`, which Omarchy turns on). Claude Desktop did; its window
class is in `STEAL` in the script. Find others with `hyprctl clients` and add them.

## A dock

```sh
omarchy pkg add nwg-dock-hyprland
sh scripts/install-dock.sh
```

[nwg-dock-hyprland](https://github.com/nwg-piotr/nwg-dock-hyprland) on the left edge, hidden until the pointer
touches the edge, 24 px icons, a semi-transparent style (`files/nwg-dock-style.css`), started from
`autostart.lua`. Pinned apps are in `~/.cache/nwg-dock-pinned` (`.desktop` names). Two things learnt:

- `-hd 0`: with the default hotspot delay the dock only appears if the pointer reaches the edge quickly.
- Hyprland 0.55+ only accepts Lua dispatches over its socket; nwg-dock 0.4.11 still sends the old
  `dispatch focuswindow ...`, so clicking an app that is **already open** may not switch to it. Starting apps
  works.

## Night light from sunset to sunrise

```sh
sh scripts/install-nightlight.sh
```

Takes the place you set in Omarchy's **weather** widget, finds its coordinates once (Open-Meteo's geocoding, the
service the widget uses), works out sunrise and sunset every day (no further network use), and writes them as
`hyprsunset` profiles: 4000 K (Omarchy's night light) from sunset to sunrise. A systemd user timer runs it at
login and just after midnight. The manual night light toggle keeps working. Set a place in the weather widget
first; without one the script changes nothing.

## Charger chime

```sh
sh scripts/install-chime.sh
```

A soft two-note bell when the charger is plugged in and a softer one when it is pulled, like macOS (a user
service listening to `udevadm monitor --subsystem-match=power_supply`). The sound is synthesised by
`scripts/mkchime.py`, so there is no copyrighted audio in the repository. Volume: 0.35 by default; set e.g.
`VOLUME=0.2` (0 to 1) in `~/.config/charger-chime.conf`.

## Check the time zone and Wi-Fi country

The installer can leave the time zone and the Wi-Fi regulatory country on another country's values (here it
was Europe/London and `GB` on a Mac elsewhere), which also moves the night light by an hour.

```sh
timedatectl | grep "Time zone"                     # fix: sudo timedatectl set-timezone Europe/Stockholm
grep -v '^#' /etc/conf.d/wireless-regdom           # e.g. WIRELESS_REGDOM="SE" for Sweden
```

To change the Wi-Fi country, edit `/etc/conf.d/wireless-regdom`: comment out the active line, uncomment yours,
and reboot.
