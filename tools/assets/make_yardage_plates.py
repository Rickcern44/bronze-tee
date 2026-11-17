#!/usr/bin/env python3
"""Writes the yardage plate textures used by the props family.

Run from the project root: python3 tools/assets/make_yardage_plates.py
Output: assets/models/props/textures/yardage_{100,150,200,250}.png (256x160, deterministic).
Each plate has the cap colour as background, a darker 6 px border and the number centred in
Barlow Condensed Bold, about 120 px tall.
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FONT_PATH = os.path.join(ROOT, "assets", "fonts", "BarlowCondensed-Bold.ttf")
OUT_DIR = os.path.join(ROOT, "assets", "models", "props", "textures")

WIDTH = 256
HEIGHT = 160
BORDER = 6
TEXT_HEIGHT = 120
SIDE_MARGIN = 10

INK_DARK = (0x0E, 0x1A, 0x17)
INK_LIGHT = (0xF4, 0xF1, 0xE6)

# (distance, background = cap colour, ink)
PLATES = [
    (100, (0xF0, 0x56, 0x2E), INK_LIGHT),  # red
    (150, (0xF4, 0xF1, 0xE6), INK_DARK),   # white
    (200, (0x3D, 0x7B, 0xD9), INK_LIGHT),  # blue
    (250, (0xD9, 0xA0, 0x66), INK_DARK),   # gold (bronze)
]


def darker(colour, factor=0.6):
    return tuple(int(round(c * factor)) for c in colour)


def fit_font(text):
    """Finds the font size whose glyph box is TEXT_HEIGHT tall and fits the plate width."""
    max_width = WIDTH - 2 * (BORDER + SIDE_MARGIN)
    size = 170
    for _ in range(6):
        font = ImageFont.truetype(FONT_PATH, size)
        left, top, right, bottom = font.getbbox(text)
        scale = min(TEXT_HEIGHT / float(bottom - top), max_width / float(right - left))
        new_size = max(8, int(size * scale))
        if new_size == size:
            break
        size = new_size
    font = ImageFont.truetype(FONT_PATH, size)
    return font, font.getbbox(text)


def render(distance, background, ink):
    text = str(distance)
    font, (left, top, right, bottom) = fit_font(text)
    image = Image.new("RGB", (WIDTH, HEIGHT), background)
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, 0, WIDTH - 1, HEIGHT - 1], outline=darker(background), width=BORDER)
    x = (WIDTH - (right - left)) / 2.0 - left
    y = (HEIGHT - (bottom - top)) / 2.0 - top
    draw.text((round(x), round(y)), text, font=font, fill=ink)
    return image


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for distance, background, ink in PLATES:
        path = os.path.join(OUT_DIR, "yardage_%d.png" % distance)
        render(distance, background, ink).save(path, format="PNG")
        print("wrote", path)


if __name__ == "__main__":
    main()
