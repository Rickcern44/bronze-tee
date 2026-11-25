# Course import pipeline (RCE-167)

## Goal
Turn "I want course X in the game" into a playable 18-hole course with real or authored topography: elevation, routing, tees, greens, fairways, bunkers, water and cart paths. Two source kinds are in scope:

* **Real US courses**: USGS 3DEP 1 m lidar elevation plus OpenStreetMap golf features, completed with scorecard data.
* **Fictional or classic-game courses**: no survey data. A written spec (routing, par and yardage, feature shapes, terrain intent) drives deterministic synthesis.

Non-US real courses and tree placement are follow-up work. Trees stay procedural rows for now.

## Shape of the solution
A **Claude skill** (`.claude/skills/course-import/`) does the judgment work: identifying the course, checking OSM completeness, finding scorecard data, writing or fixing the spec, reviewing preview images and checking licenses. It calls a **deterministic Python CLI** (`tools/course_import/`) that does the data work and can be rerun without Claude.

```
course.toml (spec, versioned) ──► fetch (real only; cached outside repo)
                                      │  3DEP DEM crop + OSM golf features
                                      ▼
                       normalize → per-hole local frame (meters)
                                      │  (fictional: synthesize heightfield + shapes here)
                                      ▼
            build → .f32 heightmaps, .srf surface maps, hole .tres, course .tres, ATTRIBUTION.md
                                      ▼
                validate + preview PNGs → skill reviews → edit course.toml → rebuild
```

Both source kinds converge on one intermediate form: per-hole features and a heightfield in hole-local meters. Build, validate and preview code is shared.

## Verified data sources (2026-11-23)
* **3DEP ImageServer** returns a cropped 1 m float GeoTIFF directly, so no 300 MB tile download is needed:
  `https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/exportImage?bbox=<minx,miny,maxx,maxy>&bboxSR=<utm epsg>&imageSR=<utm epsg>&size=<w,h>&format=tiff&pixelType=F32&interpolation=RSP_BilinearInterpolation&noData=-9999&f=image`
  The test crop around Royal Crest hole 1 in EPSG:26917 came back as 400×400 at 1.0 m, with the tee at about 260.0 m. Limit: 8000 px per side. The service is a best-available mosaic, so it is 1 m only where 1 m lidar exists.
* **TNM Access API** names the underlying 1 m product for attribution and survey date:
  `https://tnmaccess.nationalmap.gov/api/v1/products?datasets=Digital%20Elevation%20Model%20(DEM)%201%20meter&bbox=<lon,lat,lon,lat>&prodFormats=GeoTIFF`
  For Royal Crest it returned `USGS 1 Meter 17 x42y458 OH_Statewide_Phase1_2019_B19`, which matches the spike's tile.
* **OpenStreetMap**: Royal Crest already has all 18 `golf=hole` ways (`ref` 1–18, no `par`), 30 tees, 20 greens, 18 pins, 18 fairway multipolygon relations, 5 fairway ways, 8 bunkers, 5 water hazards and 11 cart paths. Fairways come as both closed ways and multipolygon relations. Use Overpass first. It was unreachable from the VM, so fall back to `https://api.openstreetmap.org/api/0.6/map.json?bbox=…` (fine for one course-sized bbox). Send a descriptive User-Agent.
* Scorecard data (par, handicap, per-tee yardage) is not in OSM. The skill finds it and records the source URL in `course.toml`.

## Contracts (fixed here so tickets can run in parallel)

### Folder layout
```
resources/courses/<course_id>/
  course.toml            # source spec, hand/skill-authored, versioned; never generated
  course.tres            # generated CourseDefinition
  holes/hole_01.tres …   # generated HoleDefinition
  terrain/hole_01.f32    # heightmap, existing format (LE float32, row-major, 2 m)
  terrain/hole_01.srf    # surface map, PNG bytes (see below)
  ATTRIBUTION.md         # generated from provenance
```
Generated files are overwritten on every build. Overrides belong in `course.toml`, never in hand edits to `.tres` files. Raw downloads are cached in `~/.cache/bronze-tee/courses/<course_id>/`, and previews go to `build/course_import/<course_id>/` (gitignored).

### Hole-local frame (unchanged from today)
The origin is the start of the OSM hole line (the white or middle tee). -Z points toward the end of the hole line (the pin), +X is the player's right, and heights are meters relative to the ground at the origin. Each hole has its own frame and crop, and the game still loads one hole at a time. The UTM zone is chosen from course longitude. Store each hole's origin lat/lon and bearing in the generated hole resource so it can be reproduced.

### Surface map (`.srf`)
* A PNG-encoded, 8-bit, two-channel (LA) image stored under a non-imported extension. The game reads it with `Image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))`, so Godot's importer never touches it. Add `*.srf` to the export `include_filter` next to `*.f32`.
* Channel 0 holds the surface ID: 0 deep rough, 1 second cut, 2 first cut, 3 fairway, 4 green, 5 collar, 6 tee, 7 path, 8 water, 9 bunker. These match `Surface` in `main.gd` plus bunker; reconcile the numbering in one place.
* Channel 1 holds the distance to the nearest boundary of a different surface, in 0.1 m units clamped at 25.5 m. The shader uses it for step shadows, banks and shallows, and to smooth sub-texel edges. Gameplay ignores it.
* Spacing is 0.5 m, with the same origin convention as the heightmap (first sample at the min-X, max-Z corner; rows advance toward -Z). The crop is derived per hole from its mapped line, tee pads and green plus a 40 m margin (RCE-179: it was a fixed origin of (-70, 40) before), and the origin is stored in the hole resource. Resource fields: `surface_map_file`, `surface_map_origin`, `surface_map_spacing`, `surface_map_dimensions`.
* The tool bakes cut bands and the collar: first cut is the fairway distance up to `first_cut_width`, second cut follows that, and the collar is a band around the green polygon. Features belonging to *neighbouring* holes inside the crop are rasterized as well: their fairways, bunkers and water are kept, and their greens and tees become fairway, so nobody putts on the wrong green.
* Holes without a surface map keep today's parametric path (ellipses and centerline width). Existing test fixtures stay valid.

