extends SceneTree

# Surface maps (.srf, RCE-169): loads tests/fixtures/surface_map_hole.tres, whose
# map is baked by tools/course_import (tests/fixtures/make_surface_map_fixture.py),
# and checks lookups, lies, hazards, out-of-map handling, the green plane cap and
# that parametric holes are unaffected. Exits non-zero on the first failure.

const FIXTURE := "res://tests/fixtures/surface_map_hole.tres"
# Surface IDs from docs/features/course-import.md.
const CONTRACT := {
	"DEEP_ROUGH": 0, "SECOND_CUT": 1, "FIRST_CUT": 2, "FAIRWAY": 3, "GREEN": 4,
	"COLLAR": 5, "TEE": 6, "PATH": 7, "WATER": 8, "BUNKER": 9,
}

var failed := false

func _initialize() -> void:
	call_deferred("check")

func fail(message: String) -> void:
	failed = true
	push_error(message)
	quit(1)

func expect(condition: bool, message: String) -> bool:
	if not condition: fail(message)
	return condition

# Parametric reference values for hole 0, compared before and after a mapped hole.
func parametric_snapshot(game) -> Array:
	var out := []
	for x in range(-50, 51, 7):
		for z in range(-300, 11, 13):
			var pos := Vector3(x, 0, z)
			out.append([game._surface_at(x, z), game._lie(pos), game._in_water(pos), game._in_bunker(pos), game._on_green(pos), snappedf(game._ground_height(x, z), 0.0001)])
	return out

