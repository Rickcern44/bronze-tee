# Real course importer

Install the Python requirements once with `python3 -m pip install -r tools/course_import/requirements.txt`.

```sh
python3 tools/course_import/course_import.py init royal_crest --bbox -81.886 41.312 -81.878 41.321
# Fill each discovered hole's par and tee yardages in resources/courses/royal_crest/course.toml.
python3 tools/course_import/course_import.py fetch royal_crest
python3 tools/course_import/course_import.py build royal_crest
python3 tools/course_import/course_import.py validate royal_crest
python3 tools/course_import/course_import.py preview royal_crest
```

`init` accepts exactly one of `--osm way/<id>` or `--bbox minlon minlat maxlon maxlat`. It writes a draft spec and discovers OSM hole references; scorecard fields need to be filled before fetch/build. `fetch` caches the OSM response, a 3DEP GeoTIFF, and source metadata under `~/.cache/bronze-tee/courses/<id>/`. `build` writes resources into the course folder. Preview images go under `build/course_import/<id>/`.

The tool uses only network downloads in `fetch` and `init`; build, validation, preview, and the unit tests run offline. Generated resources follow the course folder, provenance, local-frame, and `.srf` contracts in `docs/features/course-import.md`. In-game loading and export of those resources require RCE-168 and RCE-169.
