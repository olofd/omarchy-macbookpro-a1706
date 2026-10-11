#!/bin/sh
# Called by DKMS (dkms.conf MAKE) in its build directory: build brcmfmac for kernel $1 from that kernel's
# upstream source with the patches in this directory applied.
#
#   sh dkms-build.sh 7.2.5-3-omarchy      (also works by hand, as any user: the result is in build/)
#
# The source is the upstream release the kernel is built from, as its headers report it (`make kernelversion`:
# 7.2.5-3-omarchy -> v7.2.5, Debian's 6.1.0-26-amd64 -> v6.1.112, 6.12.0-rc3 -> v6.12-rc3). Only
# drivers/net/wireless/broadcom/brcm80211 is fetched (about 15 MB, a few seconds): from the stable tree's GitHub
# mirror, or from git.kernel.org if that fails. It is cached per version. Distribution kernels rarely patch
# brcmfmac; if yours does, its own changes are missing from this build.
set -eu
KVER=${1:?usage: sh dkms-build.sh <kernel version>}
HERE=$(cd "$(dirname "$0")" && pwd)
KSRC=/lib/modules/$KVER/build
if [ -w /var/cache ]; then CACHE=/var/cache/brcmfmac-apple-resume; else CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/brcmfmac-apple-resume; fi

[ -f "$KSRC/.config" ] || { echo "no kernel headers for $KVER ($KSRC)" >&2; exit 1; }
cfg() { sed -n "s/^$1=//p" "$KSRC/.config"; }
[ -n "$(cfg CONFIG_BRCMFMAC)" ] || { echo "kernel $KVER has no brcmfmac (CONFIG_BRCMFMAC unset)" >&2; exit 1; }

# The upstream tag: the headers' own version, or the release string when that is not available.
UP=$(make -s -C "$KSRC" kernelversion 2>/dev/null) || UP=
[ -n "$UP" ] || UP=${KVER%%-*}
case $UP in                    # tags are v6.17 and v6.12-rc3, not v6.17.0 or v6.12.0-rc3
  *-rc*) base=${UP%%-rc*}; UP=${base%.0}${UP#"$base"} ;;
  *.0) UP=${UP%.0} ;;
esac
SRC=$CACHE/v$UP/brcm80211

fetch() { # url dir
  git clone -q --depth 1 --filter=blob:none --sparse --branch "v$UP" "$1" "$2" 2>/dev/null &&
    git -C "$2" sparse-checkout set drivers/net/wireless/broadcom/brcm80211
}
if [ ! -d "$SRC" ]; then
  echo "fetching brcmfmac from Linux v$UP ..."
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  fetch https://github.com/gregkh/linux "$tmp/linux" ||
    { rm -rf "$tmp/linux"; fetch https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "$tmp/linux"; } ||
    { echo "could not fetch Linux v$UP (offline?). Run 'sudo dkms autoinstall' once online." >&2; exit 1; }
  # Fill the cache atomically: an interrupted copy must never be taken for a complete one.
  mkdir -p "$CACHE"
  rm -rf "$CACHE/v$UP.tmp.$$"
  mkdir -p "$CACHE/v$UP.tmp.$$"
  cp -a "$tmp/linux/drivers/net/wireless/broadcom/brcm80211" "$CACHE/v$UP.tmp.$$/"
  rm -rf "$CACHE/v$UP"
  mv "$CACHE/v$UP.tmp.$$" "$CACHE/v$UP"
fi

rm -rf "$HERE/build"
mkdir -p "$HERE/build"
cp -a "$SRC" "$HERE/build/"
for p in "$HERE"/*.patch; do
  echo "applying $(basename "$p")"
  # --fuzz=0: on a future kernel the change must land exactly where it belongs, or the build fails visibly.
  patch -d "$HERE/build" -p5 --forward --batch --fuzz=0 --no-backup-if-mismatch < "$p"
done

# The same options as the kernel's own brcmfmac. The parent brcm80211/Makefile normally adds -DDEBUG for
# CONFIG_BRCMDBG; building only brcmfmac/ needs it passed on, or debug.c fails to compile.
set -- CONFIG_BRCMFMAC=m CONFIG_BRCMUTIL=m
for o in BRCMFMAC_PROTO_BCDC BRCMFMAC_PROTO_MSGBUF BRCMFMAC_SDIO BRCMFMAC_USB BRCMFMAC_PCIE BRCMDBG BRCM_TRACING; do
  v=$(cfg "CONFIG_$o"); [ -n "$v" ] && set -- "$@" "CONFIG_$o=$v"
done
KCFLAGS=
[ "$(cfg CONFIG_BRCMDBG)" = y ] && KCFLAGS=-DDEBUG
make -C "$KSRC" M="$HERE/build/brcm80211/brcmfmac" KCFLAGS="$KCFLAGS" "$@" -j"$(nproc)" modules
