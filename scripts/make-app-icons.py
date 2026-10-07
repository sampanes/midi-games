"""Draw the Key Games app icon and write every size the app needs.

A small rainbow keyboard (C to G in the game's note colors, with the black
keys between) under a gold star, on a dark purple background.

Writes:
  Android launcher icons (legacy PNGs + adaptive foreground/background),
  the Android TV banner, and the Windows .ico.

Usage: python scripts/make-app-icons.py
Needs Pillow. Uses Arial Bold for the banner text when it can find it.
"""

import functools
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "apps", "key_games")
RES = os.path.join(APP, "android", "app", "src", "main", "res")

S = 1024  # working size of one icon square

# Same colors as the game's pitchClasses (C, D, E, F, G).
WHITE_KEYS = ["#FF3B3B", "#FF9A1F", "#FFE81F", "#3DDC4A", "#2FA8FF"]
BLACK_AFTER = [0, 1, 3]  # black keys after C, D and F
BG_CENTER = (74, 52, 112)
BG_EDGE = (20, 17, 28)
GOLD = "#FFD84A"


@functools.lru_cache(maxsize=None)
def background(w, h):
    """Radial purple glow fading to the app's dark background."""
    img = Image.new("RGB", (w, h), BG_EDGE)
    px = img.load()
    cx, cy = w / 2, h * 0.42
    r = math.hypot(w, h) * 0.55
    for y in range(h):
        for x in range(w):
            t = min(1.0, math.hypot(x - cx, y - cy) / r)
            t = t * t
            px[x, y] = tuple(round(c0 + (c1 - c0) * t) for c0, c1 in zip(BG_CENTER, BG_EDGE))
    return img


def star_points(cx, cy, r_out, r_in, n=5):
    pts = []
    for i in range(2 * n):
        r = r_out if i % 2 == 0 else r_in
        a = -math.pi / 2 + i * math.pi / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def foreground(size, scale):
    """Keyboard and star on a transparent square. [scale] is the share of the
    square the artwork spans (adaptive icons need a safe margin)."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    span = S * scale
    left = (S - span) / 2
    top = (S - span) / 2
    key_w = span / len(WHITE_KEYS)
    key_top = top + span * 0.40
    key_bottom = top + span
    radius = key_w * 0.22

    # Soft glow behind the keys.
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(
        (left, key_top, left + span, key_bottom), radius=radius, fill=(255, 255, 255, 90))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(S * 0.03)))

    gap = key_w * 0.07
    for i, color in enumerate(WHITE_KEYS):
        x0 = left + i * key_w + gap / 2
        d.rounded_rectangle((x0, key_top, x0 + key_w - gap, key_bottom), radius=radius, fill=color)
    black_w = key_w * 0.58
    black_h = (key_bottom - key_top) * 0.58
    for i in BLACK_AFTER:
        cx = left + (i + 1) * key_w
        d.rounded_rectangle(
            (cx - black_w / 2, key_top - 1, cx + black_w / 2, key_top + black_h),
            radius=black_w * 0.25, fill="#1E1A26", outline="#14111C", width=max(2, round(S * 0.006)))

    # Gold star above the keys, with a little glow.
    scx, scy = S / 2, top + span * 0.17
    r_out = span * 0.19
    star = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(star).polygon(star_points(scx, scy, r_out * 1.15, r_out * 0.5), fill=(255, 216, 74, 120))
    img.alpha_composite(star.filter(ImageFilter.GaussianBlur(S * 0.02)))
    d.polygon(star_points(scx, scy, r_out, r_out * 0.45), fill=GOLD)
    return img.resize((size, size), Image.LANCZOS)


def full_icon(size, rounded):
    img = background(S, S).convert("RGBA")
    img.alpha_composite(foreground(S, 0.70))
    if rounded:
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=S * 0.22, fill=255)
        img.putalpha(mask)
    return img.resize((size, size), Image.LANCZOS)


def banner():
    """Android TV home-screen banner, 320x180 (xhdpi)."""
    w, h = 1280, 720
    img = background(w, h).convert("RGBA")
    art = foreground(S, 0.86).resize((560, 560), Image.LANCZOS)
    img.alpha_composite(art, (40, 80))
    d = ImageDraw.Draw(img)
    font_path = os.path.join(os.environ.get("WINDIR", "C:\\Windows"), "Fonts", "arialbd.ttf")
    try:
        font = ImageFont.truetype(font_path, 150)
    except OSError:
        font = ImageFont.load_default()
    d.text((620, 200), "Key", font=font, fill="white")
    d.text((620, 370), "Games", font=font, fill="white")
    return img.resize((320, 180), Image.LANCZOS)


def save(img, *parts):
    path = os.path.join(*parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("[OK]", os.path.relpath(path, ROOT))


def main():
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    bg = background(S, S)
    for name, k in densities.items():
        save(full_icon(round(48 * k), rounded=True), RES, f"mipmap-{name}", "ic_launcher.png")
        adaptive = round(108 * k)
        # Adaptive icons: 108dp layers, the artwork kept inside the middle 66dp.
        save(foreground(adaptive, 0.48), RES, f"mipmap-{name}", "ic_launcher_foreground.png")
        save(bg.resize((adaptive, adaptive), Image.LANCZOS), RES, f"mipmap-{name}",
             "ic_launcher_background.png")
    save(banner(), RES, "drawable-xhdpi", "banner.png")

    ico = full_icon(256, rounded=True)
    ico_path = os.path.join(APP, "windows", "runner", "resources", "app_icon.ico")
    ico.save(ico_path, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("[OK]", os.path.relpath(ico_path, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
