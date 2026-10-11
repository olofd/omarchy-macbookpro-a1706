# 3. 5 GHz Wi-Fi (Broadcom BCM43602)

**Symptom:** only 2.4 GHz networks appear, the signal is weak, and `iw phy | grep Band` lists only `Band 1`.

**Cause:** `linux-firmware` ships the firmware for the BCM43602 but no **NVRAM** (board calibration:
antenna, power, band layout). Without it the driver brings the radio up with generic defaults:
2.4 GHz only and weak. The firmware's own regulatory tables are compiled in, so the "no clm_blob available"
message in the log is harmless. Do not create a CLM blob.

**Fix:** install an NVRAM file for this exact board:

```sh
sudo sh scripts/install-wifi.sh           # the tested values; your real country goes in /etc/conf.d/wireless-regdom
sudo reboot
```

The driver reads the file only at load time, and a live reload (`modprobe -r brcmfmac`) leaves the card dead
until the next boot (see [the sleep notes](06-wifi-after-sleep.md)), so a reboot is required.

**Check:**

```sh
iw phy | grep -c 5180        # more than 0
iw dev wlp2s0 link           # freq 5xxx once connected
```

## Which NVRAM values

The file in `files/brcmfmac43602-pcie.txt` is a community NVRAM for this chip
(`devid 0x43ba`, `boardtype 0x61b`) from [t1-revive](https://github.com/niconistal/t1-revive), with
`boardflags3` from [MikeRatcliffe's gist](https://gist.github.com/MikeRatcliffe/9614c16a8ea09731a9d5e91685bd8c80).
The installer sets three values in it:

| Setting | Value used | Notes |
| --- | --- | --- |
| `boardflags3` | `0x00000300` | `0xC0000303` gave join failures for minutes after boot |
| `ccode`, `regrev` | `X3`, `15` | Broadcom's multi-country code, what the tested Mac runs (`sudo sh scripts/install-wifi.sh SE` sets a country with revision 0 instead). `SE` with the old `boardflags3` was part of the failing pair. The system's Wi-Fi country ([10-desktop-extras.md](10-desktop-extras.md), "Check the time zone and Wi-Fi country") is applied on top by the driver |
| `macaddr` | a stable address | Without NVRAM the card reports Broadcom's placeholder (`00:90:4c:...`), likely the same on every such Mac; the script makes a random locally administered one (`02:...`) once and keeps it. The real Apple MAC is only in macOS |

Tested alternatives are in [99-log.md](99-log.md).

## Settings that do not matter here

- **`brcmfmac feature_disable=0x82000`.** Omarchy sets this on Apple Macs to run the WPA handshake in
  software (a workaround for WPA2/WPA3 transition networks). Turning it off made no difference to the
  post-wake failures ([chapter 6](06-wifi-after-sleep.md)).
- **NetworkManager MAC randomisation.** Turned off in `files/nm-no-mac-random.conf`; harmless, and the log
  shows the card switches MAC during scans, but it was not the cause of any failure.
- **DFS channels.** Both 5 GHz networks on the test router were on DFS channels (60, 112). Moving them to
  channel 36 changed nothing about the post-wake failures. Fixed channels are still worth it for stability.

## If the card does not come up after the reboot

The NVRAM file (`/usr/lib/firmware/updates/brcm/brcmfmac43602-pcie.txt`) is the only change that affects the
card; the script also turns off NetworkManager's MAC randomisation. Undo both and reboot:

```sh
sudo sh scripts/install-wifi.sh remove && sudo reboot
```

## Prefer 5 GHz

If your 2.4 and 5 GHz networks have different names, give the 5 GHz connection a higher priority:

```sh
nmcli connection modify "MyNetwork_5G" connection.autoconnect-priority 10
```
