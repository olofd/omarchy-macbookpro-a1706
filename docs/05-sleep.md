# 5. Sleep (suspend)

**Symptom:** the screen goes black, the keyboard backlight stays on, and the Mac never wakes; only holding
the power button recovers it. The log of that boot ends at `PM: suspend entry` or earlier, with nothing after.

**Result:** with the steps below, suspend and resume work. For Wi-Fi and Bluetooth after waking, add the driver
fix in [chapter 6](06-wifi-after-sleep.md).

```sh
sudo sh scripts/install-sleep.sh [MyNetwork]   # optional: a 2.4 GHz connection to fall back to (nmcli connection show)
```

## What was tried, in the order that found the cause

1. **`s2idle` instead of `deep`** was the first try, because `deep` (S3) never woke. It did **not** fix the hang
   either: both modes hang for the same reason (step 4). With that fixed, both work, and **`deep` is the one
   to use** (see [Deep or s2idle](#deep-or-s2idle) below).
2. **The NVMe fix Omarchy ships** (`d3cold_allowed=0` on the NVMe controller) is already applied by the
   installer for these models. Check: `cat /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed` prints `0`
   (`01:00.0` on this Mac; find yours with `lspci | grep -i nvme`).
3. **Bisect with `pm_test`.** The kernel can run the suspend steps one at a time and resume by itself after
   5 seconds, which turns a hang into a pass/fail per stage:

   ```sh
   echo freezer   | sudo tee /sys/power/pm_test; sudo sh -c 'echo mem > /sys/power/state'   # ok
   echo devices   | sudo tee /sys/power/pm_test; sudo sh -c 'echo mem > /sys/power/state'   # ok
   echo platform  | sudo tee /sys/power/pm_test; sudo sh -c 'echo mem > /sys/power/state'   # HUNG
   echo none | sudo tee /sys/power/pm_test
   ```

   The `platform` stage sits after the **late and noirq device suspend phases**, so the hang was a device
   going to sleep in that phase. (Use `echo mem > /sys/power/state` directly: it skips systemd's hooks and keeps
   the network up, so you can read the result over SSH.)
4. **Remove suspects before the test.** With Bluetooth and Thunderbolt removed it passed; with
   **only Thunderbolt** removed it also passed. The culprits are the two **Thunderbolt 3 controllers**
   (Alpine Ridge, `05:00.0`/`06:00.0` and `7b:00.0`/`7c:00.0` on this Mac: check yours with
   `lspci | grep -i thunderbolt`).
5. **Make it permanent** with a systemd sleep hook, `scripts/sleep-hook.sh`, installed as
   `/usr/lib/systemd/system-sleep/mac-sleep`:
   - `pre`: unload the `thunderbolt` module and remove the four PCI functions (`echo 1 > .../remove`);
     switch the keyboard backlight off and remember its level (it stays lit during sleep otherwise); stop the
     light-sensor services; disable wake-up by the T1 (USB `05ac:8600`), which otherwise wakes the Mac a few
     seconds into sleep; write `/var/log/wake-diag/last-pre-sleep.log`.
   - `post`: after a deep sleep, tell the T1 the Mac is awake (the ACPI call `SOCW(1)`, see
     [Deep or s2idle](#deep-or-s2idle)); restore the backlight and the light services; `echo 1 >
     /sys/bus/pci/rescan` and `modprobe thunderbolt` to bring the controllers back; start
     `/usr/local/sbin/wifi-recover` (chapter 6) with `systemd-run`; 10 seconds later, restart the Touch Bar
     renderer (`t1-touchbar.service`), whose volume and brightness popups stop after a wake.

   The rescan runs detached (`systemd-run`): it takes about 5 seconds per controller, and systemd keeps the
   desktop frozen until every sleep hook has finished, so run inline it delayed typing by 10 seconds after
   every wake.

   The USB-C ports come back about 10 seconds after a wake; an adapter plugged in during sleep is picked up by
   the rescan. The controllers are found by vendor, device ID and class, not by address, so the hook works if
   they sit elsewhere on your model.

   **Unmount USB-C drives before closing the lid.** The USB-C ports hang off these controllers, so a drive is cut
   off at every sleep (the hook syncs first and logs a warning, `journalctl -t mac-sleep`, if one was mounted).

The `pm_trace` feature (which stores the last device in the RTC) was tried and was **not usable** here: it
printed the same hash after different hangs, and it scrambles the system clock.

## Why not unload the Wi-Fi driver around sleep?

It is the obvious move and it is **wrong** on this card: the BCM43602 does not recover from a live driver
unload/reload, and stays dead until a reboot. See [06-wifi-after-sleep.md](06-wifi-after-sleep.md).

## Pitfalls

- A background process started from a sleep hook is **killed when the suspend service ends**. Anything that
  has to run after wake must be started with `systemd-run --no-block` (the hook starts `wifi-recover` that way).
- The **keyboard backlight** is not switched off by Omarchy's own sleep hook except for hibernate; the hook
  here does it for suspend too.
- `pm_test` blanks the screen during each test: run it over SSH, or wait for the screen to come back.
- Re-test after kernel updates.

## Deep or s2idle

Both work with the hook. Measured on the MacBookPro13,2, unplugged, lid closed:

| Mode | Battery used | Average |
| --- | --- | --- |
| `deep` (S3) | 5.6 % in 6.5 hours | 33 mA, about 0.9 % per hour: 4-5 days from full |
| `s2idle` | 82 % → empty in under 10 hours | over 300 mA |

These Macs have no low-power idle state (no ACPI LPS0 device; `/sys/devices/system/cpu/cpuidle/` has no
`low_power_idle_*`), so in s2idle the machine stays about as warm as an idle laptop with the screen off.
`files/mem-sleep.conf` therefore makes **`deep`** the default at boot (`w /sys/power/mem_sleep - - - - deep` in
`/etc/tmpfiles.d/`). Check: `cat /sys/power/mem_sleep` shows `s2idle [deep]`.

Deep needs one more thing, also in the hook: after an S3 wake the T1 is never told the Mac is awake, and the
Touch Bar and Touch ID stay dark (everything reports ready). macOS and Windows call the ACPI method
`\_SB.PCI0.XHC1.RHUB.ASOC.SOCW(1)` at wake; the hook does the same through the `acpi_call` module
(`acpi_call-dkms`, installed by `install-sleep.sh`), and logs it: `journalctl -t mac-sleep` shows
`T1 wake call SOCW(1): 0x0`. Found by a tester on a MacBookPro14,3,
[t1bridge issue #18](https://github.com/standardagents/t1bridge/issues/18). **Never** call `ASOC.FRST`: it is
an EC hard reset that leaves the T1 stuck in recovery mode.

To go back to s2idle: `echo s2idle | sudo tee /sys/power/mem_sleep` (until the next boot), or change the line
in `/etc/tmpfiles.d/mem-sleep.conf` (running `install-sleep.sh` again sets it back to deep).

## Hibernate

Omarchy's installer sets up a swapfile and the resume offset, so `systemctl hibernate` works: the Mac powers
off, and the next power-on (after the disk password) restores the session. Hibernate uses no power, where deep
sleep uses a little (fine overnight, not for a week in a bag).

**Closing the lid: deep sleep, then hibernation after 12 hours.** When hibernation is set up (a resume device,
as Omarchy's installer makes), `install-sleep.sh` sets the lid to `suspend-then-hibernate`
([`files/logind-lid.conf`](../files/logind-lid.conf)) with
[`files/sleep-then-hibernate.conf`](../files/sleep-then-hibernate.conf): after 12 hours of deep sleep on
battery the Mac wakes by itself (RTC alarm), hibernates and powers off, so a forgotten Mac never runs flat.
Within 12 hours it wakes as fast as before. On the charger it stays in deep sleep; the 12 hours start when the
charger is unplugged. The battery is measured only at the 12-hour mark (`SuspendEstimationSec=12h`): the
default wakes the Mac every hour to measure it, and each wake runs the whole sleep hook. The sleep hook runs
for both halves (the wake in between brings Thunderbolt back, the hibernation removes it again). To try it
without waiting 12 hours (unplug the charger first; the file in `/run` is gone at the next boot):

```sh
sudo mkdir -p /run/systemd/sleep.conf.d
printf '[Sleep]\nHibernateDelaySec=2min\nSuspendEstimationSec=2min\n' | sudo tee /run/systemd/sleep.conf.d/99-test.conf
systemctl suspend-then-hibernate     # sleeps, wakes by itself after 2 minutes, hibernates, powers off
```

With the stock driver, Wi-Fi was gone after every restore until a reboot: Apple's EFI leaves the Wi-Fi chip
unreachable in the boot that restores the image. The driver patch of the next chapter resets the chip at that
point; `journalctl -k -b | grep "ACPI DRST"` shows when it did. The details are in
[chapter 6](06-wifi-after-sleep.md#after-hibernation).
