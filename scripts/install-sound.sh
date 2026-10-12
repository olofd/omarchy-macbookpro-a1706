#!/bin/sh
# Sound on the A1706 (Cirrus Logic CS8409): the in-kernel driver loads but the speakers stay silent.
# Builds the community driver (davidjo/snd_hda_macbookpro) with DKMS so it is rebuilt on kernel updates, with
# this guide's patches from snd-hda-macbookpro/ applied (the internal mic's level).
#   sudo sh install-sound.sh        then reboot. Safe to run again: an installed driver only gets the patches
#                                   it is missing (and a rebuild then).
set -eu
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo sh $0" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
PATCHES=$HERE/../snd-hda-macbookpro
# DKMS links to the source folder, so it must stay (a temporary one leaves it "broken").
src=/usr/local/src/snd_hda_macbookpro
DKMS_NAME=snd_hda_macbookpro/0.1
# Which of our patches the installed module was built with (a patched source alone proves nothing).
STAMP=$src/.omarchy-macbookpro-a1706-patches
WANT=$(cat "$PATCHES"/*.patch 2>/dev/null | sha256sum | cut -d' ' -f1)
cat /proc/asound/card*/codec#* 2>/dev/null | grep -qi cs8409 ||
  { echo "no CS8409 codec: this fix is not for this machine"; exit 0; }
# The built-in mic's starting level (the mic patch makes the gain real: 100 % would clip). Not a reason to
# rebuild the driver, so CHANGED is reset after it.
put_file "$HERE/../files/wireplumber-internal-mic.conf" \
  /etc/wireplumber/wireplumber.conf.d/60-a1706-internal-mic.conf 644
CHANGED=0

# apply_patches DIR: apply each of our patches that DIR does not have yet (CHANGED=1 if any); 1 if one fails.
apply_patches() {
  for p in "$PATCHES"/*.patch; do
    [ -f "$p" ] || continue
    patch -d "$1" -p1 -R --dry-run --force --fuzz=0 < "$p" >/dev/null 2>&1 && continue   # already in
    patch -d "$1" -p1 --forward --batch --fuzz=0 --no-backup-if-mismatch < "$p" || return 1
    echo "applied ${p##*/}"
    CHANGED=1
  done
}

if dkms status 2>/dev/null | grep -qi 'snd_hda_macbookpro.*: installed'; then
  [ -d "$src" ] || { echo "Sound: installed, but its source $src is gone; patches not checked" >&2; exit 0; }
  apply_patches "$src" || { echo "a patch did not apply to $src" >&2; exit 1; }
  if [ "$CHANGED" = 0 ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$WANT" ]; then
    echo "Sound: already installed (with this guide's patches)."; exit 0
  fi
  # build --force really rebuilds (install --force alone reinstalls the module built before).
  dkms build "$DKMS_NAME" -k "$(uname -r)" --force
  dkms install "$DKMS_NAME" -k "$(uname -r)" --force
  echo "$WANT" > "$STAMP"
  echo "The built-in mic's level now works: about 85 % is right (as yourself:"
  echo "  pactl set-source-volume alsa_input.pci-0000_00_1f.3.analog-stereo 85%   after the reboot)."
  needs_reboot "the patched sound driver"; exit 0
fi

kpkg=$(pacman -Qqo "/usr/lib/modules/$(uname -r)/vmlinuz" 2>/dev/null) ||
  { echo "the running kernel $(uname -r) is no longer installed (updated without a reboot): reboot first" >&2
    exit 1; }
pacman -S --needed --noconfirm base-devel dkms git wget patch "${kpkg}-headers"
for repo in https://github.com/davidjo/snd_hda_macbookpro.git \
            https://github.com/egorenar/snd_hda_macbookpro.git; do
  rm -rf "$src"
  git clone --depth 1 "$repo" "$src"
  apply_patches "$src" || { echo "A patch did not apply to $repo, trying the next." >&2; continue; }
  if (cd "$src" && sh ./install.cirrus.driver.sh -i); then
    echo "$WANT" > "$STAMP"
    echo "Installed from $repo."; needs_reboot "the sound driver"; exit 0
  fi
  echo "Build from $repo failed, trying the next." >&2
done
echo "The sound driver did not build." >&2; exit 1
