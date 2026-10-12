# 6. Wi-Fi and Bluetooth after sleep

**State: fixed** with a patched `brcmfmac` driver, installed as a DKMS module that is rebuilt for every new
kernel. Without it, after every resume the BCM43602 fails to join 5 GHz networks for minutes (2.4 GHz works),
and on 2.4 GHz Bluetooth audio (AirPods, A2DP) stutters. After a cold boot both work.

```sh
sudo sh scripts/install-wifi-sleep-fix.sh        # a few minutes the first time; then reboot
```

It needs the headers of the running kernel (the sound step, chapter 2, installs them) and internet once per
kernel version: the driver source comes from the stable kernel tree (its GitHub mirror, or git.kernel.org). It also works on other distributions with DKMS; see
[`brcmfmac-apple-resume/README.md`](../brcmfmac-apple-resume/README.md) for the details of the patch, a manual
build and how to report results. To undo: `sudo sh scripts/install-wifi-sleep-fix.sh
remove`, then reboot.

## Check it

```sh
modinfo -F parm brcmfmac | grep mac_efi_restore        # the patched driver is the one installed
# close the lid for a minute, open it, then:
journalctl -k -b | grep "restored the chip setup"       # the fix ran at the resume
iw dev wlp2s0 link                                      # back on your 5 GHz network
```

On the MacBookPro13,2 it was tested on, 5 GHz joined at the first attempt about 13 seconds after opening the
lid, and AirPods played cleanly again.

## The cause

During sleep (s2idle and deep alike) the Wi-Fi chip **loses power**. At the resume the driver (`brcmf_pcie_pm_leave_D3()`) sees that
the firmware is gone (`intmask` reads 0), re-probes the card and downloads the firmware again. That re-probe is
meant to be a cold start, and it nearly is, with one difference: at a real cold boot **Apple's EFI has already
set part of the chip up** before Linux starts, and the 2015 firmware relies on that without ever doing it
itself. After a resume nobody does it.

Registers of the chip's ChipCommon core, read once the firmware is up:

| Register | After a cold boot (works) | After a resume (fails) | Missing after the resume |
| --- | --- | --- | --- |
| `gpioouten` | `00007007` | `00000007` | GPIO 12, 13 and 14 never become outputs |
| `gpioout` | `00006006` | `00000006` | GPIO 13 and 14 never driven high |
| `chipcontrol` | `01400090` | `01000000` | bits `0x00400090` |
| chipcontrol register 2 | `903aaa2a` | `d032aa2a` | two bits |

GPIO 12-14 were already `6000`/`7000` before the driver touched the chip at boot: EFI set them, not the
firmware (which sets GPIO 0-2). Pins like these drive the external front end on Mac Wi-Fi cards: the 5 GHz
amplifier and the antenna switch that Wi-Fi shares with Bluetooth. Without them 5 GHz joins fail and Bluetooth
loses its coexistence with Wi-Fi, which is exactly what you see.

## The fix

[`brcmfmac-apple-resume/0001-brcmfmac-pcie-restore-Apple-EFI-chip-setup-after-resume.patch`](../brcmfmac-apple-resume/0001-brcmfmac-pcie-restore-Apple-EFI-chip-setup-after-resume.patch)
(one function in `pcie.c`, about 90 lines; the kernel's `checkpatch.pl` has nothing to fix apart from the
`Signed-off-by:` line that is added when it goes upstream):

- At the **first probe** of a BCM43602 with Apple's PCI subsystem vendor (`106b`) after the module loads, before
  the driver's own watchdog reset (which keeps EFI's values), it saves `chipcontrol`, the GPIO registers and the
  indirect chipcontrol registers.
- At a **later probe** that finds the saved output GPIOs no longer enabled (the chip lost power), it writes them
  back after the reset and before the firmware download, so the resumed chip starts like a cold-booted one.
- Nothing changes at a normal boot, on other cards, or when the chip kept its power. The module parameter
  `brcmfmac.mac_efi_restore=0` turns it off.

`scripts/install-wifi-sleep-fix.sh` installs it as the DKMS package
[`brcmfmac-apple-resume`](../brcmfmac-apple-resume/): for each kernel, `dkms-build.sh` fetches the `brcmfmac`
of the upstream release that kernel is based on (v7.2.5 for 7.2.5-3-omarchy; about 15 MB from the stable tree's
GitHub mirror, or git.kernel.org), caches it in `/var/cache/brcmfmac-apple-resume`, applies the patch and builds
it with the kernel's own configuration. It is the same approach as the sound driver
(chapter 2).

