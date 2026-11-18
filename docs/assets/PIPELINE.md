# Bronze Tee asset pipeline: agent handoff

Read this file first. It is written so an agent can build, check and apply assets with no questions back.
Decide, do the work, and report at the end. Stop and ask only for the items under "Stop and ask".

## 1. What we make and how

| Kind | Tool | Source of truth | Output |
|---|---|---|---|
| 3D models (trees, props, nature) | Blender 5.3, headless | `tools/blender/` (`bt_kit.py`, `families/*.py`) | `assets/models/{trees,props,nature}/*.glb`, `assets/models/manifest.json`, `assets/models/palette/*.png` |
| Tileable textures | Python 3 + Pillow (no numpy) | `tools/textures/` (`tex_kit.py`, `families/*.py`) | `assets/textures/library/<category>/<id>.png`, `assets/textures/library/manifest.json` |
| Previews (contact sheets) | Blender / Pillow | same tools | `assets/models/_previews/`, `assets/textures/library/_previews/` |
| Validation | Godot headless + Python | `tools/assets/validate.gd`, `tools/textures/validate.py` | exit code 0 = pass |

Blender is not used for flat textures. It is used for geometry and baked ambient occlusion (vertex colour).
The model colours come from a 4x4 swatch palette (`_PALETTE_DEFAULT_HEX` in `tools/blender/bt_kit.py`).

## 2. Hard rules

1. **Generators are the source of truth.** Never hand-edit a `.glb`, a library PNG, or a manifest. Change the generator, rebuild.
2. **Deterministic.** Same code gives byte-identical files (seeded by asset id). Any change you make must keep this.
3. **Same ids, part names and pivots** for existing models. Engine code depends on them.
4. **Do not touch** `scripts/`, `scenes/`, `project.godot` or `assets/fonts/` unless the task says so. The only game file the texture work edits is `scripts/main.gd` (the `TERRAIN_TEXTURES` map), and only as described in section 6.
5. **Old textures stay.** `assets/textures/terrain/*.png` and `assets/textures/*.png` are rollback copies. Do not delete or overwrite them.
6. **No commits or pushes** unless the task says so. The local copy is not a git repository.
7. Run Python with `python3` and `PYTHONDONTWRITEBYTECODE=1`. Do not leave `__pycache__` or scratch files in the repo.

## 3. One command

```sh
tools/pipeline.sh check        # environment: Blender, Godot, Python, Pillow found?
tools/pipeline.sh textures     # build + validate textures, write previews
tools/pipeline.sh models       # build 48 models, validate in Godot
tools/pipeline.sh previews     # regenerate model thumbnails, lineups and contact sheets
tools/pipeline.sh all          # everything above, then the determinism check
tools/pipeline.sh determinism  # build twice, compare hashes
```

Tool locations come from environment variables with defaults:
`BLENDER` (default `/Applications/Blender.app/Contents/MacOS/Blender`), `GODOT` (default
`$HOME/Downloads/Godot_mono.app/Contents/MacOS/Godot`; use the .NET build, plain Godot hangs the tests), `PYTHON` (default `python3`).
On the server set these first. `pipeline.sh check` tells you what is missing.

## 4. Contracts

### Models (full detail: `tools/blender/README.md`)
- Metres, +Y up, faces -Z in Godot. Root empty named after the asset id, one mesh per part, named by part.
- Pivot `base` (min Z = 0), `rim` (cup) or `sunk` (large rocks). One shared palette material per asset, flat shading, AO in `COLOR_0`.
- Triangle budgets are checked by `validate.gd`. 48 assets today; ids and counts are in `assets/models/manifest.json`.
- Add a model: edit or add `tools/blender/families/<family>.py`, run `tools/pipeline.sh models`, then `previews`, then look at the contact sheet.

### Textures
- 512x512 RGB PNG, seamless (edges match), deterministic, soft stylized look, mid luminance so the game can tint them.
- Palette hints: leaf greens `8FCB5E` `4F9D45` `2F6B3A`, trunk `6B4A32`, rock `B3AC9E` `8A8478` `5F5A52`, bronze `C98F4A`, water `3A78C8`.
- `manifest.json` schema: `{"version":1,"assets":[{"id","category","file":"res://assets/textures/library/<category>/<id>.png","size":[512,512],"tileable":true,"avg_color":"#RRGGBB","seed":int,"use":"one line"}]}`, sorted by id.
- Add a texture: add a spec to `tools/textures/families/<family>.py` (see `turf.py` for the data style), run `tools/pipeline.sh textures`, look at `_previews/*.png`.
- `validate.py` checks existence, size, seam match, avg colour and unique ids. Seam ratio must be <= 1.5.

