#!/bin/sh
# A small dock on the left edge of the Mac (nwg-dock-hyprland, Arch extra): hidden until the mouse touches the
# left edge, 24 px icons, a "glass" look (files/nwg-dock-style.css), pinned apps below. Started at login from
# Hyprland's autostart.lua (marked block).
#
#   sudo pacman -S --needed nwg-dock-hyprland     (once, by the owner; or: omarchy pkg add nwg-dock-hyprland)
#   sh install-dock.sh                                (as the user; starts it now too)
#   sh install-dock.sh --remove                       undo (stops it, removes the autostart line)
#
# Known limit (2026-10-11): Hyprland 0.55+ only takes Lua dispatches, and this dock (0.4.11) still sends the
# old "dispatch focuswindow ..." form, so clicking an app that is already open may not switch to it. Starting
# apps works. -hd 0: no hotspot delay, so the dock appears however slowly the pointer reaches the edge.
set -eu
[ "$(id -u)" -ne 0 ] || { echo "run as the user, not root" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
AUTO=$HOME/.config/hypr/autostart.lua
BEGIN="-- >>> mac-dock (omarchy-macbookpro-a1706 install-dock.sh)"
END="-- <<< mac-dock"
CMD="nwg-dock-hyprland -d -p left -i 24 -mb 2 -hd 0"

strip() {
  awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$AUTO" > "$AUTO.tmp.$$" &&
    mv "$AUTO.tmp.$$" "$AUTO"
}

if [ "${1:-}" = "--remove" ] || [ "${1:-}" = remove ]; then
  pkill -f '^nwg-dock-hyprland' || true
  strip
  echo "Dock removed from startup and stopped."
  exit 0
fi
command -v nwg-dock-hyprland >/dev/null ||
  { echo "install it first: sudo pacman -S --needed nwg-dock-hyprland" >&2; exit 1; }

mkdir -p "$HOME/.config/nwg-dock-hyprland" "$HOME/.cache"
tr -d '\r' < "$HERE/../files/nwg-dock-style.css" > "$HOME/.config/nwg-dock-hyprland/style.css"
# Pinned apps, by their .desktop names (ls /usr/share/applications ~/.local/share/applications). Kept if you
# already have a list: edit ~/.cache/nwg-dock-pinned, or pin from the dock's right-click menu.
[ -s "$HOME/.cache/nwg-dock-pinned" ] || printf '%s\n' chromium foot > "$HOME/.cache/nwg-dock-pinned"

strip
cat >> "$AUTO" <<EOF
$BEGIN
-- The dock on the left edge (see install-dock.sh).
o.exec_on_start("$CMD")
$END
EOF

pkill -f '^nwg-dock-hyprland' || true
sleep 1
setsid -f $CMD >/dev/null 2>&1
echo "Dock running, and started at every login."
