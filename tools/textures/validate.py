"""Validate the texture library manifest. Exit code 1 if any check fails.

Per manifest entry: the file exists, is 512x512 RGB, avg_color matches the file,
and the ids are unique. Seams: the left/right edge columns and the top/bottom edge
rows must differ by no more than 1.5x the mean difference between adjacent interior
columns/rows of the same texture.

    python3 tools/textures/validate.py
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageStat

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LIB = ROOT / "assets" / "textures" / "library"
MANIFEST = LIB / "manifest.json"
SIZE = 512
SEAM_LIMIT = 1.5


def _diff(a, b):
    return (abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])) / 3.0


def seam_ratios(px):
    """Return (left/right seam / interior, top/bottom seam / interior)."""
    seam_lr = sum(_diff(px[0, y], px[SIZE - 1, y]) for y in range(SIZE)) / SIZE
    seam_tb = sum(_diff(px[x, 0], px[x, SIZE - 1]) for x in range(SIZE)) / SIZE
    inter_lr = sum(_diff(px[x, y], px[x + 1, y])
                   for x in range(SIZE - 1) for y in range(SIZE)) / ((SIZE - 1) * SIZE)
    inter_tb = sum(_diff(px[x, y], px[x, y + 1])
                   for y in range(SIZE - 1) for x in range(SIZE)) / ((SIZE - 1) * SIZE)
    ratio_lr = seam_lr / inter_lr if inter_lr else (0.0 if seam_lr == 0 else float("inf"))
    ratio_tb = seam_tb / inter_tb if inter_tb else (0.0 if seam_tb == 0 else float("inf"))
    return ratio_lr, ratio_tb


def average_hex(img):
    """Same rounding as tex_kit.average_hex, computed independently here."""
    mean = ImageStat.Stat(img).mean
    return "#%02X%02X%02X" % tuple(min(255, max(0, int(round(c)))) for c in mean)


def check_entry(entry, seen_ids):
    problems = []
    tid = entry.get("id")
    category = entry.get("category")
    if tid in seen_ids:
        problems.append("duplicate id")
    seen_ids.add(tid)
    if entry.get("file") != "res://assets/textures/library/%s/%s.png" % (category, tid):
        problems.append("file field does not match id/category")
    if entry.get("size") != [SIZE, SIZE]:
        problems.append("manifest size is not [512, 512]")

    path = LIB / str(category) / (str(tid) + ".png")
    if not path.is_file():
        return ["missing file %s" % path], None

    with Image.open(path) as opened:
        if opened.size != (SIZE, SIZE):
            problems.append("image is %dx%d" % opened.size)
        expected_mode = "RGBA" if entry.get("alpha") is True else "RGB"
        if opened.mode != expected_mode:
            problems.append("image mode is %s, not %s" % (opened.mode, expected_mode))
        if entry.get("alpha") is True and opened.mode == "RGBA":
            lo, hi = opened.getchannel("A").getextrema()
            if lo != 0 or hi == 0:
                problems.append("alpha must contain transparent and visible pixels")
            if entry.get("tileable") is not False:
                problems.append("alpha assets must be non-tileable")
        img = opened.convert("RGB")

    avg = average_hex(img)
    if avg != entry.get("avg_color"):
        problems.append("avg_color %s does not match file %s" % (entry.get("avg_color"), avg))

    if entry.get("tileable") is False:
        return problems, "non-tileable  avg %s" % avg
    ratio_lr, ratio_tb = seam_ratios(img.load())
    if ratio_lr > SEAM_LIMIT:
        problems.append("left/right seam ratio %.2f > %.1f" % (ratio_lr, SEAM_LIMIT))
    if ratio_tb > SEAM_LIMIT:
        problems.append("top/bottom seam ratio %.2f > %.1f" % (ratio_tb, SEAM_LIMIT))
    detail = "seam LR %.2fx  TB %.2fx  avg %s" % (ratio_lr, ratio_tb, avg)
    return problems, detail


def main():
    if not MANIFEST.is_file():
        print("FAIL manifest missing: %s" % MANIFEST)
        print("FAIL")
        return 1
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assets = manifest.get("assets", [])
    failed = 0
    seen_ids = set()
    for entry in assets:
        label = "%s/%s" % (entry.get("category"), entry.get("id"))
        problems, detail = check_entry(entry, seen_ids)
        if problems:
            failed += 1
            print("FAIL %-28s %s" % (label, "; ".join(problems)))
        else:
            print("OK   %-28s %s" % (label, detail))
    if not assets:
        print("FAIL manifest has no assets")
        failed += 1
    print("")
    if failed:
        print("FAIL: %d of %d textures failed" % (failed, len(assets)))
        return 1
    print("PASS: all %d textures validated" % len(assets))
    return 0


if __name__ == "__main__":
    sys.exit(main())
