# 9. Touch ID

**State: works** for `sudo` and for Polkit password prompts (the system dialogs), with
[T1Bridge](https://github.com/standardagents/t1bridge)'s fingerprint support. The password always works as the
fallback. The lock screen is left out on purpose (below).

It needs the Touch Bar step first (chapter 4): the T1 chip, which owns the sensor, must be running. T1 data that
was regenerated with t1-revive on the same Mac works; data from another Mac does not.

```sh
sudo sh scripts/install-touchid.sh install     # the matched libfprint/fprintd pair, sockets, firewall rule; reboot
sh scripts/install-touchid.sh enroll           # as your user, in the desktop; touch the sensor until "enroll-completed"
sudo sh scripts/install-touchid.sh pam         # Touch ID for sudo and Polkit (keep `sudo -s` open in another terminal while testing)
sudo sh scripts/install-touchid.sh status      # what is there
sudo sh scripts/install-touchid.sh unpam       # undo the PAM step
```

## What the installer does

- Installs `libfprint-t1bridge` and `fprintd-t1bridge`, a **matched pair** from T1Bridge's repository that
  replaces the distribution's libfprint and fprintd. Never run Omarchy's generic fingerprint setup afterwards: it
  installs the stock pair back.
- Adds your user to the `t1bridge` group, enables `t1-touchid-auth.socket` and `t1bridge-fingerprint.socket`, and
  imports the T1's machine data from `/boot` (an empty import was the real cause of failed enrollments in
  [t1bridge #29](https://github.com/standardagents/t1bridge/issues/29)).
- Opens TCP port 61500 in ufw **only on the T1's private USB network link** and only from link-local addresses.
  The link is found by its driver (`apple_t1_ncm`) at install time and the rule names that interface (`eth0`
  here; USB Ethernet adapters get `enx...` names, not this one). The T1 uses the port to store the fingerprint
  keybag. Never open it on Wi-Fi or Ethernet.
- `pam` puts `pam_fprintd.so max-tries=3 timeout=15` as `sufficient` just before the password stack
  (`auth include system-auth`, or right after Omarchy's lid-closed line if its fingerprint setup ran before) in `/etc/pam.d/sudo` and in `/etc/pam.d/polkit-1` (a copy of the system's file, or
  your own if you have one): three tries within 15 seconds, then the password prompt. It checks the result and
  puts the backup back if the password stack is not intact. Backups are kept, and `unpam` restores them.

## Experience

- The **first enrollment failed** with `enroll-unknown-error`; `journalctl -b -u t1-touchid-auth` said `prepare
  device keybag failed`. Restarting `t1-touchid-auth.service` and enrolling again worked (six touches). The
  installer says so when it happens.
- Matching right after enrolling: 2 of 3 touches. With one try only (`max-tries=1`) a missed first touch went
  straight to the password, so three tries are allowed. Enrolling a second finger (up to three) helps further:
  `sh scripts/install-touchid.sh enroll left-index-finger`.
- **Lock screen: not done.** A T1Bridge user reported that Omarchy's lock screen re-arms the reader about every
  31 seconds while nobody is at the machine, and that this wedged the T1's Secure Enclave. T1Bridge's setup
  guide describes `/etc/pam.d/omarchy-lock-fingerprint` if you want to try it.
