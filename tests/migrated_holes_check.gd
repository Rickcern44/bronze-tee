extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func original_height(hole: int, x: float, z: float, cup_z: float) -> float:
	var green_distance := Vector2(x / 15.5, (z - cup_z) / 14.5).length()
	var green_weight := 1.0 - smoothstep(1.0, 1.6, green_distance)
	if hole == 2:
		var tee_blend := smoothstep(8.0, 35.0, -z)
		var hill_one := 2.3 * exp(-pow((z + 125.0) / 42.0, 2.0))
		var hill_two := 1.6 * exp(-pow((z + 235.0) / 50.0, 2.0))
		var cross_slope := 0.65 * sin(x * 0.035) * sin(-z * 0.019)
		var fairway := tee_blend * (hill_one + hill_two + cross_slope)
		var green := 0.45 + x * 0.018 + (z - cup_z) * 0.012 + 0.10 * sin(x * 0.18) * sin((z - cup_z) * 0.13)
		return lerpf(fairway, green, green_weight)
	var fairway := 0.75 * sin(-z * 0.023) + 0.32 * sin(x * 0.055) * sin(-z * 0.017)
	var green := 0.75 * sin(-cup_z * 0.023) + x * 0.006 + (z - cup_z) * 0.003
	return lerpf(fairway, green, green_weight)

func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var expected_elevations := [-1.72249, -2.52441, -0.34885]
	for hole in range(3):
		game._load_hole(hole)
		assert(game.active_hole == game.COURSE.holes[hole])
		assert(not game.elevation_samples.is_empty())
		assert(absf(game._ground_height(0, 0)) < 0.001)
		assert(absf(game._ground_height(0, -100) - expected_elevations[hole]) < 0.001, "Wrong imported tile or coordinate alignment")
		assert(int(game.terrain_material.get_shader_parameter("water_count")) == game.active_hole.water_ellipses.size())
		# The editable procedural recipe remains supported for fictional holes.
		var procedural = game.active_hole.duplicate(true)
		procedural.elevation_file = ""
		game.HOLES[hole] = procedural
		game._load_hole(hole)
		assert(game.elevation_samples.is_empty())
		for x in [-20.0, -10.0, 0.0, 10.0, 20.0]:
			for z in [0.0, -40.0, -100.0, -125.0, -235.0, game.CUP.z - 10.0, game.CUP.z, game.CUP.z + 10.0]:
				assert(absf(game._ground_height(x, z) - original_height(hole, x, z, game.CUP.z)) < .0001, "Terrain changed on hole %d at %s" % [hole + 1, Vector2(x, z)])
		assert(int(game.terrain_material.get_shader_parameter("water_count")) == game.active_hole.water_ellipses.size())
	game._load_hole(1)
	assert(game._in_water(Vector3(-42, 0, -103)))
	assert(game.active_hole.tree_count == 10 and not game.active_hole.trees_on_left)
	game._load_hole(2)
	assert(game.active_hole.hills.size() == 2 and game.active_hole.water_ellipses.is_empty())
	var original: float = game._ground_height(0, -125)
	var altered = game.active_hole.duplicate(true)
	altered.hills[0] = Vector3(-125, 42, 4.0)
	altered.water_ellipses.append(Vector4(40, -100, 7, 10))
	game.HOLES[2] = altered
	game._load_hole(2)
	assert(game._ground_height(0, -125) > original + 1.0, "Changing the resource must change the terrain")
	assert(game._in_water(Vector3(40, 0, -100)))
	assert(int(game.terrain_material.get_shader_parameter("water_count")) == 1)
	game._load_hole(1)
	assert(not game._in_water(Vector3(40, 0, -100)), "Hole changes must reset water")
	print("PASS imported and procedural terrain, editable hills, water and reset")
	quit()