## 5. Library status (26 textures built)

Applied in game (via `scripts/main.gd` `TERRAIN_TEXTURES`): green, collar, fairway_light, fairway_dark, first_cut, second_cut, deep_rough, cart_path.
Not applied: water (still `assets/textures/terrain/water.png`), everything else in the library.

| Phase | Textures | State |
|---|---|---|
| P0 | turf: fairway_light, fairway_dark, first_cut, second_cut, deep_rough, collar, green, native_fescue; sand: bunker_sand, bunker_sand_raked; ground: dirt, gravel_path, cart_path | built, reviewed |
| P1 | water_deep, water_shallow, mud, leaf_litter, pine_needles, moss, wildflower_meadow, rock_grey, cliff_strata, cobble, bark_oak, bark_pine, bark_birch | built, fixed once, optional polish (below) |
| P2 | wood: boardwalk_planks, bridge_planks, fence_wood; masonry: stone_wall, brick, concrete; roofing and siding: roof_shingle, siding_white, metal_green | not started |
| P3 | decals (alpha PNG): divot, ball_mark, tire_tracks, mow_stripe, tee_box_edge; foliage cards (alpha): leaf_cluster_green, leaf_cluster_autumn | not started |

### P1 status
The first round of P1 fixes is done (mud, cobble, rock_grey, both water textures, bark_pine, wildflower_meadow). Remaining polish, optional:
- `cobble`: still sits on a fairly regular grid; shading is subtle.
- `rock_grey`: facets are busy at tile scale.
- `mud`: puddle sheen is grey-blue blobs rather than clear puddles.
- `bark_pine`: vertical elongation is modest.
Water (`water_deep`, `water_shallow`) is good enough to use. Not yet applied to the game.

## 6. Applying textures to the game

The game reads terrain textures from `TERRAIN_TEXTURES` in `scripts/main.gd`. Slot to library mapping:

| Slot | Library file |
|---|---|
| green_texture | `turf/green.png` |
| collar_texture | `turf/collar.png` |
| fairway_light_texture, fairway_dark_texture | `turf/fairway_light.png`, `turf/fairway_dark.png` |
| first_cut_texture, second_cut_texture, deep_rough_texture | `turf/first_cut.png`, `turf/second_cut.png`, `turf/deep_rough.png` |
| water_texture | `water/water_deep.png` or `water/water_shallow.png` (water fixes are done) |
| path_texture | `ground/cart_path.png` |

To swap a slot: change only the path string, keep every other line of `main.gd`. Then run
`$GODOT --headless --path . --import` so the new PNGs are imported, and confirm no errors.
`TERRAIN_ALBEDO_GAIN` (0.75) scales albedo. Do not change it unless told; report if textures look clipped or dark.
To roll back, restore the old path strings (old files are still in `assets/textures/terrain/`).

Textures with no game slot (sand, dirt, gravel, fescue, bark, rock, cover, decals) are library-only until engine code uses them. Do not add engine code for them without a task.

## 7. Definition of done (for any task)

1. `tools/pipeline.sh textures` and/or `models` exit 0. Validators print PASS.
2. `tools/pipeline.sh determinism` passes (two builds byte-identical).
3. Files you were not asked to change are unchanged (hash or mtime check against a snapshot taken at the start).
4. You looked at the relevant preview image and judged it against the descriptions in this file.
5. Report: files changed, commands run, validator output summary, textures or models you are unsure about, anything you could not verify.

## 8. Stop and ask (only these)

- A task would change gameplay code beyond the `TERRAIN_TEXTURES` paths.
- A validator keeps failing after two fix attempts.
- You need a tool that is not installed (Blender 5.3, the .NET Godot build, Pillow).
- A fix needs a change to a model id, part name or pivot.

Everything else: choose the sensible option, note the choice in your report.

## 9. Moving the project to the server

The working copy is not a git repo. The server needs, at minimum: `tools/`, `docs/assets/`, `assets/models/`, `assets/textures/`, `scripts/main.gd` (and the rest of the game), `project.godot`.
The `.godot/` import cache is local and is rebuilt by `--import` on the server. `_previews/` folders are for humans and can be left out.
