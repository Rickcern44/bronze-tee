extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	for mode in [0, 1]:
		game._reset_ball()
		game.wind_index = 0
		game.ball_position = game.CUP + Vector3(0, 0, 80)
		game.ball_position.y = game._ground_height(game.ball_position.x, game.ball_position.z) + game.BALL_RADIUS
		game.club_index = 10 # Pitching wedge
		game.aim = 0
		game.spin_index = mode
		game.backswing = .6 * game.BACKSWING_FOR_FULL_POWER
		var data: Dictionary = game._shot_data(.6)
		var landing: Dictionary = game.physics_bridge.Forecast(data, true, false)
		var finish: Dictionary = game.physics_bridge.Forecast(data, false, false)
		assert(landing.surface == "Green", "Approach must land on the green")
		if mode == 0:
			assert(finish.position.z < landing.position.z, "Normal shot should release forward")
		else:
			assert(finish.position.z > landing.position.z, "Selected backspin should pull the ball back")
		game._hit_ball()
		for tick in range(2400):
			game._physics_process(1.0 / 60.0)
			if not game.in_motion: break
		assert(not game.in_motion, "Approach did not finish")
		assert(game.ball_position.distance_to(finish.position) < .02, "Live shot and forecast disagree")
	print("PASS normal release, selected backspin, and live approach forecasts")
	quit()
