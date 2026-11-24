extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var fixture = load("res://tests/fixtures/data_driven_hole.tres")
	var course = load("res://resources/courses/royal_crest_legacy/course.tres")
	course.holes.insert(1, fixture)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	course.holes.remove_at(1) # The game has already built its ordered hole list.
	assert(game.HOLES.size() == 5 and game.HOLES[1] == fixture)
	assert(game.HOLES[0] is Resource)
	assert(game.COURSE.display_name == "Royal Crest")
	assert(absf(game.CUP.z + 311.52) < .001)
	assert(game._in_water(Vector3(44, 0, -120)))
	assert(game.tree_obstacles.size() >= 20)
	# This fixture is appended without adding any generator branch for a new hole.
	game._load_hole(1)
	assert(game.CUP == Vector3(0, 0, -240))
	assert(Vector2(game.TEE.x, game.TEE.z) == Vector2(3, 1))
	assert(absf(game.TEE.y - game._ground_height(3, 1) - game.BALL_RADIUS) < .0001)
	assert(game.GREEN_RADII == Vector2(10, 8))
	assert(is_equal_approx(game.FAIRWAY_BASE_WIDTH, 12.0))
	assert(is_equal_approx(game.FIRST_CUT_WIDTH, 4.0))
	assert(is_equal_approx(game._ground_height(0, -100), 1.25 * sin(100 * .023)))
	assert(game.terrain_material.get_shader_parameter("green_radii") == Vector2(10, 8))
	assert(is_equal_approx(game.terrain_material.get_shader_parameter("fairway_base_width"), 12.0))
	assert(is_equal_approx(game.terrain_material.get_shader_parameter("first_cut_width"), 4.0))
	assert(is_equal_approx(game.terrain_material.get_shader_parameter("path_center_x"), 31.0))
	assert(int(game.terrain_material.get_shader_parameter("water_count")) == 1)
	assert(game.tree_obstacles.size() == 4)
	assert(is_equal_approx(game.tree_obstacles[0].base.x, 42.0))
	assert(game._surface_at(40, -100) == game.Surface.WATER)
	game.ball_position = Vector3(40, game._ground_height(40, -100) + game.BALL_RADIUS, -100)
	game.club_index = game.CLUBS.size() - 1
	var forecast: Dictionary = game.physics_bridge.Forecast(game._shot_data(.3), false, false)
	assert(forecast.phase == 4, "Physics must see the same water as the terrain")
	# Loading another hole must not retain the fixture's values.
	game._load_hole(2)
	assert(game.GREEN_RADII == Vector2(15.5, 14.5))
	assert(is_equal_approx(game.FAIRWAY_BASE_WIDTH, 15.5))
	assert(game._in_water(Vector3(-42, 0, -103)))
	assert(not game._in_water(Vector3(40, 0, -100)))
	game._load_hole(0)
	assert(game.tree_obstacles.size() >= 20 and game._in_water(Vector3(44, 0, -120)))
	# Round progression must follow resource order even with a fixture inserted.
	game.strokes = 4
	assert(game._complete_hole())
	game._next_hole()
	assert(game.hole_index == 1 and game.active_hole == fixture and game.hole_scores == [4])
	game.strokes = 3
	assert(game._complete_hole())
	game._next_hole()
	assert(game.hole_index == 2 and game.active_hole.number == 2 and game.hole_scores == [4, 3])
	assert(game._in_water(Vector3(-42, 0, -103)))
	print("PASS editable hole, geometry and shader, physics water, ordered progression and hole reset")
	quit()
