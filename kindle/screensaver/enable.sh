#!/usr/bin/env sh
# Point the stock screensaver directory at /mnt/us/screensaver/images and
# install the periodic fetch. Reversible with disable.sh.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

BASE=/mnt/us/screensaver
IMAGES="$BASE/images"
LOG="$BASE/logs/enable.log"
BLANKET=/usr/share/blanket/screensaver

# shellcheck disable=SC1090
[ -f "$BASE/env.sh" ] && . "$BASE/env.sh"

mkdir -p "$BASE/logs" "$IMAGES"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"; }

log "=== enable custom screensaver ==="

# Keep the server address in a plain one-line file so it is easy to change
# (over USB or via Server > Auto-detect).
if [ ! -s "$BASE/server.txt" ]; then
  printf '%s\n' "${FRAME_URL:-http://192.168.1.63:8000/frame}" >"$BASE/server.txt"
  log "created server.txt: $(cat "$BASE/server.txt")"
fi

log "blanket: $(ls -ld "$BLANKET" 2>&1)"
log "blanket readlink: $(readlink "$BLANKET" 2>&1)"
log "blanket contents: $(ls "$BLANKET" 2>&1 | tr '\n' ' ')"
log "root mount: $(mount 2>&1 | grep ' / ' | tr '\n' ' ')"
log "ad screensaver dir: $(ls -ld /usr/share/blanket/ad_screensaver 2>&1)"
log "crontab: $(ls -ld /etc/crontab /etc/crontab/root 2>&1 | tr '\n' ' ')"

if [ "$(readlink "$BLANKET" 2>/dev/null)" = "$IMAGES" ]; then
  log "already enabled -> $IMAGES"
else
  # Seed the slot names from the current screensaver images, so the file names
  # (bg_ss00.png, ...) match exactly what the renderer expects.
  if [ -d "$BLANKET" ] && [ ! -L "$BLANKET" ]; then
    for f in "$BLANKET"/*.png "$BLANKET"/*.jpg "$BLANKET"/*.jpeg; do
      [ -f "$f" ] || continue
      cp -a "$f" "$IMAGES/" 2>>"$LOG"
    done
    log "seeded from originals: $(ls "$IMAGES" 2>/dev/null | tr '\n' ' ')"
  fi

  # Fallback: create sane slot names if nothing was seeded.
  if [ -z "$(ls "$IMAGES"/bg_ss*.png 2>/dev/null)" ]; then
    log "WARN: nothing seeded; creating placeholder slots bg_ss00..bg_ss05"
    i=0
    while [ "$i" -lt 6 ]; do
      slot=$(printf '%s/bg_ss%02d.png' "$IMAGES" "$i")
      cp -a "$BASE/placeholder.png" "$slot" 2>>"$LOG"
      i=$((i + 1))
    done
  fi

  mntroot rw >>"$LOG" 2>&1
  if [ -d "$BLANKET" ] && [ ! -L "$BLANKET" ]; then
    mv "$BLANKET" "$BLANKET.orig" 2>>"$LOG" && log "moved $BLANKET -> $BLANKET.orig"
  fi
  ln -sfn "$IMAGES" "$BLANKET" 2>>"$LOG" && log "linked $BLANKET -> $IMAGES"
  sync
  mntroot ro >>"$LOG" 2>&1 || { sleep 2; sync; mntroot ro >>"$LOG" 2>&1; }
fi

"$BASE/register_cron.sh"

# Fill the slots now so we don't show a stock screensaver.
log "fetching an image from ${FRAME_URL:-(not set)}"
"$BASE/refill.sh" || log "WARN: initial fetch failed"

log "=== done; slots: $(ls "$IMAGES" 2>/dev/null | tr '\n' ' ') ==="
