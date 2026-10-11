#!/bin/sh
# Installed as /usr/local/sbin/wifi-recover by install-sleep.sh, started after every wake by the sleep hook
# through systemd-run (a plain background process is killed when the suspend service ends).
# With the driver fix (install-wifi-sleep-fix.sh, docs/06) 5 GHz rejoins by itself and this finds Wi-Fi
# connected at its first check. Without it, 5 GHz joins fail after a resume while 2.4 GHz works, so this gives
# 5 GHz a few seconds and then brings up your 2.4 GHz connection. It never restarts wpa_supplicant: that raced
# NetworkManager and once left the Wi-Fi interface "unavailable (supplicant-failed)" until a reboot.
# Every wake writes a diagnostic log to /var/log/wake-diag/ (the last 40 are kept).
# The 2.4 GHz connection to fall back to (its NetworkManager name), in /etc/wifi-recover.conf:
#   FALLBACK=MyNetwork
FALLBACK=
[ -r /etc/wifi-recover.conf ] && FALLBACK=$(sed -n 's/^FALLBACK=//p' /etc/wifi-recover.conf | head -n 1)
D=/var/log/wake-diag
mkdir -p "$D"; ls -1t "$D" | tail -n +41 | while read -r f; do rm -f "$D/$f"; done
LOG=$D/$(date +%Y%m%d-%H%M%S).log
iface=$(ls /sys/class/net | grep '^wl' | head -n 1)
t0=$(date +%s)
snap() { # label
  {
    echo "=== $1 (+$(( $(date +%s) - t0 )) s) $(date +%T)"
    echo "-- nmcli:   $(nmcli -t -f DEVICE,STATE,CONNECTION device 2>&1 | grep -E '^wl|^p2p' | tr '\n' ' ')"
    echo "-- link:    $(iw dev "$iface" link 2>&1 | head -3 | tr '\n' ' ')"
    echo "-- rfkill:  $(rfkill list 2>&1 | tr '\n' ' ' | cut -c1-200)"
    echo "-- units:   NM=$(systemctl is-active NetworkManager) wpa=$(systemctl is-active wpa_supplicant)"
    echo "-- module:  brcmfmac loaded=$(lsmod | grep -c '^brcmfmac ') srcversion=$(cat /sys/module/brcmfmac/srcversion 2>/dev/null) reg=$(iw reg get 2>&1 | awk '/^country/ {print $2; exit}')"
    pci=$(basename "$(readlink -f "/sys/class/net/$iface/device" 2>/dev/null)" 2>/dev/null)
    echo "-- pci:     $(lspci -nn -s "$pci" 2>&1 | head -1) power=$(cat "/sys/class/net/$iface/device/power_state" 2>&1)"
  } >> "$LOG"
}
{ echo "wake diagnostics $(date '+%F %T') kernel $(uname -r)"; echo "wake reason: $(cat /sys/power/pm_wakeup_irq 2>/dev/null)"; } >> "$LOG"
snap "wake"
[ -n "$iface" ] || { echo "no Wi-Fi interface at wake" >> "$LOG"; journalctl -k -b 0 --no-pager | tail -40 >> "$LOG"; exit 0; }
sleep 2
# The country is not pushed again here: after a wake the driver already writes the system country into the
# firmware, and more changes while the card joins only add trouble (docs/06).
for i in 1 2 3 4 5 6; do
  sleep 4
  snap "check $i"
  if [ "$(nmcli -t -f DEVICE,STATE device | grep "^$iface:" | cut -d: -f2)" = connected ]; then echo "RESULT: connected after check $i" >> "$LOG"; break; fi
  # Give 5 GHz about 20 s (with the driver fix it is back in about 10) before taking the 2.4 GHz connection.
  [ "$i" -ge 5 ] && [ -n "$FALLBACK" ] && nmcli connection up "$FALLBACK" >> "$LOG" 2>&1
done
{ echo "=== kernel and Wi-Fi log since wake"
  journalctl -b 0 --no-pager --since "-$(( $(date +%s) - t0 + 20 )) sec" 2>/dev/null | grep -iE "brcmf|wpa_supplicant|$iface|NetworkManager.*($iface|sleep)|pcieport|PM:" | cut -c1-200 | tail -80
} >> "$LOG"
exit 0
