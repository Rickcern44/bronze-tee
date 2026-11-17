"""Builds the Bronze Tee .glb assets with Blender (headless). Entry point of the Blender pipeline.

Run (args after `--` are for this script):
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \
        -P tools/blender/build.py -- --family=trees
    ... -- --family=zz_smoke        (one family into assets/models/<family>/, partial manifest)
    ... --                          (every families/*.py: full rebuild, writes assets/models/manifest.json)

What it does
1. Writes assets/models/palette/palette_default.png and palette_autumn.png (pure Python, no Blender image API).
2. For each selected family module in tools/blender/families/*.py (names not starting with "_"):
   deletes that family's old .glb and .glb.import files, then calls build(out_dir) -> list of manifest entries.
3. With --family: writes assets/models/<family>/manifest.partial.json (validate.gd reads it with --family).
   Without it: writes assets/models/manifest.json (palettes, all entries sorted by id).

Exit code 0 on success, 1 on any error (including a traceback inside a family).
"""

import argparse
import glob
import importlib.util
import json
import os
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bt_kit as bt  # noqa: E402

FAMILIES_DIR = os.path.join(HERE, "families")


def _args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog="build.py")
    parser.add_argument("--family", default="", help="build only this family")
    return parser.parse_args(argv)


def _family_files(only):
    if only:
        path = os.path.join(FAMILIES_DIR, only + ".py")
        if not os.path.isfile(path):
            raise SystemExit("build: no family file %s" % path)
        return [path]
    return sorted(p for p in glob.glob(os.path.join(FAMILIES_DIR, "*.py"))
                  if not os.path.basename(p).startswith("_"))


def _load_family(path):
    name = os.path.splitext(os.path.basename(path))[0]
    spec = importlib.util.spec_from_file_location("bt_family_" + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not callable(getattr(module, "build", None)):
        raise RuntimeError("family %s has no build(out_dir) function" % name)
    return module


def _clear_family_glbs(out_dir):
    if not os.path.isdir(out_dir):
        return
    for name in os.listdir(out_dir):
        if name.endswith(".glb") or name.endswith(".glb.import"):
            os.remove(os.path.join(out_dir, name))


def _check_entries(family, entries):
    if not isinstance(entries, list) or not entries:
        raise RuntimeError("family %s returned no entries" % family)
    seen = set()
    for entry in entries:
        if not isinstance(entry, dict) or not entry.get("id"):
            raise RuntimeError("family %s returned an entry without an id" % family)
        if entry["id"] in seen:
            raise RuntimeError("duplicate id %s in family %s" % (entry["id"], family))
        if entry.get("family") != family:
            raise RuntimeError("entry %s has family %r, expected %r" % (entry["id"], entry.get("family"), family))
        seen.add(entry["id"])


def _write_json(path, data):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def main():
    args = _args()
    palettes = bt.write_palettes()
    print("palettes written: %s" % ", ".join(palettes.values()))
    palette_refs = {name: bt.to_res(path) for name, path in palettes.items()}

    families = _family_files(args.family)
    if not families:
        raise RuntimeError("no family modules in %s; refusing to overwrite manifest.json with an empty build"
                           % FAMILIES_DIR)
    everything = []
    for path in families:
        family = os.path.splitext(os.path.basename(path))[0]
        out_dir = os.path.join(bt.MODELS_DIR, family)
        os.makedirs(out_dir, exist_ok=True)
        _clear_family_glbs(out_dir)
        bt.reset_scene()
        module = _load_family(path)
        entries = module.build(out_dir)
        _check_entries(family, entries)
        entries = sorted(entries, key=lambda e: e["id"])
        if args.family:
            _write_json(os.path.join(out_dir, "manifest.partial.json"),
                        {"version": 1, "family": family, "assets": entries})
        everything.extend(entries)
        print("family %s: %d assets" % (family, len(entries)))

    if not args.family:
        everything.sort(key=lambda e: e["id"])
        _write_json(os.path.join(bt.MODELS_DIR, "manifest.json"),
                    {"version": 1, "palettes": palette_refs, "assets": everything})
        print("wrote manifest.json with %d assets" % len(everything))
    print("BUILD OK")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except BaseException:
        traceback.print_exc()
        print("BUILD FAILED")
        sys.exit(1)
    sys.exit(0)
