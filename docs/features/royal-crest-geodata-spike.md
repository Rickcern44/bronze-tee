# Royal Crest: geodata feasibility spike

The four playable holes use real, offline elevation crops and approximate mapped centerlines. The aim is a recognizable playable course, not a survey or an exact recreation.

## Sources and attribution

* Ground elevation: [USGS 3DEP 1-meter DEM, OH Statewide Phase 1 2019](https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/1m/Projects/OH_Statewide_Phase1_2019_B19/TIFF/USGS_1M_17_x42y458_OH_Statewide_Phase1_2019_B19.tif), tile `17_x42y458`, published July 2023. The USGS [catalog](https://catalog.data.gov/dataset/1-meter-digital-elevation-models-dems-usgs-national-map-3dep-downloadable-data-collection) states that 3DEP products are public domain. The source is a bare-earth model; a 1 m horizontal grid is not a guarantee of putting-green accuracy. The source survey predates any later course changes.
* Centerlines: OpenStreetMap ways [hole 1](https://www.openstreetmap.org/way/1500889372), [hole 2](https://www.openstreetmap.org/way/1500889373), [hole 3](https://www.openstreetmap.org/way/1500889374), and [hole 4](https://www.openstreetmap.org/way/1500889375); © OpenStreetMap contributors, [ODbL](https://www.openstreetmap.org/copyright). The mapped points are approximate; the lines are not surveys of tee or pin positions. Scorecard yardages are retained as metadata and do not necessarily match the mapped lines or tees.
* Tee pads and marker positions are approximate. Blue scorecard distances follow [this Royal Crest scorecard](https://stymie.golf/golf-courses/ohio/lorain-county/columbia-station/royal-crest-golf-club); the black tee is a fictional difficulty option 20 yards behind blue, not a claim that Royal Crest has black tees. The white pads were moved back from the mapped centerline origin, and blue and black are placed farther back along the first leg. Tree positions, fairway width and shapes, cart path, green boundary and cup remain game-authored approximations. We have not yet compared them against imagery or established their exact real-world locations. Do not interpret the green's slopes as accurate enough for real-world putting advice.

## How the crop works

`tools/import_royal_crest_elevation.py` transforms the mapped tee and green into the GeoTIFF's projected CRS (the supplied tile is NAD83 / UTM zone 17N, EPSG:26917). Each mapped tee is a local origin, negative Z points toward that hole's mapped green, and positive X points right. The importer bilinearly samples the source at 2 m spacing and subtracts the mapped origin's elevation. The outputs `resources/courses/royal_crest_legacy/terrain/royal_crest_01.f32` through `royal_crest_04.f32` are little-endian float32, row-major, with their first sample at X = -120 m, Z = 100 m; rows advance toward negative Z. Holes 1–3 use 161 × 301 samples; hole 4 uses 171 × 251.

Each hole resource configures its grid and centerline points. The same `_ground_height` function feeds the terrain mesh, ball simulation through `PhysicsBridge`, previews, trees and the cup. It bilinearly interpolates the sampled ground and blends it into a playable plane over each green. The plane is fitted to nearby elevation samples and its slope is capped at 2%: raw 1 m data produced excessively steep greens. The resulting putting surface is an approximation, not a measured green. Queries outside the grid clamp to its edge. The rendered terrain mesh is sampled on a 2 m grid and triangulated; between vertices it approximates the physics surface. Fictional holes can still use procedural terrain. The default tee aim points down the first mapped leg.

To reproduce the crop, download the tile above and run:

```sh
python3 -m pip install numpy pyproj rasterio
python3 tools/import_royal_crest_elevation.py /path/to/USGS_1M_17_x42y458_OH_Statewide_Phase1_2019_B19.tif resources/courses/royal_crest_legacy/terrain/royal_crest_01.f32 --hole 1
```

Repeat with `--hole 2`, `--hole 3` and `--hole 4` and the corresponding output filenames. The source tile is roughly 322 MB; each resulting game file is under 200 KB. Keep the source tile outside the game project. The generated `.f32` files are non-resource files: when creating a Godot export preset, include `*.f32` in its non-resource export filter so exported builds contain the terrain.

## Next steps

1. Compare the mapped route with appropriately licensed Ohio aerial imagery and confirm the correct tee, green and turning points with someone familiar with the hole.
2. Trace the fairway, green, bunkers, water and important trees; the current centerline-and-width fairway is only an approximation. Check each source's license and attribution before incorporating or sharing derived data.
3. Play-test shots and putting on the imported slopes. Tune the fitted greens or author more detailed green contours if the current playable approximation does not feel right; keep the source elevation separate for comparison.
4. Generalize the importer only after proving the coordinate transform and authoring workflow on this hole. A future tool should record source, survey date, CRS, orientation and licensing with each imported course.
