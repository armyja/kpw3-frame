#!/usr/bin/env sh
# Install (or refresh) the cron entry that periodically fetches a new image.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

BASE=/mnt/us/screensaver
LOG="$BASE/logs/enable.log"

# shellcheck disable=SC1090
[ -f "$BASE/env.sh" ] && . "$BASE/env.sh"

# The Kindle keeps its cron jobs in /etc/crontab/root.
if [ -d /etc/crontab ]; then
  CRON=/etc/crontab/root
else
  CRON=/etc/crontab
fi

LINE="$FETCH_SCHEDULE /bin/sh $BASE/fetch.sh >> $BASE/logs/cron.log 2>&1"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"; }

mntroot rw >/dev/null 2>&1

if [ ! -f "$CRON" ]; then
  touch "$CRON" 2>>"$LOG" && log "created $CRON"
fi

if [ -f "$CRON" ]; then
  grep -v "screensaver/fetch.sh" "$CRON" >"$CRON.tmp" 2>/dev/null && mv "$CRON.tmp" "$CRON"
  echo "$LINE" >>"$CRON"
  log "cron installed in $CRON"
else
  log "WARN: no cron file at $CRON; periodic fetch was NOT installed"
fi

mntroot ro >/dev/null 2>&1

# Make sure crond notices.
initctl restart cron >/dev/null 2>&1

log "--- $CRON ---"
cat "$CRON" >>"$LOG" 2>&1
