#!/usr/bin/env sh
# RTC suspend / wake test.
#
# Arms a hardware wake alarm, suspends to RAM, and checks that the device wakes
# up on its own. It does NOT touch the Kindle UI (no takeover, no framework
# stop): it answers the question "can we suspend with the framework running and
# still be woken by the RTC?".
#
# On success it writes suspend.ok - the wall-display loop refuses to start
# without that file.
#
# Every step is logged to logs/suspend.log, so a hang can be pinpointed.
#
# Usage: suspend_test.sh [seconds]      (default 60)
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

BASE=/mnt/us/screensaver
. "$BASE/common.sh"
load_server

LOG="$LOGS/suspend.log"
OK_FILE="$BASE/suspend.ok"
SECS=${1:-60}

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"; }

# Tell "exited" apart from "got killed" in the log.
trap 'log "EXIT (status $?)"' EXIT
trap 'log "SIGNAL TERM -> exiting"; exit 143' TERM
trap 'log "SIGNAL HUP -> exiting"; exit 129' HUP
trap 'log "SIGNAL INT -> exiting"; exit 130' INT

log "=== suspend test (${SECS}s) pid=$$ ==="

SAY_SECONDS=0 say "Suspend test (${SECS}s)

The screen will go dark now.
It should wake up by itself.

If it does not come back:
hold the power button ~20s."

alarm=$(arm_alarm "$SECS")
if [ -z "$alarm" ]; then
  log "ERROR: could not arm any RTC alarm"
  say "Suspend test: FAILED to arm

No writable /sys/class/rtc/*/wakealarm
accepted the alarm, so nothing was
suspended."
  exit 1
fi
log "armed $alarm for ${SECS}s"
log "charging=$(charge_state) net=$(net_state)"

# Ask for the radio to stay on, so it can reconnect faster after the wake.
lipc-set-prop com.lab126.cmd wirelessEnable 1 >/dev/null 2>&1

PM_STATE=${WALL_PM_STATE:-mem}
log "suspending via /sys/power/state = $PM_STATE"
t0=$(date +%s)
if ! echo "$PM_STATE" >/sys/power/state; then
  clear_alarm "$alarm"
  log "ERROR: suspend failed"
  say "Suspend test: could not suspend"
  exit 1
fi
t1=$(date +%s)
elapsed=$((t1 - t0))
clear_alarm "$alarm"
log "resumed after ${elapsed}s (asked ${SECS}s)"

if [ "$elapsed" -lt $((SECS - 20)) ]; then
  rm -f "$OK_FILE"
  log "RESULT: FAIL - woke too early"
  say "Suspend test: FAIL

Woke after only ${elapsed}s
(asked ${SECS}s), so the alarm did
not do the waking."
  exit 1
fi

# Safety net: we are awake and about to wait. Keep an alarm armed so the device
# can never end up asleep with no wake source if power management suspends us.
safety=$(arm_alarm 300)
log "safety alarm armed: ${safety:-NONE}"

WAIT=${WALL_WIFI_WAIT:-240}
log "waiting for the server (charging=$(charge_state), $(net_state))"

wifi=no
wstart=$(date +%s)
n=0
kicked=no
while [ $(( $(date +%s) - wstart )) -lt "$WAIT" ]; do
  n=$((n + 1))
  if http_ok "$SERVER_BASE/health"; then
    wifi=yes
    break
  fi
  el=$(( $(date +%s) - wstart ))
  # Passive by default; only poke the radio if clearly stuck.
  if [ "$kicked" = no ] && [ "$el" -ge "${WALL_KICK_AFTER:-60}" ]; then
    log "still unreachable after ${el}s -> poking the radio"
    run_timeout 8 lipc-set-prop com.lab126.cmd wirelessEnable 1 >/dev/null 2>&1
    kick_wifi && log "asked wpa_cli to reconnect"
    kicked=yes
  fi
  log "  attempt $n at ${el}s: $(net_probe)"
  sleep 3
done
took=$(( $(date +%s) - wstart ))
log "server after resume: $wifi (took ${took}s of ${WAIT}s, $(net_state))"
clear_alarm "$safety"

touch "$OK_FILE"
log "RESULT: PASS (wifi=$wifi)"

if [ "$wifi" = yes ]; then
  say "Suspend test: PASS

Woke up by itself after ${elapsed}s
and the server answered in ${took}s.

The wall display can be enabled."
else
  say "Suspend test: PASS (with caveat)

Woke up by itself after ${elapsed}s,
but the server did not answer within
${WAIT}s.

The wall loop will keep the current
image and retry on the next wake."
fi
exit 0
