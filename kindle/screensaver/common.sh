#!/usr/bin/env sh
# Shared config/helpers for the KPW3 screensaver scripts.

BASE=/mnt/us/screensaver
IMAGES="$BASE/images"
LOGS="$BASE/logs"
SERVER_FILE="$BASE/server.txt"

mkdir -p "$LOGS" 2>/dev/null

# Pull in the user config right away, so every script sees SINGLE_IMAGE,
# WALL_* ... even if it never calls load_server.
# shellcheck disable=SC1090
[ -f "$BASE/env.sh" ] && . "$BASE/env.sh"

# Preferred tool for on-screen messages (fall back to eips).
FBINK=""
for candidate in /mnt/us/libkh/bin/fbink /mnt/us/koreader/fbink /usr/bin/fbink; do
  [ -f "$candidate" ] && { FBINK="$candidate"; break; }
done

# Resolve the server URL. server.txt (one line) wins; otherwise env.sh FRAME_URL.
# Sets: FRAME_URL, SERVER_BASE, SERVER_SCHEME, SERVER_HOST, SERVER_PORT
load_server() {
  # shellcheck disable=SC1090
  [ -f "$BASE/env.sh" ] && . "$BASE/env.sh"

  if [ -s "$SERVER_FILE" ]; then
    FRAME_URL=$(head -n 1 "$SERVER_FILE" | tr -d '\r\n')
  fi
  FRAME_URL=${FRAME_URL:-"http://192.168.1.63:8000/frame"}

  SERVER_BASE=${FRAME_URL%/*}            # http://host:port
  SERVER_SCHEME=${SERVER_BASE%%://*}     # http
  hostport=${SERVER_BASE#*://}           # host:port
  case "$hostport" in
    *:*) SERVER_HOST=${hostport%:*}; SERVER_PORT=${hostport##*:} ;;
    *)   SERVER_HOST=$hostport;      SERVER_PORT=80 ;;
  esac
}

# Draw a message on the e-ink panel and keep it there for a few seconds.
say() {
  message=$1
  seconds=${SAY_SECONDS:-12}

  if [ -n "$FBINK" ]; then
    "$FBINK" -c -f -m -M "$message" >/dev/null 2>&1
  else
    /usr/sbin/eips -c >/dev/null 2>&1
    row=4
    printf '%s\n' "$message" | while IFS= read -r line; do
      /usr/sbin/eips "$row" 3 "$line" >/dev/null 2>&1
      row=$((row + 2))
    done
  fi

  sleep "$seconds"
}

# Run a command under a hard timeout when the system has `timeout`.
run_timeout() {
  secs=$1
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# HTTP
#
# We prefer the Kindle's own /usr/bin/wget (a small busybox applet on the root
# filesystem).  It only speaks plain HTTP, which is all our server needs, and -
# unlike the 7 MB xh binary living on /mnt/us (a FUSE mount) - it does not
# depend on the FUSE daemon being fully awake right after a suspend.
# xh is kept as a fallback.
# ---------------------------------------------------------------------------

http_ok() {
  url=$1
  if command -v wget >/dev/null 2>&1; then
    wget -q -T 4 -O /dev/null "$url" >/dev/null 2>&1
  else
    run_timeout 6 "$BASE/xh" -q -o /dev/null get "$url" >/dev/null 2>&1
  fi
}

# http_get URL OUTFILE
# Downloads to tmpfs first (a slow FUSE write must not make the socket time
# out), tries wget with a generous timeout, then falls back to xh.
# NOTE: all internal variables are prefixed so this can never clobber the
# caller's variables (a shared name once silently threw away downloads).
http_get() {
  _dl_url=$1
  _dl_out=$2
  _dl_tmp="/tmp/kpw3.dl.$$"
  rm -f "$_dl_tmp"

  if command -v wget >/dev/null 2>&1; then
    if wget -q -T 60 -O "$_dl_tmp" "$_dl_url" >>"$LOGS/http.log" 2>&1; then
      cp -f "$_dl_tmp" "$_dl_out" && { rm -f "$_dl_tmp"; return 0; }
    fi
    echo "$(date '+%F %T') wget failed for $_dl_url (see line above); trying xh" >>"$LOGS/http.log"
  fi

  if run_timeout 90 "$BASE/xh" -q -o "$_dl_tmp" get "$_dl_url" >>"$LOGS/http.log" 2>&1; then
    cp -f "$_dl_tmp" "$_dl_out" && { rm -f "$_dl_tmp"; return 0; }
  fi

  rm -f "$_dl_tmp"
  return 1
}

# One-line network state, for logging (ip / default route / wi-fi state).
net_state() {
  ip=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9][0-9.]*\).*/\1/p' | head -n 1)
  route=$(awk '$1 == "wlan0" && $2 == "00000000" { found = 1 } END { print (found ? "yes" : "no") }' /proc/net/route 2>/dev/null)
  cm=$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)
  printf 'ip=%s route=%s cm=%s' "${ip:-none}" "${route:-?}" "${cm:-?}"
}

