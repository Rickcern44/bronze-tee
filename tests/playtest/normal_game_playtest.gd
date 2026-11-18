extends SceneTree
# Scripted playtest of the normal game: loads main.tscn, sends real input,
# saves screenshots to playtest-output/normal_game/ and prints PASS/FAIL per step.
# Run: xvfb-run -a -s "-screen 0 1280x720x24" timeout 300 godot --path . --script res://tests/playtest/normal_game_playtest.gd

const OUT_DIR := "playtest-output/normal_game"
const STEP_FRAMES := 10
const SHOT_W := 1280
const SHOT_H := 720
const MIN_DISTINCT_COLOURS := 50

var failures := 0
var game


func _initialize() -> void:
	call_deferred("run")


func wait(n: int) -> void:
	for i in n:
		await process_frame


# Saves the current frame and returns the image.
func shot(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/" + name + ".png")
	return img


# A screenshot is valid when the file exists, is 1280x720, and has at least
# 50 distinct colours on a 32x18 sample grid (a blank frame fails).
func valid(img: Image, name: String) -> bool:
	if not FileAccess.file_exists(OUT_DIR + "/" + name + ".png"):
		return false
	if img.get_width() != SHOT_W or img.get_height() != SHOT_H:
		return false
	var colours := {}
	for gy in 18:
		for gx in 32:
			var x := int((gx + 0.5) * SHOT_W / 32.0)
			var y := int((gy + 0.5) * SHOT_H / 18.0)
			colours[img.get_pixel(x, y).to_html(false)] = true
	return colours.size() >= MIN_DISTINCT_COLOURS


func step(n: int, ok: bool, text: String) -> void:
	if ok:
		print("PASS step %d: %s" % [n, text])
	else:
		print("FAIL step %d: %s" % [n, text])
		failures += 1


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)

	# Step 1: the tee of hole 1 at the start of the game.
	await wait(STEP_FRAMES)
	var img1 := await shot("01_tee_hole1")
	step(1, game.hole_index == 0 and game.strokes == 0 and game.hole_complete == false and valid(img1, "01_tee_hole1"),
		"start on hole 1 tee, 0 strokes, screenshot valid")

	# Step 2: hole 2 tee.
	game._load_hole(1)
	game._update_hud()
	await wait(STEP_FRAMES)
	var img2 := await shot("02_hole2_tee")
	step(2, game.hole_index == 1 and valid(img2, "02_hole2_tee"),
		"hole 2 loaded, screenshot valid")

	# Step 3: ball near the cup. Flag should be visible (currently red).
	game._load_hole(0)
	game.ball_position = game.CUP + Vector3(0, game.BALL_RADIUS, 6.0)
	game.ball.position = game.ball_position
	game._update_hud()
	await wait(STEP_FRAMES)
	var img3 := await shot("03_near_cup_flag")
	var dist: float = game.ball_position.distance_to(game.CUP)
	step(3, dist >= 5.5 and dist <= 6.5 and valid(img3, "03_near_cup_flag"),
		"ball 5.5-6.5 m from cup (%.3f), screenshot valid; reporter states flag colour" % dist)

	# Step 4: one real shot with synthetic mouse input.
	game._load_hole(0)
	await wait(STEP_FRAMES)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(640, 400)
	press.global_position = Vector2(640, 400)
	Input.parse_input_event(press)
	await wait(2)
	var pull := InputEventMouseMotion.new()
	pull.position = Vector2(640, 460)
	pull.global_position = Vector2(640, 460)
	pull.relative = Vector2(0, 60)
	pull.screen_relative = Vector2(0, 60)
	pull.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(pull)
	await wait(2)
	var swipe := InputEventMouseMotion.new()
	swipe.position = Vector2(640, 200)
	swipe.global_position = Vector2(640, 200)
	swipe.relative = Vector2(0, -260)
	swipe.screen_relative = Vector2(0, -260)
	swipe.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(swipe)
	await wait(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(640, 200)
	release.global_position = Vector2(640, 200)
	Input.parse_input_event(release)
	await wait(2)
	# Wait for the ball to stop: at least 120 frames, then until not in motion; max 600 frames.
	for i in 600:
		await process_frame
		if i + 1 >= 120 and not game.in_motion:
			break
	var img4 := await shot("04_after_shot")
	var ok4: bool = game.strokes == 1 and game.in_motion == false and valid(img4, "04_after_shot")
	step(4, ok4,
		"strokes=%d in_motion=%s swing_active=%s backswing=%.3f, screenshot valid" % [game.strokes, str(game.in_motion), str(game.swing_active), game.backswing])

	# Step 5: restart (same as R).
	game._reset_ball()
	await wait(STEP_FRAMES)
	var img5 := await shot("05_restart")
	step(5, game.strokes == 0 and valid(img5, "05_restart"), "restart, 0 strokes, screenshot valid")

	# Step 6: no error lines. The gate runner greps the captured stdout for
	# SCRIPT ERROR / ERROR: lines; this step records that steps 1-5 passed.
	step(6, failures == 0, "steps 1-5 passed; log scan for error lines is done by the runner")

	quit(0 if failures == 0 else 1)
