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
		var max_slope := 0.0
		for x in range(-15, 16):
			for z in range(-14, 15):
				var pos: Vector3 = game.CUP + Vector3(float(x), 0, float(z))
				if game._on_green(pos):
					max_slope = maxf(max_slope, game._ground_slope(pos).length())
		assert(max_slope < .045, "Unexpected steep playable green on hole %d: %f" % [hole + 1, max_slope])
		for stimp in game.GREEN_SPEEDS:
			game.physics_bridge.SetGreenSpeed(stimp)
			for offset in [Vector3(-6, 0, 5), Vector3(6, 0, -5), Vector3(0, 0, 6)]:
				for heading in [90.0, 180.0, 270.0]:
					game.ball_position = game.CUP + offset
					game.ball_position.y = game._ground_height(game.ball_position.x, game.ball_position.z) + game.BALL_RADIUS
					game.club_index = game.CLUBS.size() - 1
					game.aim = heading
					var result: Dictionary = game.physics_bridge.Forecast(game._shot_data(.3), false, false)
					assert(result.phase == 2 or result.phase == 3, "Putt did not stop on hole %d at stimp %.0f" % [hole + 1, stimp])
					assert(game._on_green(result.position), "Short putt ran off the green")
		# Exercise the game loop and compare it with the library-backed forecast.
		game.physics_bridge.SetGreenSpeed(10.0)
		game.ball_position = game.CUP + Vector3(6, 0, 5)
		game.ball_position.y = game._ground_height(game.ball_position.x, game.ball_position.z) + game.BALL_RADIUS
		game.club_index = game.CLUBS.size() - 1
		game.aim = 90.0
		game.backswing = .3 * game.BACKSWING_FOR_FULL_POWER
		var expected: Dictionary = game.physics_bridge.Forecast(game._shot_data(.3), false, false)
		game._hit_ball()
		for tick in range(2400):
			game._physics_process(1.0 / 60.0)
			if not game.in_motion: break
		assert(not game.in_motion, "Live putt did not finish")
		assert(game.ball_position.distance_to(expected.position) < .02, "Live putt and forecast disagree")
		print("PASS hole ", hole + 1, " putting scenarios, maximum green slope ", max_slope * 100.0, "%")
	quit()