# Verbose probe used to explain "woke up but cannot reach the server".
# Assumes load_server has run. Prints a compact line.
net_probe() {
  pg=no
  ps=no
  wg=no
  xho=no

  ping -c 1 -W 2 192.168.1.1 >/dev/null 2>&1 && pg=yes
  ping -c 1 -W 2 "$SERVER_HOST" >/dev/null 2>&1 && ps=yes

  if command -v wget >/dev/null 2>&1; then
    wget -q -T 4 -O /dev/null "$SERVER_BASE/health" >/dev/null 2>&1 && wg=yes
  fi

  xhout=$("$BASE/xh" --timeout 3 -q -o /dev/null get "$SERVER_BASE/health" 2>&1)
  xhrc=$?
  [ "$xhrc" -eq 0 ] && xho=yes

  printf 'ping-gw=%s ping-srv=%s wget=%s xh=%s' "$pg" "$ps" "$wg" "$xho"
  [ -n "$xhout" ] && printf ' xh-err=[%s]' "$(printf '%.90s' "$xhout")"
  printf ' %s' "$(net_state)"
}

# Actively ask the Wi-Fi supplicant to reconnect - much faster than waiting for
# the power management to bring the radio back by itself.
kick_wifi() {
  if command -v wpa_cli >/dev/null 2>&1; then
    wpa_cli -i wlan0 reconnect >/dev/null 2>&1
    wpa_cli -i wlan0 reassociate >/dev/null 2>&1
    return 0
  fi
  return 1
}

# Charging state as reported by powerd ("1" = charging / on USB power).
charge_state() {
  v=$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)
  [ -z "$v" ] && v=$(lipc-get-prop -i com.lab126.powerd isCharging 2>/dev/null)
  printf '%s' "${v:-?}"
}

# Ask the server how often it wants to be polled.
# /health answers "ok" or "ok <seconds>"; prints the seconds (or nothing).
server_interval() {
  if command -v wget >/dev/null 2>&1; then
    body=$(run_timeout 8 wget -q -T 5 -O - "$SERVER_BASE/health" 2>/dev/null | head -n 1)
  else
    body=$(run_timeout 8 "$BASE/xh" -q get "$SERVER_BASE/health" 2>/dev/null | head -n 1)
  fi
  case "$body" in
    ok\ [0-9]*) printf '%s' "${body#ok }" ;;
    *) printf '' ;;
  esac
}

# Keep only SLOT_COUNT screensaver slots. Each slot is a full-size PNG write, so
# 20 slots meant ~7 MB of copying per update; the renderer only shows one of
# them and in single-image mode they are all identical. Creates missing slots
# and deletes higher-numbered ones (so no stale picture can be picked).
ensure_slots() {
  keep=${SLOT_COUNT:-1}
  case "$keep" in '' | *[!0-9]*) keep=1 ;; esac
  [ "$keep" -lt 1 ] && keep=1

  i=0
  while [ "$i" -lt "$keep" ]; do
    slot=$(printf '%s/bg_ss%02d.png' "$IMAGES" "$i")
    [ -f "$slot" ] || cp -f "$BASE/placeholder.png" "$slot" 2>/dev/null
    i=$((i + 1))
  done

  for f in "$IMAGES"/bg_ss*.png; do
    [ -f "$f" ] || continue
    num=${f##*/bg_ss}
    num=${num%.png}
    num=${num#0}
    case "$num" in '' | *[!0-9]*) continue ;; esac
    if [ "$num" -ge "$keep" ]; then
      rm -f "$f"
      echo "removed extra slot $(basename "$f") (SLOT_COUNT=$keep)"
    fi
  done
}

# Persist the interval into env.sh (atomic rename) so the next cycle picks it
# up. Returns 0 when env.sh was rewritten.
save_interval() {
  secs=$1
  case "$secs" in '' | *[!0-9]*) return 1 ;; esac
  f="$BASE/env.sh"
  [ -f "$f" ] || return 1

  tmp="$BASE/.env.new"
  replaced=no
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "export WALL_INTERVAL="*)
        printf 'export WALL_INTERVAL=${WALL_INTERVAL:-%s}\n' "$secs"
        replaced=yes
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <"$f" >"$tmp"

  if [ "$replaced" = no ]; then
    printf 'export WALL_INTERVAL=${WALL_INTERVAL:-%s}\n' "$secs" >>"$tmp"
  fi
  mv -f "$tmp" "$f" 2>/dev/null || return 1
  return 0
}

# ---------------------------------------------------------------------------
# RTC wake alarms (modern Kindles: /sys/class/rtc/rtcN/wakealarm).
# ---------------------------------------------------------------------------

# arm_alarm SECONDS -> prints the alarm path on success, nothing on failure.
arm_alarm() {
  secs=$1
  for rtc in /sys/class/rtc/rtc1 /sys/class/rtc/rtc0 /sys/class/rtc/rtc2; do
    [ -w "$rtc/wakealarm" ] || continue
    now=$(cat "$rtc/since_epoch" 2>/dev/null)
    case "$now" in '' | *[!0-9]*) now=$(date +%s) ;; esac
    target=$((now + secs))
    echo 0 >"$rtc/wakealarm" 2>/dev/null
    echo "$target" >"$rtc/wakealarm" 2>/dev/null
    if [ "$(cat "$rtc/wakealarm" 2>/dev/null)" = "$target" ]; then
      echo "$rtc/wakealarm"
      return 0
    fi
  done
  return 1
}

clear_alarm() {
  [ -n "$1" ] && echo 0 >"$1" 2>/dev/null
  return 0
}
