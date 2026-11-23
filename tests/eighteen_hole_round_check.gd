extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var started := Time.get_ticks_usec()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var initial_load_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var fixture = load("res://tests/fixtures/eighteen_hole_course.tres")
	game.HOLES = fixture.holes.duplicate()
	game.hud_state.course_name = fixture.display_name
	game.hud_state.hole_pars = PackedInt32Array()
	for hole in game.HOLES:
		game.hud_state.hole_pars.append(hole.par)
	game.debug_menu.setup(game.HOLES)
	game.hole_scores.clear()
	var reload_total_usec := 0
	for i in range(18):
		var load_started := Time.get_ticks_usec()
		game._load_hole(i)
		reload_total_usec += Time.get_ticks_usec() - load_started
		game.strokes = 4 + (i % 3) - 1
		assert(game._complete_hole(), "hole %d should complete" % (i + 1))
		if i < 17:
			game._next_hole()
		assert(game.hole_index == i if i == 17 else game.hole_index == i + 1)
		assert(game.hole_scores.size() == i + 1)
		if i == 8:
			assert(game.hole_scores.slice(0, 9).reduce(func(a: int, b: int) -> int: return a + b, 0) == 36)
	assert(game.hole_scores.size() == 18)
	assert(game._round_relative() == 0, "alternating fixture scores should finish at even par")
	game._update_hud()
	assert(game.debug_menu.buttons.size() == 18)
	assert(game.debug_menu.buttons[17].text.contains("HOLE 18"))
	assert(game.hud.hole_card._section_rows.size() == 2)
	assert(game.hud.hole_card._section_totals[0].text == "36")
	assert(game.hud.hole_card._section_totals[1].text == "36")
	assert(game.hud.hole_card._total_label.text == "TOTAL  72")
	game._start_new_round()
	assert(game.hole_index == 0 and game.hole_scores.is_empty() and game.strokes == 0)
	var mean_reload_ms := float(reload_total_usec) / 18.0 / 1000.0
	game.HOLES = [load("res://resources/holes/royal_crest_01.tres")]
	game._elevation_grid_cache.clear()
	var cold_started := Time.get_ticks_usec()
	game._load_hole(0)
	var cold_heightmap_ms := float(Time.get_ticks_usec() - cold_started) / 1000.0
	var decoded_count: int = game.elevation_samples.size()
	var warm_started := Time.get_ticks_usec()
	game._load_hole(0)
	var warm_heightmap_ms := float(Time.get_ticks_usec() - warm_started) / 1000.0
	assert(decoded_count == 161 * 301 and game.elevation_samples.size() == decoded_count, "decoded 2 m grid should survive cached hole reload")
	print("PASS 18-hole progression, OUT/IN/total scores, debug selector and restart")
	print("MEASURE initial scene+2m terrain load %.1f ms; 18-hole fixture reload mean %.1f ms; 2m heightmap cold %.1f ms, cached %.1f ms" % [initial_load_ms, mean_reload_ms, cold_heightmap_ms, warm_heightmap_ms])
	quit()
