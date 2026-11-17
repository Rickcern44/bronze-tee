extends SceneTree
func _initialize() -> void: call_deferred("check")
func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	assert(game.active_hole.yards == 353.0)
	assert(absf(game._distance_to_cup(game.TEE) - 319.52) < 0.1)
	assert(game._on_green(game.CUP))
	assert(game._fairway_contains(0, -150))
	assert(not game._in_water(Vector3(0, 0, -150)))
	assert(game._in_water(Vector3(44, 0, -120)))
	assert(game._in_water(Vector3(-30, 0, game.CUP.z - 20)))
	assert(not game._in_bunker(Vector3(24, 0, -185)))
	assert(game.tree_obstacles.size() >= 20)
	game._reset_ball()
	assert(game.club_index == 0)
	print("PASS Royal Crest scorecard, mapped distance, fairway, green, water and trees")
	quit()
