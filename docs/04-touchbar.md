# 4. Touch Bar, camera and ambient light sensor (the T1 chip)

**Symptom:** the Touch Bar is dark, the FaceTime camera and Touch ID do not exist, `lsusb` shows
`05ac:1281 Apple Mobile Device [Recovery Mode]` instead of `05ac:8600 Apple iBridge`.

**Cause:** the T1 (Apple's "iBridge" chip) runs its own OS and **has no firmware in ROM**. macOS writes the
firmware to the EFI partition, `EFI/APPLE/EMBEDDEDOS/` (`combined.memboot`, `FDRData`, `version.plist`,
about 30 MB), and Apple's boot firmware loads it into the chip at every power-on. A Linux install that
formats the whole disk deletes that folder, and the T1 falls back to recovery mode. No driver can help until
the firmware is back. The files are signed for this specific machine, so they cannot be copied from
another Mac.

## Two ways to get it back

1. **Boot macOS once** (Internet Recovery works for some; a full install to an external SSD is more reliable),
   reach the desktop, and shut down cleanly. This rewrites the folder.
2. **[t1-revive](https://github.com/niconistal/t1-revive)** rebuilds it from Linux alone: it drives Apple's
   restore protocol, lets the chip fetch its Apple-signed data from Apple's servers, boots it, and stages the
   three files on the EFI partition. It took 4.5 minutes here, no macOS involved. It needs mains power and
   network access to `gs.apple.com` and `swcdn.apple.com`, and the machine must stay awake.

Then a driver draws the Touch Bar: **[t1bridge](https://github.com/standardagents/t1bridge)**, installed from
its signed pacman repository. `scripts/install-touchbar.sh` does all of it:

```sh
sudo bash scripts/install-touchbar.sh
# log out and back in
sudo t1bridge status          # touchbar: ready
```

What the script does, step by step, so you can follow it by hand:

1. Checks you are on mains power and which USB ID the T1 has (`8600` = fine, `1281` = needs regenerating).
2. Adds the t1bridge pacman repository after **verifying the signing key's fingerprint**
   (`35B166F7 8B063B04 DE1E3D91 3E6C4216 EB03D371`).
3. Installs `t1bridge`, `t1bridge-dkms` and the build tools in one full `pacman -Syu` (never a partial upgrade).
   Omarchy blocks direct system upgrades outside `omarchy update`, so this one runs with
   `OMARCHY_ALLOW_DIRECT_PACMAN=1`; run `omarchy update` and reboot first.
4. If the T1 is in recovery mode: clones and builds t1-revive (it builds its own patched libimobiledevice
   stack in its own folder, nothing system-wide), runs its `preflight --install` and
   `regenerate --no-confirm`.
5. Creates the `t1bridge` group, enables the hardware service, adds you to the group.
6. Enables the **renderer as a user service**. This is the step that is easy to forget: the hardware layer
   can report `touchbar: ready` while the Touch Bar stays black, because the thing that draws on it runs in
   your login session (`systemctl --user enable --now t1-touchbar.service`).
7. Installs the Omarchy provider so the bar has volume, mute, media and brightness controls.

## Back up the result

```sh
sudo tar -C /boot/EFI -czf efi-apple.tgz APPLE
```

Keep it **off the machine and out of git**: it holds data unique to this Mac. To restore it:
`sudo tar -C /boot/EFI -xzf efi-apple.tgz`, then shut down and power on.

## Notes

- A **full power-off and power-on** is the reliable way to reload the firmware, and a plain reboot also works
  once the folder is staged.
- On kernel 6.19 and newer, two T2-oriented modules (`apple-ibridge-hid`, `apple-ib-touchbar`) can load by
  themselves and conflict with the older out-of-tree driver. They do not matter for t1bridge; if you use the
  older `apple-ibridge` DKMS setup instead, blacklist them.
- Touch ID needs t1bridge's fingerprint packages and a few PAM edits: see [09-touch-id.md](09-touch-id.md).
- The **ambient light sensor** appears as an IIO device (`/sys/bus/iio/devices/iio:device0`, name `als`) once
  the T1 is running. See [07-light.md](07-light.md).
