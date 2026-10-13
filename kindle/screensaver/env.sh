#!/usr/bin/env sh
# Configuration for the KPW3 frame. Every value has a sensible default, so you
# normally only touch FRAME_URL (or nothing at all - Server > Auto-detect can
# set that for you).
#
# NOTE: WALL_INTERVAL is also driven by the server: /health answers
# "ok <seconds>" and wall.sh writes the new value back into this file.

# Where the picture comes from.
#   /frame               -> whatever the server decides (rotating or pinned)
#   /frame?name=pic.jpg  -> one specific file on the server
export FRAME_URL=${FRAME_URL:-"http://192.168.1.50:8000/frame"}

# Seconds between automatic refreshes (the server may override this).
export WALL_INTERVAL=${WALL_INTERVAL:-900}

# How long to wait for Wi-Fi and the server after each wake.
export WALL_WIFI_WAIT=${WALL_WIFI_WAIT:-240}

# How long to let a freshly reconnected link settle before a big download.
export WALL_SETTLE=${WALL_SETTLE:-1}

# Only poke the radio (wpa_cli reconnect) if still stuck after this many seconds.
export WALL_KICK_AFTER=${WALL_KICK_AFTER:-60}

# Sleep state written to /sys/power/state. "mem" (suspend to RAM) is what this
# device supports and what keeps the battery happy.
export WALL_PM_STATE=${WALL_PM_STATE:-mem}

# Screensaver slots to keep in images/. Each slot is a full-size PNG written on
# every update, so 1 is the fastest; the stock renderer only shows one of them.
export SLOT_COUNT=${SLOT_COUNT:-1}

# yes = every sleep screen shows the same picture
# no  = rotate through the slots, one new picture per fetch
export SINGLE_IMAGE=${SINGLE_IMAGE:-yes}

# cron schedule used by register_cron.sh (the non-RTC fallback path).
export FETCH_SCHEDULE=${FETCH_SCHEDULE:-"*/10 * * * *"}

# Pinged to detect that Wi-Fi is up.
export WIFI_TEST_IP=${WIFI_TEST_IP:-192.168.1.1}
