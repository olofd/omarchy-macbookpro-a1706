#!/bin/sh
# Checks that what the guide fixes works right now: after setup, after a sleep or a hibernation, after a kernel
# update. Prints one line per check (ok / FAIL / --, where -- means not set up here or not applicable) and exits
# 1 if anything failed. Needs no root.
#   sh scripts/verify.sh              all checks
#   sh scripts/verify.sh --since T    the kernel-error check covers the log from T (journalctl time) instead of
#                                     the last wake
# sleep-test.sh runs it after every test sleep.
set -u
SINCE=
[ "${1:-}" = --since ] && SINCE=${2:-}
FAILED=0
ok() { printf '  ok    %-22s %s\n' "$1" "$2"; }
bad() { printf '  FAIL  %-22s %s\n' "$1" "$2"; FAILED=1; }
na() { printf '  --    %-22s %s\n' "$1" "$2"; }
check() { # check NAME DETAIL CONDITION...: ok if the condition command succeeds
  _n=$1 _d=$2; shift 2
  if "$@" >/dev/null 2>&1; then ok "$_n" "$_d"; else bad "$_n" "$_d"; fi
}
usb_present() { grep -qsx "$2" /sys/bus/usb/devices/*/idProduct && grep -qsx "$1" /sys/bus/usb/devices/*/idVendor; }
user_active() { systemctl --user -q is-active "$1"; }
sys_active() { systemctl -q is-active "$1"; }

echo "$(cat /sys/class/dmi/id/product_name 2>/dev/null), kernel $(uname -r), up $(uptime -p | sed 's/^up //')"

echo "Sound"
if aplay -l 2>/dev/null | grep -q 'CS8409'; then ok "speakers" "CS8409 card present"
else bad "speakers" "no CS8409 card (install-sound.sh)"; fi
# The driver was built with exactly this guide's patches (install-sound.sh records their checksum).
want=$(cat "$(dirname "$0")"/../snd-hda-macbookpro/*.patch 2>/dev/null | sha256sum | cut -d' ' -f1)
have=$(cat /usr/local/src/snd_hda_macbookpro/.omarchy-macbookpro-a1706-patches 2>/dev/null)
if [ "$have" = "$want" ]; then ok "sound driver patches" "built with this guide's patches"
else bad "sound driver patches" "not built with this guide's current patches (install-sound.sh)"; fi

echo "Wi-Fi and Bluetooth"
wl=; for n in /sys/class/net/wl*; do [ -e "$n" ] && wl=${n##*/} && break; done
if [ -z "$wl" ]; then bad "Wi-Fi" "no wireless interface"
else
  state=$(nmcli -t -f DEVICE,STATE dev 2>/dev/null | sed -n "s/^$wl://p")
  if [ "$state" = connected ]; then
    freq=$(iw dev "$wl" link 2>/dev/null | sed -n 's/.*freq: \([0-9]*\).*/\1/p')
    ok "Wi-Fi" "connected, ${freq:-?} MHz ($([ "${freq:-0}" -ge 5000 ] && echo 5 GHz || echo 2.4 GHz))"
    gw=$(ip route show default dev "$wl" 2>/dev/null | awk '/default/ {print $3; exit}')
    if [ -n "$gw" ]; then check "Wi-Fi traffic" "gateway $gw answers" ping -c 2 -W 2 "$gw"
    else na "Wi-Fi traffic" "no default route on $wl"; fi
  else bad "Wi-Fi" "$wl is ${state:-unknown}"; fi
  if modinfo -F parm brcmfmac 2>/dev/null | grep -q mac_efi_restore; then ok "Wi-Fi driver fix" "patched brcmfmac installed"
  else bad "Wi-Fi driver fix" "stock brcmfmac (install-wifi-sleep-fix.sh)"; fi
fi
if command -v bluetoothctl >/dev/null; then
  check "Bluetooth" "controller powered" sh -c 'bluetoothctl show | grep -q "Powered: yes"'
else na "Bluetooth" "bluetoothctl missing"; fi

