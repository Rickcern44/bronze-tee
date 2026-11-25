extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func press(game: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._input(event)

func check() -> void:
	var game = load("res://tests/legacy_course.gd").game()
	root.add_child(game)
	await process_frame
	assert(not game.debug_menu.visible and game.debug_menu.buttons.size() == game.HOLES.size())
	# Opening while drawing a swing cancels the gesture and releases the mouse.
	game.swing_active = true
	game.backswing = 90
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	press(game, KEY_F3)
	assert(game.debug_menu.visible and not game.swing_active and game.backswing == 0)
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	game._input(mouse)
	assert(not game.swing_active, "Menu clicks must not start a swing")
	press(game, KEY_4)
	assert(not game.debug_menu.visible and game.hole_index == 3)
	assert(game.strokes == 0 and game.hole_scores == [-1, -1, -1])
	assert(game._round_relative() == 0 and game.ball_position == game.TEE)
	game.strokes = 5
	assert(game._complete_hole())
	game._update_hud()
	assert(game.hole_scores == [-1, -1, -1, 5] and game._round_relative() == 0)
	assert(game.hud.hole_out_banner._summary.text.contains("ROUND E"))
	press(game, KEY_F3)
	await process_frame
	var button_position: Vector2 = game.debug_menu.buttons[1].get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = button_position
	move.global_position = button_position
	root.push_input(move, true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = button_position
	click.global_position = button_position
	click.pressed = true
	root.push_input(click, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = button_position
	release.global_position = button_position
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	assert(not game.debug_menu.visible and game.hole_index == 1, "Mouse click should select a hole")
	assert(game.hole_scores == [-1] and game._round_relative() == 0)
	game.strokes = 4
	assert(game._complete_hole() and game._round_relative() == 1)
	game._next_hole()
	assert(game.hole_index == 2 and game.hole_scores == [-1, 4])
	game._reset_ball()
	assert(game.hole_scores == [-1, 4])
	# Menu freezes live ball motion; Escape resumes rather than quitting.
	game.backswing = game.BACKSWING_FOR_FULL_POWER
	game._hit_ball()
	var before: Vector3 = game.ball_position
	press(game, KEY_F3)
	game._physics_process(1.0 / 60.0)
	assert(game.in_motion and game.ball_position == before)
	press(game, KEY_ESCAPE)
	assert(not game.debug_menu.visible)
	game._physics_process(1.0 / 60.0)
	assert(game.ball_position != before)
	print("PASS debug menu, hole selection, paused play and practice scoring")
	quit()