func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var S: Dictionary = game.Surface

	# 1. One numbering: the game enum, the shader constants and the contract agree.
	if not expect(S.size() == CONTRACT.size(), "Surface enum has %d values, contract has %d" % [S.size(), CONTRACT.size()]): return
	var shader_code: String = game.terrain_material.shader.code
	for key in CONTRACT:
		if not expect(S.get(key, -1) == CONTRACT[key], "Surface.%s is %s, contract says %d" % [key, S.get(key), CONTRACT[key]]): return
		var regex := RegEx.create_from_string("const int SRF_%s = (\\d+);" % key)
		var found := regex.search(shader_code)
		if not expect(found != null and int(found.get_string(1)) == CONTRACT[key], "terrain.gdshader SRF_%s does not match the contract" % key): return

	# 2. Parametric baseline before any map is loaded.
	game._load_hole(0)
	await process_frame
	if not expect(game.surface_map == null, "hole 0 should be parametric"): return
	var baseline := parametric_snapshot(game)
	var baseline_tee: Vector3 = game.TEE

	# 3. Mapped fixture hole.
	game.HOLES.append(load(FIXTURE))
	game._load_hole(game.HOLES.size() - 1)
	await process_frame
	if not expect(game.surface_map != null and game.surface_map.get_format() == Image.FORMAT_LA8, "fixture surface map not loaded as LA8"): return
	if not expect(game.surface_map.get_size() == Vector2i(161, 261), "fixture surface map size"): return
	# Channel 1 is in alpha: byte (row 140, col 80) is 103, the corner is clamped at 255.
	var centre: Color = game.surface_map.get_pixel(80, 140)
	if not expect(centre.r8 == S.FAIRWAY and centre.a8 == 103, "LA8 readback: expected id %d / distance 103, got %d / %d" % [S.FAIRWAY, centre.r8, centre.a8]): return
	if not expect(game.surface_map.get_pixel(0, 0).a8 == 255, "distance should clamp at 255"): return

	# Surface lookups and lies. Fixture layout: fairway |x| <= 10, z -15..-80;
	# first cut 3 m and second cut 9 m around it; tee pad |x|, |z| <= 4; green
	# ellipse at (0, -92) radii 12 x 9 (cup at x 6) with a 1.5 m collar; water x -36..-26,
	# z -30..-60; bunker ellipse at (16, -86) radii 4 x 3; path x 28..30.5.
	var cases := [
		[Vector2(0, -50), S.FAIRWAY, "Fairway"],
		[Vector2(11.5, -50), S.FIRST_CUT, "FirstCut"],
		[Vector2(15, -50), S.SECOND_CUT, "Rough"],
		[Vector2(-20, -100), S.DEEP_ROUGH, "Rough"],
		[Vector2(6, -92), S.GREEN, "Green"],
		[Vector2(12.75, -92), S.COLLAR, "Fairway"],
		[Vector2(17, -86), S.BUNKER, "Bunker"],
		[Vector2(-31, -45), S.WATER, "Rough"],
		[Vector2(29, -50), S.PATH, "Rough"],
		[Vector2(2, -2), S.TEE, "Fairway"],
		# Out of map (X -40..40, Z 20..-110) is deep rough.
		[Vector2(100, -50), S.DEEP_ROUGH, "Rough"],
		[Vector2(-41, -50), S.DEEP_ROUGH, "Rough"],
		[Vector2(0, 30), S.DEEP_ROUGH, "Rough"],
		[Vector2(6, -200), S.DEEP_ROUGH, "Rough"],
	]
	for item in cases:
		var p: Vector2 = item[0]
		var pos := Vector3(p.x, 0, p.y)
		var surface: int = game._surface_at(p.x, p.y)
		if not expect(surface == item[1], "surface at %s was %d, expected %d" % [p, surface, item[1]]): return
		if not expect(game._lie(pos) == item[2], "lie at %s was %s, expected %s" % [p, game._lie(pos), item[2]]): return
		if not expect(game._in_water(pos) == (surface == S.WATER), "_in_water at %s" % p): return
		if not expect(game._in_bunker(pos) == (surface == S.BUNKER), "_in_bunker at %s" % p): return
		if not expect(game._on_green(pos) == (surface == S.GREEN), "_on_green at %s" % p): return
		if not expect(game._on_path(p.x, p.y) == (surface == S.PATH), "_on_path at %s" % p): return
		if not expect(game._fairway_contains(p.x, p.y) == (surface == S.FAIRWAY), "_fairway_contains at %s" % p): return
		if not expect(game._first_cut_contains(p.x, p.y) == (surface == S.FIRST_CUT), "_first_cut_contains at %s" % p): return
	# The ball at the tee marker is on the tee.
	if not expect(game._lie(game.TEE) == "Tee", "lie at the tee marker"): return
	# Bunker lie plumbs through to the lie factor.
	if not expect(is_equal_approx(game._lie_factor(Vector3(17, 0, -86)), 0.62), "bunker lie factor"): return
	# Every water sample in the fixture rectangle is water, edges included.
	for x in [-35.5, -31.0, -26.5]:
		for z in [-30.5, -45.0, -59.5]:
			if not expect(game._in_water(Vector3(x, 0, z)), "water at (%s, %s)" % [x, z]): return
	if not expect(not game._in_water(Vector3(-25, 0, -45)) and not game._in_water(Vector3(-37, 0, -45)), "water must stop at its edge"): return

	# Green plane: the fixture terrain has a 5% cross slope; the fit is capped at 2%.
	var slope: Vector2 = game.imported_green_slope
	if not expect(slope.length() <= 0.02 + 1e-6, "green slope %s exceeds 2%%" % slope): return
	if not expect(slope.length() > 0.019 and slope.x > 0.0, "green slope %s should be the capped 5%% cross slope" % slope): return
	if not expect(is_equal_approx(game._mapped_green_weight(6, -92), 1.0), "green weight on the green"): return
	if not expect(game._mapped_green_weight(-20, -40) == 0.0, "green weight far from the green"): return
	if not expect(game._mapped_green_weight(500, 500) == 0.0, "green weight outside the map"): return
	var on_green: float = game._ground_height(6, -92)
	var plane: float = game.imported_green_height
	if not expect(absf(on_green - plane) < 0.001, "ground at the cup %f should follow the green plane %f" % [on_green, plane]): return

	# Shader receives the map.
	var material: ShaderMaterial = game.terrain_material
	if not expect(material.get_shader_parameter("use_surface_map") == true, "use_surface_map not set"): return
	if not expect(material.get_shader_parameter("surface_ids") != null and material.get_shader_parameter("surface_distances") != null, "surface textures not set"): return
	if not expect(material.get_shader_parameter("surface_dimensions") == Vector2(161, 261), "surface_dimensions not set"): return

	# 4. Back to the parametric hole: state is reset and results are unchanged.
	game._load_hole(0)
	await process_frame
	if not expect(game.surface_map == null and game.surface_ids.is_empty(), "surface map state not cleared"): return
	if not expect(game.terrain_material.get_shader_parameter("use_surface_map") == false, "use_surface_map not cleared"): return
	if not expect(game.TEE == baseline_tee, "parametric tee moved"): return
	var after := parametric_snapshot(game)
	for i in range(baseline.size()):
		if not expect(after[i] == baseline[i], "parametric hole changed at sample %d: %s vs %s" % [i, after[i], baseline[i]]): return

	if failed: return
	print("PASS surface map lookups, lies, hazards, out-of-map, green cap and parametric holes")
	quit(0)
