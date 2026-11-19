# Asset work handoff

Paused 2026-11-18. Read `docs/assets/PIPELINE.md` first (rules, contracts, commands, definition of done). This file lists where things stand and what is left.

## Where things stand

### Models (Blender pipeline, `tools/blender/`)
- 48 models in `assets/models/{trees,props,nature}/`, rebuilt with the refreshed palette. Godot `validate.gd` passes (48 assets, 0 failures).
- The palette change is in `tools/blender/bt_kit.py` (`_PALETTE_DEFAULT_HEX` and the autumn overrides), so every rebuild keeps the new colours.
- Previews in `assets/models/_previews/` were regenerated after the palette change.
- Another Claude session ("3D Modeller") owns `tools/blender/`. It has not been told that `bt_kit.py` was edited. It should know, or it may overwrite the palette.
- Hand-tuned models, if any are made later, go in `assets/models/handmade/` with the same id, pivot and part names. The folder does not exist now (the old copy was a duplicate and was removed).

### Textures (Pillow pipeline, `tools/textures/`)
- 42 textures built in `assets/textures/library/` (P0: 13, P1: 13, P2: 9, P3: 7). `validate.py` checks the library.
- P1 fixes are done once. Optional polish remains (see below).
- Phases P2 and P3 were rebuilt after the server copy was lost. Their appearance can differ from that copy. They remain library assets and are not applied to the game.

### Game wiring (`scripts/main.gd`, `TERRAIN_TEXTURES`)
Applied from the library: green, collar, fairway_light, fairway_dark, first_cut, second_cut, deep_rough, cart_path.
Still the old file: `water_texture` (`assets/textures/terrain/water.png`).
Old textures are still in `assets/textures/terrain/` for rollback. A backup of the original `main.gd` is not in the repo (it was in a session scratchpad); rolling back means restoring the old `res://assets/textures/terrain/...` path strings.
The user was going to validate the new textures in the running game. No result has been reported yet.

### Runner
`tools/pipeline.sh` (`check`, `textures`, `models`, `previews`, `determinism`, `all`). `all` passed on this machine in 135 s. Not yet run on the server.

## What is left

1. **Server move.** Get the project to the server (it is not a git repo here). Needs `tools/`, `docs/assets/`, `assets/`, `scripts/` and `project.godot`. Install Blender 5.3, the .NET build of Godot and Pillow, set `BLENDER`, `GODOT`, `PYTHON` if the paths differ, then run `tools/pipeline.sh check` and `tools/pipeline.sh all`.
2. **In-game check of the new textures.** The user validates the eight applied slots. If they look too bright or dark, the first lever is `TERRAIN_ALBEDO_GAIN` (0.75) in `main.gd`; do not change it without being told. Roll back by restoring the old path strings.
3. **Apply water.** Point `water_texture` at `res://assets/textures/library/water/water_deep.png` (or `water_shallow.png`), then run `$GODOT --headless --path . --import`. `water_deep` is the better fit; its dark ripples are a bit prominent if it looks busy.
4. **Tell the 3D Modeller session** about the `bt_kit.py` palette edit, so it keeps it.
5. **Phase 2 textures (9, rebuilt):** wood: `boardwalk_planks`, `bridge_planks`, `fence_wood`; masonry: `stone_wall`, `brick`, `concrete`; roofing and siding: `roof_shingle`, `siding_white`, `metal_green`. See `_previews/p2.png`.
6. **Phase 3 textures (7, rebuilt):** alpha decals `divot`, `ball_mark`, `tire_tracks`, `mow_stripe`, `tee_box_edge`; alpha foliage cards `leaf_cluster_green`, `leaf_cluster_autumn`. These are non-tileable RGBA images. See `_previews/p3.png`.
7. **Optional P1 polish:**
   - `cobble`: still on a fairly regular grid; shading is subtle.
   - `rock_grey`: facets are busy at tile scale.
   - `mud`: puddle sheen reads as grey-blue blobs.
   - `bark_pine`: vertical elongation is modest.
   - `water_deep`: dark ripple segments could have lower contrast.
8. **Library textures with no game slot** (sand, dirt, gravel, fescue, bark, rock, cover, decals) are library-only. Engine code to use them is a separate task and has not been scoped.
9. **Housekeeping.** Godot extracts embedded textures next to model files (about 33 extra `*_palette_default.png` and similar in `assets/models/{trees,props}/`). Harmless but untidy; could be stopped with an import setting. Not done.

## Known caveats

- numpy is not installed for the default `python3` (3.9.6). The texture tools use Pillow only; keep it that way.
- Use the .NET Godot build (`Godot_mono.app`). Plain Godot hangs the tests.
- Build model families together only when all family modules exist; `build.py` with no `--family` rewrites `manifest.json`.
- Previews render with Cycles on the CPU; allow a few minutes for all families.
- Not a git repo: nothing is committed, and there is no history to roll back to. Keep copies before large changes.

## Verify before you start

```sh
tools/pipeline.sh check
tools/pipeline.sh all
```

Expected: every step OK, textures `PASS: all 26`, models `PASS (48 assets, 0 failures)`, determinism PASS.
