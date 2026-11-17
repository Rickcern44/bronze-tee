extends SceneTree
func _initialize() -> void: call_deferred("check")
func take_shot(game: Node, club: int, power: float) -> void:
	game.club_index = club
	game.backswing = power * game.BACKSWING_FOR_FULL_POWER
	game._hit_ball()
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if not game.in_motion: return
	assert(false, "shot did not stop")
func play_hole(game: Node) -> void:
	for shot in range(15):
		if game.hole_complete: return
		var distance: float = game._distance_to_cup(game.ball_position)
		game._aim_at_cup()
		# On the dogleg, aim the tee shot up the initial fairway.
		if game.hole_index == 3 and game.ball_position.z > -180:
			game.aim = 0.0
		if distance > 150:
			take_shot(game, 0, .85)
		elif distance > 70:
			take_shot(game, 5, .75)
		elif distance > 18:
			take_shot(game, 10, clampf(sqrt(distance / 110.0), .2, 1.0))
		else:
			var needed_speed := sqrt(distance * 2.0 * (game.STIMP_LAUNCH_SPEED * game.STIMP_LAUNCH_SPEED / (2.0 * game.GREEN_SPEEDS[game.green_speed_index] * .3048)))
			take_shot(game, game.CLUBS.size() - 1, clampf(pow(needed_speed / (8.0 * game.PUTTER_ROLL_SPEED_FACTOR), 1.0 / game.PUTTER_POWER_EXPONENT), .12, 1.0))
		print("hole ",game.hole_index+1," shot ",game.strokes," left ",game._distance_to_cup(game.ball_position))
	assert(game.hole_complete, "hole not completed")
func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.wind_index = 0
	play_hole(game)
	game._next_hole()
	game.wind_index = 0
	play_hole(game)
	assert(game.hole_scores.size() == 2)
	game._next_hole()
	game.wind_index = 0
	play_hole(game)
	assert(game.hole_scores.size() == 3)
	game._next_hole()
	game.wind_index = 0
	play_hole(game)
	assert(game.hole_scores.size() == 4)
	print("PASS full four-hole round ",game.hole_scores," ",game._round_relative())
	quit()
