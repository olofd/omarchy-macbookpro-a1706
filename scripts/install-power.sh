#!/bin/sh
# Power: let the graphics use frame buffer compression (FBC). On Skylake the i915 driver turns FBC off while the
# graphics chip is behind the IOMMU (intel_fbc.c, WaFbcTurnOffFbcWhenHyperVisorIsUsed: "VT-d enabled"), and
# this kernel puts it there ("VT-d active for gfx access" in the boot log). The boot option intel_iommu=igfx_off
# takes only the graphics chip out of the IOMMU: Thunderbolt and the other devices keep their DMA protection.
#   sudo sh install-power.sh            add the boot option (Omarchy/Limine), then reboot
#   sudo sh install-power.sh remove     take it out again, then reboot
# Check after the reboot: sudo cat /sys/kernel/debug/dri/*/i915_fbc_status   ("FBC enabled")
set -eu
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo sh $0" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
CONF=/etc/limine-entry-tool.d/50-a1706-power.conf
command -v limine-update >/dev/null ||
  { echo "this is for Omarchy's Limine boot setup (no limine-update): add intel_iommu=igfx_off yourself"
    exit 0; }

case "${1:-}" in remove|--remove)
  [ -f "$CONF" ] || { echo "Power: nothing to remove."; exit 0; }
  rm -f "$CONF"; limine-update
  needs_reboot "the boot options"; exit 0 ;;
esac

put_text "$CONF" 644 <<'EOF'
# omarchy-macbookpro-a1706 scripts/install-power.sh: frame buffer compression on Skylake (see the script).
KERNEL_CMDLINE[default]+=" intel_iommu=igfx_off"
EOF
if [ "$CHANGED" = 0 ] && grep -qw 'intel_iommu=igfx_off' /proc/cmdline; then
  echo "Power: already up to date."; exit 0
fi
[ "$CHANGED" = 0 ] || limine-update
needs_reboot "the boot options (frame buffer compression)"
