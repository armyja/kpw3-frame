#!/usr/bin/env python3
"""E-ink frame image server for jailbroken Kindles (tested target: Kindle Paperwhite 3).

It serves a single PNG that fits the Kindle screen (default 1072x1448 grayscale,
Floyd-Steinberg dithered), rotating through the images you drop into a folder.

The Kindle side (kindle-dash) simply does a GET of /frame on a schedule, so the
image on the e-ink screen changes every time the server hands out the next one.

Usage
-----
    python frame_server.py                       # serve ./images on 0.0.0.0:8000
    python frame_server.py --port 8080
    python frame_server.py --render preview.png --image some-photo.jpg   # render once, no server

Endpoints
---------
    /frame          -> next image (what the Kindle requests)
    /frame?index=3  -> a specific image (1-based)
    /frame?name=x   -> a specific image by file name
    /frame?random=1 -> a random image
    /list           -> JSON list of the available images
    /health         -> plain text "ok"
"""

from __future__ import annotations

import argparse
import io
import json
import random
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

try:
    from PIL import Image, ImageEnhance, ImageOps
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: pip install pillow")

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff", ".gif"}


def parse_size(value: str) -> tuple[int, int]:
    try:
        w, h = value.lower().split("x")
        return int(w), int(h)
    except ValueError:
        raise argparse.ArgumentTypeError("size must be like 1072x1448")


