#!/bin/sh
# Installed as /usr/lib/systemd/system-sleep/mac-sleep by install-sleep.sh. $1 is pre or post.
# On the A1706, suspend only works with the Thunderbolt 3 controllers out of the way: they hang the late stage of
# suspend (found with pm_test; with them removed it passes). They are removed before sleep and rescanned after.
# The USB-C ports hang off them, so a USB-C drive is cut off at every sleep: unmount drives before closing the lid.
# (Unloading the Wi-Fi driver around sleep was tried and made it worse: the card stayed dead until a reboot.)
kbd=/sys/class/leds/spi::kbd_backlight
lights="kbd-auto-backlight screen-auto-brightness"

# The Intel Thunderbolt 3 (Alpine Ridge) controllers and their USB controllers, found by vendor, device and
# class rather than by PCI address, which differs between models. Their PCI bridges (class 0x0604) stay; the
# rescan after the wake brings everything back. On a MacBookPro13,2: 05:00.0 and 7b:00.0 (8086:15d2, class
# 0x088000) and 06:00.0 and 7c:00.0 (8086:15d4, USB, class 0x0c0330).
tb_devices() {
  for p in /sys/bus/pci/devices/*; do
    [ "$(cat "$p/vendor" 2>/dev/null)" = 0x8086 ] || continue
    case "$(cat "$p/class" 2>/dev/null)" in 0x0880*|0x0c03*) ;; *) continue ;; esac
    case "$(cat "$p/device" 2>/dev/null)" in
      0x1575|0x1577|0x15b5|0x15b6|0x15bf|0x15c1|0x15d2|0x15d4|0x15d9|0x15db|0x15dc|0x15dd|0x15de|0x15e8|0x15e9|0x15eb|0x15ec)
        echo "$p" ;;
    esac
  done
}

case "$1" in
  pre)
    # A wake check still running from the last wake (lid opened and closed within ~25 s) would otherwise block
    # this wake's check (same unit name) and resume after the next wake with stale timing.
    systemctl stop wifi-recover.service 2>/dev/null
    # A Thunderbolt rescan from the last wake still running (lid closed again within ~10 s): let it finish, so the
    # controllers it brings back are removed below.
    i=0; while systemctl is-active --quiet mac-tb-rescan.service && [ $i -lt 30 ]; do sleep 0.5; i=$((i + 1)); done
    # The T1 (iBridge, USB 05ac:8600) wakes the machine by itself a few seconds into sleep (its wakeup source
    # fired right at the wake). Keyboard, lid and power button still wake it.
    for d in /sys/bus/usb/devices/*; do
      [ "$(cat "$d/idVendor" 2>/dev/null)" = 05ac ] && [ "$(cat "$d/idProduct" 2>/dev/null)" = 8600 ] &&
        echo disabled > "$d/power/wakeup"
    done
    iface=$(ls /sys/class/net | grep '^wl' | head -n 1)
    mkdir -p /var/log/wake-diag
    { echo "pre-sleep $(date '+%F %T')"
      nmcli -t -f DEVICE,STATE,CONNECTION device 2>&1 | grep '^wl'
      iw dev 2>&1 | grep -E 'ssid|channel'
      [ -n "$iface" ] && echo "brcmfmac loaded=$(lsmod | grep -c '^brcmfmac ') power=$(cat "/sys/class/net/$iface/device/power_state" 2>&1)"
    } > /var/log/wake-diag/last-pre-sleep.log 2>&1
    # The light services are stopped (and only the ones that ran are started again after).
    : > /run/mac-sleep-lights
    for s in $lights; do
      systemctl is-active --quiet "$s" && echo "$s" >> /run/mac-sleep-lights && systemctl stop "$s"
    done
    # The keyboard light stays on through sleep otherwise: remember it, switch it off.
    if [ -e "$kbd/brightness" ]; then
      cat "$kbd/brightness" > /run/mac-kbd-backlight
      echo 0 > "$kbd/brightness"
    fi
    sync
    modprobe -r thunderbolt 2>/dev/null
    for p in $(tb_devices); do
      dev=$(readlink -f "$p")
      for b in /sys/block/*; do
        case "$(readlink -f "$b")" in "$dev"/*)
          grep -q "^/dev/${b##*/}" /proc/mounts &&
            logger -t mac-sleep "USB-C drive ${b##*/} is mounted and is cut off by the sleep: unmount it first" ;;
        esac
      done
      echo 1 > "$p/remove"
    done
    ;;
  post)
    # After a "deep" (S3) sleep the T1 is never told the Mac is awake, and the Touch Bar and Touch ID stay dark.
    # macOS and Windows call the ACPI method ASOC.SOCW(1) at wake (t1bridge issue #18); it answers in ~90 ms.
    # (Never ASOC.FRST: an EC hard reset that leaves the T1 in recovery mode.) Not needed after s2idle.
    if grep -q '\[deep\]' /sys/power/mem_sleep && modprobe acpi_call 2>/dev/null && [ -w /proc/acpi/call ]; then
      printf '%s\n' '\_SB.PCI0.XHC1.RHUB.ASOC.SOCW 1' > /proc/acpi/call
      logger -t mac-sleep "T1 wake call SOCW(1): $(tr -d '\0' < /proc/acpi/call)"
    fi
    # The keyboard level first, then the services: started first, they would take the restore for a manual change.
    [ -s /run/mac-kbd-backlight ] && cat /run/mac-kbd-backlight > "$kbd/brightness"
    for s in $(cat /run/mac-sleep-lights 2>/dev/null); do systemctl start "$s"; done
    # The rescan takes ~5 s per Thunderbolt controller, and the desktop stays frozen until this hook ends: run it
    # detached, so the keyboard works at once and the USB-C ports follow ~10 s later.
    systemd-run --no-block --collect --unit=mac-tb-rescan \
      sh -c 'echo 1 > /sys/bus/pci/rescan; modprobe thunderbolt' >/dev/null 2>&1
    # Wi-Fi check and wake log, detached: a background child would be killed when the suspend service ends.
    systemd-run --no-block --collect --unit=wifi-recover /usr/local/sbin/wifi-recover >/dev/null 2>&1
    # The Touch Bar renderer (t1bridge 0.1.12) stops calling its desktop provider after a wake, so the volume and
    # brightness popups stop until it restarts. Restart it, for each user running it, 10 s after the wake: systemd
    # keeps the users' services frozen until every sleep hook has finished, so the hook cannot do it itself.
    systemd-run --no-block --collect --on-active=10 --unit=t1-touchbar-restart sh -c '
      for u in $(loginctl list-users --no-legend | awk "{print \$2}"); do
        systemctl --user -M "$u@" is-active --quiet t1-touchbar.service &&
          systemctl --user -M "$u@" restart t1-touchbar.service
      done' >/dev/null 2>&1
    ;;
esac
exit 0
