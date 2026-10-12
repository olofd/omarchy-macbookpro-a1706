#!/bin/sh
# Trackpad and workspace gestures for Hyprland on Omarchy (the A1706's SPI trackpad), in a marked block of the
# user's ~/.config/hypr/input.lua (Omarchy keeps personal overrides there). Safe to run again: it changes the
# file only if the block differs from this script's.
#   sh install-input.sh            (as your user, not with sudo)
#   sh install-input.sh remove     undo (Omarchy's own trackpad settings apply again)
set -eu
[ "$(id -u)" -ne 0 ] || { echo "run as your user, not root" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
f=$HOME/.config/hypr/input.lua
BEGIN="-- >>> a1706 trackpad (omarchy-macbookpro-a1706 install-input.sh)"
END="-- <<< a1706 trackpad"
[ -f "$f" ] || { echo "no $f (is Omarchy's Hyprland config there?)" >&2; exit 1; }

# Earlier versions wrote the block without markers: from "-- a1706 trackpad:" to the gesture line. Give it the
# markers, so it is replaced in place below.
if grep -q '^-- a1706 trackpad:' "$f"; then
  awk -v b="$BEGIN" -v e="$END" '
    /^-- a1706 trackpad:/ { print b; old = 1; next }
    old && /^hl\.gesture\(\{ fingers = 3, direction = "horizontal", action = "workspace" \}\)$/ {
      print e; old = 0; next }
    !old { print }' "$f" > "$f.tmp.$$" && cat "$f.tmp.$$" > "$f" && rm -f "$f.tmp.$$"
fi

case "${1:-}" in remove|--remove)
  drop_block "$f" "$BEGIN" "$END"
  echo "Removed from $f."
  exit 0 ;;
esac

# Natural scrolling, no tap-to-click (a palm brushing the pad moves the text cursor), palm rejection while
# typing, three-finger swipe between workspaces.
put_block "$f" "$BEGIN" "$END" <<'LUA'
hl.config({
  input = {
    touchpad = {
      natural_scroll = true,
      clickfinger_behavior = true,
      scroll_factor = 0.33,
      tap_to_click = false,
      disable_while_typing = true,
    },
  },
})
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
LUA
if [ "$CHANGED" = 1 ]; then
  echo "Trackpad settings written to $f. Hyprland picks them up by itself (check: hyprctl configerrors)."
else
  echo "Trackpad settings: already up to date."
fi