class Renderer:
    """Loads images from a folder and renders them to e-ink friendly PNG bytes."""

    def __init__(
        self,
        images_dir: Path,
        size: tuple[int, int],
        fit: str = "cover",
        rotate: int = 0,
        levels: int = 16,
        dither: str = "floyd",
        contrast: float = 1.15,
        brightness: float = 1.0,
        autocontrast: bool = True,
        order: str = "name",
        pin: str | None = None,
        single: bool = False,
    ) -> None:
        self.images_dir = images_dir
        self.size = size
        self.fit = fit
        self.rotate = rotate
        self.levels = max(2, min(256, levels))
        self.dither = dither
        self.contrast = contrast
        self.brightness = brightness
        self.autocontrast = autocontrast
        self.order = order
        self.pin = pin
        self.single = single

        self._lock = threading.Lock()
        self._pointer = 0
        self._cache: dict[tuple, bytes] = {}

    # -- image discovery -------------------------------------------------
    def list_images(self) -> list[Path]:
        files = [
            p
            for p in self.images_dir.iterdir()
            if p.is_file() and p.suffix.lower() in IMAGE_EXTS
        ]
        if self.order == "mtime":
            files.sort(key=lambda p: (p.stat().st_mtime, p.name))
        elif self.order == "random":
            files.sort(key=lambda _: random.random())
        else:
            files.sort(key=lambda p: p.name.lower())
        return files

    # -- rendering -------------------------------------------------------
    def render_bytes(self, path: Path) -> bytes:
        st = path.stat()
        key = (
            str(path),
            st.st_mtime_ns,
            st.st_size,
            self.size,
            self.fit,
            self.rotate,
            self.levels,
            self.dither,
            self.contrast,
            self.brightness,
            self.autocontrast,
        )
        with self._lock:
            cached = self._cache.get(key)
        if cached is not None:
            return cached

        im = Image.open(path)
        im = ImageOps.exif_transpose(im)
        im = im.convert("RGB")

        # Rotate before fitting: used when the Kindle itself is mounted sideways,
        # so that the picture appears upright on the rotated device.
        if self.rotate == 90:
            im = im.transpose(Image.Transpose.ROTATE_270)  # 90° clockwise
        elif self.rotate == 180:
            im = im.transpose(Image.Transpose.ROTATE_180)
        elif self.rotate == 270:
            im = im.transpose(Image.Transpose.ROTATE_90)  # 270° clockwise == 90° ccw

        if self.fit == "cover":
            im = ImageOps.fit(im, self.size, method=Image.LANCZOS, centering=(0.5, 0.5))
        elif self.fit == "contain":
            im.thumbnail(self.size, Image.LANCZOS)
            canvas = Image.new("RGB", self.size, (255, 255, 255))
            canvas.paste(im, ((self.size[0] - im.width) // 2, (self.size[1] - im.height) // 2))
            im = canvas
        else:  # stretch
            im = im.resize(self.size, Image.LANCZOS)

        gray = im.convert("L")
        if self.autocontrast:
            gray = ImageOps.autocontrast(gray, cutoff=1)
        if self.brightness != 1.0:
            gray = ImageEnhance.Brightness(gray).enhance(self.brightness)
        if self.contrast != 1.0:
            gray = ImageEnhance.Contrast(gray).enhance(self.contrast)

        if self.dither == "none":
            gray = gray.point(lambda v: round(v / 255 * (self.levels - 1)) * (255 // (self.levels - 1)))
        else:
            dither_mode = Image.FLOYDSTEINBERG
            gray = gray.quantize(colors=self.levels, dither=dither_mode).convert("L")

        buf = io.BytesIO()
        gray.save(buf, format="PNG", optimize=True)
        data = buf.getvalue()

        with self._lock:
            if len(self._cache) > 64:
                self._cache.clear()
            self._cache[key] = data
        return data

    # -- selection -------------------------------------------------------
    def pick(self, index: int | None, name: str | None, use_random: bool):
        files = self.list_images()
        if not files:
            return None, files
        if self.pin:
            for p in files:
                if p.name == self.pin:
                    return p, files
            print(f"pinned image '{self.pin}' not found; falling back", flush=True)
        if self.single and not name and not use_random and index is None:
            return files[0], files
        if name:
            for p in files:
                if p.name == name:
                    return p, files
            return None, files
        if use_random:
            return random.choice(files), files
        with self._lock:
            if index is not None:
                self._pointer = (index - 1) % len(files)
            else:
                self._pointer = self._pointer % len(files)
            chosen = files[self._pointer]
            self._pointer = (self._pointer + 1) % len(files)
        return chosen, files


def local_ipv4s() -> list[str]:
    """All IPv4 addresses of this machine that we can discover cheaply."""
    import socket

    addrs: set[str] = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            addrs.add(info[4][0])
    except OSError:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        addrs.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    return sorted(addrs)


def lan_ip() -> str:
    """Best LAN address for the Kindle to reach this server.

    Prefers a real private range and skips VPN/benchmark/CGNAT adapters
    (Tailscale 100.64/10, 198.18/15, ...) which are useless to the Kindle.
    """
    import re

    def score(ip: str) -> int:
        if ip.startswith("192.168."):
            return 0
        if ip.startswith("10."):
            return 1
        if re.match(r"172\.(1[6-9]|2\d|3[01])\.", ip):
            return 2
        if ip.startswith("127.") or ip.startswith("169.254."):
            return 9
        if ip.startswith("198.18.") or ip.startswith("198.19."):
            return 9
        if re.match(r"100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.", ip):
            return 9
        return 5

    candidates = [ip for ip in local_ipv4s() if not ip.startswith("127.")]
    if not candidates:
        return "127.0.0.1"
    return sorted(candidates, key=score)[0]


def placeholder_png(size: tuple[int, int]) -> bytes:
    im = Image.new("L", size, 255)
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue()


def make_handler(renderer: Renderer, interval: int = 900):
    screen_size = renderer.size

    class Handler(BaseHTTPRequestHandler):
        server_version = "EinkFrame/1.0"

        def _send(self, code: int, body: bytes, ctype: str) -> None:
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def log_message(self, fmt, *args):  # quieter, single-line logging
            print(f"{self.address_string()} - {fmt % args}", flush=True)

        def do_HEAD(self):
            self.do_GET()

        def do_GET(self):
            parsed = urlparse(self.path)
            qs = parse_qs(parsed.query)
            route = parsed.path.rstrip("/") or "/"

            if route in ("/", "/frame", "/frame.png", "/next"):
                index = None
                if "index" in qs:
                    try:
                        index = int(qs["index"][0])
                    except ValueError:
                        index = None
                name = qs.get("name", [None])[0]
                use_random = qs.get("random", ["0"])[0] in ("1", "true", "yes")

                path, files = renderer.pick(index, name, use_random)
                if path is None:
                    print(f"no image found in {renderer.images_dir}", flush=True)
                    return self._send(200, placeholder_png(screen_size), "image/png")

                try:
                    data = renderer.render_bytes(path)
                except Exception as exc:  # noqa: BLE001 - keep the server alive
                    print(f"failed to render {path}: {exc}", flush=True)
                    return self._send(200, placeholder_png(screen_size), "image/png")

                print(
                    f"serving {path.name} ({len(files)} image(s) available)",
                    flush=True,
                )
                return self._send(200, data, "image/png")

            if route == "/list":
                files = renderer.list_images()
                body = json.dumps([p.name for p in files], ensure_ascii=False).encode()
                return self._send(200, body, "application/json")

            if route == "/health":
                # "ok" plus the refresh interval the Kindle should use.
                return self._send(200, f"ok {interval}".encode(), "text/plain")

            if route == "/interval":
                return self._send(200, str(interval).encode(), "text/plain")

            return self._send(404, b"not found", "text/plain")

    return Handler


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="E-ink frame image server")
    p.add_argument("--host", default="0.0.0.0")
    p.add_argument("--port", type=int, default=8000)
    p.add_argument("--images", type=Path, default=Path(__file__).parent / "images")
    p.add_argument("--size", type=parse_size, default=(1072, 1448), help="e.g. 1072x1448")
    p.add_argument("--fit", choices=["cover", "contain", "stretch"], default="contain")
    p.add_argument(
        "--rotate",
        type=int,
        choices=[0, 90, 180, 270],
        default=0,
        help="rotate the picture clockwise before fitting (for a sideways-mounted Kindle)",
    )
    p.add_argument("--levels", type=int, default=16, help="gray levels (e-ink ~16)")
    p.add_argument("--dither", choices=["floyd", "none"], default="floyd")
    p.add_argument("--contrast", type=float, default=1.15)
    p.add_argument("--brightness", type=float, default=1.0)
    p.add_argument("--no-autocontrast", action="store_true")
    p.add_argument("--order", choices=["name", "mtime", "random"], default="name")
    p.add_argument(
        "--pin",
        default=None,
        help="always serve this image (a file name inside --images) on /frame",
    )
    p.add_argument(
        "--single",
        action="store_true",
        help="always serve the first image (by --order); use for a fixed screensaver",
    )
    p.add_argument(
        "--interval",
        type=int,
        default=900,
        help="refresh interval (seconds) advertised to the Kindle via /health and /interval",
    )
    # one-shot rendering
    p.add_argument("--render", type=Path, help="render a single image to this PNG and exit")
    p.add_argument("--image", type=Path, help="source image for --render")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    renderer = Renderer(
        images_dir=args.images,
        size=tuple(args.size),
        fit=args.fit,
        rotate=args.rotate,
        levels=args.levels,
        dither=args.dither,
        contrast=args.contrast,
        brightness=args.brightness,
        autocontrast=not args.no_autocontrast,
        order=args.order,
        pin=args.pin,
        single=args.single,
    )

    if args.render:
        if not args.image:
            build_parser().error("--render requires --image")
        data = renderer.render_bytes(args.image)
        args.render.write_bytes(data)
        print(f"wrote {args.render} ({len(data)} bytes)")
        return 0

    args.images.mkdir(parents=True, exist_ok=True)
    count = len(renderer.list_images())
    print(f"serving {count} image(s) from {args.images} on {args.host}:{args.port}", flush=True)
    print(f"Kindle should use:  http://{lan_ip()}:{args.port}/frame", flush=True)
    if count == 0:
        print("no images yet - drop some .jpg/.png files into the images folder", flush=True)
    if args.pin:
        print(f"pin mode: /frame always serves '{args.pin}'", flush=True)
    elif args.single:
        print("single mode: /frame always serves the first image", flush=True)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(renderer, args.interval))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
