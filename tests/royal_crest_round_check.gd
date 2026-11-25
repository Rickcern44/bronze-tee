extends SceneTree
# Plays the imported 18-hole Royal Crest (the project default course) start to
# finish with an autopilot that drives the same game loop as a player: it picks
# a target, selects a club, sets the backswing, calls _hit_ball and steps
# _physics_process until the ball stops. Every hole must be holed out, with
# tee shots, approaches and putts all coming from the real physics.
# Set ROYAL_CREST_LOG=1 to print every shot.

const MAX_STROKES := 14
const MAX_TICKS := 60 * 60
const DRIVE_RANGE := 215.0
const PARS := [4, 3, 4, 5, 3, 4, 4, 4, 4, 4, 4, 3, 4, 5, 4, 5, 3, 4]
const YARDS := [353, 207, 345, 544, 153, 417, 344, 300, 396, 338, 321, 204, 318, 532, 433, 479, 172, 349]

var game
var verbose := false

func _initialize() -> void:
	call_deferred("check")

func fail(text: String) -> void:
	push_error(text)
	print("FAIL ", text)
	quit(1)

func check() -> void:
	verbose = OS.get_environment("ROYAL_CREST_LOG") == "1"
	game = load("res://scenes/main.tscn").instantiate() # no override: the project default must be Royal Crest
	root.add_child(game)
	await process_frame
	if game.HOLES.size() != 18:
		return fail("expected 18 holes, got %d" % game.HOLES.size())
	if game.COURSE.id != "royal_crest" or game.COURSE.source_kind != "real":
		return fail("course id/source_kind: %s/%s" % [game.COURSE.id, game.COURSE.source_kind])
	var total_par := 0
	var total_strokes := 0
	for hole in range(18):
		game._load_hole(hole)
		game.wind_index = 0
		game.wind_direction = 0.0
		var hole_def = game.HOLES[hole]
		if hole_def.par != PARS[hole] or int(hole_def.yards) != YARDS[hole]:
			return fail("hole %d scorecard par %d yards %d" % [hole + 1, hole_def.par, hole_def.yards])
		total_par += hole_def.par
		var strokes := play_hole(hole)
		if strokes < 0:
			return fail("hole %d was not holed out (strokes %d, ball %s, cup %s)" % [hole + 1, game.strokes, str(game.ball_position), str(game.CUP)])
		total_strokes += strokes
		print("hole %2d par %d: %d strokes" % [hole + 1, hole_def.par, strokes])
		game.hole_scores.resize(hole)
		game.hole_scores.append(strokes)
		if hole < 17:
			game.hole_complete = true
			game._next_hole()
	if total_par != 71:
		return fail("course par %d, expected 71" % total_par)
	print("PASS 18-hole Royal Crest round: %d strokes on par %d" % [total_strokes, total_par])
	quit()

# Centerline point `distance` metres of play ahead of the ball, or the cup.
func target_ahead(distance: float) -> Vector3:
	var line: Array = game.active_hole.fairway_centerline
	var remaining: float = game._distance_to_cup(game.ball_position)
	if remaining <= distance or line.size() < 2:
		return game.CUP
	# Nearest centerline segment to the ball, then walk forward along the line.
	var ball := Vector2(game.ball_position.x, game.ball_position.z)
	var best_segment := 0
	var best_distance := INF
	for i in range(line.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(ball, line[i], line[i + 1])
		if closest.distance_to(ball) < best_distance:
			best_distance = closest.distance_to(ball)
			best_segment = i
	var point := Geometry2D.get_closest_point_to_segment(ball, line[best_segment], line[best_segment + 1])
	var left := distance
	var index := best_segment + 1
	while index < line.size():
		var step: float = point.distance_to(line[index])
		if step >= left:
			point = point.move_toward(line[index], left)
			return Vector3(point.x, 0, point.y)
		left -= step
		point = line[index]
		index += 1
	return game.CUP

func play_hole(hole: int) -> int:
	for shot in range(MAX_STROKES):
		if game.hole_complete:
			return game.strokes
		var putting: bool = game._on_green(game.ball_position)
		var power := 1.0
		if putting:
			game.club_index = game.CLUBS.size() - 1
			game._aim_at_cup()
			var forward := Vector2(game.CUP.x - game.ball_position.x, game.CUP.z - game.ball_position.z).normalized()
			power = game._putt_suggested_power(forward)
		else:
			var remaining: float = game._distance_to_cup(game.ball_position)
			if remaining > DRIVE_RANGE * 1.15:
				game.club_index = 0
				var target := target_ahead(DRIVE_RANGE)
				game.aim = rad_to_deg(atan2(target.x - game.ball_position.x, -(target.z - game.ball_position.z)))
			else:
				game._aim_at_cup()
				game.recommendation_key.clear()
				game._update_recommendation()
				game.club_index = game.recommended_club
				# Scale the swing so a full-shot estimate of this club lands at the cup.
				power = clampf(remaining / maxf(game._estimate_full_shot_distance(game.club_index), 1.0), 0.15, 1.0)
		game.backswing = power * game.BACKSWING_FOR_FULL_POWER
		var lie: String = game._lie(game.ball_position)
		var club_name: String = game.CLUBS[game.club_index].name
		var before: Vector3 = game.ball_position
		game._hit_ball()
		var ticks := 0
		while game.in_motion and ticks < MAX_TICKS:
			game._physics_process(1.0 / 60.0)
			ticks += 1
		if game.in_motion:
			push_error("hole %d shot %d never stopped" % [hole + 1, shot + 1])
			return -1
		if verbose:
			print("  h%d s%d %s from %s power %.2f -> %s lie %s, %.0f m to cup" % [hole + 1, game.strokes, club_name, lie, power, str(game.ball_position.snapped(Vector3(.1, .1, .1))), game._lie(game.ball_position), game._distance_to_cup(game.ball_position)])
	return game.strokes if game.hole_complete else -1
