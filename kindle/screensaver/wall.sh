#!/usr/bin/env sh
# "Wall display": fetch an image, show it full-screen, deep-sleep, and let the
# RTC hardware alarm wake the device to do it again.
#
# It leaves the Kindle UI alone (no takeover / no framework stop), which keeps
# the suspend path that the suspend test proved safe, and means there is nothing
# to restore when it stops. KUAL stays reachable the whole time.
#
#   wall.sh start     start the loop in the background (needs suspend.ok)
#   wall.sh run       run the loop (this is what start launches)
#   wall.sh stop      ask the loop to stop
#
# Tunables (env.sh or environment): WALL_INTERVAL (default 900s),
# WALL_WIFI_WAIT (default 90s).
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

BASE=/mnt/us/screensaver
. "$BASE/common.sh"

LOG="$LOGS/wall.log"
PIDFILE="$BASE/wall.pid"
STOPFILE="$BASE/wall.stop"
LASTIMG="$BASE/wall.png"
INTERVAL=${WALL_INTERVAL:-900}
WIFI_WAIT=${WALL_WIFI_WAIT:-90}

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"; }

# Tell "exited" apart from "got killed" in the log.
trap 'log "EXIT (status $?)"' EXIT
trap 'log "SIGNAL TERM -> exiting"; exit 143' TERM
trap 'log "SIGNAL HUP -> exiting"; exit 129' HUP
trap 'log "SIGNAL INT -> exiting"; exit 130' INT

# Same, but with a renderer that WAITS for the panel to finish refreshing.
# eips does wait_for_complete after a flashing image refresh; fbink does not.
# Use this for the very last paint before sleeping, so the device never
# suspends in the middle of a refresh (that garbles the screen).
draw_final() {
  [ -f "$1" ] || return 1
  /usr/sbin/eips -f -g "$1" >/dev/null 2>&1
}

# Path of the newest image we have: wall.png from this session, else the last
# fetched current.png.
current_img() {
  if [ -f "$LASTIMG" ]; then
    printf '%s' "$LASTIMG"
  elif [ -f "$BASE/current.png" ]; then
    printf '%s' "$BASE/current.png"
  fi
}

# Wait until the server answers. Re-enables the radio first (Kindle radios are
# off while suspended and can take a while to come back), and never blocks on
# that call.
wifi_up() {
  log "waiting for the server (charging=$(charge_state), $(net_state))"
  start=$(date +%s)
  deadline=$(( start + WIFI_WAIT ))
  n=0
  kicked=no
  while [ "$(date +%s)" -lt "$deadline" ]; do
    n=$((n + 1))
    if http_ok "$SERVER_BASE/health"; then
      log "server reachable after $(( $(date +%s) - start ))s"
      return 0
    fi
    el=$(( $(date +%s) - start ))
    # Passive by default: the radio normally comes back on its own, and poking
    # wpa_cli tears a working link down. Only escalate when clearly stuck.
    if [ "$kicked" = no ] && [ "$el" -ge "${WALL_KICK_AFTER:-60}" ]; then
      log "still unreachable after ${el}s -> poking the radio"
      run_timeout 8 lipc-set-prop com.lab126.cmd wirelessEnable 1 >/dev/null 2>&1
      kick_wifi && log "asked wpa_cli to reconnect"
      kicked=yes
    fi
    [ $((n % 5)) -eq 1 ] && log "  waiting ($el s, $(net_state))"
    sleep 1
  done
  log "server not reachable within ${WIFI_WAIT}s ($(net_state))"
  return 1
}

fetch_image() {
  load_server
  t0=$(date +%s)
  if wifi_up; then
    sync_interval # the server tells us how often it wants to be polled
    sleep "${WALL_SETTLE:-1}"
    n=0
    while [ "$n" -lt 3 ]; do
      if "$BASE/fetch.sh"; then
        [ -f "$BASE/current.png" ] && cp -f "$BASE/current.png" "$LASTIMG"
        log "fetched in $(( $(date +%s) - t0 ))s"
        return 0
      fi
      n=$((n + 1))
      log "fetch attempt $n failed; retrying in 2s"
      sleep 2
    done
    log "fetch failed after 3 attempts"
  else
    log "no server within ${WIFI_WAIT}s"
  fi
  return 1
}

