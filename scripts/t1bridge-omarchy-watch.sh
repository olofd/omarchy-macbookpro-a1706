#!/bin/bash
# Keeps the Touch Bar's desktop state current from events, so the renderer's once-a-second status call
# (t1bridge-omarchy-provider v1 status) reads one line instead of running five programs (~40 ms of CPU every
# second before). Installed as ~/.local/bin/t1bridge-omarchy-watch and run by the user service
# t1bridge-omarchy-watch.service (install-touchbar-renderer.sh).
#
# It waits on PipeWire's change events (pactl subscribe: sink volume, mute, default output) and on D-Bus
# media players appearing or leaving (NameOwnerChanged for org.mpris.MediaPlayer2.*), and after each burst
# writes "VOLUME MUTED MEDIA" (e.g. "46 0 1", or "- - 0" without an output) to
# $XDG_RUNTIME_DIR/t1bridge-omarchy/state. Idle, it costs nothing. If an event stream ends (PipeWire
# restarted), it exits and systemd starts it again; the file is removed on exit, and the provider then
# works the state out itself.
set -uo pipefail
PATH="$PATH:/usr/share/omarchy/bin"
DIR=${XDG_RUNTIME_DIR:-/run/user/$UID}/t1bridge-omarchy
STATE=$DIR/state
mkdir -p "$DIR"
trap 'rm -f "$STATE"' EXIT

# sink_state SINK: "PERCENT MUTED" (MUTED 1 or 0) for SINK's first channel (as the provider computes it).
sink_state() {
  LC_ALL=C pactl list sinks 2>/dev/null | awk -v sink="$1" '
    /^\tName: / { hit = ($2 == sink) }
    hit && /^\tMute: / { muted = ($2 == "yes") }
    hit && /^\tVolume: / {
      for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+%$/) { sub("%", "", $i); print $i, muted + 0; exit }
    }'
}

write_state() {
  local sink pct="" mute="" media=0 names
  sink=$(omarchy-audio-output-sink 2>/dev/null)
  if [[ -n $sink ]]; then read -r pct mute < <(sink_state "$sink"); fi
  [[ $pct =~ ^[0-9]+$ ]] || { pct=-; mute=-; }
  names=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus \
    ListNames 2>/dev/null)
  [[ $names == *org.mpris.MediaPlayer2.* ]] && media=1
  printf '%s %s %s\n' "$pct" "${mute:-0}" "$media" > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
}

events() {
  pactl subscribe 2>/dev/null | grep --line-buffered -E "on (sink|server) " &
  dbus-monitor --session "type='signal',sender='org.freedesktop.DBus',member='NameOwnerChanged',\
arg0namespace='org.mpris.MediaPlayer2'" 2>/dev/null | grep --line-buffered "member=NameOwnerChanged" &
  # When one stream ends, end the other too, so the pipe closes and the service restarts both.
  wait -n
  # shellcheck disable=SC2046  # one PID per word, by design
  kill $(jobs -p) 2>/dev/null
}

write_state
events | while read -r _; do
  # Changes come in bursts (a volume slide is dozens of events): settle for 50 ms, then write once.
  while read -r -t 0.05 _; do :; done
  write_state
done
exit 1