echo "T1: Touch Bar, Touch ID, camera, light sensor"
if usb_present 05ac 8600; then
  ok "T1" "on USB (05ac:8600)"
  check "Touch Bar hardware" "t1-touchbar-hw.service" sys_active t1-touchbar-hw.service
  check "Touch Bar renderer" "t1-touchbar.service (user)" user_active t1-touchbar.service
  if systemctl --user cat t1bridge-omarchy-watch.service >/dev/null 2>&1; then
    check "Touch Bar watcher" "t1bridge-omarchy-watch.service" user_active t1bridge-omarchy-watch.service
  fi
  if grep -qsx als /sys/bus/iio/devices/iio:device*/name; then
    ok "light sensor" "als present"
    for s in kbd-auto-backlight screen-auto-brightness; do
      if systemctl --user cat "$s.service" >/dev/null 2>&1; then check "$s" "user service" user_active "$s.service"
      elif systemctl cat "$s.service" >/dev/null 2>&1; then check "$s" "service" sys_active "$s.service"; fi
    done
  else bad "light sensor" "no als device"; fi
  if pacman -Q fprintd-t1bridge >/dev/null 2>&1; then
    check "Touch ID" "t1bridge-fingerprint.socket" sys_active t1bridge-fingerprint.socket
  else na "Touch ID" "not installed"; fi
else bad "T1" "not on USB (Touch Bar, Touch ID, camera, light sensor all need it)"; fi

echo "Thunderbolt and USB-C"
bridges=0; nhis=0; xhcis=0
for d in /sys/bus/pci/devices/*; do
  [ "$(cat "$d/vendor")" = 0x8086 ] || continue
  case "$(cat "$d/device")" in
    0x1578) bridges=$((bridges + 1)) ;;
    0x15d2) [ -e "$d/driver" ] && [ "$(basename "$(readlink "$d/driver")")" = thunderbolt ] && nhis=$((nhis + 1)) ;;
    0x15d4) [ -e "$d/driver" ] && [ "$(basename "$(readlink "$d/driver")")" = xhci_hcd ] && xhcis=$((xhcis + 1)) ;;
  esac
done
if [ "$bridges" -eq 0 ]; then bad "Thunderbolt" "no Alpine Ridge bridge at all (dead since boot, or another model)"
else
  if [ "$nhis" -ge "$bridges" ]; then ok "Thunderbolt" "$nhis of $bridges controllers on the thunderbolt driver"
  else bad "Thunderbolt" "$nhis of $bridges controllers on the thunderbolt driver"; fi
  if [ "$xhcis" -ge "$bridges" ]; then ok "USB-C" "$xhcis of $bridges USB controllers on xhci_hcd"
  else bad "USB-C" "$xhcis of $bridges USB controllers on xhci_hcd"; fi
  if lsmod | grep -q '^tb_ar_shim '; then ok "Thunderbolt sleep fix" "tb_ar_shim $(modinfo -F version tb_ar_shim 2>/dev/null) loaded"
  else bad "Thunderbolt sleep fix" "tb_ar_shim not loaded (install-thunderbolt-sleep.sh)"; fi
fi

echo "Sleep"
check "deep sleep" "mem_sleep is [deep]" grep -q '\[deep\]' /sys/power/mem_sleep
check "sleep hook" "/usr/lib/systemd/system-sleep/mac-sleep" test -x /usr/lib/systemd/system-sleep/mac-sleep
if grep -qw disk /sys/power/state && [ "$(cat /sys/power/resume 2>/dev/null)" != 0:0 ]; then
  ok "hibernation" "resume device $(cat /sys/power/resume)"
  lid=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager \
    HandleLidSwitch 2>/dev/null | awk '{print $2}' | tr -d '"')
  if [ "$lid" = suspend-then-hibernate ]; then ok "lid" "suspend-then-hibernate"
  else bad "lid" "HandleLidSwitch=${lid:-?} (install-sleep.sh)"; fi
else na "hibernation" "no resume device"; fi

echo "Kernel log"
if [ -z "$SINCE" ]; then
  SINCE=$(journalctl -k -b 0 -o short-iso --no-pager 2>/dev/null |
    awk '/Waking up from system sleep|hibernation exit/ {t=$1} END {print t}')
fi
if [ -n "$SINCE" ]; then scope="since $SINCE"; else scope="this boot"; fi
errs=$(journalctl -k -b 0 ${SINCE:+--since "$SINCE"} --no-pager -o cat 2>/dev/null | grep -E \
  'device inaccessible|not ready [0-9]+ms after|tb_cfg_(read|write): -|MMIO read failed|Firmware has halted|probe after resume failed|marked gone|budget spent|BUG:|Oops|Call Trace' |
  sort | uniq -c | sort -rn | head -5)
if [ -z "$errs" ]; then ok "errors" "none $scope"
else bad "errors" "$scope:"; printf '%s\n' "$errs" | sed 's/^ */          /'; fi

[ "$FAILED" = 0 ] && echo "All checks passed." || echo "Some checks FAILED."
exit "$FAILED"
