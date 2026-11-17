"""Makes assets/models/_previews/<family>.png: a grid of the family's thumbnails with id and height under each.

Run with the SYSTEM python3 (needs Pillow; this does not run inside Blender):
    python3 tools/blender/contact_sheet.py --family=trees
Reads assets/models/<family>/manifest.partial.json (falls back to assets/models/manifest.json) and the thumbnails
written by previews.py to assets/models/_previews/thumbs/<id>.png. Missing thumbnails are drawn as a grey box.
Exit code 0 on success, 1 on error.
"""

import argparse
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MODELS_DIR = os.path.join(PROJECT_ROOT, "assets", "models")
PREVIEWS_DIR = os.path.join(MODELS_DIR, "_previews")
THUMB_DIR = os.path.join(PREVIEWS_DIR, "thumbs")
FONT_BOLD = os.path.join(PROJECT_ROOT, "assets", "fonts", "BarlowCondensed-Bold.ttf")
FONT_REG = os.path.join(PROJECT_ROOT, "assets", "fonts", "BarlowCondensed-Regular.ttf")

BG = (244, 241, 230)
INK = (14, 26, 23)
MUTED = (80, 92, 88)
THUMB = 256
CAPTION = 56
PAD = 24
MAX_COLUMNS = 4


def _font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def _entries(family):
    partial = os.path.join(MODELS_DIR, family, "manifest.partial.json")
    if os.path.isfile(partial):
        with open(partial, encoding="utf-8") as handle:
            return json.load(handle)["assets"]
    with open(os.path.join(MODELS_DIR, "manifest.json"), encoding="utf-8") as handle:
        return [e for e in json.load(handle)["assets"] if e["family"] == family]


def build_sheet(family):
    entries = sorted(_entries(family), key=lambda e: e["id"])
    if not entries:
        raise RuntimeError("no assets for family %s" % family)
    columns = min(MAX_COLUMNS, len(entries))
    rows = (len(entries) + columns - 1) // columns
    cell_w = THUMB + PAD * 2
    cell_h = THUMB + CAPTION + PAD
    sheet = Image.new("RGB", (columns * cell_w, rows * cell_h + PAD), BG)
    draw = ImageDraw.Draw(sheet)
    id_font = _font(FONT_BOLD, 22)
    info_font = _font(FONT_REG, 18)
    for index, entry in enumerate(entries):
        col, row = index % columns, index // columns
        x0 = col * cell_w + PAD
        y0 = row * cell_h + PAD // 2
        thumb_path = os.path.join(THUMB_DIR, entry["id"] + ".png")
        if os.path.isfile(thumb_path):
            thumb = Image.open(thumb_path).convert("RGB").resize((THUMB, THUMB), Image.LANCZOS)
        else:
            thumb = Image.new("RGB", (THUMB, THUMB), (200, 200, 200))
        sheet.paste(thumb, (x0, y0))
        draw.rectangle([x0 - 1, y0 - 1, x0 + THUMB, y0 + THUMB], outline=(190, 185, 170))
        height_m = entry["size"][1]
        draw.text((x0, y0 + THUMB + 6), entry["id"], font=id_font, fill=INK)
        draw.text((x0, y0 + THUMB + 30), "height %.2f m" % height_m, font=info_font, fill=MUTED)
    os.makedirs(PREVIEWS_DIR, exist_ok=True)
    out = os.path.join(PREVIEWS_DIR, family + ".png")
    sheet.save(out)
    return out, len(entries)


def main(argv):
    parser = argparse.ArgumentParser(prog="contact_sheet.py")
    parser.add_argument("--family", required=True)
    args = parser.parse_args(argv)
    out, count = build_sheet(args.family)
    print("wrote %s (%d assets)" % (os.path.relpath(out, PROJECT_ROOT), count))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as exc:  # noqa: BLE001 - report any failure with exit code 1
        print("CONTACT SHEET FAILED: %s" % exc, file=sys.stderr)
        sys.exit(1)
