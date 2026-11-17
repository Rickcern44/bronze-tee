extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func flat_height(_x: float, _z: float) -> float: return 0.0
func rising_right(_position: Vector3) -> Vector2: return Vector2(0.02, 0.0)

func press(game: Node, code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	game._input(key)

func check() -> void:
	# On a slope rising right, the first arrow points left (downhill).
	var read := GreenRead.new()
	root.add_child(read)
	read.ground_height = Callable(self, "flat_height")
	read.ground_slope = Callable(self, "rising_right")
	read.radii = Vector2(9, 9)
	read.show_read(Vector3(0, 0, 5), Vector3.ZERO, false, true)
	var vertices: PackedVector3Array = read._builder._vertices
	assert(vertices.size() > 3 and vertices[2].x < vertices[0].x, "Arrows must point downhill")
	read.queue_free()
	var camera := Vector3(0, 1, 10)
	var ball := Vector3(0, 1, 0)
	assert(BallTrail.view_visibility(Vector3(0, 1, 5), camera, ball) < 0.2, "Trail in sightline must fade")
	assert(BallTrail.view_visibility(Vector3(3, 1, 5), camera, ball) > 0.9, "Off-axis trail should remain visible")
	assert(BallTrail.view_visibility(Vector3(0, 1, 9.8), camera, ball) < 0.1, "Near-camera trail must fade")
	var trail := BallTrail.new()
	root.add_child(trail)
	trail.track(Vector3.ZERO, Vector3.FORWARD, false, true, 0.2)
	trail.set_resting()
	trail._process(0.7)
	assert(is_equal_approx(trail._rest_blend, 1.0) and BallTrail.REST_ALPHA == 0.0)
	trail.queue_free()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.ball_position = game.CUP + Vector3(0, 0, 5)
	game.ball_position.y = game._ground_height(game.ball_position.x, game.ball_position.z) + game.BALL_RADIUS
	game.club_index = game.CLUBS.size() - 1
	game._physics_process(1.0 / 60.0)
	assert(game.green_read.visible and not game.aim_line.visible)
	assert(is_equal_approx(game.camera.fov, 42.0))
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	game._input(wheel)
	assert(is_equal_approx(game.putt_zoom_fov, 37.0))
	var fine := InputEventKey.new()
	fine.keycode = KEY_D
	fine.shift_pressed = true
	fine.pressed = true
	var old_aim: float = game.aim
	game._input(fine)
	assert(absf(game.aim - old_aim - 0.05) < 0.0001)
	press(game, KEY_H)
	game._physics_process(1.0 / 60.0)
	assert(game.green_read.visible and not game.aim_line.visible and game.green_read._builder.is_empty())
	press(game, KEY_H)
	press(game, KEY_V)
	game._physics_process(1.0 / 60.0)
	assert(game.green_read.visible and not game.putt_preview.visible and game.hud.preview_panel.visible, "Putt preview must be numbers only")
	assert(game.landing_prediction.power < 1.0, "Putt preview should start at a useful suggested pace")
	game.swing_active = true
	game.backswing = 0.35 * game.BACKSWING_FOR_FULL_POWER
	game._update_landing_preview()
	assert(is_equal_approx(game.landing_prediction.power, 0.35), "Swing power must drive the preview")
	game.swing_active = false
	press(game, KEY_V)
	game._physics_process(1.0 / 60.0)
	assert(game.green_read.visible)
	game.backswing = 0.4 * game.BACKSWING_FOR_FULL_POWER
	game._hit_ball()
	game._physics_process(1.0 / 60.0)
	assert(not game.green_read.visible, "Read should not obscure a moving putt")
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if not game.in_motion: break
	game._physics_process(1.0 / 60.0)
	assert(game.hud_state.putt_previous_valid and game.hud_state.putt_start_distance_m > 4.9)
	assert(game.green_read.visible and not game.green_read._builder.is_empty())
	print("PASS downhill read, optional preview and camera-aware trail")
	quit()
