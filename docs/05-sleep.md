# 5. Sleep (suspend)

**Symptom:** the screen goes black, the keyboard backlight stays on, and the Mac never wakes; only holding
the power button recovers it. The log of that boot ends at `PM: suspend entry` or earlier, with nothing after.

**Result:** with the steps below, suspend and resume work. For Wi-Fi and Bluetooth after waking, add the driver
fix in [chapter 6](06-wifi-after-sleep.md).

```sh
sudo sh scripts/install-sleep.sh [MyNetwork]   # optional: a 2.4 GHz connection to fall back to (nmcli connection show)
```

## What was tried, in the order that found the cause

1. **Use `s2idle` instead of `deep`.** `cat /sys/power/mem_sleep` shows `s2idle [deep]` by default.
   `deep` (S3) never woke. `files/mem-sleep.conf` makes `s2idle` the default at boot
   (`w /sys/power/mem_sleep - - - - s2idle` in `/etc/tmpfiles.d/`). This alone did **not** fix the hang, but it
   is the mode that works with the fix below.
2. **The NVMe fix Omarchy ships** (`d3cold_allowed=0` on the NVMe controller) is already applied by the
   installer for these models. Check: `cat /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed` prints `0`.
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
   - `post`: restore the backlight and the light services, `echo 1 > /sys/bus/pci/rescan` to bring the
     controllers back, and start `/usr/local/sbin/wifi-recover` (chapter 6) with `systemd-run`.

   The USB-C ports come back after wake; an adapter plugged in during sleep is picked up by the rescan. The
   controllers are found by vendor, device ID and class, not by address, so the hook works if they sit elsewhere
   on your model.

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

## Hibernate

Omarchy's installer sets up a swapfile and the resume offset. Hibernate was not tested here. It is not
needed for Wi-Fi: 5 GHz after a resume is fixed by the driver patch in the next chapter.
