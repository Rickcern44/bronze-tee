extends SceneTree

# Bunkers (RCE-170): a ball hit onto the fixture bunker (surface ID 9 in
# tests/fixtures/surface_map_hole.tres, ellipse at (16, -86) radii 4 x 3) must
# end up with lie Bunker, show it on the HUD state, apply the 0.62 lie factor
# and give a different (longer-club) recommendation than the same distance from
# the fairway. Exits non-zero on the first failure.

const FIXTURE := "res://tests/fixtures/surface_map_hole.tres"
const BUNKER_CENTER := Vector2(16, -86)
const SAND_WEDGE := 11

func _initialize() -> void:
	call_deferred("check")

func expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func move_to(game, pos: Vector3) -> void:
	game.ball_position = Vector3(pos.x, game._ground_height(pos.x, pos.z) + game.BALL_RADIUS, pos.z)
	game.velocity = Vector3.ZERO
	game.in_motion = false
	game.airborne = false
	game.hole_complete = false
	game.shot_start = game.ball_position
	game.tree_obstacles.clear()
	game.wind_index = 0

func check() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.HOLES.append(load(FIXTURE))
	game._load_hole(game.HOLES.size() - 1)
	await process_frame
	if not expect(game.CLUBS[SAND_WEDGE].name == "Sand Wedge", "club index %d is not the sand wedge" % SAND_WEDGE): return

	# Fly a sand wedge from the fairway at the bunker; some swing strength must finish inside it.
	var landed_power := -1.0
	for backswing in range(40, 181, 4):
		game._reset_ball()
		move_to(game, Vector3(BUNKER_CENTER.x, 0, BUNKER_CENTER.y + 16.0))
		game.club_index = SAND_WEDGE
		game.aim = 0.0
		game.backswing = float(backswing)
		game._hit_ball()
		for tick in range(1800):
			game._physics_process(1.0 / 60.0)
			if not game.in_motion: break
		if not expect(not game.in_motion, "shot did not come to rest at backswing %d" % backswing): return
		if game._in_bunker(game.ball_position):
			landed_power = float(backswing)
			break
	if not expect(landed_power > 0.0, "no sand wedge power ended in the bunker"): return
	game._physics_process(1.0 / 60.0)
	if not expect(game._surface_at(game.ball_position.x, game.ball_position.z) == game.Surface.BUNKER, "ball is not on the bunker surface"): return
	if not expect(game._lie(game.ball_position) == "Bunker", "lie should be Bunker, was %s" % game._lie(game.ball_position)): return
	if not expect(is_equal_approx(game._lie_factor(game.ball_position), 0.62), "bunker lie factor"): return
	var floor_y: float = game._ground_height(game.ball_position.x, game.ball_position.z)
	if not expect(absf(game.ball_position.y - (floor_y + game.BALL_RADIUS)) < 0.01, "resting ball is not on the bunker floor"): return

	# HUD state and next-shot recommendation from the sand.
	game._update_hud()
	if not expect(game.hud_state.lie == "Bunker", "HUD lie was %s" % game.hud_state.lie): return
	game.recommendation_key = []
	game._update_recommendation()
	game._update_hud()
	if not expect(game.hud_state.recommended_name != "" and game.hud_state.recommended_club_index >= 0, "no club recommended from the bunker"): return
	var bunker_pos: Vector3 = game.ball_position
	var distance: float = game._distance_to_cup(bunker_pos)
	var bunker_yards: float = game._estimate_full_shot_distance(SAND_WEDGE)

	# The same club flies shorter from sand than from the fairway at the same distance to the cup.
	var cup: Vector3 = game.CUP
	var fairway := Vector3(cup.x, 0, cup.z + distance)
	move_to(game, fairway)
	if not expect(game._lie(game.ball_position) == "Fairway", "comparison point should be fairway, was %s" % game._lie(game.ball_position)): return
	var fairway_yards: float = game._estimate_full_shot_distance(SAND_WEDGE)
	if not expect(bunker_yards < fairway_yards * 0.9, "sand wedge from the bunker (%.1f m) should fly clearly shorter than from the fairway (%.1f m)" % [bunker_yards, fairway_yards]): return
	print("PASS bunker lie, HUD and recommendation (backswing %d, %.1f vs %.1f m)" % [int(landed_power), bunker_yards, fairway_yards])
	quit(0)
