#!/usr/bin/env sh
# Fetch an image from the server and put it on the screensaver.
#
# SINGLE_IMAGE=yes (default): the fetched image is copied to *every* slot, so
#                             every lock screen shows the same picture.
# SINGLE_IMAGE=no:            rotate through the slots, one per invocation.
#
# The server URL is read from server.txt (one line) or env.sh FRAME_URL.
# Pass --force to re-apply even when the picture did not change.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

BASE=/mnt/us/screensaver
. "$BASE/common.sh"
load_server

LOG="$LOGS/fetch.log"
STATE="$BASE/slot"
CURRENT="$BASE/current.png"
FORCE="$1"
DL="$BASE/new.$$.png"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"; }

# Clean up leftovers from an interrupted run.
rm -f "$BASE"/new.*.png 2>/dev/null

# Keep only a few screensaver slots (see ensure_slots in common.sh).
SLOT_COUNT=${SLOT_COUNT:-1}
ensure_slots

slots=$(ls "$IMAGES"/bg_ss*.png 2>/dev/null)
if [ -z "$slots" ]; then
  log "ERROR: no bg_ss*.png slots in $IMAGES"
  exit 1
fi
count=$(printf '%s\n' "$slots" | wc -l | tr -d ' ')

rm -f "$DL"
if ! http_get "$FRAME_URL" "$DL"; then
  rm -f "$DL"
  log "ERROR: fetch failed from $FRAME_URL"
  exit 1
fi

if [ "$SINGLE_IMAGE" = "yes" ]; then
  if [ "$FORCE" != "--force" ] && [ -f "$CURRENT" ] && cmp -s "$DL" "$CURRENT"; then
    rm -f "$DL"
    log "image unchanged; nothing to do"
    exit 0
  fi
  cp -f "$DL" "$CURRENT"
  rm -f "$DL"
  for f in $slots; do cp "$CURRENT" "$f"; done
  log "applied the same image to $count slot(s)"
else
  slot=$(cat "$STATE" 2>/dev/null)
  case "$slot" in '' | *[!0-9]*) slot=0 ;; esac
  slot=$((slot % count))
  target=$(printf '%s\n' "$slots" | sed -n "$((slot + 1))p")

  cp -f "$DL" "$target"
  rm -f "$DL"
  cp -f "$target" "$CURRENT"
  echo $(((slot + 1) % count)) >"$STATE"
  log "updated $(basename "$target") (slot $slot/$count)"
fi
