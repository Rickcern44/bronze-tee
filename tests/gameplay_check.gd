extends SceneTree
var game

func _initialize() -> void:
	call_deferred("run_checks")

func move_to(pos: Vector3) -> void:
	game.ball_position = Vector3(pos.x, game._ground_height(pos.x, pos.z) + game.BALL_RADIUS, pos.z)
	game.velocity = Vector3.ZERO
	game.in_motion = false
	game.airborne = false
	game.hole_complete = false
	game.shot_start = game.ball_position
	game._aim_at_cup()

func play(club: int, power: float) -> void:
	game.club_index = club
	game.backswing = power * game.BACKSWING_FOR_FULL_POWER
	game._hit_ball()
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if not game.in_motion:
			return
	assert(false, "shot did not stop")

func run_checks() -> void:
	game = load("res://tests/hazard_course.gd").new()
	root.add_child(game)
	await process_frame
	# Avoid rebuilding rendering-only close grass during simulation tests.
	game.wind_rng.seed = 654321
	var speeds_seen := {}
	var directions_seen := {}
	var horizontal_signs := {}
	var forward_signs := {}
	for sample in range(80):
		game._randomize_wind()
		speeds_seen[game.wind_index] = true
		directions_seen[int(game.wind_direction / 45.0)] = true
		var wind: Vector3 = game._wind_velocity()
		if wind.x > 0.01: horizontal_signs[1] = true
		if wind.x < -0.01: horizontal_signs[-1] = true
		if wind.z > 0.01: forward_signs[1] = true
		if wind.z < -0.01: forward_signs[-1] = true
	assert(speeds_seen.size() == game.WIND_SPEEDS_MPH.size() - 1 and not speeds_seen.has(0))
	assert(directions_seen.size() == 8 and horizontal_signs.size() == 2 and forward_signs.size() == 2)
	print("PASS randomized wind speeds and directions on restart")
	game._reset_ball()
	game.wind_index = 0
	play(0, 1.0)
	var calm: Vector3 = game.ball_position
	var calm_carry: float = game.carry
	assert(calm_carry > 100.0 and game.trail_points.size() > 3)
	game._reset_ball()
	game.wind_index = 4
	game.wind_direction = 90.0
	play(0, 1.0)
	var crosswind: Vector3 = game.ball_position
	assert(crosswind.x > calm.x + 1.0, "crosswind did not move ball right")
	game._reset_ball()
	game.wind_index = 4
	game.wind_direction = 0.0
	play(0, 1.0)
	assert(game.carry > calm_carry, "tailwind should increase carry")
	game._reset_ball()
	game.wind_index = 4
	game.wind_direction = 180.0
	play(0, 1.0)
	assert(game.carry < calm_carry, "headwind should reduce carry")
	print("PASS wind: calm ", calm, " crosswind ", crosswind)
	game.wind_index = 0
	game._reset_ball()
	# Clubs have consistent, ordered launch speeds at the same power and lie.
	var speeds: Array[float] = []
	for club in [0, 5, 10]:
		game._reset_ball()
		game.club_index = club
		game.backswing = game.BACKSWING_FOR_FULL_POWER
		game._hit_ball()
		speeds.append(game.velocity.length())
	assert(speeds[0] > speeds[1] and speeds[1] > speeds[2])
	game._reset_ball()
	move_to(Vector3(0, 0, -100))
	assert(game._lie(game.ball_position) == "Fairway")
	assert(game._lie_factor(game.ball_position) == 1.0)
	move_to(Vector3(-35, 0, -100))
	assert(game._lie(game.ball_position) == "Rough")
	assert(game._lie_factor(game.ball_position) < 1.0)
	move_to(Vector3(24, 0, -185))
	assert(game._lie(game.ball_position) == "Bunker")
	assert(game._lie_factor(game.ball_position) < 0.82)
	var tree: Dictionary = game.tree_obstacles[0]
	var base: Vector3 = tree.base
	assert(game._tree_hit(base + Vector3(-3, 2, 0), base + Vector3(3, 2, 0)))
	assert(not game._tree_hit(base + Vector3(-3, 50, 0), base + Vector3(3, 50, 0)))
	# Exercise an actual simulated flight into a trunk.
	game._reset_ball()
	game.wind_index = 0
	move_to(base + Vector3(-5, 0, 0))
	game.ball_position.y = base.y + 2.0
	game.club_index = 0
	game.aim = 90.0
	game.backswing = 100.0
	game._hit_ball()
	var hit := false
	for tick in range(1200):
		game._physics_process(1.0 / 60.0)
		if game.message.contains("Tree hit"):
			hit = true
		if not game.in_motion: break
	assert(hit and not game.in_motion, "tree impact should register and resolve")
	print("PASS lies and swept tree collision")
	game._reset_ball()
	move_to(game.CUP + Vector3(0, 0, 0.8))
	play(game.CLUBS.size() - 1, 0.36)
	assert(game.hole_complete and game.strokes == 1, "short putt should hole")
	assert(game.message.contains("UNDER"))
	game._reset_ball()
	assert(game.strokes == 0 and not game.hole_complete and game.trail_points.is_empty())
	# Roll a putt over the near edge of the right-hand water hazard.
	game.tree_obstacles.clear()
	move_to(Vector3(34, 0, -120))
	var replay_start: Vector3 = game.ball_position
	game.aim = 90.0
	game.club_index = game.CLUBS.size() - 1
	game.backswing = 180.0
	game._hit_ball()
	for tick in range(1200):
		game._physics_process(1.0 / 60.0)
		if not game.in_motion: break
	assert(game.strokes == 2 and game.ball_position == replay_start and game.message.contains("Water"))
	print("PASS short putt, scoring, reset, water")
	# Play the actual hole using repeated 5-irons, wedge approaches, and putts.
	game._reset_ball()
	game.wind_index = 0
	play(0, 0.85)
	print("Drive distance remaining ", game._distance_to_cup(game.ball_position))
	for shot in range(8):
		if game.hole_complete: break
		var distance: float = game._distance_to_cup(game.ball_position)
		game._aim_at_cup()
		if distance > 105.0:
			play(5, 0.85)
		elif distance > 18.0:
			play(10, clampf(sqrt(distance / 110.0), 0.2, 1.0))
		else:
			var needed_speed := sqrt(distance * 2.0 * (game.STIMP_LAUNCH_SPEED * game.STIMP_LAUNCH_SPEED / (2.0 * game.GREEN_SPEEDS[game.green_speed_index] * .3048)))
			play(game.CLUBS.size() - 1, clampf(pow(needed_speed / (8.0 * game.PUTTER_ROLL_SPEED_FACTOR), 1.0 / game.PUTTER_POWER_EXPONENT), 0.12, 1.0))
		print("Shot ", game.strokes, " remaining ", game._distance_to_cup(game.ball_position), " ", game.message)
	assert(game.hole_complete, "hole should be completable")
	print("PASS complete hole in ", game.strokes, " strokes")
	quit()
