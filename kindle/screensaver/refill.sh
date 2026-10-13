#!/usr/bin/env sh
# Grab a fresh image now (KUAL "Refresh image now").
# Single-image mode: one fetch (it fills every slot).
# Rotating mode:     one fetch per slot.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

BASE=/mnt/us/screensaver
. "$BASE/common.sh"
load_server

if [ "$SINGLE_IMAGE" = "yes" ]; then
  "$BASE/fetch.sh" --force
  exit $?
fi

slots=$(ls "$IMAGES"/bg_ss*.png 2>/dev/null | wc -l | tr -d ' ')
case "$slots" in '' | *[!0-9]*) slots=0 ;; esac

i=0
while [ "$i" -lt "$slots" ]; do
  "$BASE/fetch.sh" || break
  i=$((i + 1))
done
