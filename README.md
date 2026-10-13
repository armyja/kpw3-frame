# KPW3 Frame

**English** · [中文](README.zh-CN.md)

Turn a jailbroken **Kindle Paperwhite 3** into an e-ink photo frame that pulls
pictures from a server you control.

The Kindle wakes itself with a hardware alarm, downloads one picture, paints it,
and drops straight back into deep sleep. E-ink keeps the image with no power, so
it lasts weeks on a charge — and because the fetch happens *while the screen is
"off"*, the picture you wake up to is always the current one.

No cloud, no account, no USB tether. The server is either a single Python file on
your PC or a ~45 KB Android APK that runs the same tiny HTTP server and does the
image conversion on the phone.

```
   server (PC or Android)                          Kindle Paperwhite 3
   ──────────────────────                          ───────────────────
   GET /health  ->  ok <seconds>   ◀── wall.sh reads the interval once per wake
   GET /frame   ->  1072x1448 greyscale PNG  ◀── wall.sh downloads, paints, sleeps
   GET /list    ->  ["a.jpg", ...]
```

## Contents

- [What you get](#what-you-get)
- [Requirements](#requirements)
- [Install — the server](#install--the-server)
- [Install — the Kindle](#install--the-kindles)
- [Configuration](#configuration)
- [How it works](#how-it-works)
- [Measured numbers](#measured-numbers)
- [Troubleshooting](#troubleshooting)
- [Design notes (the interesting part)](#design-notes-the-interesting-part)
- [Acknowledgements](#acknowledgements)
- [Licence](#licence)

## What you get

Two KUAL entries and nothing else:

```
Custom Screensaver (KPW3)
 ├ Refresh image now      → fetch once and paint it, using the current settings
 └ Start wall display     → start the automatic loop (press the power button to stop)
```

Everything else lives in `/mnt/us/screensaver/` as scripts you can run by hand
when you need them (see [Configuration](#configuration)).

## Requirements

| | |
|---|---|
| Kindle | Paperwhite 3 (2015, `kindlepw2`), jailbroken, with **KUAL** and **MRPI** |
| Firmware | built and tested on **5.16.2.1.1** |
| Server | a PC/Mac/Raspberry Pi on the same Wi-Fi **(Python 3.9+ and Pillow)**, or the Android APK |
| Optional | **FBInk** for on-screen status messages (the copy inside `libkh` or KOReader works), and the static **`xh`** binary only if your device has no `wget` |

The screen is 1072 × 1448, 16 greys. Both servers render to exactly that.

## Install — the server

### Option A — PC / Raspberry Pi

```bash
pip install -r server/requirements.txt
python server/frame_server.py --pin my-photo.jpg --fit cover --rotate 90
```

Put your pictures in `server/images/`, then double-click `start-server.bat`
(Windows) or run the command above. On startup it prints the address to use:

```
Kindle should use:  http://192.168.1.50:8000/frame
```

Every request to `/frame` returns the next picture, converted to
1072 × 1448 greyscale with Floyd–Steinberg dithering. Useful flags:

| flag | meaning |
|---|---|
| `--pin NAME` / `--single` | always serve one fixed picture |
| `--rotate 0\|90\|180\|270` | rotate before fitting (`90` for a sideways-mounted Kindle) |
| `--fit cover\|contain` | fill the screen (crop) or fit it whole (margins) |
| `--interval N` | refresh interval advertised to the Kindle (default 900 s) |

### Option B — Android

`android/` builds a 45 KB APK with **no third-party dependencies**:

```bat
android\build.bat          :: aapt2 → javac → d8 → zipalign → apksigner
adb install -r android\build\kpw3-frame-debug.apk
```

It runs the same HTTP protocol in a foreground service, lets you pick pictures
with the system picker, converts them on the device, and can also write the
Kindle's `server.txt` **over USB** (OTG + Storage Access Framework) — handy when
you know the phone's address but the Kindle can't reach it yet.

## Install — the Kindle

Copy two folders over USB (the Kindle appears as a normal USB drive):

```
kindle/screensaver/            →  /mnt/us/screensaver/
kindle/extensions/kpw3-screensaver/  →  /mnt/us/extensions/kpw3-screensaver/
```

Then eject and run the one-time setup from KUAL… or, if you prefer, add a
`Enable` entry back to `menu.json` — by default it is deliberately kept out of the
menu because it is a one-off. The equivalent is:

```sh
sh /mnt/us/screensaver/enable.sh      # symlink the screensaver dir + install the cron fallback
```

Point the Kindle at your server, either

- by editing `/mnt/us/screensaver/server.txt` over USB (one line, plain URL), or
- by tapping **Write to Kindle (USB)** in the Android app, or
- from a shell: `sh /mnt/us/screensaver/set_server.sh detect` (it scans the LAN for
  the server; it is not in the KUAL menu to keep the menu to two entries).

Finally start it: **KUAL → Start wall display**. Press the power button once to
stop; the screen goes back to being a normal Kindle.

## Configuration

Everything lives in `/mnt/us/screensaver/env.sh` — a normal shell file you can
edit over USB. The ones you are likely to touch:

| setting | default | meaning |
|---|---|---|
| `FRAME_URL` | `http://192.168.1.50:8000/frame` | where to fetch (also set by the APK or `set_server.sh`) |
| `WALL_INTERVAL` | `900` | seconds between refreshes — **the server overrides this** |
| `WALL_WIFI_WAIT` | `240` | how long to wait for Wi-Fi + server after a wake |
| `SLOT_COUNT` | `1` | screensaver slots to keep (1 = fastest updates) |
| `SINGLE_IMAGE` | `yes` | same picture every time, or rotate |

**You normally never need to touch the Kindle to change the interval.** The
server advertises it via `/health` (`ok 900`), the loop reads it once per wake
and writes the new value straight back into `env.sh`, so it takes effect on the
next wake — no USB, no restart.

Scripts that are *not* in the KUAL menu, in case you need them:

| script | what it does |
|---|---|
| `enable.sh` / `disable.sh` | build or undo the screensaver symlink (fully reversible) |
| `set_server.sh show\|test\|detect` | print / test / auto-discover the server |
| `wall.sh stop` | stop the loop from a shell |
| `suspend_test.sh` | arm a 60 s RTC alarm, suspend, and report PASS/FAIL on screen |
| `diag.sh` | read-only report → `/mnt/us/diag.txt` |

## How it works

```
wall.sh  (the loop)
   ├─ arm an RTC wake alarm for WALL_INTERVAL   ── read it back, or don't sleep
   ├─ echo mem > /sys/power/state                 (deep sleep; e-ink holds the image)
   ├─ … the alarm fires, the device resumes …
   ├─ wait for the server (/health), sync the interval into env.sh
   ├─ fetch.sh: download → convert nothing (the server already did) → 1 slot
   ├─ paint it with eips -f (which waits for the panel to finish)
   └─ repeat, until the power button is pressed (early wake = exit)
```

The stock screensaver still works too: `enable.sh` points
`/usr/share/blanket/screensaver` at `/mnt/us/screensaver/images`, so if the
device ever sleeps on its own (or you just press the power button while the loop
is stopped) the same picture appears. A cron entry (`FETCH_SCHEDULE`) refreshes
that folder every 10 minutes as a harmless fallback.

## Measured numbers

On a Paperwhite 3, one wake-to-picture cycle takes **≈ 7 seconds**:

| stage | time | notes |
|---|---|---|
| Wi-Fi reconnects | 2–3 s | the radio is off during suspend; platform-imposed |
| download | ~1 s | 335 KB over Wi-Fi |
| write the screensaver slot | <0.1 s | was several seconds with 20 slots — hence `SLOT_COUNT=1` |
| `eips -f` full refresh | 1–2 s | physical e-ink refresh; unavoidable |

Each cycle logs its own breakdown, so you can see where your time goes:

```
server reachable after 2s
server asks for 60s (was 900s) -> saving to env.sh
fetched in 3s
painted in 2s
wake-to-sleep prep took 5s
```

Battery: the device is asleep between refreshes, with one radio wake per
interval. At 15-minute intervals that is a very long time per charge.

## Troubleshooting

| symptom | what to check |
|---|---|
| nothing happens on `Start` | check `logs/wall.log` — it logs every step |
| the picture never changes | `Refresh image now`; then look for `applied the same image to 1 slot(s)` in `logs/fetch.log` |
| the screen shows the Kindle UI again | the loop probably exited (power button = stop). Restart it |
| the lock screen has leftovers from the status bar | the framework repainted after we drew; that is the price of not taking over the screen (see below) |
| `garbled`/`torn` image | the panel was suspended mid-refresh; `draw_final` uses `eips`, which waits, so this should not happen |
| Wi-Fi never comes back | the Kindle turns its radio off while suspended; `WALL_WIFI_WAIT` (240 s) covers a slow AP |
| nothing after a firmware update | re-run `enable.sh` — the symlink can be reset |

## Design notes (the interesting part)

These are the things that cost the most time to learn. They are why the code
looks the way it does.

1. **Do not take over the screen.** The obvious approach (stop the Kindle UI,
   draw, suspend, restart the UI) is what the well-known dashboard projects do,
   and on this device it ended in a spontaneous reboot: stopping `lab126_gui`
   makes the system's power management fight the suspend, and the watchdog kills
   it. Killing the UI also means `poll_daemons` starts noticing. We leave the UI
   alone; the loop only *paints*, and the loop's own suspend is what keeps the
   image on screen. The trade-off is that the framework can repaint its status
   bar over our picture for a moment after a wake.

2. **We have to paint the picture ourselves.** The stock screensaver is drawn by
   the framework when **powerd** decides to sleep (`goingToScreenSaver`). A raw
   `echo mem > /sys/power/state` bypasses powerd, so that never fires — the panel
   would keep whatever was on screen. `wall.sh` draws explicitly instead.

3. **The last paint uses `eips`, not `fbink`.** `fbink` returns as soon as it has
   submitted the update, so suspending right after it can catch the panel
   mid-refresh and leave a torn image. `eips` waits for the refresh to complete.
   (FBInk's `-w` flag is not documented as supported for images.)

4. **Never suspend without reading the wake alarm back.** `arm_alarm` writes the
   RTC alarm and then reads it back; if the value does not match, the loop sleeps
   normally instead of suspending. Suspending with no alarm is how you end up
   needing a 20-second power-button hold.

5. **Stay awake safely.** While the loop is doing its work it arms a 300 s
   "safety" alarm, so if power management suspends it in the middle the device
   still wakes and carries on.

6. **One screensaver slot.** The stock renderer picks one file out of
   `/usr/share/blanket/screensaver`, so with a single-image setup all slots would
   hold identical bytes — writing 20 copies per refresh cost several seconds of
   flash I/O for nothing. `SLOT_COUNT=1` and the rest are deleted; the kids-mode
   images (`bg_kids_ss*`) are left alone.

7. **The interval is pushed, not pulled by USB.** Making the server the source of
   truth (`/health` → `ok <seconds>`, written into `env.sh` by the Kindle) means
   changing the refresh rate is a one-tap change on the server, and the same
   mechanism would work for any other setting you want to hand out later.

8. **Escalate, don't guess.** The loop is passive about Wi-Fi by default: calling
   `wpa_cli reconnect` immediately after a wake *tears down a working link*, which
   cost 21 s instead of 9 s in testing. It is only tried after 60 s of failure.

## Acknowledgements

This project stands on other people's work. Thank you, in particular:

- **[pascalw/kindle-dash](https://github.com/pascalw/kindle-dash)** (MIT) — the
  original "fetch an image from a URL on a schedule and deep-sleep between
  refreshes" idea, and the shape of the loop we started from. Its bundled
  `xh`/`next-wakeup` binaries and `eips` drawing did not survive on this device,
  but the architecture is theirs.
- **[brunomarinho/labs-kindle-artframe](https://github.com/brunomarinho/labs-kindle-artframe)**
  (MIT) — the clearest explanation of *why* the GUI framework has to be stopped
  for suspend to work, the "an early wake is a power-button press, so exit" rule,
  and the FBInk usage pattern.
- **[jstriblet/kindle-wall-display](https://github.com/jstriblet/kindle-wall-display)**
  — the fail-safe rules we deliberately copied: never suspend without reading the
  armed alarm back, keep the last good image when a fetch fails, and prove suspend
  with a short "suspend test" before trusting a loop with your battery.
- **[jjss520/custom_screensaver](https://github.com/jjss520/custom_screensaver)**
  — the trick that makes a custom lock screen possible at all: symlink
  `/usr/share/blanket/screensaver` into user storage.
- **[chengandre/kindle-custom-screensaver](https://github.com/chengandre/kindle-custom-screensaver)**
  — useful for the opposite reason: it showed that newer (`kindlehf`) devices need
  a completely different mechanism, which confirmed we were on the legacy path.
- **[NiLuJe/FBInk](https://github.com/NiLuJe/FBInk)** (GPL-3.0, *not* bundled) —
  the best way to draw on a Kindle and the source of the `wait_for_complete`
  detail that shaped note 3 above.
- **[ducaale/xh](https://github.com/ducaale/xh)** (MIT, *not* bundled) — the static
  ARM HTTP client we use as a fallback when a device has no usable `wget`.
- **[KindleModding](https://kindlemodding.org/)** — KUAL/MRPI installation guides
  and the LIPC reference pages (`com.lab126.powerd`, `com.lab126.keyboard`,
  `com.lab126.pillow`) that made it possible to ask the right questions.
- The **MobileRead** forums and wiki — every Kindle question has an answer there,
  usually from 2013, and usually still correct.
- **[mitanshu7/tailscale_kual](https://github.com/mitanshu7/tailscale_kual)**,
  **[bookfere/BookFere-Tools](https://github.com/bookfere/BookFere-Tools)** and
  `kindle-wall-display` again — for showing how KUAL's `menu.json` (including
  nested submenus) is meant to be written.

## Working on this repo

Nothing here needs a build system. The Kindle scripts and the Python server are
edit-and-copy, and the tests run without a device:

```bat
tools\syntax_check.bat         :: busybox-sh syntax check of every Kindle script
tools\sh_test\run_test.bat     :: server_interval / save_interval / ensure_slots
```

```bash
javac -d tools/jvm_test/out android/java/com/kpw3/frame/PngEncoder.java \
      android/java/com/kpw3/frame/Dither.java android/java/com/kpw3/frame/EnvPatcher.java \
      tools/jvm_test/*.java
java -cp tools/jvm_test/out com.kpw3.frame.EnvPatchTest kindle/screensaver/env.sh
java -cp tools/jvm_test/out com.kpw3.frame.PngDitherTest out.png 16
```

The Android app builds with `android\build.bat` — `aapt2` + `javac` + `d8` +
`apksigner`, no Gradle and no Android Studio required.

If `github.com` is unreachable from your network (only `api.github.com` answers),
`tools/push_via_api.py` publishes the current commit through the REST API instead
of `git push`:

```bash
python tools/push_via_api.py <owner>/<repo>
```

## Licence

MIT — see [LICENSE](LICENSE). Third-party tools are credited above and are not
redistributed here.
