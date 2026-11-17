# Blender asset pipeline (tools/blender)

Builds the game's `.glb` models with Blender 5.3 (headless), then Godot validates them. The output contract
(file names, manifest schema, part names, pivots, units, +Y up, faces -Z) is the same as the old Godot generators.
The old generators are kept in `tools/assets/_legacy_godot/` for reference only.

## Layout

| File | Purpose |
|---|---|
| `bt_kit.py` | Shared core: palette, swatch UVs, bmesh primitives, facing swatches, bevel/decimate, noise displacement, AO bake, tree collision, export, manifest entry. Usage example at the top. |
| `build.py` | Entry point. `--family=<name>` builds one family. No family builds everything. |
| `families/*.py` | One module per family (`trees`, `props`, `nature`), each with `build(out_dir) -> list[dict]`. Files starting with `_` are ignored. |
| `previews.py` | Blender renders: 512 thumbnails, 1600x900 lineup, optional autumn lineup. |
| `contact_sheet.py` | Pillow grid of thumbnails with id and height, run with system `python3`. |

## Commands

Blender path: `/Applications/Blender.app/Contents/MacOS/Blender`. Always headless. Wrap with `perl -e 'alarm 900; exec @ARGV'`
(macOS has no `timeout`).

```sh
B=/Applications/Blender.app/Contents/MacOS/Blender
G=/Users/rickcerny/Downloads/Godot_mono.app/Contents/MacOS/Godot
P=/Users/rickcerny/dev/sandbox/bronze-tee

# build one family (writes assets/models/<family>/*.glb and manifest.partial.json)
perl -e 'alarm 900; exec @ARGV' $B -b --factory-startup --python-exit-code 1 -P $P/tools/blender/build.py -- --family=trees

# build everything (writes assets/models/manifest.json; only do this when all families exist)
perl -e 'alarm 900; exec @ARGV' $B -b --factory-startup --python-exit-code 1 -P $P/tools/blender/build.py --

# validate in Godot (one family, or the full manifest without --family)
perl -e 'alarm 300; exec @ARGV' $G --headless --path $P --script res://tools/assets/validate.gd -- --family=trees
perl -e 'alarm 300; exec @ARGV' $G --headless --path $P --script res://tools/assets/validate.gd

# previews: thumbnails and lineup, then the contact sheet
perl -e 'alarm 900; exec @ARGV' $B -b --factory-startup --python-exit-code 1 -P $P/tools/blender/previews.py -- --family=trees
perl -e 'alarm 900; exec @ARGV' $B -b --factory-startup --python-exit-code 1 -P $P/tools/blender/previews.py -- --family=trees --palette=autumn --skip-thumbs
python3 $P/tools/blender/contact_sheet.py --family=trees
```

Exit codes: `build.py` and `previews.py` return 0 on success and 1 on any error (a traceback is printed).
`contact_sheet.py` returns 0 or 1. `validate.gd` returns 0 on PASS.

Outputs:
- `assets/models/<family>/<id>.glb` and `manifest.partial.json` (per family)
- `assets/models/manifest.json` (full build only)
- `assets/models/palette/palette_default.png`, `palette_autumn.png` (every build, pure Python)
- `assets/models/_previews/thumbs/<id>.png`, `_previews/<family>_lineup.png`, `_previews/autumn_<family>.png`,
  `_previews/<family>.png` (contact sheet). `_previews/.gdignore` keeps Godot from importing them.

## The contract in short

- Units metres, +Y up, the model faces -Z in Godot. Blender is Z up and the front is +Y; the exporter converts.
- Pivot: `base` (min Z = 0 after build), `rim` (cup: max Z = 0), `sunk` (large rocks: must span Z = 0).
- Root empty named after the asset id, one mesh object per part, named by part (`Trunk`, `Canopy`, `Flag`...).
- One shared material per asset: palette texture (closest filtering), roughness 0.9, metallic 0.
  Yardage plates use `Part.set_texture()` with their own texture and get a separate material.
- Swatch i sits at UV ((col+0.5)/4, (row+0.5)/4) in glTF (row 0 at top). Faces pick a swatch by facing:
  up = light, down = dark, sides = mid.
- AO: Cycles bake into `COLOR_0` (vertex colour), remapped so the darkest crease is 0.55 and open surfaces 1.0.
  A temporary ground plane at Z = -0.02 gives contact shadow and is never exported.
- Flat shading everywhere. Triangle budgets are checked by validate (trees 1200, small trees 600, props 400,
  rocks 300, shrubs 500) and counted after modifiers.
- Deterministic: every random draw comes from `bt.rng_for(asset_id, salt, seed)`. Same seed, same file.

## Adding a family

Create `families/<name>.py` with `build(out_dir)`. Inside, create `bt.Asset(...)` per model, add parts with the
`Part` helpers, call `asset.finish(out_dir, collision=..., variation=...)` and return the list of entries.
Look at the usage example at the top of `bt_kit.py`. Then run `build.py --family=<name>`, `validate.gd
--family=<name>`, `previews.py --family=<name>` and `contact_sheet.py --family=<name>`, and look at the sheet.

## Known limits

- Build one family at a time. A full build deletes only the `.glb` files of the families it builds, then rewrites
  `manifest.json` from the families it finds, so run it only when every family module exists.
- `build.py` with no `--family` refuses to run when `families/` has no modules, so an empty build can never overwrite `manifest.json`.
- `build.py` rewrites both palette PNGs on every run (same content each time).
- Previews render with Cycles on the CPU. A full family lineup takes about 10 s per 1600x900 frame.
