#!/usr/bin/env bash
# Exercises the real server_interval() / save_interval() from common.sh on a
# normal shell (run with Git Bash on Windows - no Kindle needed).
#
# Usage: server_interval_test.sh <project-root>
set -u

PROJ="$1"
COMMON="$PROJ/kindle/screensaver/common.sh"
ENVSH="$PROJ/kindle/screensaver/env.sh"

# shellcheck disable=SC1090
. "$COMMON"   # defines the functions; sets BASE to the Kindle path

BASE=/tmp/kpw3test
LOGS="$BASE/logs"
STUB="$BASE/stub"
mkdir -p "$LOGS" "$BASE/images" "$STUB"
cp "$ENVSH" "$BASE/env.sh"

# A real executable stub on PATH, because run_timeout wraps calls in `timeout`,
# which cannot invoke shell functions.
make_wget() {
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$1" >"$STUB/wget"
  chmod +x "$STUB/wget"
  hash -r
}
PATH="$STUB:$PATH"

failures=0
check() {
  if [ "$2" = "$3" ]; then
    echo "  [ok]   $1"
  else
    echo "  [FAIL] $1 (expected '$3', got '$2')"
    failures=$((failures + 1))
  fi
}

SERVER_BASE="http://example"

# --- server_interval parses "ok <seconds>" --------------------------------
make_wget "ok 777"
check "parses 'ok 777'" "$(server_interval)" "777"

make_wget "ok"
check "'ok' alone -> empty" "$(server_interval)" ""

make_wget "garbage"
check "garbage -> empty" "$(server_interval)" ""

make_wget "ok abc"
check "non-numeric -> empty" "$(server_interval)" ""

# --- save_interval rewrites env.sh ---------------------------------------
save_interval 555
check "save_interval returns 0" "$?" "0"
line=$(grep '^export WALL_INTERVAL=' "$BASE/env.sh")
check "env.sh patched" "$line" 'export WALL_INTERVAL=${WALL_INTERVAL:-555}'

count_before=$(wc -l <"$BASE/env.sh")
save_interval 555
count_after=$(wc -l <"$BASE/env.sh")
check "idempotent line count" "$count_before" "$count_after"

if grep -q '^export FETCH_SCHEDULE=' "$BASE/env.sh" && grep -q '^export SINGLE_IMAGE=' "$BASE/env.sh"; then
  echo "  [ok]   other settings untouched"
else
  echo "  [FAIL] other settings were lost"
  failures=$((failures + 1))
fi

# CRLF in the source must not survive
printf 'A=1\r\nexport WALL_INTERVAL=${WALL_INTERVAL:-1}\r\n' >"$BASE/env.sh"
save_interval 90
if grep -q $'\r' "$BASE/env.sh"; then
  echo "  [FAIL] CRLF left in env.sh"
  failures=$((failures + 1))
else
  echo "  [ok]   CRLF removed"
fi

# missing line gets appended
printf 'A=1\n' >"$BASE/env.sh"
save_interval 42
check "appended when missing" "$(grep -c '^export WALL_INTERVAL=' "$BASE/env.sh")" "1"

# --- ensure_slots: prunes / recreates the screensaver slots ---------------
IMAGES="$BASE/images"
printf 'x' >"$BASE/placeholder.png"

slots_list() { ls "$IMAGES"/bg_ss*.png 2>/dev/null | wc -l | tr -d ' '; }

# start with 6 slots, ask for 1
rm -f "$IMAGES"/bg_ss*.png
i=0
while [ "$i" -lt 6 ]; do printf 'img%s' "$i" >"$(printf '%s/bg_ss%02d.png' "$IMAGES" "$i")"; i=$((i + 1)); done
check "6 slots present" "$(slots_list)" "6"

SLOT_COUNT=1
ensure_slots >/dev/null
check "SLOT_COUNT=1 -> 1 slot" "$(slots_list)" "1"
check "kept bg_ss00" "$([ -f "$IMAGES/bg_ss00.png" ] && echo yes)" "yes"
check "bg_ss01 gone" "$([ -f "$IMAGES/bg_ss01.png" ] && echo yes || echo no)" "no"

# ask for 4 again -> recreated from the placeholder
SLOT_COUNT=4
ensure_slots >/dev/null
check "SLOT_COUNT=4 -> 4 slots" "$(slots_list)" "4"

# only numbered slots are touched
printf 'other' >"$IMAGES/bg_kids_ss00.png"
printf 'big' >"$IMAGES/bg_ss100.png"
SLOT_COUNT=2
ensure_slots >/dev/null
check "kids image untouched" "$([ -f "$IMAGES/bg_kids_ss00.png" ] && echo yes)" "yes"
check "2 slots after prune" "$(slots_list)" "2"

# garbage / zero values clamp to 1
SLOT_COUNT=abc
ensure_slots >/dev/null
check "garbage clamps to 1" "$(slots_list)" "1"
SLOT_COUNT=0
ensure_slots >/dev/null
check "zero clamps to 1" "$(slots_list)" "1"

rm -rf "$BASE"
if [ "$failures" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
else
  echo "$failures CHECK(S) FAILED"
  exit 1
fi
