"""Build the procedural texture library.

Run with the system Python 3 (Pillow required):

    python3 tools/textures/build.py

Writes assets/textures/library/<category>/<id>.png, manifest.json, and the contact
sheet assets/textures/library/_previews/p0.png. Output is deterministic.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from families import ground, sand, turf  # noqa: E402
from tex_kit import contact_sheet  # noqa: E402

ROOT = HERE.parents[1]
LIB = ROOT / "assets" / "textures" / "library"
FAMILIES = (turf, sand, ground)
CATEGORIES = ("turf", "sand", "ground")


def main():
    LIB.mkdir(parents=True, exist_ok=True)
    entries = []
    for family in FAMILIES:
        entries.extend(family.build(LIB))
    entries.sort(key=lambda e: e["id"])

    ids = [e["id"] for e in entries]
    duplicates = sorted({i for i in ids if ids.count(i) > 1})
    if duplicates:
        raise SystemExit("duplicate texture ids: " + ", ".join(duplicates))

    # Remove PNGs left behind by removed textures (only inside category folders).
    keep = {(e["category"], e["id"]) for e in entries}
    for category in CATEGORIES:
        for png in (LIB / category).glob("*.png"):
            if (category, png.stem) not in keep:
                png.unlink()

    manifest = {"version": 1, "assets": entries}
    (LIB / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    previews = LIB / "_previews"
    previews.mkdir(exist_ok=True)
    (previews / ".gdignore").touch(exist_ok=True)
    contact_sheet(entries, LIB, previews / "p0.png")

    for e in entries:
        print("built %s/%s.png %s" % (e["category"], e["id"], e["avg_color"]))
    print("manifest: %s" % (LIB / "manifest.json"))
    print("contact sheet: %s" % (previews / "p0.png"))


if __name__ == "__main__":
    main()
