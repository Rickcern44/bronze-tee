# Procedural texture library

Generates the stylized, seamless 512x512 terrain textures used by the course.
Pillow only (numpy is not required). Output is deterministic: each texture seeds
its own `random.Random` from a hash of its id.

## Layout

- `tex_kit.py`: shared helpers (periodic noise, colour ramps, wrapped strokes,
  pebbles, cracks, PNG save, manifest entry, contact sheet).
- `families/turf.py`, `sand.py`, `ground.py` (P0) and `families/water.py`,
  `cover.py`, `rock.py`, `bark.py` (P1): one module per family. Each exposes
  `build(out_dir) -> list of manifest entries`.
- `build.py`: runs every family, writes the PNGs, `manifest.json`, and the
  contact sheets `_previews/p0.png` (P0 only) and `_previews/p1.png` (P1 only).
- `validate.py`: checks the manifest and PNGs (size, avg colour, edge seams, unique ids).

Outputs go to `assets/textures/library/<category>/<id>.png` and
`assets/textures/library/manifest.json`. `_previews/` has a `.gdignore`, so Godot
does not import the contact sheet.

## Usage

```
python3 tools/textures/build.py
python3 tools/textures/validate.py
```

Use the system Python 3 with Pillow installed. `validate.py` exits with code 1 on any failure.

## Catalog

Ids are the file names under `assets/textures/library/<category>/`.

| Phase | Category | Ids |
| --- | --- | --- |
| P0 | turf | fairway_light, fairway_dark, first_cut, second_cut, deep_rough, collar, green, native_fescue |
| P0 | sand | bunker_sand, bunker_sand_raked |
| P0 | ground | dirt, gravel_path, cart_path |
| P1 | water | water_deep, water_shallow |
| P1 | cover | mud, leaf_litter, pine_needles, moss, wildflower_meadow |
| P1 | rock | rock_grey, cliff_strata, cobble |
| P1 | bark | bark_oak, bark_pine, bark_birch |

Each entry's `use` line in `manifest.json` describes it.

## Adding a texture

1. Pick the family it belongs to (or add a new `families/<name>.py` with a
   `build(out_dir)` function and register it in `FAMILIES` in `build.py`).
2. Add a spec or a `save_texture(...)` call with a unique id, the category, and a one-line `use` hint.
   Build the image from `paint(make_lut(...), fbm(rng, octaves), ...)`, then add
   `draw_strokes`, `draw_dots`, or `draw_walks` as needed. All of these wrap at the edges.
   Keep the colours in the palette (leaf greens 8FCB5E / 4F9D45 / 2F6B3A, trunk brown 6B4A32,
   rock greys B3AC9E / 8A8478, bronze C98F4A) and the average luminance near mid.
3. Run `build.py` and then `validate.py`. Review `_previews/p0.png`.

Use integer `cells` and stroke/stripe cycles that divide 512, so the pattern repeats across the seam.
