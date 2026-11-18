extends SceneTree
# Blue flag playtest: one screenshot per Royal Crest hole showing the blue course flag,
# plus geometry and HUD-accent checks.
# Run: ./tools/playtest.sh blue_flags
# Output dir: FLAG_OUT_DIR env var, default playtest-output/blue_flags.

const OUT_DIR_DEFAULT := "playtest-output/blue_flags"
const SETTLE_FRAMES := 90
const MIN_FLAG_PX := 20.0
const WIN_X := 6
const WIN_Y := 3
const APPROACH_DISTANCES := [25.0, 40.0, 18.0]
const SHOT_W := 1280
const SHOT_H := 720
const MIN_DISTINCT_COLOURS := 50

var out_dir := OUT_DIR_DEFAULT
var failures := 0
var game


func _initialize() -> void:
	call_deferred("run")


func wait(n: int) -> void:
	for i in n:
		await process_frame


# Saves the current frame under out_dir/name.png and returns the image.
func shot(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/" + name + ".png")
	return img


func valid(img: Image, name: String) -> bool:
	if not FileAccess.file_exists(out_dir + "/" + name + ".png"):
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


# Projection of the flag for the current camera: found, behind, centre, projected width.
func flag_geometry(flag: Node3D) -> Dictionary:
	var result := {"behind": true, "centre": Vector2.ZERO, "px": 0.0, "inside": false}
	if flag == null:
		return result
	var pos: Vector3 = flag.global_position
	result.behind = game.camera.is_position_behind(pos)
	var c: Vector2 = game.camera.unproject_position(pos)
	result.centre = c
	var left: Vector2 = game.camera.unproject_position(pos + Vector3(0.9, 0, 0))
	var right: Vector2 = game.camera.unproject_position(pos - Vector3(0.9, 0, 0))
	result.px = absf(left.x - right.x)
	result.inside = c.x >= 0 and c.x < SHOT_W and c.y >= 0 and c.y < SHOT_H
	return result


# Mean colour of the window around the centre of the flag, in the screenshot.
func window_mean(img: Image, c: Vector2) -> Color:
	var x0 := clampi(int(c.x) - WIN_X, 0, SHOT_W - 1)
	var x1 := clampi(int(c.x) + WIN_X, 0, SHOT_W - 1)
	var y0 := clampi(int(c.y) - WIN_Y, 0, SHOT_H - 1)
	var y1 := clampi(int(c.y) + WIN_Y, 0, SHOT_H - 1)
	var sum := Vector3.ZERO
	var count := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := img.get_pixel(x, y)
			sum += Vector3(p.r, p.g, p.b)
			count += 1
	var m := sum / float(count)
	return Color(m.x, m.y, m.z)


func is_blue(m: Color) -> bool:
	return m.b >= 0.55 and m.b - m.r >= 0.30 and m.b - m.g >= 0.20


func run() -> void:
	var env_dir := OS.get_environment("FLAG_OUT_DIR")
	if env_dir != "":
		out_dir = env_dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)

	# Steps 1 to 4: one passing screenshot per hole.
	for h in range(1, 5):
		game._load_hole(h - 1)
		var passed := false
		var pass_img: Image = null
		var report := ""
		var found_any := false
		var colour_ok := false
		for d in APPROACH_DISTANCES:
			var p: Vector3 = game.CUP + Vector3(0, 0, d)
			p.y = game._ground_height(p.x, p.z) + game.BALL_RADIUS
			game.ball_position = p
			game.ball.position = p
			var v: Vector3 = game.CUP - p
			game.club_index = 0
			game.aim = rad_to_deg(atan2(v.x, -v.z))
			game._update_hud()
			await wait(SETTLE_FRAMES)
			var img := await shot("flag_hole%d_d%d" % [h, int(d)])
			var flag: Node3D = game.find_child("CupFlag", false, false)
			found_any = flag != null
			if flag != null:
				colour_ok = flag.material_override.albedo_color.is_equal_approx(game.FLAG_COLOR)
			var geo := flag_geometry(flag)
			var mean := window_mean(img, geo.centre)
			var pixels_ok := is_blue(mean)
			var attempt_ok: bool = found_any and not geo.behind and geo.px >= MIN_FLAG_PX and geo.inside and pixels_ok
			report = "distance %d m, club_index %d, px %.1f, centre (%.0f,%.0f), mean rgb (%.3f, %.3f, %.3f)" % [
				int(d), game.club_index, geo.px, geo.centre.x, geo.centre.y, mean.r, mean.g, mean.b]
			if attempt_ok:
				img.save_png(out_dir + "/flag_hole%d.png" % h)
				pass_img = img
				passed = true
				break
		var img_ok := passed and valid(pass_img, "flag_hole%d" % h)
		step(h, found_any and colour_ok and passed and img_ok,
			"hole %d: found=%s color_ok=%s; %s" % [h, str(found_any), str(colour_ok), report])

	# Step 5: pole and geometry unchanged.
	game._load_hole(0)
	var pole: Node3D = game.find_child("CupPole", false, false)
	var flag5: Node3D = game.find_child("CupFlag", false, false)
	var pole_ok := false
	var flag_mesh_ok := false
	if pole != null and flag5 != null:
		var pole_mesh := pole.mesh as BoxMesh
		var flag_mesh := flag5.mesh as BoxMesh
		pole_ok = pole_mesh != null and pole_mesh.size == Vector3(0.012, 4.0, 0.012) \
			and pole.material_override.albedo_color.is_equal_approx(Color(0.95, 0.94, 0.82))
		flag_mesh_ok = flag_mesh != null and flag_mesh.size == Vector3(1.8, 0.8, 0.08)
	step(5, pole_ok and flag_mesh_ok, "pole and flag geometry unchanged (pole %s, flag mesh %s)" % [str(pole_ok), str(flag_mesh_ok)])

	# Step 6: HUD accent untouched.
	step(6, HudPalette.FLAG.is_equal_approx(Color("F0562E")), "HudPalette.FLAG is F0562E")

	# Step 7: no earlier step failed.
	step(7, failures == 0, "no earlier step failed")

	quit(0 if failures == 0 else 1)
