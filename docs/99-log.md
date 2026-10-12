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

- Mic "too quiet": first measurements were wrong twice. With AirPods connected they were the default mic
  (silence in A2DP); then every recording's first 0.6 s held a start-up thump near 0 dBFS. Speech after it:
  peaks ~-22 dBFS. The driver writes the mic gain 0x27 (-12 dB) at every capture start, bypassing the mixer
  (+12 dB shown). Patch: gain from the mixer's cached value. Tone test, old vs new (63 %): -52.8 vs -41.8 dBFS.
- `dkms install --force` only reinstalls the module built before: a patched source needs `dkms build --force`.
- Thump at every recording start: only after the mic was powered down (a recording within PipeWire's suspend
  delay is clean); a DC step that clips 0.1 s and drains over ~0.5 s. Muting the input amp until 0.54 s showed no
  step at the unmute, so the step is before the amp: second patch keeps it muted 500 ms after a capture start.

## Touch Bar
- Hardware layer showed `touchbar: ready` while the bar stayed black: the user service
  `t1-touchbar.service` was never enabled in the login session. Enabling it fixed it.
- t1-revive: 4 min 28 s. Needs mains power (it refused on battery) and a patched libimobiledevice stack it builds itself.
- Volume/mute/media/brightness: Omarchy provider script from the t1-revive repository.

- Renderer (t1bridge 0.1.12) idle: main thread ~196 wakeups/s (a 5 ms poll of the hardware socket); service
  ~41 ms CPU/s, nearly all the provider's once-a-second status (five programs). poll(2) with a wake socket pair
  plus an event-fed provider: 1 wakeup/s, 4 ms CPU/s. Volume, brightness and keyboard-light sliders added.

## Wi-Fi
- No NVRAM: 2.4 GHz only. Installed an NVRAM with the card's MAC (which was the placeholder).
- A first failsafe service (delete the NVRAM if no Wi-Fi interface after 90 s) fired during a suspend test and
  removed the file. **Do not add such a failsafe.**
- NVRAM `boardflags3=0xC0000303`, `ccode=SE`: connected, but joins failed for minutes after each boot.
  `boardflags3=0x00000300`, `ccode=00`: joins in ~9 s. (Values from another 13,2 owner's README.)
- Final NVRAM default: `ccode=X3`, `regrev=15` (Broadcom's multi-country code, with the system's country applied on
  top), and a random locally administered MAC (02:...) instead of Broadcom's placeholder, which every such Mac shares.

## Suspend
- `deep`: no wake. `s2idle`: no wake either (hang before any resume log).
- Unloading Touch Bar and Wi-Fi drivers around sleep: no change in the hang.
- `pm_test` bisect: `freezer` ok, `devices` ok, `platform` hung. Removing the two Thunderbolt controllers: pass.
- Real suspend with the Thunderbolt hook: wakes. Wi-Fi then dead (`brcmf_msgbuf_query_dcmd` timeouts).
- Unload/reload brcmfmac in the hook: made it worse (card dead until reboot).
- No hook for Wi-Fi: wake works, 5 GHz joins fail for minutes, 2.4 GHz joins at once.
- Background processes in the hook were killed with the suspend service: use `systemd-run`.
- `deep` again, with the Thunderbolt hook: `pm_test` platform and core pass, real S3 wakes. Wi-Fi back at the first
  check. The Touch Bar and Touch ID stay dark (`t1bridge status` all ready); the ACPI call `ASOC.SOCW(1)` through
  acpi_call (t1bridge issue #18) brings them back in ~90 ms. Now in the hook.
- Battery, unplugged, lid closed: deep 216 mAh in 6.5 h (33 mA, 0.9 %/h); s2idle 82 % to empty in under 10 h
  (over 300 mA; no low-power idle state on this Mac). Deep is the default since.
- Typing after a wake was ~11 s late: the Thunderbolt rescan (~5 s per controller) ran inside the hook, and systemd
  keeps the desktop frozen until all hooks end. Rescan detached: the desktop thaws ~0.1 s after the wake.
- Touch Bar volume/brightness popups stopped after every wake (the renderer stops calling its desktop provider);
  restarting `t1-touchbar.service` brings them back. A restart from inside the hook never ran (the user's
  services are frozen then): it runs from a timer 10 s after the wake.

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

## Wi-Fi after hibernation (fixed)
- Stock driver: after the restore "Firmware has halted or crashed", a TRAP dump, then an oops in
  `brcmf_pcie_setup` (write through an unmapped address) racing the crash reset. Wi-Fi gone until reboot.
- `.restore` always re-probing, plus `.thaw`: no oops, but `brcmf_chip_recognition: MMIO read failed: 0xffffffff`.
- Interrupt thread skipping mailbox and console while the card is down: the false firmware crash is gone, the
  re-probe still reads all ones.
- ACPI: `_PS0`/`_PS3` of the root port RP12 (`APPU`/`APPD`) do nothing during hibernation (`_TTS(4)` sets the
  sleep type first). Not the cause.
- Logging build: at the restore the card's ID, BARs, memory decoding and link are as before; PCI status
  Signaled Target Abort; the BAR0 window moved from `0x18003000` to `0x18001000` (Apple's EFI used the chip).
  Still all ones after 335 ms. A PERST# pulse through RP12's ACPI method `DRST`: chip answers, re-probe, firmware
  up, 5 GHz. No power cycle (`DPWR`) needed. Verified again with the final patch.

## Power
- Frame buffer compression was off ("VT-d enabled": Skylake workaround while the graphics are behind the IOMMU).
  `intel_iommu=igfx_off`: FBC enabled. The saving is too small to measure next to normal app load.
- ACPI interrupt (GPE07, the EC) at ~83/s, on battery as well as on the charger (kernel bug 198169 says AC
  only). EC trace: SMBus alarms (query 0x10) about 3.5/s from address 0x0a, the smart battery manager that the
  kernel ignores on Macs; each costs ~9 EC transactions. It is ~1.3 % of all interrupts (6,300/s, mostly the
  timer for busy apps), so not worth a kernel patch.

## Light and input
- Light sensor present as IIO `als`; scale 0 (covered) / ~16 (room) / 360-700 (flashlight).
- `tap-to-click` set with `["tap-to-click"] = false` did nothing; `tap_to_click = false` works.
- Auto-brightness ignored "brightness up" after the screen was turned down in a lit room and the lights went off:
  the manual offset was unbounded. Clamped to the screen's range (the same fix for the keyboard light).
