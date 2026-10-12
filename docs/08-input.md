# 8. Keyboard, trackpad and gestures

## Keyboard

- The built-in keyboard and trackpad are **SPI** devices (`applespi`). Omarchy's installer detects the model and
  installs `macbook12-spi-driver-dkms`. Until it is installed (live image, first boot) use a USB keyboard.
- Layout: Omarchy uses PC layouts, so on a Nordic or German layout the AltGr symbols (`{ [ ] } | \`) are typed
  with an **Option** key acting as AltGr plus the number row (Swedish: Option+7 = `{`); if one Option key gives
  nothing, use the other. Set the layout in `~/.config/hypr/input.lua` (`kb_layout`, `kb_variant`); Omarchy's
  file has a commented example.
- The keyboard backlight is `spi::kbd_backlight`; see [07-light.md](07-light.md).

## Trackpad

`sh scripts/install-input.sh` (as yourself, no sudo) appends this to your `~/.config/hypr/input.lua` (Omarchy
keeps personal overrides there):

```lua
hl.config({
  input = {
    touchpad = {
      natural_scroll = true,        -- content follows the fingers, like macOS
      clickfinger_behavior = true,  -- two-finger click = right click
      scroll_factor = 0.33,         -- Omarchy's suggestion is 0.4; 0.33 felt closer to macOS
      tap_to_click = false,         -- see below
      disable_while_typing = true,
    },
  },
})
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
```

- Hyprland's Lua config uses `tap_to_click` with underscores in a table. The option name in `hyprctl` is
  `input:touchpad:tap-to-click`; `["tap-to-click"] = false` in the Lua table is accepted silently and does
  nothing. Check with `hyprctl getoption input:touchpad:tap-to-click` (`bool: false`, `set: true`).
- **Why tap-to-click is off:** the text cursor jumping back into the text while typing is a palm brushing the
  pad, which registers as a tap, and a click moves the caret. Libinput's disable-while-typing is weaker on
  this SPI trackpad. Pressing the pad down still clicks.
- **Three-finger swipe** moves between workspaces. Also `Super+Tab`, `Super+scroll`, and `Super+1..9`.

## Window management in Omarchy (Hyprland, tiling)

There is no minimise: windows tile, and you use **workspaces** instead. `Super+1..9` switch, `Super+Shift+1..9`
send a window there, `Super+arrows` move focus, `Alt+Tab` cycles windows on the workspace, `Super+W` closes,
`Super+Space` opens the Omarchy menu, `Super+Alt+Space` the app launcher, `Super+K` the list of all keybindings.
Copy and paste in terminals are
`Super+C` / `Super+V`; select-all is `Ctrl+A` in text boxes.

## Start apps on their own workspaces

A small script you write yourself (e.g. `~/.local/bin/workspace-startup`, made executable), run from
`~/.config/hypr/autostart.lua`, can open each app on its workspace at login:

```lua
o.exec_on_start("/home/you/.local/bin/workspace-startup")
```

with `hyprctl dispatch "hl.dsp.exec_cmd(\"uwsm-app -- chromium\", { workspace = \"2 silent\" })"` per app.
(Hyprland's Lua dispatch syntax is `hl.dsp.exec_cmd(cmd, { workspace = "N silent" })`; the older
`exec [workspace N silent]` form is a parse error.)