## After hibernation

Restoring a hibernation image (chapter 5) is a different failure: the card does not come back at all, until a
reboot. The kernel log shows `brcmf_chip_recognition: MMIO read failed: 0xffffffff` and `probe after resume
failed, err=-19` (the stock driver first reports a firmware crash, and can oops).

A driver build that logged the card's PCI state at every step showed why. At the restore the card is on the
bus as before (its ID, BARs, memory decoding and the link are all unchanged), but its status register shows
**Signaled Target Abort**: the chip rejects every read of its registers, and waiting does not help. Its
register window had moved too, so Apple's EFI had used the chip in the boot that loaded the image, and left it
in a state that a cold boot or an S3 resume never shows. The driver then made it worse: it read the all-ones
mailbox as a firmware crash, and that crash handling raced the re-probe.

The Mac's ACPI table has the method macOS resets the card with: `DRST` on the card's root port (`RP12`), which
drives its reset line (PERST#). One pulse brings the chip back at its power-on defaults, and it then probes as
at a cold boot. The second patch,
[`0002-brcmfmac-pcie-survive-restoring-from-hibernation.patch`](../brcmfmac-apple-resume/0002-brcmfmac-pcie-survive-restoring-from-hibernation.patch):

- At a restore, if the chip reads all ones and the root port has `DRST`, it pulses it, waits for the card and
  puts its PCI configuration back. It logs `chip did not answer after the restore: reset it (ACPI DRST)`.
- A restore always re-probes the card (the firmware is never still running then), and `.thaw` (after the image
  is written, or when hibernating fails) wakes the card as after a suspend, where it used to stay in D3.
- While the card is down, its interrupt handler no longer reads the mailbox and console, so a chip answering all
  ones is not taken for a crashed firmware.

With it, Wi-Fi is back on 5 GHz right after the restore. `install-wifi-sleep-fix.sh` installs both patches.

## How it was found

1. A driver that logs the firmware's real answer (the stock driver reports every failed join as status 16 and an
   all-zero BSSID) showed `fw event=0 status=1`: the **firmware** refuses the join (`SET_SSID` → `FAIL`).
2. The driver's debug log (`echo 0x1002 > /sys/module/brcmfmac/parameters/debug`) showed that after every
   resume it writes the system's Wi-Fi country into the firmware as revision 0 ("using ISO3166 code and 0
   rev"), where before the sleep it found "country code already set". It looked like the cause. It was not:
   changing the country from `GB` to `DE` failed the same way, and a cold boot writes the same `DE` rev 0 and
   works.
3. So the difference had to be in the chip. A driver build that dumps the ChipCommon power-management and
   control registers at boot, at sleep and at wake gave the table above. The chip is at its power-on values at
   wake, and the EFI setup is the only lasting difference once the firmware runs.

## What did not help (before the fix)

| Attempt | Result |
| --- | --- |
| Move the router's 5 GHz channels to non-DFS (36) | no change after wake |
| `feature_disable=0x82000` off (firmware does the WPA handshake) | no change |
| NetworkManager MAC randomisation off | no change |
| NVRAM `boardflags3 0x300`, `ccode 00` (vs `0xC0000303`, `SE`) | much better **at boot** (joins in about 9 s instead of minutes); no change after wake |
| Re-send the regulatory country after wake (`iw reg set ...`) | no change; it only adds country changes while the card joins |
| Another system country (`DE` instead of `GB`) | no change after wake |
| Restart `wpa_supplicant` after wake | no change; once left NetworkManager's interface unusable until reboot |
| Unload and reload `brcmfmac` around sleep | **worse**: the card stays dead until a reboot |
| PCI bus reset with the driver unloaded, then reload | **worse**: the card vanished, reboot needed |
| A short sleep (12 s) | 5 GHz usually came back (the chip had not lost power yet); longer sleeps fail |

## The fallback that stays installed

`scripts/wifi-recover.sh` (from the sleep step, chapter 5) still runs after every wake: it writes a diagnostic
log to `/var/log/wake-diag/`, and if Wi-Fi is not back about 20 seconds after the wake it brings up the 2.4 GHz
connection you gave the sleep step (if any). With the fix it finds Wi-Fi connected at its first check (the log
says `RESULT: connected after check 1`) and does nothing.
