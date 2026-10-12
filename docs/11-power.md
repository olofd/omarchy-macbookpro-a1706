# 11. Power: graphics compression

**Symptom:** none you can see. The graphics never compress the screen image (frame buffer compression, FBC),
so every frame the display shows is read from memory in full, also while nothing on the screen changes.

**Cause:** on Skylake, the i915 driver turns FBC off while the graphics chip is behind the IOMMU (Intel's
workaround `WaFbcTurnOffFbcWhenHyperVisorIsUsed` in `intel_fbc.c`, reason "VT-d enabled"), and current kernels
put it there: the boot log says `VT-d active for gfx access`.

**Fix:** the boot option `intel_iommu=igfx_off`, which takes only the graphics chip out of the IOMMU;
Thunderbolt and the other devices keep their DMA protection. It is what every Mac without this problem
already runs with FBC on. Omarchy boots with Limine, so the script adds it as
`/etc/limine-entry-tool.d/50-a1706-power.conf` and rebuilds the boot entry:

```sh
sudo sh scripts/install-power.sh          # then reboot; `remove` takes it out again
```

**Check** after the reboot:

```sh
grep -o intel_iommu=igfx_off /proc/cmdline
sudo sh -c 'grep -H . /sys/kernel/debug/dri/*/i915_fbc_status'    # "FBC enabled", "FBC possible"
```

`Compressing: yes` shows while the picture stands still (it says no while anything on the screen moves). The
saving is small (expected to be a few tenths of a watt at idle), too small to measure
next to everyday app load on this Mac, so it is a default worth having rather than a fix you will notice.
