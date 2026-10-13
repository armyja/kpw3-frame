#!/usr/bin/env sh
# Undo enable.sh: restore the stock screensaver directory and remove the cron job.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

BASE=/mnt/us/screensaver
LOG="$BASE/logs/enable.log"
BLANKET=/usr/share/blanket/screensaver

mkdir -p "$BASE/logs"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"; }

log "=== disable custom screensaver ==="

if [ -d /etc/crontab ]; then
  CRON=/etc/crontab/root
else
  CRON=/etc/crontab
fi

mntroot rw >>"$LOG" 2>&1

if [ -L "$BLANKET" ]; then
  rm -f "$BLANKET" && log "removed symlink $BLANKET"
fi
if [ -d "$BLANKET.orig" ] && [ ! -e "$BLANKET" ]; then
  mv "$BLANKET.orig" "$BLANKET" && log "restored $BLANKET from $BLANKET.orig"
fi

if [ -f "$CRON" ]; then
  grep -v "screensaver/fetch.sh" "$CRON" >"$CRON.tmp" 2>/dev/null && mv "$CRON.tmp" "$CRON"
  log "removed cron entry from $CRON"
fi

mntroot ro >>"$LOG" 2>&1

initctl restart cron >/dev/null 2>&1
log "=== disabled ==="
