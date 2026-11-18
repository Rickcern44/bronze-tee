"""Build the procedural texture library.

Run with the system Python 3 (Pillow required):

    python3 tools/textures/build.py

Writes assets/textures/library/<category>/<id>.png, manifest.json, and the contact
sheets assets/textures/library/_previews/p0.png (P0) and p1.png (P1). Output is
deterministic.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from families import bark, cover, ground, rock, sand, turf, water  # noqa: E402
from tex_kit import contact_sheet  # noqa: E402

ROOT = HERE.parents[1]
LIB = ROOT / "assets" / "textures" / "library"
P0_FAMILIES = (turf, sand, ground)
P1_FAMILIES = (water, cover, rock, bark)
FAMILIES = P0_FAMILIES + P1_FAMILIES
CATEGORIES = ("turf", "sand", "ground", "water", "cover", "rock", "bark")


def main():
    LIB.mkdir(parents=True, exist_ok=True)
    p0, p1 = [], []
    for family in P0_FAMILIES:
        p0.extend(family.build(LIB))
    for family in P1_FAMILIES:
        p1.extend(family.build(LIB))
    entries = sorted(p0 + p1, key=lambda e: e["id"])

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
    contact_sheet(sorted(p0, key=lambda e: e["id"]), LIB, previews / "p0.png")
    contact_sheet(sorted(p1, key=lambda e: e["id"]), LIB, previews / "p1.png")

    for e in entries:
        print("built %s/%s.png %s" % (e["category"], e["id"], e["avg_color"]))
    print("manifest: %s" % (LIB / "manifest.json"))
    print("contact sheets: %s, %s" % (previews / "p0.png", previews / "p1.png"))


if __name__ == "__main__":
    main()
