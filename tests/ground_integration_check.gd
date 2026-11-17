extends SceneTree
func _initialize() -> void: call_deferred("check")
func check() -> void:
	var game = load("res://tests/flat_course.gd").new()
	root.add_child(game)
	await process_frame
	for scenario in [[0, 0], [5, 0], [10, 1]]:
		game._reset_ball()
		game.wind_index = 0
		game.club_index = scenario[0]
		game.shot_type_index = scenario[1]
		game.backswing = 180.0
		var predicted: Dictionary = game._predict_landing(1.0)
		game._hit_ball()
		var bounced := false
		var highest := 0.0
		var landing_y := 0.0
		for tick in range(2400):
			game._physics_process(1.0 / 60.0)
			if game.has_landed and not bounced:
				bounced = true
				landing_y = game.ball_position.y
				assert(game.ball_position.distance_to(predicted.position) < 0.03)
				assert(game.velocity.y > 0.6, "first impact must have a visible bounce")
				assert(game.hud.ball_panel.chip_state() == StateChip.State.BOUNCING, "HUD must show rebound")
				assert(game.message.contains("Landed on"), "landing feedback must be visible")
			if bounced:
				highest = maxf(highest, game.ball_position.y - landing_y)
			if not game.in_motion: break
		assert(bounced and highest > 0.05 and not game.in_motion)
		print("PASS ", game.CLUBS[scenario[0]].name, " bounce height ", highest, " m")
	quit()
