# Procedural texture library

Generates the stylized, seamless 512x512 terrain textures used by the course.
Pillow only (numpy is not required). Output is deterministic: each texture seeds
its own `random.Random` from a hash of its id.

## Layout

- `tex_kit.py`: shared helpers (periodic noise, colour ramps, wrapped strokes,
  pebbles, cracks, PNG save, manifest entry, contact sheet).
- `families/turf.py`, `families/sand.py`, `families/ground.py`: one module per
  family. Each exposes `build(out_dir) -> list of manifest entries`.
- `build.py`: runs every family, writes the PNGs, `manifest.json`, and
  `_previews/p0.png` (contact sheet).
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
