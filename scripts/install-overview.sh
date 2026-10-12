#!/bin/sh
# Workspace overview on the Mac (Omarchy 4): every workspace on one screen, with live window previews and
# drag-and-drop moving. The Omarchy shell plugin moorgrove.overview (github.com/itsmoorgrove/omarchy-overview,
# MIT; code read 2026-10-11: it only reads/writes ~/.config/hypr/bindings.lua, never goes online).
# Opens with:  three fingers up on the trackpad (like Mission Control; three fingers sideways still switch
# workspaces),  Super + the key left of 1 (§ on the Swedish layout),  or the icon in the bar.
#
#   sh install-overview.sh            (as the user)       sh install-overview.sh --remove     to undo
#
# Safe to run again. The gesture, the key and one window rule live in marked blocks at the end of input.lua,
# bindings.lua and hyprland.lua.
# The window rule: when the overview closes, Hyprland gives focus back to the window you came from for a moment.
# Some apps answer that with an activation request (Claude Desktop does), and with Omarchy's focus_on_activate
# the compositor jumps straight back to that app's workspace (seen 4-40 ms after every switch). Such apps get
# focus_on_activate = false, as Omarchy already does for Telegram. Add yours to STEAL below if you see this.
set -eu
[ "$(id -u)" -ne 0 ] || { echo "run as the user, not root" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"

ID=moorgrove.overview
REPO=https://github.com/itsmoorgrove/omarchy-overview.git
HYPR=$HOME/.config/hypr
BEGIN="-- >>> mac-overview (omarchy-macbookpro-a1706 install-overview.sh)"
END="-- <<< mac-overview"
TOGGLE="omarchy-shell shell toggle $ID"
STEAL="com.anthropic.Claude"   # window classes (hyprctl clients) that steal focus back

strip() { drop_block "$1" "$BEGIN" "$END"; }

if [ "${1:-}" = "--remove" ] || [ "${1:-}" = remove ]; then
  strip "$HYPR/input.lua"; strip "$HYPR/bindings.lua"; strip "$HYPR/hyprland.lua"
  omarchy plugin disable "$ID" >/dev/null 2>&1 || true
  omarchy plugin remove "$ID" --yes >/dev/null 2>&1 || true
  hyprctl reload >/dev/null
  echo "Overview removed."
  exit 0
fi

if ! omarchy plugin list 2>/dev/null | grep -q "^$ID "; then
  omarchy plugin add "$REPO" --yes
fi
omarchy plugin list 2>/dev/null | grep -q "^$ID  *enabled " ||
  { omarchy plugin enable "$ID" >/dev/null; CHANGED=1; }

for f in input.lua bindings.lua hyprland.lua; do
  [ -f "$HYPR/$f.before-overview" ] || cp "$HYPR/$f" "$HYPR/$f.before-overview"
done
put_block "$HYPR/input.lua" "$BEGIN" "$END" <<EOF
-- Three fingers up: the workspace overview (three fingers sideways switch workspaces, above).
hl.gesture({ fingers = 3, direction = "up", action = function() hl.dispatch(hl.dsp.exec_cmd("$TOGGLE")) end })
EOF
put_block "$HYPR/bindings.lua" "$BEGIN" "$END" <<EOF
-- Super + § (the key left of 1 on the Swedish layout; keysym "section"): the workspace overview.
o.bind("SUPER + section", "Workspace overview", "$TOGGLE")
EOF
put_block "$HYPR/hyprland.lua" "$BEGIN" "$END" <<EOF
-- Apps that pull focus back to their own workspace undo switches from the overview.
$(for c in $STEAL; do echo "o.window(\"$c\", { focus_on_activate = false })"; done)
EOF
[ "$CHANGED" = 1 ] || { echo "Overview: already up to date."; exit 0; }

hyprctl reload >/dev/null
errors=$(hyprctl configerrors 2>&1 | grep -v '^$' || true)
if [ -n "$errors" ]; then
  echo "Hyprland reports config errors, rolling back the gesture and key:" >&2
  echo "$errors" >&2
  strip "$HYPR/input.lua"; strip "$HYPR/bindings.lua"; strip "$HYPR/hyprland.lua"; hyprctl reload >/dev/null
  exit 1
fi
echo "Overview ready: three fingers up, Super + § (left of 1), or the bar icon."
