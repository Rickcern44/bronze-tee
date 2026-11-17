extends SceneTree
func _initialize() -> void: call_deferred("check")
func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	assert(game.club_index == game.recommended_club, "initial tee uses recommendation")
	game._load_hole(1)
	assert(game.club_index == game.recommended_club and game.club_index != 0, "par 3 tee should not force driver")
	game.wind_index = 0
	game.recommendation_key.clear()
	game._select_club_for_next_shot()
	assert(game.club_index == game.recommended_club and game.club_index != 0)
	var chosen_before: int = game.club_index
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_Q
	game._input(key)
	assert(game.club_index != chosen_before)
	var manual: int = game.club_index
	game._physics_process(1.0 / 60.0)
	assert(game.club_index == manual, "manual override must persist")
	game.shot_start = game.TEE
	game.strokes = 1
	game._water_penalty()
	assert(game._lie(game.ball_position) == "Tee")
	assert(game.club_index == game.recommended_club and game.club_index != 0, "tee replay should select recommendation")
	game._reset_ball()
	assert(game.club_index == game.recommended_club and game.club_index != 0, "restart should select recommendation")
	print("PASS initial and par-3 tee recommendation, override, water replay and restart")
	quit()
