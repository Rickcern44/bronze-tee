extends SceneTree
var game
func _initialize() -> void:
	call_deferred("check")
func move_to(pos: Vector3) -> void:
	game.ball_position = Vector3(pos.x, game._ground_height(pos.x, pos.z) + game.BALL_RADIUS, pos.z)
	game.velocity = Vector3.ZERO
	game.in_motion = false
	game.hole_complete = false
	game.strokes = 1
	game.shot_start = game.ball_position
func test_prediction(pos: Vector3, club: int, power: float, heading: float, wind: int, direction: float) -> void:
	game._reset_ball()
	move_to(pos)
	game.club_index = club
	game.aim = heading
	game.wind_index = wind
	game.wind_direction = direction
	var prediction: Dictionary = game._predict_landing(power)
	var projected: Vector3 = prediction.position
	game.backswing = power * game.BACKSWING_FOR_FULL_POWER
	game._hit_ball()
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if game.has_landed or not game.in_motion: break
	var actual: Vector3 = game.ball_position
	assert(actual.distance_to(projected) < 0.02, "predicted landing does not match actual")
	print("PASS landing ", prediction.surface, " error ", actual.distance_to(projected))
func check() -> void:
	game = load("res://tests/hazard_course.gd").new()
	root.add_child(game)
	await process_frame
	test_prediction(Vector3(0, 0, -20), 0, 1.0, 0.0, 0, 90.0)
	test_prediction(Vector3(0, 0, -20), 0, 0.75, 3.0, 4, 90.0)
	test_prediction(Vector3(-35, 0, -100), 5, 0.8, 0.0, 2, 180.0)
	test_prediction(Vector3(24, 0, -185), 10, 0.8, 0.0, 2, 0.0)
	# A half-power pitching wedge lands on the green and matches the live shot.
	test_prediction(game.CUP + Vector3(0, 0, 60), 10, 0.5, 0.0, 0, 0.0)
	assert(game._on_green(game.ball_position), "half-power approach should reach the green")
	game._reset_ball()
	game.wind_index = 0
	game.wind_direction = 90.0
	var calm: Dictionary = game._predict_landing(1.0)
	game.wind_index = 4
	var wind: Dictionary = game._predict_landing(1.0)
	assert(wind.position.x > calm.position.x + 1.0)
	var event := InputEventKey.new()
	event.keycode = KEY_V
	event.pressed = true
	game._input(event)
	game._update_landing_preview()
	assert(game.landing_view and game.landing_marker.visible and game.landing_prediction.power == 1.0)
	game.swing_active = true
	game.backswing = 90.0
	game._update_landing_preview()
	assert(is_equal_approx(game.landing_prediction.power, 0.5))
	game._input(event)
	game._update_landing_preview()
	assert(not game.landing_marker.visible)
	game.swing_active = false
	move_to(game.CUP + Vector3(0, 0, 3))
	game.club_index = game.CLUBS.size() - 1
	game.aim = 0.0
	var putt: Dictionary = game._predict_landing(0.55)
	game.backswing = 0.55 * game.BACKSWING_FOR_FULL_POWER
	game._hit_ball()
	for tick in range(1200):
		game._physics_process(1.0 / 60.0)
		if not game.in_motion: break
	assert(game.ball_position.distance_to(putt.position) < 0.02, "putt prediction mismatch")
	print("PASS wind, toggle, live power and putt preview")
	quit()
