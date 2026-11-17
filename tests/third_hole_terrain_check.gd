extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	# Keep a dedicated procedural-slope scenario even though the course now
	# uses imported elevation on hole 3.
	var procedural = game.HOLES[2].duplicate(true)
	procedural.elevation_file = ""
	game.HOLES[2] = procedural
	game._load_hole(2)
	game.wind_index = 0
	assert(game._ground_height(0, -125) > game._ground_height(0, 0) + 1.0)
	assert(game.get_node_or_null("CupWalls") != null and game.get_node_or_null("CupBottom") != null)
	assert(absf(game.CUP_RADIUS * 2.0 - .10795) < .00001)
	var start := Vector3(0, 0, game.CUP.z + 5.0)
	start.y = game._ground_height(start.x, start.z) + game.BALL_RADIUS
	game.ball_position = start
	game.shot_start = start
	game.club_index = game.CLUBS.size() - 1
	game.aim = 90.0
	var uphill: Dictionary = game._predict_landing(.5)
	var key := InputEventKey.new()
	key.keycode = KEY_G
	key.pressed = true
	game._input(key)
	assert(game.GREEN_SPEEDS[game.green_speed_index] == 12.0)
	var faster_green: Dictionary = game._predict_landing(.5)
	assert(start.distance_to(faster_green.position) > start.distance_to(uphill.position))
	# Return to the default 10 ft green for the live preview comparison.
	game._input(key)
	game._input(key)
	assert(game.GREEN_SPEEDS[game.green_speed_index] == 10.0)
	game.aim = -90.0
	var downhill: Dictionary = game._predict_landing(.5)
	assert(start.distance_to(downhill.position) > start.distance_to(uphill.position) + .3, "green slope should change roll distance")
	game.backswing = .5 * game.BACKSWING_FOR_FULL_POWER
	game._hit_ball()
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if not game.in_motion: break
	assert(game.ball_position.distance_to(downhill.position) < .02, "sloped putting preview differs from live roll")
	print("PASS third-hole hills, uphill/downhill roll and live putting preview")
	quit()
