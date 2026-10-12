# brcmfmac-apple-resume: Wi-Fi and Bluetooth after sleep on BCM43602 Macs

A fix for the Linux `brcmfmac` Wi-Fi driver on MacBook Pros with a **Broadcom BCM43602**: after waking from
sleep, 5 GHz Wi-Fi no longer connects (2.4 GHz still does), and Bluetooth audio stutters while Wi-Fi is on
2.4 GHz. After a cold boot both work. This patch makes them work after sleep too, and DKMS rebuilds it
automatically for every new kernel.

## Is this for you?

- **Hardware:** a Mac with a BCM43602 Wi-Fi card: `lspci -nn | grep 14e4:43ba`. That is the MacBook Pro 2016
  and 2017, 13" and 15" (MacBookPro13,1, 13,2, 13,3, 14,1, 14,2, 14,3). **Tested on a MacBookPro13,2**; please
  report the others.
- **Symptom:** after a resume the log shows failed joins:

  ```text
  wpa_supplicant: wlp2s0: CTRL-EVENT-ASSOC-REJECT bssid=00:00:00:00:00:00 status_code=16
  ```

  while 2.4 GHz networks connect. On 2.4 GHz, Bluetooth audio (e.g. AirPods) stutters.
- **Sleep:** your Mac must already suspend and resume (deep or s2idle). On the 2016/2017 Touch Bar models that needs
  the Thunderbolt hook from [chapter 5](../docs/05-sleep.md) of the guide.

## Install

```sh
git clone https://github.com/olofd/omarchy-macbookpro-a1706
sudo sh omarchy-macbookpro-a1706/scripts/install-wifi-sleep-fix.sh
sudo reboot
```

Tested on Omarchy (Arch); it should work on Arch, Debian/Ubuntu, Fedora and openSUSE too: the script installs
`dkms`, `git` and `patch` with your package manager. You need the **headers of your running kernel** (Omarchy: `linux-omarchy-headers`;
Arch: `linux-headers`; Debian/Ubuntu: `linux-headers-$(uname -r)`; Fedora: `kernel-devel`) and internet once per
kernel version, because the driver source comes from the stable kernel tree (its GitHub mirror, or git.kernel.org). The first build takes a few minutes.

The script never unloads the running driver (on this card that leaves Wi-Fi dead until a reboot): the patched
driver is used from the next boot.

## Check that it works

```sh
modinfo -F parm brcmfmac | grep mac_efi_restore     # the patched driver is installed
# close the lid for a minute, open it, then:
journalctl -k -b | grep "restored the chip setup"   # the fix ran at the resume
iw dev wlp2s0 link                                  # connected to your 5 GHz network again
```

## Undo

```sh
sudo sh omarchy-macbookpro-a1706/scripts/install-wifi-sleep-fix.sh remove
sudo reboot
```

To keep it installed but switched off: `options brcmfmac mac_efi_restore=0` in a file in `/etc/modprobe.d/`,
then reboot.

## What the patch does

During sleep (deep or s2idle) the BCM43602 **loses power**. At the resume the driver (`brcmf_pcie_pm_leave_D3()` in `pcie.c`)
finds the firmware gone (`intmask` reads 0), re-probes the card and downloads the firmware again, onto a chip at
its power-on defaults. At a cold boot that is not what the firmware gets: **Apple's EFI has already set part of
the chip up** before Linux runs, and the 2015 firmware (7.35.177.61, the only one there is) relies on it without
ever doing it itself.

Registers of the chip's ChipCommon core once the firmware is running, MacBookPro13,2:

| Register | After a cold boot (works) | After a resume (fails) |
| --- | --- | --- |
| `gpioouten` | `0x00007007` | `0x00000007`: GPIO 12, 13, 14 are not outputs |
| `gpioout` | `0x00006006` | `0x00000006`: GPIO 13, 14 are not driven high |
| `chipcontrol` | `0x01400090` | `0x01000000` |
| chipcontrol register 2 (indirect) | `0x903aaa2a` | `0xd032aa2a` |

