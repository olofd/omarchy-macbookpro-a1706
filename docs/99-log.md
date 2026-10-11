# The trail: what was tried, in order

This is the working log of one install (Omarchy 4.0.4 on a MacBookPro13,2, kernel 7.2.5-3-omarchy, October
2026), kept so that nobody repeats the dead ends. Each line is something that was actually run.

## Install
- ISO written with Rufus in ISO mode (NTFS only offered): not bootable on the Mac. balenaEtcher (raw): booted.
- Installer failed with exit 126 / "Input/output error" after choosing the disk; reflashing and a retry fixed it.
- The full-disk install erased `EFI/APPLE`, so the T1 came up in recovery mode (`05ac:1281`).

## Sound
- `aplay -l`: no sound cards for the unprivileged user (group `audio` missing), card present as root; silent speakers. (The group is not needed with PipeWire; the silence was the in-kernel CS8409 driver not starting the speaker amplifiers, chapter 2.)
- davidjo/snd_hda_macbookpro via DKMS from a temporary clone: `dkms status` said "broken"; fixed by keeping
  the source in `/usr/local/src`. Worked after a reboot.

## Touch Bar
- Hardware layer showed `touchbar: ready` while the bar stayed black: the user service
  `t1-touchbar.service` was never enabled in the login session. Enabling it fixed it.
- t1-revive: 4 min 28 s. Needs mains power (it refused on battery) and a patched libimobiledevice stack it builds itself.
- Volume/mute/media/brightness: Omarchy provider script from the t1-revive repository.

## Wi-Fi
- No NVRAM: 2.4 GHz only. Installed an NVRAM with the card's MAC (which was the placeholder).
- A first failsafe service (delete the NVRAM if no Wi-Fi interface after 90 s) fired during a suspend test and
  removed the file. **Do not add such a failsafe.**
- NVRAM `boardflags3=0xC0000303`, `ccode=SE`: connected, but joins failed for minutes after each boot.
  `boardflags3=0x00000300`, `ccode=00`: joins in ~9 s. (Values from another 13,2 owner's README.)

## Suspend
- `deep`: no wake. `s2idle`: no wake either (hang before any resume log).
- Unloading Touch Bar and Wi-Fi drivers around sleep: no change in the hang.
- `pm_test` bisect: `freezer` ok, `devices` ok, `platform` hung. Removing the two Thunderbolt controllers: pass.
- Real suspend with the Thunderbolt hook: wakes. Wi-Fi then dead (`brcmf_msgbuf_query_dcmd` timeouts).
- Unload/reload brcmfmac in the hook: made it worse (card dead until reboot).
- No hook for Wi-Fi: wake works, 5 GHz joins fail for minutes, 2.4 GHz joins at once.
- Background processes in the hook were killed with the suspend service: use `systemd-run`.

## Wi-Fi and Bluetooth after wake (fixed)
- Non-DFS channel, firmware WPA handshake, MAC randomisation off, country re-send, `wpa_supplicant` restart: no change.
- A logging build of the driver: `fw event=0 status=1 reason=0` on every failed join (the firmware answers FAIL to SET_SSID).
- PCI bus reset with the driver unloaded: the card disappeared until reboot.
- Workaround for a while: fall back to 2.4 GHz in ~13 s. On 2.4 GHz, AirPods (A2DP) stuttered.
- Driver debug log (`debug=0x1002`): after every resume the driver writes the system country into the firmware as
  rev 0; before sleep it found "country code already set". Changing the country GB -> DE: still failed after wake,
  and a cold boot with debug from module load showed the same DE rev 0 write, with 5 GHz working. Not the cause.
- Driver build dumping the ChipCommon registers at probe, firmware up, suspend and wake: at wake every register is at
  its power-on value (the chip lost power). After the firmware is up, GPIO 12-14 (out-enable 7000, out 6000),
  chipcontrol bits 0x00400090 and chipcontrol register 2 differ from a cold boot: EFI set them, the firmware never does.
- Patch saving EFI's setup at the first probe and restoring it at a resume probe: 5 GHz at the first attempt
  ~13 s after wake, Bluetooth clean. Packaged as DKMS (brcmfmac-apple-resume).

## Light and input
- Light sensor present as IIO `als`; scale 0 (covered) / ~16 (room) / 360-700 (flashlight).
- `tap-to-click` set with `["tap-to-click"] = false` did nothing; `tap_to_click = false` works.
