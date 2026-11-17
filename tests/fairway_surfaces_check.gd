extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	for hole in range(game.HOLES.size()):
		game._load_hole(hole)
		game.wind_index = 0
		var z := -100.0
		var center: float = game._fairway_center(z)
		var width: float = game._fairway_width(z)
		var fairway := Vector3(center + width - 1.0, 0, z)
		var cut := Vector3(center + width + 1.5, 0, z)
		var rough := Vector3(center + width + 5.0, 0, z)
		assert(game._lie(fairway) == "Fairway")
		assert(game._lie(cut) == "FirstCut")
		assert(game._lie(rough) == "Rough")
		assert(is_equal_approx(game._lie_factor(cut), .92))
		game.ball_position = cut
		game.club_index = 5
		var shot: Dictionary = game._shot_data(1.0)
		assert(shot.lie == 6, "First-cut lie must reach the physics bridge")
		var first_speed: float = game.physics_bridge.InitialVelocity(shot).length()
		game.ball_position = fairway
		var fairway_speed: float = game.physics_bridge.InitialVelocity(game._shot_data(1.0)).length()
		assert(absf(first_speed / fairway_speed - .92) < .001)
		assert(not game._fairway_contains(center + width - 1.0, -5.0), "Fairway ends should be rounded")
	print("PASS all-hole curved fairway, first-cut and rough classification")
	quit()
