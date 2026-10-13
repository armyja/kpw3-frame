"""Generate the Android launcher icon for the KPW3 Frame app."""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(r"D:\project\kpw3-frame\android\res")


def make(size: int, out: Path) -> None:
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    s = size / 192.0

    # rounded dark square
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(42 * s), fill=(38, 50, 56, 255))
    # "screen"
    d.rounded_rectangle(
        [int(46 * s), int(28 * s), int(146 * s), int(164 * s)],
        radius=int(6 * s),
        fill=(236, 239, 241, 255),
    )
    # a picture inside the screen
    d.ellipse(
        [int(62 * s), int(48 * s), int(92 * s), int(78 * s)],
        fill=(120, 144, 156, 255),
    )
    d.polygon(
        [
            (int(56 * s), int(150 * s)),
            (int(96 * s), int(96 * s)),
            (int(136 * s), int(150 * s)),
        ],
        fill=(96, 125, 139, 255),
    )
    # stand
    d.rectangle([int(86 * s), int(168 * s), int(106 * s), int(180 * s)], fill=(120, 144, 156, 255))

    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out)
    print("wrote", out, im.size)


make(192, ROOT / "mipmap-xxhdpi" / "ic_launcher.png")
make(48, ROOT / "mipmap-mdpi" / "ic_launcher.png")
