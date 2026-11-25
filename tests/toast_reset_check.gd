extends SceneTree

# A toast raised at the end of a shot must not survive a restart or a hole change.
func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var game = load("res://tests/legacy_course.gd").game()
	root.add_child(game)
	await process_frame
	for action in ["restart", "next_hole"]:
		game._say("7 Iron selected for next shot", "7 Iron selected", "Recommended for the next shot.")
		game._update_hud()
		assert(game.hud.toast_panel.visible, "toast should show after _say")
		if action == "restart":
			game._reset_ball()
		else:
			game._load_hole(1)
		game._update_hud()
		assert(game.hud_state.toast_title.is_empty(), "toast title should clear on " + action)
		assert(not game.hud.toast_panel.visible, "toast panel should hide on " + action)
	print("PASS toast clears on restart and hole change")
	quit()
