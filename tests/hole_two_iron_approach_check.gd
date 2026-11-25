extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var game = load("res://tests/legacy_course.gd").game()
	root.add_child(game)
	await process_frame
	game._load_hole(1)
	game.wind_index = 1
	game.wind_direction = 0.0
	game.aim = 0.0
	game.swing_speed_mph = 105.0
	game.club_index = 5 # Five iron
	game.backswing = game.BACKSWING_FOR_FULL_POWER
	var shot: Dictionary = game._shot_data(1.0)
	var landing: Dictionary = game.physics_bridge.Forecast(shot, true, false)
	var finish: Dictionary = game.physics_bridge.Forecast(shot, false, false)
	assert(landing.surface == "Green", "Five iron should land on hole 2 green in this scenario")
	var release: float = (landing.position.z - finish.position.z) * game.YARDS_PER_METER
	assert(release > 8.0 and release < 20.0, "Five iron should release forward after landing")
	game._hit_ball()
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if not game.in_motion: break
	assert(not game.in_motion and game.ball_position.distance_to(finish.position) < .02, "Forecast and live approach must match")
	# With a stronger following wind, a 6 iron can land short and run onto the green.
	game._reset_ball()
	game.wind_index = 3
	game.wind_direction = 0.0
	game.aim = 0.0
	game.club_index = 6
	var short_shot: Dictionary = game._shot_data(1.0)
	var short_landing: Dictionary = game.physics_bridge.Forecast(short_shot, true, false)
	var short_finish: Dictionary = game.physics_bridge.Forecast(short_shot, false, false)
	assert(short_landing.surface == "Fairway" and short_finish.surface == "Green")
	# Ten mph into the shot reduces carry from the same tee and swing.
	game.club_index = 5
	game.wind_index = 2
	game.wind_direction = 180.0
	var into_wind: Dictionary = game.physics_bridge.Forecast(game._shot_data(1.0), true, false)
	assert(into_wind.position.z > landing.position.z + 3.0)
	print("PASS hole 2 five-iron green release, six-iron run-up, wind and live forecast")
	quit()
