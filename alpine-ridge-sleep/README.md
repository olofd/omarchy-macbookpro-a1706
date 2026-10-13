# alpine-ridge-sleep: Thunderbolt and USB-C through sleep on 2016-2017 MacBook Pros

A small kernel module, `tb_ar_shim`, that keeps the **Intel Alpine Ridge Thunderbolt 3 controllers** of the
2016-2017 MacBook Pros working across deep sleep (S3). Without it, a sleep can leave them dead: the USB-C ports
are gone after the wake until a reboot (charging still works), and the wake itself stalls for up to two
minutes. It started as **Andrew Clunis' module** from
[orospakr/linux-apple-alpine-ridge-suspend](https://github.com/orospakr/linux-apple-alpine-ridge-suspend)
(v1.0.0, GPL-2.0, validated there on a MacBookPro14,1) and was extended here, on a MacBookPro13,2, with the
power handling macOS does.

## What breaks

Two separate problems, both on every 2016-2017 model with Alpine Ridge:

1. **The bridges' configuration is lost** (found by Andrew Clunis). Suspend runs children before parents: the
   Thunderbolt driver's suspend step (`tb_lc_set_sleep()`) puts the controller to sleep before the PCI core
   reaches the controller's bridges and saves their configuration. They read all ones by then (`Unable to
   change power state from D0 to D3hot, device inaccessible`), the core saves that and restores garbage after
   the wake.
2. **The chips lose power the wrong way.** In S3 the firmware cuts the controllers' power late in its own
   sleep entry. A wake within a few seconds of that (the lid closed and opened at once, or one of the
   self-wakes these Macs have) leaves the chips unpowered and stuck: after the wake they answer nothing, and
   only a minute or more without power revives them. macOS never lets this happen: it powers the controllers
   down itself, through Apple's ACPI methods, before it sleeps. So does mainline Linux for the older Cactus
   Ridge Macs (`quirk_apple_poweroff_thunderbolt`), but not for Alpine Ridge.

What it looked like here, after a 5-second sleep:

```text
pcieport 0000:03:00.0: Unable to change power state from D3cold to D0, device inaccessible
thunderbolt 0000:05:00.0: not ready 1023ms after resume; giving up
xhci_hcd 0000:06:00.0: not ready 4095ms after resume; waiting
tb_cfg_read: -108
```

Problem 1 is why the guide's sleep hook used to remove the controllers before every sleep and rescan after it.
That workaround could still be hit by problem 2 (dead until a reboot, see [docs/99-log.md](../docs/99-log.md)).

## What the module does

It hooks each on-board controller's upstream bridge (`8086:1578`; `03:00.0` and `79:00.0` on a MacBookPro13,2,
which has two controllers) through a PM domain:

The same three steps run for a hibernation (`poweroff_late`, `poweroff_noirq`, `restore_noirq`):

- **`suspend_late`**, before any device's `suspend_noirq`: save the configuration of the bridge and every device
  below it, while the chip still answers (Andrew Clunis' fix for problem 1).
- **`suspend_noirq`**, once everything below the bridge has suspended, and only for a firmware sleep (S3): cut the
  chip's power with Apple's method `NHI0.SXFP(0)` (the USB side first, then the Thunderbolt side), as macOS and
  the mainline Cactus Ridge quirk do.
- **`resume_noirq`**, first thing after the wake: power on with the root port's `UGIO` (Apple's method that
  releases the power lines; the firmware has usually done it already, ~1 ms), and only if the chip does not
  answer within a second, Apple's full power-up `UPSB._PS0` (link retrain, ~8 s). Then restore the saved
  configuration, parents before children.
- If the chip still does not answer, it **marks the tree gone** at once (as the PCI core does for a surprise
  removal), so the wake does not wait a minute for each device.
- A controller that is removed and rescanned comes back as a new device: the module attaches itself to it again
  before a driver binds.

It loads by PCI ID and only acts on on-board controllers, recognised by Apple's ACPI methods under the bridge
(`DSB0.NHI0.SXFP`). Anywhere else it refuses to load. It logs each step:

```text
pcieport 0000:03:00.0: tb_ar_shim: suspend_late: saved config of 7 devices
pcieport 0000:03:00.0: tb_ar_shim: power cut for the sleep (SXFP)
pcieport 0000:03:00.0: tb_ar_shim: power restored (UGIO) in 1 ms
pcieport 0000:03:00.0: tb_ar_shim: resume_noirq done in 2944 us (subtree budget left 200 ms)
```

## Tested

MacBookPro13,2, kernel 7.2.5-3-omarchy, deep sleep, Thunderbolt left in (no removal):

| Test | Without the module | Configuration save only (v1.0.0 + both controllers) | This module |
| --- | --- | --- | --- |
| lid sleep, 1-2 min | dead (`device inaccessible`, `-108`, ~2 min resume) | back | back, no self-wake |
| 5-second sleep (`rtcwake -m mem -s 5`) | dead | **dead**, ~2 min resume | back, resume step ~3 ms |
| series of 8 RTC sleeps (3, 5, 10, 30 s, twice), all with self-wakes after ~6-10 s | | | 8/8 back |
| hibernation (`systemctl hibernate`) | | | back, restore step ~2 ms; Wi-Fi up too |

The self-wakes come from the Thunderbolt root ports (PCIe PME, as on a MacBookPro14,2 in
[omacom/omarchy#12194](https://github.com/omacom/omarchy/issues/12194)); the sleep hook disarms root-port wake
before every sleep, and the module copes with them anyway.

Not tested yet: s2idle, long sleeps with the module, and a device on USB-C during the sleep. Andrew Clunis' newer in-kernel version
([upstream/](https://github.com/orospakr/linux-apple-alpine-ridge-suspend/tree/main/upstream)) also leaves alone
devices whose drivers saved their own state (devices tunneled through Thunderbolt) and the xHCI; that matters
with a device attached and comes next.

## Install

```sh
sudo sh scripts/install-thunderbolt-sleep.sh          # DKMS, loads it at once; no reboot needed
sudo sh scripts/install-thunderbolt-sleep.sh remove
```

`setup.sh` runs it in the sleep step. With the module loaded, the sleep hook keeps Thunderbolt in through every
sleep, hibernation included (`journalctl -t mac-sleep` shows `Thunderbolt stays in (tb_ar_shim loaded)`); without
it, it removes the controllers before the sleep and rescans after.

## Files

| File | What it is |
| --- | --- |
| [`tb_ar_shim.c`](tb_ar_shim.c) | the module (original by Andrew Clunis; every controller, Apple's power-off and power-up, gone-marking, re-attach) |
| [`Makefile`](Makefile), [`dkms.conf`](dkms.conf) | the DKMS package `tb-ar-shim-a1706` |
| [`LICENSE`](LICENSE) | GPL-2.0, as the original |
