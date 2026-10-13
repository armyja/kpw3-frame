#!/usr/bin/env sh
# Read-only diagnostics for the screensaver approach -> /mnt/us/diag.txt
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

OUT=/mnt/us/diag.txt

{
  echo "=== date ==="
  date
  echo "=== version ==="
  cat /mnt/us/system/version.txt 2>&1
  echo "=== server.txt (the configured server) ==="
  cat /mnt/us/screensaver/server.txt 2>&1
  echo "=== env.sh FRAME_URL ==="
  grep -i 'FRAME_URL\|SINGLE_IMAGE\|FETCH_SCHEDULE' /mnt/us/screensaver/env.sh 2>&1
  echo "=== wifi ip ==="
  ifconfig wlan0 2>&1 | sed -n 's/.*inet addr:\([0-9][0-9.]*\).*/ip=\1/p'

  echo "=== /usr/share/blanket ==="
  ls -la /usr/share/blanket 2>&1
  echo "=== /usr/share/blanket/screensaver ==="
  ls -la /usr/share/blanket/screensaver 2>&1
  echo "--- readlink ---"
  readlink /usr/share/blanket/screensaver 2>&1
  echo "=== ad screensaver dir ==="
  ls -la /usr/share/blanket/ad_screensaver 2>&1
  echo "=== special offers? ==="
  lipc-get-prop com.lab126.deviced specialOffers 2>&1
  lipc-get-prop com.lab126.blanket load 2>&1

  echo "=== mount ==="
  mount 2>&1
  echo "=== rootfs writable test (mntroot) ==="
  which mntroot 2>&1

  echo "=== cron ==="
  ls -la /etc/crontab 2>&1
  ls -la /etc/crontab/ 2>&1
  echo "--- /etc/crontab/root ---"
  cat /etc/crontab/root 2>&1
  initctl status cron 2>&1
  ps 2>&1 | grep -i cron

  echo "=== screensaver work dir ==="
  ls -la /mnt/us/screensaver 2>&1
  ls -la /mnt/us/screensaver/images 2>&1

  echo "=== uptime (a small number means it rebooted recently) ==="
  cat /proc/uptime 2>&1
  up=$(cut -d. -f1 /proc/uptime 2>/dev/null)
  echo "uptime seconds: ${up:-unknown}"
  echo "boot epoch: $(( $(date +%s) - ${up:-0} ))"
  echo "now epoch: $(date +%s)"

  echo "=== tools available ==="
  for t in timeout wget setsid nohup pkill lipc-set-prop lipc-get-prop fbink eips xh; do
    printf '%s: ' "$t"
    which "$t" 2>/dev/null || echo "(not in PATH)"
  done
  ls -l /mnt/us/screensaver/xh /mnt/us/libkh/bin/fbink /mnt/us/koreader/fbink 2>&1

  echo "=== wi-fi state ==="
  lipc-get-prop com.lab126.wifid cmState 2>&1
  lipc-get-prop com.lab126.wifid currentEssid 2>&1
  echo "--- default route ---"
  cat /proc/net/route 2>&1

  echo "=== live server check (timed) ==="
  url=$(head -n 1 /mnt/us/screensaver/server.txt 2>/dev/null | tr -d '\r\n')
  base=${url%/*}
  t0=$(date +%s)
  if [ -x /mnt/us/screensaver/xh ]; then
    /mnt/us/screensaver/xh -q -o /dev/null get "$base/health" >/dev/null 2>&1
    echo "xh /health exit=$? took $(( $(date +%s) - t0 ))s"
  fi
  t0=$(date +%s)
  lipc-set-prop com.lab126.cmd wirelessEnable 1 >/dev/null 2>&1
  echo "wirelessEnable nudge exit=$? took $(( $(date +%s) - t0 ))s"

  echo "=== our processes running? ==="
  ps 2>&1 | grep -E 'wall\.sh|fetch\.sh|suspend_test' | grep -v grep

  echo "=== /sys/power/state (supported sleep states) ==="
  cat /sys/power/state 2>&1
  echo "=== wpa_cli / supplicant ==="
  which wpa_cli wpa_supplicant 2>&1
  ls -l /var/run/wpa_supplicant 2>&1
  echo "=== charging / powerd ==="
  lipc-get-prop com.lab126.powerd isCharging 2>&1
  lipc-get-prop -i com.lab126.powerd isCharging 2>&1
  lipc-get-prop com.lab126.powerd status 2>&1
  echo "=== last lines of wall.log ==="
  tail -n 20 /mnt/us/screensaver/logs/wall.log 2>&1
  echo "=== last lines of suspend.log ==="
  tail -n 20 /mnt/us/screensaver/logs/suspend.log 2>&1

  echo "=== done ==="
} >"$OUT" 2>&1

echo "wrote $OUT"
