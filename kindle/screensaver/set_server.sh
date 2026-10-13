#!/usr/bin/env sh
# Server settings for the KPW3 screensaver (called from KUAL).
#
#   set_server.sh show     show the server the frame is currently using
#   set_server.sh test     fetch once and report success/failure on screen
#   set_server.sh detect   scan the Wi-Fi for the frame server and use it
#
# The address lives in /mnt/us/screensaver/server.txt (one line), so it can
# also be edited straight from a PC over USB.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

BASE=/mnt/us/screensaver
. "$BASE/common.sh"

LOG="$LOGS/server.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"; }

kindle_ip() {
  ip=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9][0-9.]*\).*/\1/p' | head -n 1)
  [ -n "$ip" ] || ip=$(ifconfig 2>/dev/null | sed -n 's/.*inet addr:\([0-9][0-9.]*\).*/\1/p' | grep -v '^127\.' | head -n 1)
  printf '%s' "$ip"
}

cmd_show() {
  load_server
  log "show: $FRAME_URL"
  say "Frame server:

$FRAME_URL

To change it: put the new address in
server.txt (over USB), or use
Server > Auto-detect"
}

cmd_test() {
  load_server
  tmp="$BASE/.test.$$.png"
  if http_get "$FRAME_URL" "$tmp"; then
    size=$(wc -c <"$tmp" 2>/dev/null | tr -d ' ')
    rm -f "$tmp"
    log "test OK: $FRAME_URL ($size bytes)"
    say "Server OK

$FRAME_URL

got $size bytes"
  else
    rm -f "$tmp"
    log "test FAILED: $FRAME_URL"
    say "Server NOT reachable

$FRAME_URL

Check Wi-Fi and that the image
server is running on the PC"
  fi
}

cmd_detect() {
  load_server

  if http_ok "$SERVER_BASE/health"; then
    log "detect: already reachable: $FRAME_URL"
    say "Server already OK

$FRAME_URL"
    return 0
  fi

  myip=$(kindle_ip)
  prefix=$(printf '%s' "$myip" | cut -d. -f1-3)
  if [ -z "$myip" ] || [ -z "$prefix" ]; then
    log "detect: no Wi-Fi address"
    say "No Wi-Fi address

Turn Wi-Fi on and try again"
    return 1
  fi

  log "detect: scanning $prefix.0/24 for $SERVER_SCHEME://*:$SERVER_PORT/health"
  [ -n "$FBINK" ] && "$FBINK" -c -f -m -M "Scanning Wi-Fi for the frame server..." >/dev/null 2>&1

  scanfile="$BASE/.scan.$$.txt"
  rm -f "$scanfile"

  i=1
  while [ "$i" -le 254 ]; do
    n=0
    while [ "$n" -lt 16 ] && [ "$i" -le 254 ]; do
      (
        if http_ok "$SERVER_SCHEME://$prefix.$i:$SERVER_PORT/health"; then
          echo "$prefix.$i" >>"$scanfile"
        fi
      ) &
      i=$((i + 1))
      n=$((n + 1))
    done
    wait
    [ -s "$scanfile" ] && break
  done

  ip=$(head -n 1 "$scanfile" 2>/dev/null)
  rm -f "$scanfile"

  if [ -z "$ip" ]; then
    log "detect: no server found on $prefix.0/24"
    say "No frame server found

Make sure the PC server is running,
then try again - or set server.txt
from a PC over USB"
    return 1
  fi

  newurl="$SERVER_SCHEME://$ip:$SERVER_PORT/${FRAME_URL##*/}"
  printf '%s\n' "$newurl" >"$SERVER_FILE"
  log "detect: found $ip -> $newurl"

  if "$BASE/fetch.sh" --force >>"$LOG" 2>&1; then
    say "Server found

$newurl

Screensaver image updated"
  else
    say "Server found: $ip

but fetching the image failed"
  fi
}

case "$1" in
  show) cmd_show ;;
  test) cmd_test ;;
  detect) cmd_detect ;;
  *) echo "usage: $0 show|test|detect" ;;
esac
