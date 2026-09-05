"""Generates the launcher icons from the palette in armonic_colors.dart.

Run from the repo root: python3 tool/make_icons.py
Writes the Android legacy + adaptive mipmaps and the web icons/favicon.
"""
from PIL import Image, ImageDraw
import os

NAVY, NAVY2 = (0x0E, 0x11, 0x23), (0x15, 0x22, 0x46)   # backgroundSidebar -> selection
ACCENT, SOFT = (0x4C, 0x86, 0xF6), (0x8A, 0xB4, 0xFF)  # accent, accentSoft
S = 1024

def gradient(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size - 2)
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(NAVY, NAVY2))
    return img

def bars(draw, size, scale=1.0):
    """The LiveBars glyph: four rounded bars, centred, tallest third."""
    heights = [0.30, 0.52, 0.72, 0.42]
    w = size * 0.11 * scale
    gap = size * 0.065 * scale
    total = 4 * w + 3 * gap
    x = (size - total) / 2
    cy = size / 2
    for i, h in enumerate(heights):
        hh = size * h * scale
        color = SOFT if i == 2 else ACCENT
        draw.rounded_rectangle([x, cy - hh / 2, x + w, cy + hh / 2], radius=w / 2, fill=color)
        x += w + gap

def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius=radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, mask=mask)
    return out

# Master: full icon with its own rounded shape (legacy Android, web, favicon).
master = gradient(S)
bars(ImageDraw.Draw(master), S)
master = rounded(master, int(S * 0.22))

# Adaptive foreground: transparent canvas, glyph inside the 66/108 safe zone.
fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
bars(ImageDraw.Draw(fg), S, scale=0.62)

# Maskable web icon: full-bleed background, glyph in the safe zone.
maskable = gradient(S).convert("RGBA")
bars(ImageDraw.Draw(maskable), S, scale=0.8)

def save(img, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path)

res = "android/app/src/main/res"
for dpi, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
    save(master, f"{res}/mipmap-{dpi}/ic_launcher.png", px)
    save(fg, f"{res}/mipmap-{dpi}/ic_launcher_foreground.png", px * 108 // 48)

for name, img, size in [("Icon-192", master, 192), ("Icon-512", master, 512),
                        ("Icon-maskable-192", maskable, 192), ("Icon-maskable-512", maskable, 512)]:
    save(img, f"web/icons/{name}.png", size)
save(master, "web/favicon.png", 64)
save(master, "tool/icon-preview.png", 512)
print("icons written")
