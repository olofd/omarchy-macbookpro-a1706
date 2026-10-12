#!/bin/sh
# Trackpad and workspace gestures for Hyprland on Omarchy (the A1706's SPI trackpad). Appends to the
# user's ~/.config/hypr/input.lua (Omarchy keeps personal overrides there) once.
#   sh install-input.sh            (or sudo sh install-input.sh [USER])
#   sh install-input.sh remove     undo (Omarchy's own trackpad settings apply again)
set -eu
MODE=install
case "${1:-}" in remove|--remove) MODE=remove; shift ;; esac
U=${1:-${SUDO_USER:-$(id -un)}}
[ "$U" != root ] || { echo "give the user name: sudo sh $0 USER" >&2; exit 1; }
HOME_DIR=$(getent passwd "$U" | cut -d: -f6)
f=$HOME_DIR/.config/hypr/input.lua
[ -f "$f" ] || { echo "no $f (is Omarchy's Hyprland config there?)" >&2; exit 1; }
if [ "$MODE" = remove ]; then
  # The block: from its "-- a1706 trackpad" comment to the gesture line that ends it (and the blank line before).
  awk '/^-- a1706 trackpad/ {skip = 1; sub(/\n$/, "", buf)} !skip {printf "%s", buf; buf = $0 "\n"}
       skip && /^hl\.gesture\(\{ fingers = 3, direction = "horizontal", action = "workspace" \}\)$/ {skip = 0}
       END {printf "%s", buf}' "$f" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"
  chown "$U:" "$f"
  echo "Removed from $f."
  exit 0
fi
grep -q 'a1706 trackpad' "$f" && { echo "already set"; exit 0; }
cat >> "$f" <<'LUA'

-- a1706 trackpad: natural scrolling, no tap-to-click (a palm brushing the pad moves the text cursor),
-- palm rejection while typing, three-finger swipe between workspaces.
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
chown "$U:" "$f"
echo "Done. Hyprland picks the change up by itself (check: hyprctl configerrors)."
