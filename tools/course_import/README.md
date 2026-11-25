# Real course importer

Install the Python requirements once with `python3 -m pip install -r tools/course_import/requirements.txt`.

```sh
python3 tools/course_import/course_import.py init royal_crest --bbox -81.89 41.31 -81.87 41.325
# Fill each discovered hole's par, handicap and tee yardages (and [scorecard] source) in resources/courses/royal_crest/course.toml.
python3 tools/course_import/course_import.py fetch royal_crest
python3 tools/course_import/course_import.py build royal_crest
python3 tools/course_import/course_import.py validate royal_crest
python3 tools/course_import/course_import.py preview royal_crest
```

`init` accepts exactly one of `--osm way/<id>` or `--bbox minlon minlat maxlon maxlat`. It writes a draft spec and discovers OSM hole references; scorecard fields need to be filled before fetch/build. `fetch` caches the OSM response, a 3DEP GeoTIFF, and source metadata under `~/.cache/bronze-tee/courses/<id>/`. `build` writes resources into the course folder. Preview images go under `build/course_import/<id>/`.

The tool uses only network downloads in `fetch` and `init`; build, validation, preview, and the unit tests run offline. Generated resources follow the course folder, provenance, local-frame, and `.srf` contracts in `docs/features/course-import.md`. In-game loading and export of those resources require RCE-168 and RCE-169.

## Royal Crest (RCE-175)

`resources/courses/royal_crest/` is the imported 18-hole course and the project default (`bronze_tee/course/default`). Its `course.toml` is the committed source: the bbox, the stymie.golf scorecard (par, handicap, white and blue yardages) and any overrides. Regenerate with `fetch`, `build`, `validate`, `preview`; the generated `.tres`, `.f32`, `.srf` and `ATTRIBUTION.md` are committed so the game needs no tooling. `fetched.json` and `build_report.json` are working files and stay untracked. `build` takes about 5 minutes for 18 holes (pure-Python distance transforms).

Behaviour worth knowing:

* **Crop (RCE-179).** Each hole's heightmap and surface map share a crop derived from the mapped hole line, tee pads and green plus a 40 m margin, snapped outward to 10 m and at least 140 m wide and 40 m behind the tee. The origin (min X, max Z) is written into `elevation_origin` and `surface_map_origin` of the hole resource, so doglegs and far blue tees are not clipped. Force one with `crop = [minx, maxx, minz, maxz]` on a `[[holes]]` entry.
* **Greens** belong to the hole whose pin they contain; a green without a pin (practice green) renders as fairway. Multipolygon fairways (OSM relations) keep their inner rings; pins are OSM nodes.
* **Fairway band synthesis** from the hole line is only used when OSM maps no fairway in the crop. Cart paths are lines and are painted 2.5 m wide.
* **Tees.** The white pad is the mapped tee nearest the hole start. OSM rarely maps the blue tees, so the blue pad is the white pad moved back along the first leg of the hole line by the scorecard yardage difference. The game cycles white and blue with T; black tees (a fictional extra in the legacy course) are not imported.
* **Length check.** `validate` compares the mapped play length (the whole polyline) with the white yardage and fails beyond 10%. Hole 4's mapped line is 489 yd against 544 yd on the card; it carries `accept_length_mismatch = true` with a comment in `course.toml` so the scorecard stays the reference.