### Hole resource additions
`surface_map_*` (above), `origin_latlon: Vector2`, `bearing_deg: float`, and `fairway_centerline` with no 4-point cap when a surface map is present (it still drives aim, markers, path and tree rows). The tool also writes `green_radii` as the best-fit ellipse of the green polygon so existing green read and putting code keeps working.

### Course resource additions
`id`, `source_kind` (`real` | `fictional`), `provenance: Array[Dictionary]` (name, url, license, attribution, retrieved date, survey date), `crs`, `origin_latlon`, `notes`.

### `course.toml` sketch (stdlib `tomllib`, no dependency)
```toml
id = "royal_crest"
name = "Royal Crest"
kind = "real"                       # or "fictional"
[real]
osm_course = "way/123456"           # or bbox = [minlon, minlat, maxlon, maxlat]
dem = "usgs-3dep"
[scorecard]
source = "https://…"
tees = ["black", "blue", "white"]   # game supports up to 3 pads
[[holes]]
number = 1
par = 4
handicap = 7
yards = { blue = 370, white = 353 }
# optional overrides
osm_hole = "way/1500889372"
route = [[0,0],[5,-120],[0,-322]]   # fictional: required; real: replaces the OSM line
features = [{ type = "bunker", ellipse = [12, -300, 6, 4] }]
[holes.terrain]                     # fictional only
seed = 7
style = "rolling"                   # flat | rolling | hilly | links
relief_m = 4
tee_to_green_m = -3
```

## Tickets
| Ticket | Area | Depends on |
|---|---|---|
| RCE-168 Per-course folders, provenance manifest, selectable active course | Data model | none |
| RCE-169 Baked surface maps for arbitrary course features | Game | RCE-168 (folder layout only) |
| RCE-170 Bunkers: sand surface, texture and lie | Game | RCE-169 |
| RCE-171 18-hole rounds: front/back-nine scorecard and progression | Game/UI | none |
| RCE-172 course_import CLI: real US courses | Tool | contracts above; RCE-168 and RCE-169 to load output in-game |
| RCE-173 course_import: fictional/classic-course synthesis | Tool | RCE-172 |
| RCE-174 course-import Claude skill | Skill | RCE-172 (RCE-173 for the fictional path) |
| RCE-175 Import full 18-hole Royal Crest via the pipeline | Content | RCE-168–172, RCE-174 (done by driving the CLI by hand; the skill is not required) |

RCE-168, RCE-171 and RCE-172 can start in parallel.

## Acceptance for RCE-167
* Running the skill on Royal Crest produces 18 playable holes with real elevation and OSM greens, fairways, bunkers, water and paths. `./tools/check.sh` passes, and an 18-hole round can be played start to finish.
* A regenerated hole 1–4 heightmap matches the committed spike `.f32` within 0.1 m RMS over the overlapping grid. The source and frame are the same, so this is a golden test for the transform.
* The skill can produce a playable fictional 18-hole course from a written description alone.
* Every generated course ships an `ATTRIBUTION.md` with USGS (public domain) and OSM (© OpenStreetMap contributors, ODbL) credits, and `course.tres` carries the provenance.

## Risks and notes
* Getting greens right matters most. Raw 1 m lidar gives unplayable greens; keep the in-game plane fit (capped at 2%) and drive it from the green mask instead of the ellipse. Authored green contours are a later ticket.
* OSM quality varies. `validate` must flag missing greens, tees or pins, hole lines whose length is more than 10% off scorecard yardage, and features it cannot assign to a hole. The skill fixes these through `course.toml` overrides.
* Non-monotonic routes (a hole line whose Z reverses) are rejected for now. With surface maps only the aim and path helpers need the monotonic centerline.
* Recreating a commercial game's *fictional* course reproduces someone else's design. That's fine for personal play, but the skill must flag it before anything is distributed.
* Python dependencies: numpy, pyproj and rasterio are already on the VM; add scipy (distance transforms) through `tools/course_import/requirements.txt`. Tool tests use stdlib `unittest` with offline fixtures (a saved OSM JSON and a small synthetic DEM) and run as a new `check.sh` stage.

## Status: Royal Crest imported (RCE-175)
`resources/courses/royal_crest/` is the default course: 18 holes, par 71, white and blue tees from the [stymie.golf scorecard](https://stymie.golf/golf-courses/ohio/lorain-county/columbia-station/royal-crest-golf-club), OSM tees, greens, pins, fairways (including multipolygon relations), 8 bunkers, 5 water hazards and 11 cart paths, and 3DEP 1 m elevation (`USGS 1 Meter 17 x42y458 OH_Statewide_Phase1_2019_B19`). Attribution is in `ATTRIBUTION.md` and the course `provenance` (USGS public domain, © OpenStreetMap contributors under ODbL, scorecard source). `tests/royal_crest_course_check.gd` and `tests/royal_crest_round_check.gd` cover the data and a full autopilot round. Findings from importing real data: OSM pins are nodes and fairways are often multipolygon relations (both were previously dropped), `.tres` text cannot carry `\u` escapes or `Vector2.ZERO`, and the OSM hole 4 line is 10% shorter than the scorecard.
