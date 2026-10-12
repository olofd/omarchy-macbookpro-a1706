#!/bin/sh
# The guide's Touch Bar renderer and desktop provider, on top of t1bridge (install-touchbar.sh first):
#  - t1bridge-renderer/*.patch: the renderer sleeps until input, a timer or news instead of polling every
#    5 ms (~200 wakeups a second idle, now ~1), and sliding a finger on the volume, display brightness or
#    keyboard backlight controls turns the bar into a slider for that level. Built from t1bridge's source at
#    the version of the installed package, into ~/.local/lib/t1bridge-renderer, and run by the user service
#    t1-touchbar through a drop-in. The hardware service and everything else stay the package's.
#  - t1bridge-omarchy-provider + t1bridge-omarchy-watch: the provider's once-a-second status reads a line the
#    watcher keeps current from PipeWire and D-Bus events (~4 ms instead of ~40 ms of CPU per call).
# Rebuilt only when the t1bridge package or the patches change. Needs Rust (cargo; else it uses mise, which
# Omarchy ships, to fetch a toolchain into your home once) and git; the build takes under a minute.
#   sh install-touchbar-renderer.sh           (as your user, in the desktop)
#   sh install-touchbar-renderer.sh remove    back to the package's renderer (the provider stays)
set -eu
[ "$(id -u)" -ne 0 ] || { echo "run as your user, not root" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
PATCHES=$HERE/../t1bridge-renderer
LIB=$HOME/.local/lib/t1bridge-renderer
UNITS=$HOME/.config/systemd/user
DROPIN=$UNITS/t1-touchbar.service.d/50-a1706-renderer.conf
RUST=rust@1.98                     # used through mise when there is no cargo; t1bridge needs >= 1.88

case "${1:-}" in remove|--remove)
  rm -f "$DROPIN"
  rm -rf "$LIB"
  systemctl --user daemon-reload
  systemctl --user restart t1-touchbar.service 2>/dev/null || true
  echo "Back to the t1bridge package's renderer."
  exit 0 ;;
esac
command -v pacman >/dev/null && pacman -Q t1bridge >/dev/null 2>&1 ||
  { echo "t1bridge is not installed: run install-touchbar.sh first" >&2; exit 1; }

# The provider and its watcher.
put_file "$HERE/t1bridge-omarchy-provider.sh" "$HOME/.local/bin/t1bridge-omarchy-provider" 755
put_text "$UNITS/t1-touchbar.service.d/omarchy-provider.conf" 644 <<'EOF'
[Service]
Environment=T1BRIDGE_DESKTOP_PROVIDER=%h/.local/bin/t1bridge-omarchy-provider
EOF
WATCH_CHANGED=$CHANGED; CHANGED=0
put_file "$HERE/t1bridge-omarchy-watch.sh" "$HOME/.local/bin/t1bridge-omarchy-watch" 755
put_file "$HERE/../files/t1bridge-omarchy-watch.service" "$UNITS/t1bridge-omarchy-watch.service" 644
[ "$CHANGED" = 1 ] && WATCH_CHANGED=1
systemctl --user daemon-reload
systemctl --user enable --quiet t1bridge-omarchy-watch.service
if [ "$WATCH_CHANGED" = 1 ] || ! systemctl --user -q is-active t1bridge-omarchy-watch.service; then
  systemctl --user restart t1bridge-omarchy-watch.service
fi

# The renderer: built for this t1bridge version from exactly these patches, or not at all.
version=$(pacman -Q t1bridge | awk '{print $2}' | sed 's/-[0-9]*$//')
want=$( { echo "$version"; cat "$PATCHES"/*.patch; } | sha256sum | cut -d' ' -f1)
if [ -x "$LIB/t1-touchbar" ] && [ "$(cat "$LIB/built-from" 2>/dev/null)" = "$want" ] && [ -f "$DROPIN" ]; then
  [ "$WATCH_CHANGED" = 1 ] && systemctl --user restart t1-touchbar.service
  echo "Touch Bar renderer: already up to date (t1bridge $version with the guide's patches)."
  exit 0
fi
# A working cargo (a mise shim without a selected version is on PATH but fails), else Rust through mise.
if command cargo --version >/dev/null 2>&1; then cargo() { command cargo "$@"; }
elif command -v mise >/dev/null; then cargo() { mise exec "$RUST" -- cargo "$@"; }
else echo "no Rust toolchain: install rust (omarchy pkg add rust), then run this again" >&2; exit 1; fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "Building the Touch Bar renderer from t1bridge v$version with the guide's patches..."
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v$version" \
  https://github.com/standardagents/t1bridge.git "$work/t1bridge"
if ! git -C "$work/t1bridge" apply "$PATCHES"/*.patch; then
  echo "The guide's patches do not apply to t1bridge v$version: keeping the package's renderer." >&2
  rm -f "$DROPIN"; systemctl --user daemon-reload; exit 0
fi
(cd "$work/t1bridge" && cargo build --quiet --release -p t1-touchbar)
mkdir -p "$LIB"
install -m 755 "$work/t1bridge/target/release/t1-touchbar" "$LIB/t1-touchbar"
echo "$want" > "$LIB/built-from"
put_text "$DROPIN" 644 <<'EOF'
[Service]
# The guide's renderer (omarchy-macbookpro-a1706 install-touchbar-renderer.sh); remove this file, or run
# the script with `remove`, for the t1bridge package's own.
ExecStart=
ExecStart=%h/.local/lib/t1bridge-renderer/t1-touchbar
EOF
systemctl --user daemon-reload
systemctl --user restart t1-touchbar.service
echo "Touch Bar renderer installed (t1bridge $version with the guide's patches)."