GPIO 12-14 were already set this way before the driver touched the chip at boot: EFI did it, not the firmware
(which only sets GPIO 0-2). On Mac Wi-Fi cards such pins drive the external front end: the 5 GHz amplifier and
the antenna switch that Wi-Fi shares with Bluetooth. Without them, 5 GHz joins fail (the firmware answers
`SET_SSID` with status 1, which the driver reports as 16) and Bluetooth loses its coexistence with Wi-Fi.

The patch adds one function to `pcie.c`, called around the watchdog reset in `brcmf_pcie_buscore_reset()`:

1. At the **first probe** of an Apple BCM43602 after the module loads (that is, at boot, as EFI left the chip),
   before the driver's own watchdog reset (which keeps these registers), it **saves** `chipcontrol`,
   `gpioout`, `gpioouten`, `gpiocontrol`, `gpiopullup`, `gpiopulldown` and indirect chipcontrol registers 0-4.
2. At a **later probe** (a resume) that finds the saved output GPIOs no longer enabled, which means the chip lost
   power, it **writes them back** after the reset and before the firmware download. The resumed chip then starts
   like a cold-booted one.

It only acts on cards that are a BCM43602 **and** have Apple's PCI subsystem vendor (`106b`); nothing changes at
a normal boot, on other cards, or when the chip kept its power. It logs one line when it restores. The module
parameter `mac_efi_restore=0` turns it off. The kernel's `checkpatch.pl` finds nothing to fix, apart from the
missing `Signed-off-by:` line, which is added when the patch is sent upstream.

How it was found (a driver build that dumped these registers at boot, sleep and wake, and the theories that
were ruled out on the way) is in [chapter 6](../docs/06-wifi-after-sleep.md) of the guide.

## Files

| File | What it is |
| --- | --- |
| [`0001-brcmfmac-pcie-restore-Apple-EFI-chip-setup-after-resume.patch`](0001-brcmfmac-pcie-restore-Apple-EFI-chip-setup-after-resume.patch) | the change to `drivers/net/wireless/broadcom/brcm80211/brcmfmac/pcie.c`, with a full description |
| [`dkms.conf`](dkms.conf) | the DKMS package `brcmfmac-apple-resume`, version 1.0 |
| [`dkms-build.sh`](dkms-build.sh) | what DKMS runs for each kernel: fetch the `brcm80211` folder of the kernel's upstream release (about 15 MB, from the stable tree's GitHub mirror, or git.kernel.org), cache it in `/var/cache/brcmfmac-apple-resume`, apply the patch with no fuzz, build `brcmfmac.ko` with the kernel's own configuration (the kernel's own vendor modules `brcmfmac-wcc/-cyw/-bca` keep working with it: the patch changes no exported symbol) |

## Build it by hand (without DKMS)

```sh
sh dkms-build.sh "$(uname -r)"                          # as any user; the module is in build/brcm80211/brcmfmac/
sudo install -Dm644 build/brcm80211/brcmfmac/brcmfmac.ko /lib/modules/$(uname -r)/updates/brcmfmac.ko
sudo depmod -a && sudo reboot
```

The source is the upstream release your kernel headers report (`make kernelversion`: `7.2.5-3-omarchy` builds from
`v7.2.5`). If your distribution patches brcmfmac itself, those changes are not in this build. If the patch stops applying to a
future kernel, please open an issue.

## Status upstream

Not sent to the kernel yet. The plan is to submit it to the `linux-wireless` list once it has been used for a
while; reports from other BCM43602 Macs (working or not, with your model and `journalctl -k -b | grep brcmfmac`
after a resume) help a lot. Please open an issue.

## Licence

The patch changes `pcie.c`, which is under the **ISC licence** (`SPDX-License-Identifier: ISC`), and is under
the same licence. `dkms.conf` and `dkms-build.sh` are MIT, like the rest of the repository.
