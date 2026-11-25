extends SceneTree
func _initialize() -> void: call_deferred("check")
func place(game: Node, x: float, z: float) -> void:
	game.ball_position = Vector3(x, game._ground_height(x, z) + game.BALL_RADIUS, z)
	game.physics_bridge.CancelShot()
	game.velocity = Vector3.ZERO
	game.in_motion = false
	game.airborne = false
	game.has_landed = true
	game.hole_complete = false
	game._aim_at_cup()
	game._select_club_for_next_shot()
	game._update_hud()
func check() -> void:
	var game = load("res://tests/legacy_course.gd").game()
	root.add_child(game)
	await process_frame
	game._reset_ball()
	game.wind_index = 0
	game.swing_speed_mph = 95
	assert(game.club_index == 0)
	game.backswing = 180
	game._hit_ball()
	game._physics_process(1.0 / 60.0)
	assert(game.hud.distance_readout.mode == DistanceReadout.Mode.SHOT)
	var first: float = Vector2(game.ball_position.x - game.shot_start.x, game.ball_position.z - game.shot_start.z).length()
	for tick in range(20): game._physics_process(1.0 / 60.0)
	var later: float = Vector2(game.ball_position.x - game.shot_start.x, game.ball_position.z - game.shot_start.z).length()
	assert(later > first)
	place(game, 0, game.CUP.z + 170.0 / game.YARDS_PER_METER)
	game.shot_start = game.TEE
	game._physics_process(1.0 / 60.0)
	assert(not game.in_motion and game.club_index == game.recommended_club)
	assert(game.hud.distance_readout.mode == DistanceReadout.Mode.TO_PIN)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_E
	game._input(key)
	var chosen: int = game.club_index
	game._physics_process(1.0 / 60.0)
	assert(game.club_index == chosen, "manual override should remain selected")
	game.club_index = 0
	place(game, 0, game.CUP.z + 5)
	game._physics_process(1.0 / 60.0)
	assert(game.club_index == game.CLUBS.size() - 1, "green must select putter")
	game.shot_start = game.TEE
	game.club_index = 5
	game._water_penalty()
	assert(game.ball_position == game.TEE and game.club_index == game.recommended_club, "water replay at tee must select the recommendation")
	print("PASS auto clubs, tee/green/water, manual override and distance transitions")
	quit()
