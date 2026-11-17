extends SceneTree
var game
func _initialize() -> void: call_deferred("check")
func button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	game._input(event)
func motion(dx: float, dy: float) -> void:
	var event := InputEventMouseMotion.new()
	event.screen_relative = Vector2(dx, dy)
	game._input(event)
func begin_swing() -> void:
	game._reset_ball()
	game.aim = 0.0 # Isolate swipe direction from the mapped tee's initial aim.
	game.wind_index = 0
	button(true)
	motion(0, 180)
func check() -> void:
	game = load("res://tests/flat_course.gd").new()
	root.add_child(game)
	await process_frame
	begin_swing()
	motion(3, -180)
	assert(is_zero_approx(game._swipe_direction()), "small jitter should be forgiven")
	button(false)
	assert(is_zero_approx(game.last_direction) and absf(game.velocity.x) < 0.001)
	begin_swing()
	game.landing_view = true
	motion(-25, -180)
	var left: float = game._swipe_direction()
	assert(left < -1.0)
	game._update_landing_preview()
	var predicted: Vector3 = game.landing_prediction.position
	button(false)
	assert(game.last_direction == left and game.velocity.x < 0)
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if game.has_landed: break
	assert(game.ball_position.distance_to(predicted) < 0.03, "live preview must match the launched shot")
	begin_swing()
	motion(25, -180)
	var right: float = game._swipe_direction()
	assert(right > 1.0 and is_equal_approx(right, -left))
	button(false)
	assert(game.velocity.x > 0)
	begin_swing()
	motion(200, -30)
	assert(is_equal_approx(game._swipe_direction(), 12.0))
	button(false)
	game._reset_ball()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_PERIOD
	game._input(key)
	assert(is_equal_approx(game.swipe_sensitivity, 1.25))
	key.keycode = KEY_COMMA
	game._input(key)
	assert(is_equal_approx(game.swipe_sensitivity, 1.0))
	begin_swing()
	game.club_index = game.CLUBS.size() - 1
	motion(25, -180)
	button(false)
	assert(game.velocity.x > 0 and is_zero_approx(game.velocity.y), "putts respond to swipe direction")
	print("PASS swipe dead zone, left/right, cap, preview, sensitivity, and putting")
	quit()