# Suspend for $1 seconds. Returns 0 on a normal (RTC) wake, 1 if woken early
# (the user pressed the power button). Never suspends without an armed alarm.
suspend_for() {
  secs=$1

  alarm=$(arm_alarm "$secs")
  if [ -z "$alarm" ]; then
    log "could not arm any RTC alarm: sleeping ${secs}s awake"
    sleep "$secs"
    return 0
  fi
  log "armed $alarm for ${secs}s"

  # Ask for the radio to stay on, so it can reconnect faster after the wake.
  lipc-set-prop com.lab126.cmd wirelessEnable 1 >/dev/null 2>&1

  PM_STATE=${WALL_PM_STATE:-mem}
  log "suspending via /sys/power/state = $PM_STATE (charging=$(charge_state))"

  # The very last action before sleeping. WALL_DRAW=no skips it (test mode: see
  # whether the stock screensaver draws instead).
  if [ "${WALL_DRAW:-yes}" = "yes" ]; then
    img=$(current_img)
    if [ -n "$img" ]; then
      paint_start=$(date +%s)
      log "final paint: $(basename "$img")"
      draw_final "$img"
      log "painted in $(( $(date +%s) - paint_start ))s"
    else
      log "no image to paint"
    fi
  fi

  t0=$(date +%s)
  if ! echo "$PM_STATE" >/sys/power/state; then
    clear_alarm "$alarm"
    log "suspend failed"
    sleep "$secs"
    return 0
  fi
  t1=$(date +%s)
  elapsed=$((t1 - t0))
  clear_alarm "$alarm"
  log "slept ${elapsed}s (asked ${secs}s)"

  [ "$elapsed" -lt $((secs - 30)) ] && return 1
  return 0
}

# Ask the server for its refresh interval and store it in env.sh. The loop
# re-reads env.sh every cycle, so the new value takes effect on the next wake -
# no USB, no restart.
sync_interval() {
  want=$(server_interval)
  if [ -n "$want" ] && [ "$want" != "$INTERVAL" ]; then
    log "server asks for ${want}s (was ${INTERVAL}s) -> saving to env.sh"
    save_interval "$want" && INTERVAL=$want
  fi
}

run_loop() {
  echo $$ >"$PIDFILE"
  load_server
  log "=== wall display started (every ${INTERVAL}s, server $FRAME_URL) ==="

  while [ ! -f "$STOPFILE" ]; do
    # Pick up env.sh changes (e.g. written over USB by the phone app) without a
    # restart. Our copies are cleared first because env.sh uses ${VAR:-default}
    # and would otherwise keep the old values.
    unset WALL_INTERVAL WALL_WIFI_WAIT WALL_PM_STATE WALL_KICK_AFTER SINGLE_IMAGE FRAME_URL FETCH_SCHEDULE
    # shellcheck disable=SC1090
    . "$BASE/env.sh" 2>/dev/null
    INTERVAL=${WALL_INTERVAL:-900}
    WIFI_WAIT=${WALL_WIFI_WAIT:-240}
    cycle_start=$(date +%s)

    # Stay safe while awake: if power management suspends us during the fetch,
    # this alarm still brings us back.
    safety=$(arm_alarm 300)

    log "cycle: fetching"
    fetch_image || log "keeping the previous image"

    clear_alarm "$safety"
    log "wake-to-sleep prep took $(( $(date +%s) - cycle_start ))s"

    if ! suspend_for "$INTERVAL"; then
      log "woken early (power button) -> stopping"
      break
    fi
  done

  rm -f "$PIDFILE"
  log "=== wall display stopped ==="
}

cmd_start() {
  if [ ! -f "$BASE/suspend.ok" ]; then
    say "Run the suspend test first

The wall display only starts after
Wall display > Suspend test (1 min)
reports PASS."
    exit 1
  fi
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    say "Wall display is already running"
    exit 0
  fi

  rm -f "$STOPFILE"
  ("$BASE/wall.sh" run >>"$LOG" 2>&1 &)
  sleep 1
  # Show the message in the background: a long-running action keeps KUAL busy,
  # and re-entering KUAL while it is still finishing makes KUAL look stuck.
  (SAY_SECONDS=8 say "Wall display started

Updates every ${INTERVAL}s.
Press the power button once to stop." >/dev/null 2>&1) &
}

cmd_stop() {
  touch "$STOPFILE"
  pid=$(cat "$PIDFILE" 2>/dev/null)
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  rm -f "$PIDFILE"
  # Backgrounded for the same reason as cmd_start.
  (SAY_SECONDS=8 say "Wall display stopped

If the screen does not change,
press the power button once." >/dev/null 2>&1) &
}

case "$1" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  run) run_loop ;;
  *) echo "usage: $0 start|stop|run" ;;
esac
