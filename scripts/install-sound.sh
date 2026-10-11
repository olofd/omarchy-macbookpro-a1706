#!/bin/sh
# Sound on the A1706 (Cirrus Logic CS8409): the in-kernel driver loads but the speakers stay silent.
# Builds the community driver (davidjo/snd_hda_macbookpro) with DKMS so it is rebuilt on kernel updates.
#   sudo sh install-sound.sh        then reboot. Safe to run again.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo sh $0" >&2; exit 1; }
cat /proc/asound/card*/codec#* 2>/dev/null | grep -qi cs8409 || { echo "no CS8409 codec: this fix is not for this machine"; exit 0; }
dkms status 2>/dev/null | grep -qi snd_hda_macbookpro && { echo "already installed"; exit 0; }

kpkg=$(pacman -Qqo "/usr/lib/modules/$(uname -r)/vmlinuz" 2>/dev/null) ||
  { echo "the running kernel $(uname -r) is no longer installed (updated without a reboot): reboot first" >&2; exit 1; }
pacman -S --needed --noconfirm base-devel dkms git wget patch "${kpkg}-headers"
# DKMS links to the source folder, so it must stay (a temporary one leaves it "broken").
src=/usr/local/src/snd_hda_macbookpro
for repo in https://github.com/davidjo/snd_hda_macbookpro.git https://github.com/egorenar/snd_hda_macbookpro.git; do
  rm -rf "$src"
  git clone --depth 1 "$repo" "$src"
  if (cd "$src" && sh ./install.cirrus.driver.sh -i); then echo "Installed from $repo. Reboot."; exit 0; fi
  echo "Build from $repo failed, trying the next." >&2
done
echo "The sound driver did not build." >&2; exit 1
