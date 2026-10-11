#!/bin/sh
# Touch ID with T1Bridge (github.com/standardagents/t1bridge, docs/setup.md), for sudo and Polkit prompts.
# Needs the Touch Bar step first (install-touchbar.sh: the T1 must be running). T1 data regenerated on the same Mac
# with t1-revive works (t1bridge issue #29). See docs/09-touch-id.md.
# One step at a time, in this order:
#
#   sudo sh install-touchid.sh install    the matched pair libfprint-t1bridge + fprintd-t1bridge, the user in group
#                                     t1bridge, the Touch ID sockets, machine data from /boot, and a firewall
#                                     opening for the T1's xART port 61500 on the T1 link only. Then REBOOT.
#   sh install-touchid.sh enroll [FINGER] as the user, in the desktop (default right-index-finger): touch the sensor
#                                     again and again until "enroll-completed", then a verify must say "verify-match"
#   sudo sh install-touchid.sh pam        Touch ID for sudo and for Polkit prompts (3 tries in 15 s, then the password);
#                                     safe to run again: it replaces its own earlier lines
#   sudo sh install-touchid.sh unpam      undo the PAM step (backups restored)
#   sudo sh install-touchid.sh status     what is there now
#
# Not done: the lock screen. A report (t1bridge) says Omarchy's lock re-arms the reader every ~31 s while away,
# and that wedged the Secure Enclave. Never run Omarchy's generic fingerprint wizard: it replaces the matched pair.
# Before `pam`, keep a root shell open in another terminal (sudo -s) until sudo has been tested both ways.
set -eu
cmd=${1:-}
U=${SUDO_USER:-$(id -un)}
LINE="# Touch ID (omarchy-macbookpro-a1706 install-touchid.sh); password still works after it\nauth       sufficient   pam_fprintd.so max-tries=3 timeout=15"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "run as root: sudo sh $0 $cmd" >&2; exit 1; }; }
t1_if() { # the T1's private network link, found by its driver (not by a name like eth0)
  for n in /sys/class/net/*; do
    [ "$(basename "$(readlink -f "$n/device/driver" 2>/dev/null)")" = apple_t1_ncm ] && { basename "$n"; return; }
  done
}

add_touchid() { # file: our two lines just before the password stack (the first "auth include/substack"
  f=$1
  inc=$(grep -cE '^auth[[:space:]]+(include|substack)' "$f" || true)
  sed -i '/^# Touch ID (omarchy-macbookpro-a1706 install-touchid.sh)/d; /^auth[[:space:]].*pam_fprintd\.so/d' "$f"
  if grep -q 'omarchy-hw-laptop-closed' "$f"; then
    # Omarchy's fingerprint setup skips the next line while the lid is closed: our lines go right after it.
    sed -i "0,/omarchy-hw-laptop-closed/s|^\(auth.*omarchy-hw-laptop-closed.*\)$|\1\n$LINE|" "$f"
  elif grep -qE '^auth[[:space:]]+(include|substack)' "$f"; then
    sed -i -E "0,/^auth[[:space:]]+(include|substack)/s|^(auth[[:space:]]+(include\|substack))|$LINE\n\1|" "$f"
  else
    sed -i "0,/^auth/s|^auth|$LINE\nauth|" "$f"
  fi
  # Never leave a file without its password stack: if anything looks wrong, put it back and stop.
  if ! grep -q 'pam_fprintd.so max-tries=3' "$f" ||
     [ "$(grep -cE '^auth[[:space:]]+(include|substack)' "$f" || true)" != "$inc" ]; then
    for bak in "$f.before-touchid" "${f%.new}.before-touchid"; do [ -f "$bak" ] && cp "$bak" "$f" && break; done
    case "$f" in *.new) rm -f "$f" ;; esac
    echo "could not edit $f safely; left it as it was" >&2
    exit 1
  fi
}

case "$cmd" in
  install)
    need_root
    pacman -S --needed libfprint-t1bridge fprintd-t1bridge
    systemd-sysusers /usr/lib/sysusers.d/t1bridge.conf
    systemd-tmpfiles --create /usr/lib/tmpfiles.d/t1bridge.conf
    usermod -aG t1bridge "$U"
    systemctl daemon-reload
    systemctl enable t1-touchid-auth.socket t1bridge-fingerprint.socket
    # Machine data (FDRData) from the Apple EFI folder on /boot; an empty import was issue #29's blocker.
    t1bridge machine-data import --from /boot || echo "WARNING: machine-data import failed; see: sudo t1bridge status" >&2
    IF=$(t1_if)
    if [ -n "$IF" ] && command -v ufw >/dev/null; then
      # xART: IPv6 TCP 61500 from the link-local T1 only, on the T1 link only. Never on Wi-Fi/LAN.
      ufw allow in on "$IF" proto tcp from fe80::/64 to any port 61500 comment 't1bridge xART: T1 link only'
    else
      echo "WARNING: T1 link or ufw not found; no firewall rule added" >&2
    fi
    echo "Installed. Reboot, then as yourself in the desktop: sh $0 enroll"
    ;;
  enroll)
    [ "$(id -u)" -ne 0 ] || { echo "run as yourself, not root (no sudo)" >&2; exit 1; }
    F=${2:-right-index-finger}
    fprintd-list "$U" || true
    echo "Touch the Touch ID button with your $F, lift, touch again ... until it says enroll-completed."
    if ! fprintd-enroll -f "$F"; then
      echo "Enrollment failed. The first try often fails while the T1's keybag is prepared (journalctl -b -u" >&2
      echo "t1-touchid-auth shows 'prepare device keybag failed'). Run: sudo systemctl restart t1-touchid-auth.service" >&2
      echo "and then this again. Use fprintd-delete \"\$USER\" -f $F first if the finger shows up as enrolled." >&2
      exit 1
    fi
    echo "Now verify: touch it once more."
    fprintd-verify -f "$F"
    ;;
  pam)
    need_root
    fprintd-list "$U" | grep -q -- "-finger" || { echo "no enrolled finger for $U: run enroll first" >&2; exit 1; }
    [ -f /usr/lib/pam.d/polkit-1 ] || [ -f /etc/pam.d/polkit-1 ] || { echo "no polkit PAM file found" >&2; exit 1; }
    if [ ! -f /etc/pam.d/polkit-1 ] || [ -f /etc/pam.d/polkit-1.created-by-touchid ]; then
      # Polkit's own file lives in /usr/lib/pam.d; a copy in /etc/pam.d takes precedence and survives updates.
      [ -f /usr/lib/pam.d/polkit-1 ] || { echo "no /usr/lib/pam.d/polkit-1 to start from" >&2; exit 1; }
      cp /usr/lib/pam.d/polkit-1 /etc/pam.d/polkit-1.new
      add_touchid /etc/pam.d/polkit-1.new
      mv /etc/pam.d/polkit-1.new /etc/pam.d/polkit-1
      touch /etc/pam.d/polkit-1.created-by-touchid
    else
      [ -f /etc/pam.d/polkit-1.before-touchid ] || cp /etc/pam.d/polkit-1 /etc/pam.d/polkit-1.before-touchid
      add_touchid /etc/pam.d/polkit-1
    fi
    [ -f /etc/pam.d/sudo.before-touchid ] || cp /etc/pam.d/sudo /etc/pam.d/sudo.before-touchid
    add_touchid /etc/pam.d/sudo
    echo "Done. Test now, in a NEW terminal: sudo -k; sudo true  (touch the sensor)."
    echo "Then: sudo -k; sudo true  and let it time out / use the wrong finger: the password prompt must follow."
    ;;
  unpam)
    need_root
    [ -f /etc/pam.d/sudo.before-touchid ] && mv /etc/pam.d/sudo.before-touchid /etc/pam.d/sudo
    [ -f /etc/pam.d/polkit-1.created-by-touchid ] && rm -f /etc/pam.d/polkit-1 /etc/pam.d/polkit-1.created-by-touchid
    [ -f /etc/pam.d/polkit-1.before-touchid ] && mv /etc/pam.d/polkit-1.before-touchid /etc/pam.d/polkit-1
    echo "Touch ID removed from sudo and Polkit (enrolled fingers stay; fprintd-delete removes them)."
    ;;
  status)
    need_root
    pacman -Q t1bridge libfprint-t1bridge fprintd-t1bridge 2>&1 | tr '\n' ' '; echo
    systemctl is-enabled t1-touchid-auth.socket t1bridge-fingerprint.socket 2>&1 | tr '\n' ' '; echo
    id -nG "$U" | tr ' ' '\n' | grep -x t1bridge || echo "$U is not in group t1bridge"
    t1bridge status 2>&1 | tail -15
    ufw status | grep 61500 || echo "no xART firewall rule"
    fprintd-list "$U" 2>&1 | tail -4
    grep -l "install-touchid.sh" /etc/pam.d/* 2>/dev/null || echo "Touch ID not in PAM"
    ;;
  *)
    echo "usage: sudo sh $0 install|pam|unpam|status   or   sh $0 enroll [finger]" >&2; exit 2 ;;
esac
