# 1. Installing Omarchy on the A1706

## The USB stick

Omarchy 4.0.x ships as a 6.2 GB hybrid ISO. Rufus's default (ISO mode) copies the files to an NTFS or FAT32
drive and adds its own boot loader; a Mac **will not boot** that. Write the image in raw mode:

- **balenaEtcher**: pick the ISO and the stick, flash. There are no options, which is what you want.
- **Rufus**: choose **GPT**, **UEFI (non-CSM)**, click Start, and when it asks, pick **DD Image mode**.
  If Rufus only offers NTFS as a file system, it is in ISO mode: use Etcher instead.

## Booting it

1. T2 models (2018+) need Secure Boot off (Cmd-R, Startup Security Utility). The A1706 is T1 and
   does not need this.
2. Insert the stick, restart, hold **Option** at power-on, pick the orange **EFI Boot** entry.
3. If the keyboard and trackpad do nothing in the installer, use a USB keyboard and mouse.

## Disk choice, and the Touch Bar

The installer's "erase the whole disk" path **formats the EFI partition**, which deletes the Touch Bar's
firmware (`EFI/APPLE/EMBEDDEDOS`). If you keep macOS, use a "free space" install. If you erase the disk, restore
your backup of the folder afterwards, or rebuild it. Nothing is lost for good: step
[04-touchbar](04-touchbar.md) rebuilds it from Linux (it asks Apple's servers for the signed data).

## Errors seen

- **`installer child exited with 126` + an "Input/output error"** right after choosing the disk: the
  installer could not read a file from the stick. Reflash the stick (raw mode, verified write), try another
  port or stick, avoid hubs. A bad write to the stick, not the Mac, is the usual cause.
- **No orange EFI Boot entry:** the stick is not a raw-written UEFI image (see above).

## After the first boot

Connect to Wi-Fi (2.4 GHz at first: see [03-wifi](03-wifi.md)), run `omarchy update`, then come back here and
run the steps in the README in order. Enable SSH if you want to do the rest from another computer
(`sudo systemctl enable --now sshd`; Omarchy's firewall (ufw) blocks it until you allow your network, e.g.
`sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp` with your own network's range). Also check the
time zone and the Wi-Fi country the installer set: see the end of [10-desktop-extras](10-desktop-extras.md).
