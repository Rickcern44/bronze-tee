extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func press_t(game: Node) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_T
	game._input(event)

func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	for hole in range(game.HOLES.size()):
		game.tee_index = 0
		game._load_hole(hole)
		assert(game.ball_position == game.TEE)
		var positions: Array[Vector3] = []
		var yardages: Array[float] = []
		game.wind_index = 2
		game.wind_direction = 123.0
		for tee in range(3):
			game._update_hud()
			assert(game.tee_index == tee and game.hud_state.tee_name == game.TEE_NAMES[tee])
			assert(game._surface_at(game.TEE.x, game.TEE.z) == game.Surface.TEE)
			assert(game._lie(game.TEE) == "Tee")
			assert(game.club_index == game.recommended_club)
			assert(absf(game.TEE.y - game._ground_height(game.TEE.x, game.TEE.z) - game.BALL_RADIUS) < 0.0001)
			assert(game.terrain_material.get_shader_parameter("extra_tee_count") == 2)
			var bounds: AABB = game.get_node("CourseTerrain").mesh.get_aabb()
			assert(game.TEE.z + 4.0 < bounds.end.z, "Terrain must extend behind tee")
			assert(game.TEE.z + 4.0 < game.active_hole.elevation_origin.y, "Elevation must cover tee")
			assert(game.get_node("TeeBox/" + game.TEE_NAMES[tee].capitalize() + "MarkerLeft") != null)
			positions.append(game.TEE)
			yardages.append(game.hud_state.hole_yards)
			press_t(game)
			assert(game.wind_index == 2 and is_equal_approx(game.wind_direction, 123.0))
		assert(yardages[0] < yardages[1] and yardages[1] < yardages[2])
		assert(game._distance_to_cup(positions[0]) < game._distance_to_cup(positions[1]))
		assert(game._distance_to_cup(positions[1]) < game._distance_to_cup(positions[2]))
		assert(not game._fairway_contains(positions[0].x, positions[0].z), "White tee must be behind fairway")
		game.strokes = 1
		press_t(game)
		assert(game.tee_index == 0 and game.strokes == 1, "Cannot change tees mid-hole")
	game.tee_index = 2
	game._load_hole(0)
	game.strokes = 4
	assert(game._complete_hole())
	game._next_hole()
	assert(game.hole_index == 1 and game.tee_index == 2 and game.hole_scores == [4])
	print("PASS colored tees, terrain, yardages, input and round continuity")
	quit()
