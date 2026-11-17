extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._load_hole(3)
	assert(game.active_hole == game.COURSE.holes[3])
	assert(game.active_hole.par == 5 and game.active_hole.yards == 544.0)
	# Scorecard yardage follows the bend; the direct distance to the pin is shorter.
	assert(game._distance_to_cup(game.TEE) * game.YARDS_PER_METER < 544.0)
	var path_distance := 0.0
	var previous := Vector2(game._fairway_center(0), 0)
	for i in range(1, 967):
		var z := maxf(-float(i) * .5, game.CUP.z)
		var point := Vector2(game._fairway_center(z), z)
		path_distance += previous.distance_to(point)
		previous = point
	# OSM's mapped centerline is approximate and does not identify the white tee.
	assert(path_distance * game.YARDS_PER_METER > 450.0)
	assert(path_distance * game.YARDS_PER_METER < 544.0)
	assert(game._on_green(game.CUP))
	assert(game._fairway_center(-137) > 128.0)
	assert(game._fairway_center(-251) > 112.0)
	assert(game._fairway_contains(game._fairway_center(-137), -137))
	assert(not game._fairway_contains(0, -137))
	assert(int(game.terrain_material.get_shader_parameter("fairway_centerline_count")) == 4)
	assert(absf(game._ground_height(0, 0)) < 0.001)
	assert(game._ground_height(0, game.CUP.z) < -3.0)
	assert(absf(game._ground_height(129.429, -136.888) + 1.23) < 0.3, "Terrain must come from the mapped dogleg location")
	var h00: float = game._ground_height(0.0, -100.0)
	var h20: float = game._ground_height(2.0, -100.0)
	assert(absf(game._ground_height(1.0, -100.0) - (h00 + h20) * 0.5) < 0.0001, "Imported heights interpolate continuously")
	assert(game.aim > 40.0 and game.aim < 50.0)
	var terrain: MeshInstance3D = game.get_node("CourseTerrain")
	var bounds := terrain.mesh.get_aabb()
	assert(bounds.position.z <= game.CUP.z - 30, "Terrain must extend beyond the green")
	assert(bounds.position.x <= game.CUP.x - 55, "Terrain must cover the left side of the dogleg")
	assert(bounds.end.x >= 185.0, "Terrain must cover the outside of the dogleg")
	assert(game.tree_obstacles.size() >= 20)
	assert(game.active_hole.green_guard_trees.size() >= 2)
	var guard = game.tree_obstacles[-3]
	var base: Vector3 = guard.base
	assert(base.z > game.CUP.z and base.z < game.CUP.z + 40)
	assert(game._tree_hit(base + Vector3(-3, 2, 0), base + Vector3(3, 2, 0)), "Green guard trees must affect shots")
	game.ball_position = Vector3(base.x - 2, game._ground_height(base.x - 2, base.z) + game.BALL_RADIUS, base.z)
	game.club_index = game.CLUBS.size() - 1
	game.aim = 90.0
	var tree_forecast: Dictionary = game.physics_bridge.Forecast(game._shot_data(1.0), false, false)
	assert(tree_forecast.tree_hit, "Guard tree must be detected by the shared shot simulator")
	assert(game.active_hole.water_ellipses.is_empty())
	game.wind_index = 0
	game._reset_ball()
	game.wind_index = 0
	game._update_hud()
	assert(game.hud.hole_card.badge_text() == "4")
	assert(game.hud.hole_card.par_text().contains("PAR 5"))
	await process_frame
	var stroke_box: Control = game.hud.hole_card._strokes.get_parent()
	var first_cell: Control = game.hud.hole_card._cells[0]
	assert(stroke_box.get_global_rect().end.x <= first_cell.get_global_rect().position.x, "Scorecard must not overlap the stroke count")
	# Preview and live flight agree from the long-hole tee.
	game.club_index = 0
	game.aim = 0.0
	game.backswing = .85 * game.BACKSWING_FOR_FULL_POWER
	var predicted: Dictionary = game._predict_landing(.85)
	game._hit_ball()
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if game.has_landed or not game.in_motion: break
	assert(game.has_landed and game.ball_position.distance_to(predicted.position) < .03)
	var procedural = game.HOLES[0].duplicate(true)
	procedural.elevation_file = ""
	game.HOLES[0] = procedural
	game._load_hole(0)
	assert(game.elevation_samples.is_empty(), "Switching holes must clear the imported terrain")
	assert(absf(game._ground_height(0.0, 0.0)) < 0.1, "Procedural terrain should still work")
	print("PASS hole 4 yardage, par, terrain coverage, layout and live preview")
	quit()
