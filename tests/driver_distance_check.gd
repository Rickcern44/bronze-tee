extends SceneTree
func _initialize() -> void: call_deferred("check")
func check() -> void:
	var game = load("res://tests/flat_course.gd").new()
	root.add_child(game)
	await process_frame
	game._reset_ball()
	game.wind_index = 0
	game.aim = 0.0
	game.club_index = 0
	game.shape_index = 2
	game.shot_type_index = 0
	game.backswing = game.BACKSWING_FOR_FULL_POWER
	game._hit_ball()
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if not game.in_motion: break
	assert(not game.in_motion, "drive must stop")
	var total: float = Vector2(game.ball_position.x - game.TEE.x, game.ball_position.z - game.TEE.z).length() * game.YARDS_PER_METER
	var carry: float = game.carry * game.YARDS_PER_METER
	var rollout: float = game.roll_distance * game.YARDS_PER_METER
	print("calm level fairway drive: %.1f yd carry + %.1f yd rollout = %.1f yd total" % [carry, rollout, total])
	assert(absf(total - 280.0) <= 3.0)
	assert(rollout > 15.0 and rollout < 55.0)
	assert(absf((carry + rollout) - total) < 1.0)
	quit()
