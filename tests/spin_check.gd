extends SceneTree
var game

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	game = load("res://tests/flat_course.gd").new()
	root.add_child(game)
	await process_frame
	game.wind_index = 0
	game.club_index = 7
	game.aim = 0.0
	var normal: Dictionary = game._predict_landing(1.0)
	var event := InputEventKey.new()
	event.keycode = KEY_B
	event.pressed = true
	game._input(event)
	assert(game.spin_index == 1)
	var back: Dictionary = game._predict_landing(1.0)
	assert(back.position.distance_to(normal.position) > 0.05, "spin must affect landing preview")
	game.backswing = game.BACKSWING_FOR_FULL_POWER
	game._hit_ball()
	assert(game.backspin_rpm > 0.0)
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if game.has_landed or not game.in_motion: break
	assert(game.ball_position.distance_to(back.position) < 0.02, "spin preview must match live shot")
	game._reset_ball()
	assert(game.spin_index == 0)
	print("PASS spin control, lift, RPM and live landing preview")
	quit()
