# Omarchy on the MacBook Pro 13" 2016/2017 with Touch Bar (A1706, T1)

Everything needed to make a **MacBookPro13,2 (A1706)** a first-class [Omarchy](https://omarchy.org) machine:
sound, Touch Bar, 5 GHz Wi-Fi that survives sleep, working sleep, Touch ID, camera, ambient light sensor with
automatic brightness, trackpad. Written from a real install (Omarchy 4.0.4, kernel 7.2.5, October 2026): every command here was run
on the machine, and every dead end that cost hours is written down too, so you can skip it.

> The same guide very likely applies to the other T1 Touch Bar models, **MacBookPro14,2** (the 2017 A1706)
> and the 15" **MacBookPro13,3 and 14,3** (A1707), whose hardware is nearly identical. They are untested here.
> The 13" models without a Touch Bar (**MacBookPro13,1 and 14,1**, A1708) have no T1 but probably share the
> sound, Wi-Fi and sleep parts.

> **Only here for Wi-Fi and Bluetooth after sleep** on a 2016/2017 MacBook Pro (BCM43602, any distribution)?
> See [`brcmfmac-apple-resume/`](brcmfmac-apple-resume/): a driver fix, installed with one command.

## What works, and how well

| Part | State | Notes |
| --- | --- | --- |
| Installer, boot, disk, keyboard, trackpad | works | The erase-disk install wipes the Touch Bar firmware: read [the install notes](docs/01-install.md) **before** you install |
| Sound (speakers) | works | Community CS8409 driver via DKMS. Microphone is quiet. [docs/02-sound.md](docs/02-sound.md) |
| 5 GHz Wi-Fi (BCM43602) | works at boot | Needs an NVRAM file. [docs/03-wifi.md](docs/03-wifi.md) |
| Touch Bar, camera, ambient light sensor | works | Needs the T1 firmware restored. [docs/04-touchbar.md](docs/04-touchbar.md) |
| Sleep (deep, S3) | works | Thunderbolt controllers removed around it, the T1 told after the wake; about 0.9 % battery per hour. [docs/05-sleep.md](docs/05-sleep.md) |
| Wi-Fi and Bluetooth after sleep | **fixed** (driver patch) | Stock brcmfmac fails 5 GHz and Bluetooth stutters after a resume; a DKMS-packaged patch fixes it. [docs/06-wifi-after-sleep.md](docs/06-wifi-after-sleep.md) |
| Automatic keyboard light and screen brightness | works | From the ambient light sensor. [docs/07-light.md](docs/07-light.md) |
| Trackpad palm trouble, scrolling, gestures | tuned | [docs/08-input.md](docs/08-input.md) |
| Touch ID | works | For sudo and Polkit prompts, with T1Bridge. [docs/09-touch-id.md](docs/09-touch-id.md) |
| Workspace overview, dock, night light by location | optional | [docs/10-desktop-extras.md](docs/10-desktop-extras.md) |

## The short version

On a fresh Omarchy install (2.4 GHz Wi-Fi or a USB Ethernet adapter is enough to start), with the charger
plugged in, in a terminal in the desktop:

```sh
omarchy update                     # first: a current Omarchy and kernel, then reboot
git clone https://github.com/olofd/omarchy-macbookpro-a1706 && cd omarchy-macbookpro-a1706
sh scripts/setup.sh                # as yourself; it asks for sudo where it needs it
```

`setup.sh` runs every step below in order. Each step checks what is already there and only does what is
missing or changed, so it is safe to run again, and on an up-to-date Mac it changes nothing. When a step needs
a reboot (sound, Wi-Fi, the Touch Bar, the driver fix), the steps that depend on it wait and the summary says
so: **reboot and run it again** until it says "All done". Run it again after every `git pull` too: that is how
the Mac keeps matching this repository. Options: `--fallback MyNetwork` (a 2.4 GHz connection for the wake
check, [chapter 5](docs/05-sleep.md)), `--no-touchid`, `--no-extras`. Two Touch ID steps stay by hand (it
prints them): enrolling a finger, and adding Touch ID to sudo. After the Touch Bar step, back up the T1
firmware it restored: `sudo tar -C /boot/EFI -czf efi-apple.tgz APPLE`, and keep the file off the machine.

The steps, one by one (what `setup.sh` runs):

```sh
sudo sh scripts/install-sound.sh              # then reboot
sudo sh scripts/install-wifi.sh               # NVRAM for 5 GHz (the tested values); then reboot
sudo bash scripts/install-touchbar.sh         # mains power; restores the T1 firmware; log out/in after
sudo sh scripts/install-sleep.sh              # deep sleep; optional argument: a 2.4 GHz connection to fall back to
sudo sh scripts/install-wifi-sleep-fix.sh     # patched Wi-Fi driver (DKMS) for 5 GHz and Bluetooth after sleep; reboot
sudo sh scripts/install-light.sh              # automatic keyboard light and screen brightness
sh scripts/install-input.sh                   # trackpad settings, in your ~/.config/hypr/input.lua
sudo sh scripts/install-touchid.sh install    # Touch ID; reboot, then the enroll and pam steps (docs/09)
sh scripts/install-overview.sh                # desktop extras (docs/10); also install-dock, -nightlight, -chime
```

In this order: the light sensor and Touch ID need the Touch Bar step (both sit on the T1), and the sleep steps
are only worth testing once Wi-Fi works.

## Check and undo each step

| Step | Check | Undo |
| --- | --- | --- |
| Sound | `aplay -l` lists `CS8409/CS42L83 Analog` | `sudo dkms remove snd_hda_macbookpro/0.1 --all`, `sudo rm -rf /usr/local/src/snd_hda_macbookpro`, reboot |
| Wi-Fi (5 GHz) | `iw phy \| grep -c 5180` prints more than 0 | `sudo sh scripts/install-wifi.sh remove`, reboot |
| Touch Bar | `sudo t1bridge status` says `touchbar: ready` | `sudo pacman -Rns t1bridge t1bridge-dkms` and delete the `[standardagents]` lines from `/etc/pacman.conf`; the restored T1 firmware stays (it is Apple's) |
| Sleep | `cat /sys/power/mem_sleep` shows `[deep]`; the lid closes and opens | `sudo sh scripts/install-sleep.sh remove`, reboot |
| Wi-Fi after sleep | `modinfo -F parm brcmfmac \| grep mac_efi_restore` | `sudo sh scripts/install-wifi-sleep-fix.sh remove`, reboot |
| Light sensor | `systemctl is-active kbd-auto-backlight screen-auto-brightness` | `sudo sh scripts/install-light.sh remove` |
| Trackpad | `hyprctl configerrors` is empty; two-finger scroll is natural | `sh scripts/install-input.sh remove` |
| Touch ID | `sudo -k; sudo true` asks for your finger | `sudo sh scripts/install-touchid.sh unpam` (the packages: [docs/09](docs/09-touch-id.md)) |
| Desktop extras | see [docs/10](docs/10-desktop-extras.md) | `sh scripts/install-<name>.sh remove` |

## Before you install anything

1. **Back up `EFI/APPLE` from macOS** if the Mac still boots macOS. It holds the Touch Bar firmware (in
   macOS Terminal: `sudo diskutil mount disk0s1`, then copy `/Volumes/EFI/EFI/APPLE` to a USB stick). If you
   already wiped it, [docs/04-touchbar.md](docs/04-touchbar.md) rebuilds it without macOS.
2. Use a **USB stick written in raw (DD) mode** (balenaEtcher, or Rufus in "DD image" mode). A stick made in
   Rufus's ISO mode will not boot on a Mac. See [docs/01-install.md](docs/01-install.md).
3. You need a **USB keyboard and mouse** for the first minutes: the SPI keyboard and trackpad drivers are
   installed by the installer, and the live image may not have them.

## Layout

```text
README.md              this file
docs/                  one page per problem: what is wrong, why, the fix, how to check it
scripts/               setup.sh (all of it), the installers it runs and the small services (all safe to run again)
files/                 the data they install: the Wi-Fi NVRAM, system units, config
brcmfmac-apple-resume/ the Wi-Fi driver patch and its DKMS package (built per kernel from the upstream source)
docs/99-log.md         the full trail of what was tried and what each test showed
```

## Credit

This builds on other people's work, linked where it is used: the CS8409 driver
([davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)), the T1 firmware regeneration
([niconistal/t1-revive](https://github.com/niconistal/t1-revive)), the T1 driver and Touch ID
([standardagents/t1bridge](https://github.com/standardagents/t1bridge)), the workspace overview
([itsmoorgrove/omarchy-overview](https://github.com/itsmoorgrove/omarchy-overview)), the dock
([nwg-piotr/nwg-dock-hyprland](https://github.com/nwg-piotr/nwg-dock-hyprland)), the Wi-Fi NVRAM
(t1-revive's, with values from [MikeRatcliffe's gist](https://gist.github.com/MikeRatcliffe/9614c16a8ea09731a9d5e91685bd8c80)
and [nohzafk/omarchy-macbookpro-t1](https://github.com/nohzafk/omarchy-macbookpro-t1)) and the state-of-Linux pages
([Dunedan/mbp-2016-linux](https://github.com/Dunedan/mbp-2016-linux),
[xtocdra/macbookpro13-2](https://github.com/xtocdra/macbookpro13-2)).

Not affiliated with Apple, Omarchy or the projects above. Use at your own risk: these scripts write to system
directories, a firmware step talks to Apple's servers, and the Wi-Fi fix replaces a kernel driver. The sound,
Touch Bar and overview steps download and run the current code of those upstream projects (as root for sound and
Touch Bar): read it there if you want to know exactly what runs.

## Licence

MIT ([LICENSE](LICENSE)), except the driver patch in `brcmfmac-apple-resume/`, which changes the Linux brcmfmac
driver and is under the ISC licence, like the file it changes (`pcie.c`). Issues and pull requests are welcome,
especially reports from the other T1 models.
