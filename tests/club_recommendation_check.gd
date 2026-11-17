extends SceneTree
func _initialize() -> void: call_deferred("check")
func check() -> void:
	var game = load("res://tests/flat_course.gd").new()
	root.add_child(game)
	await process_frame
	game.wind_index = 0
	game.swing_speed_mph = 95.0
	game.ball_position = Vector3(0, game._ground_height(0, game.CUP.z + 170.0 / game.YARDS_PER_METER) + game.BALL_RADIUS, game.CUP.z + 170.0 / game.YARDS_PER_METER)
	game.club_index = 10
	game.shape_index = 0
	game.shot_type_index = 1
	game._update_recommendation()
	assert(game.CLUBS[game.recommended_club].name == "5 Iron")
	assert(absf(game.recommended_yards - 170.0) < 5.0)
	assert(game.club_index == 10 and game.shape_index == 0 and game.shot_type_index == 1)
	game._update_hud()
	assert(game.hud.state.recommended_name == "5 Iron" and game.hud.club_card.recommendation_text().contains("5 IRON"))
	var original_cup: Vector3 = game.CUP
	game.CUP.z -= 100.0 # Prevent cup capture while comparing roll distance.
	var expected_distance: float = game._estimate_full_shot_distance(5)
	var start: Vector3 = game.ball_position
	game.club_index = 5
	game.shape_index = 2
	game.shot_type_index = 0
	game.aim = 0
	game.backswing = game.BACKSWING_FOR_FULL_POWER
	game._hit_ball()
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if not game.in_motion: break
	var actual_distance := Vector2(game.ball_position.x - start.x, game.ball_position.z - start.z).length()
	assert(absf(expected_distance - actual_distance) < 0.02, "full-shot estimate must match simulated rollout")
	game.CUP = original_cup
	game.ball_position = start
	game.in_motion = false
	game.hole_complete = false
	game.swing_speed_mph = 70.0
	game._update_recommendation()
	assert(game.recommended_club < 5, "slower swing should recommend a longer club")
	game.swing_speed_mph = 95.0
	game.wind_index = 4
	game.wind_direction = 180.0
	game._update_recommendation()
	assert(game.recommended_club < 5, "headwind should recommend a longer club")
	game.wind_index = 0
	game.strokes = 1
	game._reset_ball()
	game._update_recommendation()
	assert(game.recommended_club == 0, "driver is closest when beyond range")
	game.queue_free()
	await process_frame
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.ball_position = game.CUP + Vector3(0, game._ground_height(0, game.CUP.z) + game.BALL_RADIUS, 5)
	game.in_motion = false
	game._update_recommendation()
	assert(game.recommended_club == game.CLUBS.size() - 1)
	print("PASS recommendation, speed, headwind, selection preserved, green and out-of-range")
	quit()
