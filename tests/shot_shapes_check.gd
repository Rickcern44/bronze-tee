extends SceneTree
var game
func _initialize() -> void:
	call_deferred("check")

func take_shot(shape: int, shot_type: int) -> Dictionary:
	game._reset_ball()
	game.wind_index = 0
	game.shape_index = shape
	game.shot_type_index = shot_type
	game.club_index = 5
	game.backswing = game.BACKSWING_FOR_FULL_POWER
	var prediction: Dictionary = game._predict_landing(1.0)
	game._hit_ball()
	var landing := Vector3.ZERO
	var peak := 0.0
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		peak = maxf(peak, game.ball_position.y - game.TEE.y)
		if game.has_landed:
			landing = game.ball_position
			break
		if not game.in_motion:
			assert(false, "shot stopped before landing")
	assert(landing.distance_to(prediction.position) < 0.02, "preview and flight differ")
	return {"landing": landing, "peak": peak}

func check() -> void:
	game = load("res://tests/legacy_course.gd").game()
	root.add_child(game)
	await process_frame
	game.tree_obstacles.clear()
	var locations := []
	for shape in range(game.SHAPES.size()):
		var result := take_shot(shape, 0)
		locations.append(result.landing.x)
	for i in range(locations.size() - 1):
		assert(locations[i] < locations[i + 1], "shape order should curve left to right")
	print("PASS hook, draw, straight, fade, slice: ", locations)
	var normal := take_shot(2, 0)
	var flop := take_shot(2, 1)
	var punch := take_shot(2, 2)
	var stinger := take_shot(2, 3)
	assert(flop.peak > normal.peak and absf(flop.landing.z) < absf(normal.landing.z))
	assert(punch.peak < normal.peak and stinger.peak < punch.peak)
	print("PASS normal/flop/punch/stinger heights: ", [normal.peak, flop.peak, punch.peak, stinger.peak])
	for shape in range(game.SHAPES.size()):
		for kind in range(game.SHOT_TYPES.size()):
			take_shot(shape, kind)
	print("PASS preview matches actual flight for all 20 combinations")
	game._reset_ball()
	game.club_index = game.CLUBS.size() - 1
	game.wind_index = 0
	game.shape_index = 0
	game.shot_type_index = 1
	var putt: Vector3 = game._launch_velocity(0.5)
	game.shape_index = 4
	game.shot_type_index = 3
	assert(putt.is_equal_approx(game._launch_velocity(0.5)))
	game._reset_ball()
	var key := InputEventKey.new()
	key.keycode = KEY_U
	key.pressed = true
	game._input(key)
	assert(game.shape_index == 1)
	key.keycode = KEY_K
	game._input(key)
	assert(game.shot_type_index == 1)
	game.landing_view = true
	game._update_landing_preview()
	var first: Vector3 = game.landing_prediction.position
	key.keycode = KEY_I
	game._input(key)
	game._update_landing_preview()
	assert(first.distance_to(game.landing_prediction.position) > 0.1, "preview should update when shape changes")
	game._reset_ball()
	assert(game.shape_index == 2 and game.shot_type_index == 0)
	print("PASS putter ignores selections and restart resets modes")
	quit()
