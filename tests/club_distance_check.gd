extends SceneTree
func _initialize() -> void: call_deferred("check")
func run_shot(game: Node, club: int, power: float) -> Vector2:
	game._reset_ball()
	game.wind_index = 0
	game.aim = 0.0
	game.club_index = club
	game.backswing = game.BACKSWING_FOR_FULL_POWER * power
	game._hit_ball()
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if not game.in_motion: break
	assert(not game.in_motion, "shot did not stop")
	return Vector2(game.carry * game.YARDS_PER_METER, (game.TEE.z - game.ball_position.z) * game.YARDS_PER_METER)
func check() -> void:
	var game = load("res://tests/flat_course.gd").new()
	root.add_child(game)
	await process_frame
	game.swing_speed_mph = 95.0
	var expected := [[224, 242], [205, 218], [192, 202], [180, 188], [175, 182], [162, 168], [152, 158], [142, 150], [131, 135], [120, 123], [108, 111], [80, 81], [68, 69]]
	for index in range(expected.size()):
		var result := run_shot(game, index, 1.0)
		assert(absf(result.x - expected[index][0]) < 5.0, "carry outside benchmark: " + game.CLUBS[index].name)
		assert(absf(result.y - expected[index][1]) < 5.0, "total outside benchmark: " + game.CLUBS[index].name)
		print(game.CLUBS[index].name, " ", result)
	game.swing_speed_mph = 105.0
	var fast := run_shot(game, 5, 1.0)
	game.swing_speed_mph = 85.0
	var slow := run_shot(game, 5, 1.0)
	assert(fast.x > slow.x)
	var partial := run_shot(game, 5, 0.5)
	assert(partial.x < slow.x)
	game._reset_ball()
	game.swing_speed_mph = 95
	var slower_preview: Dictionary = game._predict_landing(1.0)
	game.swing_speed_mph = 105
	var faster_preview: Dictionary = game._predict_landing(1.0)
	assert(faster_preview.position.z < slower_preview.position.z)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_BRACKETLEFT
	game._input(key)
	assert(game.swing_speed_mph == 100)
	key.keycode = KEY_BRACKETRIGHT
	game._input(key)
	assert(game.swing_speed_mph == 105)
	print("PASS club benchmarks, swing speed, power, preview and controls")
	quit()
